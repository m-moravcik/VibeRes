# VibeRes — security and performance audit

Date: 2026-08-01  
Audited commit: `8247221ec545b9a603ad616d06c6085686d0ae83` (`v0.8.5`)  
Application: native macOS SwiftUI menu-bar app and CLI  
Overall risk: **High until F-01 and F-02 are fixed**

## Executive summary

The application has a generally small attack surface: no backend, no embedded web view, no inbound URL handler, strict Swift concurrency, hardened runtime, signed Sparkle updates, and bounded display enumeration. The published `v0.8.5` app itself is correctly Developer ID signed, notarized, stapled, and its nested Sparkle helpers validate.

The largest risk is the release pipeline. Two release runs can build different ZIP files for the same version and publish the appcast from one run with the asset from the other. This happened in production for both `v0.8.4` and `v0.8.5`; Sparkle correctly rejected the mismatched archives. After the audited snapshot, commit `7dae351` republished the `v0.8.5` appcast from the actually served archive and restored live signature validity. The workflow race remains in the audited code until releases are serialized and the public asset is verified before feed publication. The same workflow also exposes signing/notarization/Sparkle secrets to code checked out from any matching tag, without tag rulesets or a protected environment.

The most important application-level defect is the display-revert safety path: it discards errors and consumes recovery state before verifying that the previous mode was restored. Other confirmed issues are a missing ScreenCaptureKit privacy declaration, integer overflow from unbounded AppIntent input, non-atomic multi-display profile application on the main actor, and synchronous unbounded profile I/O.

| ID | Priority | Area | Finding |
|---|---:|---|---|
| F-01 | P1 | Release integrity | Concurrent release runs published appcasts for different ZIPs; live feed was repaired after the audit snapshot |
| F-02 | P1 | Supply chain | Unprotected tag code and shell-interpolated manual input execute with signing secrets |
| F-03 | P1 | Availability/safety | Revert and permanent-confirm failures are silently discarded and recovery state is lost |
| F-04 | P2 | Privacy | ScreenCaptureKit is shipped without `NSScreenCaptureUsageDescription` |
| F-05 | P2 | Input safety | Unbounded AppIntent integers can trap in `ModeScoring` |
| F-06 | P2 | Performance/reliability | Multi-display profiles perform sequential WindowServer commits on `MainActor` |
| F-07 | P3 | Performance/resilience | Profile JSON is synchronously and without size/count limits loaded on `MainActor` |
| F-08 | P3 | Reliability/privacy UX | Screen-recording denial is cached permanently despite an unreachable two-attempt design |

## Findings

### F-01 — Appcast/asset race breaks update integrity (P1)

Evidence:

- `.github/workflows/release.yml:28-46` supports tag push and manual dispatch but uses `release-${{ github.ref }}` as the concurrency group. A tag run uses `refs/tags/vX.Y.Z`; a manual run uses `refs/heads/main`, so both execute concurrently for the same release.
- The workflow commits the appcast at `.github/workflows/release.yml:196-255` before creating the GitHub Release at lines 287-296.
- `v0.8.4` had concurrent tag and manual runs (`30696060658` and `30696066524`). Multiple `v0.8.5` tag/manual runs also overlapped; three failed and one published the release.
- At the audited snapshot, the appcast advertised `v0.8.5` with `length="2856710"` while GitHub served a `2,856,757`-byte `VibeRes-0.8.5.zip` with SHA-256 `bd4ff3b2a58f11a2f0ad9e3e8a36b9bd0a1929d9c098b0c8810b0c35abf4f4f3`.
- Direct CryptoKit verification with the embedded public key returned `signatureValid=false` for that appcast signature and downloaded ZIP.
- The ZIP's macOS code signature is valid. The failure is specifically the Sparkle enclosure signature/feed-to-asset binding.
- Post-audit commit `7dae351` changed the live enclosure to the correct `length="2856757"` and a new signature; verification against the same downloaded ZIP now returns `signatureValid=true`. This mitigates the current feed but does not remove the race from the audited workflow.
- Post-audit commit `e42195e` also moved release creation before appcast publication. That removes the window where the feed points to a nonexistent asset, but it still does not serialize tag/manual runs: run A can upload A, run B can clobber with B, B can publish appcast B, and A can then publish appcast A. One global concurrency group and a public-asset verification gate are still required.

Impact:

- During the incident, Sparkle had to reject the archive and clients could not update through the affected appcast.
- Retrying appcast Git pushes does not solve the race; a successful run can still publish a feed produced by a different concurrent build.

Recommendation:

1. Use one global release concurrency group, such as `group: release`, for tag and manual events.
2. Do not automatically start both a tag release and a manual release for the same version. Make manual dispatch a repair path or remove it.
3. Create/upload the GitHub Release before publishing the appcast.
4. Download the published asset into a clean directory, verify its SHA-256/length and Ed25519 signature, then commit an appcast generated from those exact downloaded bytes.
5. Add a final smoke check that fetches the public appcast and asset and verifies the enclosure signature with `SUPublicEDKey`.

### F-02 — Signing secrets are reachable from unprotected tag code (P1)

Evidence:

- Any `v*.*.*` tag starts the workflow (`.github/workflows/release.yml:28-31`).
- The workflow checks out that tag, then executes repository-controlled scripts while Developer ID, notarization, Sparkle private-key, and tap tokens are available (`.github/workflows/release.yml:72-76`, `134-208`, `308-312`).
- GitHub currently reports no repository rulesets and no Actions environments/protection rules.
- There is no check that the tag commit is reachable from protected `main`.
- Manual input is inserted directly into Bash source as `TAG="${{ inputs.tag }}"` (`.github/workflows/release.yml:65-66`). A crafted string is shell code, not data.
- Actions are referenced by movable major tags (`actions/checkout@v4`) and Homebrew tooling is installed without a version pin in the same high-privilege pipeline.

Impact:

- Anyone able to create a matching tag can make tag-controlled code run with the signing certificate and update private key. A compromised write account therefore becomes a signed-malware supply-chain compromise, not only a source compromise.
- Direct expression interpolation adds command-injection risk to manual runs.

Recommendation:

1. Protect `v*` tags with an active GitHub ruleset and restrict creation/update/deletion.
2. Require the release commit to be an ancestor of the protected `main` branch before secrets are loaded.
3. Put signing steps in a protected GitHub Environment with required approval.
4. Pass inputs through `env`, validate `^v[0-9]+\.[0-9]+\.[0-9]+$`, and never interpolate `${{ inputs.* }}` inside `run:` source.
5. Pin third-party Actions to full commit SHAs and pin release tooling versions.

Reference: [GitHub guidance on script injection](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#understanding-the-risk-of-script-injections).

### F-03 — Revert loses the recovery path on failure (P1)

Evidence:

- `VibeRes/Core/DisplayStore.swift:413-422` clears the countdown, pending confirmation, and full revert history even when the permanent apply fails through `try?`.
- `VibeRes/Core/DisplayStore.swift:436-442` consumes the history before applying old modes, suppresses every error with `try?`, and returns `snapshot.count` rather than the number successfully restored.
- The timeout/revert feature explicitly handles the case where the user sees a black or unreadable screen, so this is a safety-critical path.

Impact:

- A failed revert can leave the display in a bad mode with no retry state, no error, and a false success count.
- A failed permanent confirmation is presented as success and erases the only undo state.

Recommendation:

- Apply each revert entry with explicit error handling; retain failed entries for retry and report only successful restores.
- Clear pending/revert state only after the permanent commit succeeds. On failure, keep or re-arm recovery and surface a sanitized error.
- Add a switcher protocol/fake so begin/configure/complete failures can be tested.

### F-04 — Missing ScreenCaptureKit privacy declaration (P2)

Evidence:

- `VibeRes/Core/DesktopCapture.swift:44-65` requests screen-recording access and captures the desktop with `SCScreenshotManager`.
- `project.yml:101-103` explicitly omits `NSScreenCaptureUsageDescription` because it says live capture is not implemented, but live capture is implemented.
- The built and published `Info.plist` has no screen-capture usage description.
- Apple directs ScreenCaptureKit apps to add the key with an explanation before capture: [ScreenCaptureKit documentation](https://developer.apple.com/documentation/screencapturekit).

Impact:

- The privacy-sensitive feature does not meet Apple's platform declaration contract and cannot present an app-authored reason for the permission request.

Recommendation:

- Add a clear, localized `NSScreenCaptureUsageDescription` to the generated and checked-in Info.plist sources, then test the first-run TCC flow from a clean permission state.

### F-05 — AppIntent input can overflow and terminate execution (P2)

Evidence:

- `VibeRes/Shortcuts/SetResolutionIntent.swift:32-43` accepts arbitrary `Int` width, height, and refresh values and sends them directly to scoring.
- `VibeRes/Core/ModeScoring.swift:23-32` uses trapping subtraction, `abs`, addition, and multiplication.
- The CLI already restricts dimensions to `1...16384` and refresh to `1...1000`; the AppIntent does not.
- Runtime proof: evaluating `abs(1920 - Int.min)` exits with a Swift arithmetic-overflow trap.

Impact:

- A malformed Shortcut/AppIntent invocation can terminate the intent/app process. Less extreme invalid values may select an unintended closest mode.

Recommendation:

- Validate AppIntent values using the same bounds as the CLI before scoring and return parameter-specific `needsValueError` errors. Also make scoring overflow-safe so it remains safe if a future caller forgets validation.

### F-06 — Profile apply is not a background or atomic multi-display operation (P2)

Evidence:

- `ProfileStore` is `@MainActor`.
- `VibeRes/UI/ProfilesSection.swift:351-362` creates `Task.detached` but immediately calls `profiles.applyDetailed` inside `MainActor.run`; the actual work remains on the UI actor.
- `VibeRes/Core/ProfileStore.swift:400-479` loops entries/displays and calls `ResolutionSwitcher.apply` for each display.
- `VibeRes/Core/ResolutionSwitcher.swift:46-62` begins and completes a separate CoreGraphics display transaction for every display.
- The comment at `ProfileStore.swift:481` calls the operation a batch, but only revert-history recording is batched; the system changes are not.

Impact:

- N displays cause N synchronous WindowServer commits, increasing latency and flicker.
- Failure after earlier commits leaves a partially applied profile. The UI actor is occupied during the operation despite the “background task” comment.

Recommendation:

- Add a true batch switcher: one `CGBeginDisplayConfiguration`, configure every chosen display mode, then one `CGCompleteDisplayConfiguration`.
- Perform pure matching/scoring away from `MainActor`; use the actor only to publish outcomes and mutate observable state.

### F-07 — Unbounded synchronous profile I/O on `MainActor` (P3)

Evidence:

- `VibeRes/Core/ProfileStore.swift:29-39` is `@MainActor` and calls `load()` during initialization.
- Lines 50-67 load the entire JSON file and synchronously decode/encode/write it.
- There is no file-size limit or profile/entry count limit. Every mutation writes the full catalog.

Impact:

- A large or hand-edited same-user file can stall startup/UI and cause memory pressure. This is a local resilience issue, not a remote trust-boundary vulnerability.

Recommendation:

- Check file metadata and enforce a conservative size limit before `Data(contentsOf:)`; cap profile and entry counts after decode.
- Move persistence to a dedicated actor/background I/O path and coalesce repeated saves.

### F-08 — Screen-recording denial cache cannot recover in-session (P3)

Evidence:

- `VibeRes/Core/DesktopCapture.swift:85-105` immediately returns for `.denied`. After the first failed request, `deniedAttempts` therefore can never reach two and `.stuckLoop` is unreachable through this path.
- `resetPermissionCache()` exists at lines 76-80 but has no caller. Toggling Live Preview only changes the preference.

Impact:

- Granting permission in System Settings after an initial denial does not re-enable the feature until relaunch. The documented retry/stuck-loop behavior is not the behavior implemented.

Recommendation:

- Re-preflight on an explicit Live Preview re-enable and wire that action to cache reset without repeatedly prompting. Add permission-state unit tests around a small injectable TCC adapter.

## Hardening note: App Sandbox

`ENABLE_APP_SANDBOX` is `NO`, and the published app has no sandbox entitlement. Hardened runtime is enabled, but it is not a sandbox. This increases the blast radius of a future UI/updater exploit to the full user account. It is not a standalone exploitable defect found in this audit. Treat sandbox enablement as a compatibility project requiring tests for CoreGraphics display configuration, ScreenCaptureKit, Sparkle, `SMAppService`, and network access.

## Positive controls and rejected findings

- Sparkle is pinned to `2.9.4`. The two published May 2026 advisories affect `<= 2.9.1`, so this project is outside their vulnerable ranges: [CVE-2026-47121](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-hg88-v3cw-3qrh), [CVE-2026-47122](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-g3hp-f6mg-559v).
- The downloaded `v0.8.5` ZIP matches GitHub's SHA-256 and is Developer ID signed by team `7TM9VA58W5`, hardened, notarized, stapled, and valid under `codesign --deep --strict`; nested Sparkle helpers validate. The broken update is the mismatched Ed25519 enclosure signature, not an invalid macOS signature.
- `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are both enabled, the feed uses HTTPS, and the public Ed25519 key is embedded.
- Release build uses Swift `-O`, whole-module optimization, hardened runtime, and no debug entitlements. The scheme causes `-fprofile-instr-generate` to appear in the linker command, but the produced binary has no LLVM profile sections/symbols and no `get-task-allow`; this was rejected as a runtime finding.
- Profile names and decoded dimensions are sanitized/bounded, and `profiles.json` is set to mode `0600` after writes.
- Screen capture is opt-in, single-shot rather than a continuous stream, capped at 480-point width, and cached for the popover lifetime.
- Display enumeration caps active displays at 32.
- A sandboxed `codesign` run initially reported invalid signatures, but it failed identically for a system Apple app. Re-running outside the filesystem sandbox validated both controls; the initial result was rejected.

## Verification performed

- `xcodebuild test ...` — **passed**, 172 tests in 31 suites, 0 failures, test execution 0.627 s; end-to-end command 8.70 s.
- `xcodebuild build ... -configuration Release ...` — **passed**, universal arm64/x86_64 app; end-to-end command 9.98 s; peak build-process memory footprint 72.7 MB.
- Published `v0.8.5` ZIP SHA-256 — **matched** GitHub API: `bd4ff3b2...abf4f4f3`.
- `codesign --verify --deep --strict`, `stapler validate`, and `spctl --assess` outside sandbox — **passed** for the published app.
- CryptoKit Ed25519 verification of the appcast enclosure against the downloaded ZIP — **failed** at the audited snapshot, confirming F-01; **passed** after the `7dae351` republish mitigation.
- GitHub repository rulesets — none. GitHub Actions environments — none.
- Automated `autoreview` helper — no usable result; it was interrupted after running for more than ten minutes while the repository was changing concurrently. All findings above were independently verified from current source, CI/API state, or executable proof.

## Resolution

Worked through on 2026-08-01, after the audit. Test count over the whole run: 172 → 193.

| ID | Status | Commit |
|---|---|---|
| F-01 | Fixed | `7dae351`, `e42195e`, `7fe4b91` |
| F-02 | Fixed in the workflow; repository settings assessed as unnecessary for a single-owner repo | `7fe4b91` |
| F-03 | Fixed | `5ca0f4d` |
| F-04 | Fixed | `6bda190` |
| F-05 | Fixed | `6bda190` |
| F-06 | Atomicity fixed; performance claim retracted, scoring deliberately left on `MainActor` | `7663c94` |
| F-07 | Fixed | `bc62577` |
| F-08 | Fixed | `bc62577` |

Notes where the fix differs from the recommendation:

- **F-02** — the workflow no longer interpolates manual input into a shell, pins `actions/checkout` by SHA, and refuses to release a tag that is not an ancestor of `main`. The tag ruleset and protected environment were then assessed against the actual access model rather than adopted on principle: the repository is public with exactly one collaborator (`m-moravcik`, admin), the release workflow triggers only on `v*.*.*` tag pushes and `workflow_dispatch`, and there is no `pull_request_target`, so fork pull requests never receive secrets. Everyone who can reach the signing secrets is the owner. A tag ruleset restricting tag creation to the owner therefore constrains nobody, and a protected environment can only name that same person as reviewer. The control that does bite a leaked token is the ancestor-of-`main` gate, which is shipped: a stolen token cannot release attacker code by pushing a tag alone. Recommend revisiting if a second maintainer is ever added.
- **F-06** — the batch switcher was built and every matched display now commits in one transaction. The second recommendation, moving matching and scoring off `MainActor`, was measured rather than assumed: scoring three displays against a real 60-mode list takes **86 µs**, about 1/200th of a frame. The cost that actually occupies the UI actor is `CGCompleteDisplayConfiguration`, and moving *that* off the main actor buys nothing observable — the desktop is blanked for the duration of a reconfiguration either way — while requiring CoreGraphics display configuration off-main and `@unchecked Sendable` holes for `CGDisplayMode`. Not done, on purpose.
- Fixing F-06 exposed a defect the audit did not list: the revert snapshot was recorded *before* each switch was attempted and never removed on failure, so Revert offered to restore displays that had never changed and reported a count that included them. Fixed in the same commit.

### Correction to the F-06 rationale

The commit message for `7663c94` justifies the batch with visible flicker and with auto-apply retriggering on intermediate states. Both were asserted, not measured, and neither survives checking:

- **Flicker was never measured and was never reported.** A `CGCompleteDisplayConfiguration` blanks the displays taking part in *that* transaction, so applying three displays one after another blanks each monitor once, staggered — not the whole desktop three times. Whether that is perceptible was not tested, and the app's owner does not recall ever seeing it.
- **Auto-apply cannot fire on an intermediate state.** `DisplayStore.applyRefresh` bumps `setChangeToken` only when a display is added or removed; mode-only changes deliberately do not bump it, precisely so auto-apply does not fight a manual resolution change (`DisplayStore.swift:260-263`). Every intermediate state within a profile apply is mode-only.

What the change is actually worth, and what F-06 should have been argued on:

- **Atomicity.** Committing per display meant a failure on display 3 left displays 1 and 2 already changed, with no rollback and a profile half applied — which the audit itself lists under Impact. One transaction cannot half-apply: a display CoreGraphics refuses is dropped before the commit, and a failed commit changes nothing.
- **The revert-snapshot defect above**, which only became visible once outcomes were patched from a transaction result instead of guessed before the attempt.

The batch is worth keeping on those grounds. The performance half of F-06 remains unsubstantiated and should not be cited as fixed.

## Limitations

- No Instruments trace, long-running energy test, or multi-monitor hardware benchmark was performed. Performance findings are based on confirmed execution paths and build measurements, not claimed runtime latency numbers.
- TCC first-run behavior was not destructively reset on the user's Mac.
- No signing or release secrets were read. GitHub protection-state checks were read-only.
