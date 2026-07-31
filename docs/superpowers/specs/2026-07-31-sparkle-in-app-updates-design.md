# In-app updates via Sparkle

**Status:** approved, not implemented
**Date:** 2026-07-31 (rewritten the same day after an adversarial review found
four blockers in the first draft; the corrections are called out inline so the
same mistakes are not reintroduced)

## Goal

Replace the manual update path with a one-click in-app update, keeping dialogs
off the happy path.

Today: banner → "Open release" → browser → download ZIP → unzip → drag to
`/Applications` → confirm replace → quit the still-running old copy → relaunch.

After: Sparkle checks and downloads in the background, and the popover shows one
row — "Update ready, restart now?". One click installs and relaunches.

## Non-goals

- Delta updates. `Sparkle.framework` is 3.0 MB against a 1.8 MB app, so deltas
  would mostly ship the framework; not worth the appcast machinery either way.
- Beta channels. Sparkle supports them via `sparkle:channel`; add when there is
  a beta to ship.
- Installing without consent. The user always decides when the restart happens.
  Downloading ahead of time is silent; installing is not.
- **A dialog-free updater.** This is not achievable and pretending otherwise was
  the first draft's central error. See "What the user can still see".

## Prior art, and where it is wrong

The design follows [`steipete/CodexBar`](https://github.com/steipete/CodexBar)
(MIT): the protocol/factory split, the delegate-driven "update ready" state, and
the install-origin gates. We write our own implementation; `Updater.swift`
credits the source.

Two things are **not** copied, because reviewing CodexBar against Sparkle's own
documentation showed its code diverging from it:

- It mirrors the auto-update preference into its own `UserDefaults` key.
  `SPUUpdater.h:198` says plainly: *"developers shouldn't maintain an additional
  user default for this property … Do not always set it on launch unless you
  want to ignore the user's preference."*
- `InstallOrigin.isHomebrewCask` tests whether the running bundle's path
  contains `/Caskroom/`. It never does — see gate 2.

## Architecture

A protocol with two implementations and a factory. The UI never learns whether
Sparkle exists.

```swift
@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    var updateStatus: UpdateStatus { get }
    func checkForUpdates(_ sender: Any?)
    func installUpdate()
}
```

- `SparkleUpdaterController` — wraps `SPUStandardUpdaterController`, conforms to
  **both** `SPUUpdaterDelegate` and `SPUStandardUserDriverDelegate`. Compiled
  only under `#if canImport(Sparkle) && ENABLE_SPARKLE`.
- `DisabledUpdaterController` — no-op carrying an `unavailableReason` the
  Settings UI shows verbatim, so a disabled updater explains itself.
- `UpdateStatus` — `@Observable`, holds `isUpdateReady`; drives the popover row.

`ENABLE_SPARKLE` is a `SWIFT_ACTIVE_COMPILATION_CONDITIONS` entry set for Release
only. `#if canImport(Sparkle) && ENABLE_SPARKLE` is valid Swift and CodexBar
compiles the same construct.

### File placement

`Updater.swift` goes in `VibeRes/UI/`, **not** `VibeRes/Core/`. `project.yml:118`
compiles `VibeRes/Core` into the `viberes` command-line tool, which has no
bundle, no Sparkle, and `SWIFT_STRICT_CONCURRENCY: minimal`. This is the same
constraint that keeps `ApplyOutcome.summary` and `Failure.userFacingDescription`
English.

### Concurrency

`SPUUpdaterDelegate` is declared `NS_SWIFT_UI_ACTOR` (`SPUUpdaterDelegate.h:69`)
as of Sparkle 2.9, so in Swift the whole protocol is `@MainActor`. Implement the
callbacks as plain main-actor methods.

Do **not** mark them `nonisolated` and hop via `Task { @MainActor in }`, which is
what CodexBar does as a pre-2.9 leftover. Beyond being unnecessary, it is a bug:
`willInstallUpdateOnQuit` must return `Bool` synchronously while the state change
happens in a detached task, and separate tasks have no ordering guarantee — so
`failedToDownloadUpdate` setting `isUpdateReady = false` can land after
`willInstallUpdateOnQuit` set it true. That is exactly the stale-row bug the
delegate table below exists to prevent. No `@unchecked Sendable` box is needed.

### Install-origin gates

`makeUpdaterController()` decides which implementation to build, in order:

| Gate | Condition | Result |
| --- | --- | --- |
| 1 | Not signed with our Developer ID | Disabled — "Updates unavailable in this build." |
| 2 | Installed by Homebrew cask | Disabled — "Updates managed by Homebrew. Run: `brew upgrade --cask m-moravcik/viberes/viberes-app`" |
| 3 | Bundle path extension is not `.app` | Disabled — "Updates unavailable in this build." |
| 4 | Otherwise | `SparkleUpdaterController` |

**Gate 1 is the security boundary, and it now runs first.** An updater that
downloads and executes a binary without verifying who signed it is remote code
execution; a debug or ad-hoc build must never self-update. The check requires a
`Developer ID Application` authority for team `7TM9VA58W5`. Sparkle's EdDSA
signature on the downloaded archive is a second, independent check — neither
replaces the other.

Ordering is not a security matter (gates 1–3 all return the same disabled
controller) but a truthfulness one: with the Homebrew check first, an unsigned
build sitting near a Caskroom path would be told to run `brew upgrade` for
something Homebrew never installed.

**Gate 2 must not use path containment.** A cask `app` artifact is
`Cask::Artifact::App < Moved`: Homebrew **moves** the bundle to `/Applications`
and leaves a symlink in the Caskroom pointing at it. Verified locally:

```
/opt/homebrew/Caskroom/1password/8.12.12/1Password.app -> /Applications/1Password.app
```

So `Bundle.main.bundleURL.resolvingSymlinksInPath()` for a cask install resolves
to `/Applications/…`, which contains no `/Caskroom/` — the check is inverted, not
merely brittle, and is always false. CodexBar's own test suite hides this by
feeding the function a synthetic Caskroom path.

Detect it the other way round: enumerate `Caskroom/viberes-app/*/VibeRes.app`
under `HOMEBREW_PREFIX`, `/opt/homebrew` and `/usr/local`, `realpath` each, and
compare against the resolved running bundle.

Consequence if the gate fails open: cask users self-update through Sparkle and
the next `brew upgrade --cask` overwrites the app with whatever the tap pins —
which can be an **older** version if the tap lags. A silent downgrade, not just
a redundant reinstall.

**The cask therefore does not get `auto_updates true`.** With Sparkle disabled
for cask installs, marking the cask self-updating would leave nobody updating it.

## Sparkle configuration

```
SUFeedURL                 <see "Feed hosting">
SUPublicEDKey             <generated>
SUEnableAutomaticChecks   true
SUAutomaticallyUpdate     true
SUScheduledCheckInterval  86400
SURequireSignedFeed       true
```

All are real Sparkle 2.x keys (`SUConstants.m`). There is no
`SUAutomaticallyChecksForUpdates` key. Values must be YAML booleans/numbers in
`project.yml`'s `info.properties`, not strings — Sparkle 2.9 validates types when
reading Info.plist entries.

**`SUAutomaticallyUpdate` is load-bearing and was missing from the first draft.**
`SPUUpdater.h:232`: *"By default, updates are not automatically downloaded."* And
`:235`: the initial value normally derives from that plist key, *"This is not done
if `SUEnableAutomaticChecks` is set in the Info.plist however."* Since
`willInstallUpdateOnQuit` only fires after an **automatic** download, omitting it
means `isUpdateReady` never flips, the popover row never appears, and nothing
logs an error.

The Settings toggle binds **directly** to
`updater.automaticallyChecksForUpdates` and `automaticallyDownloadsUpdates`,
which Sparkle persists itself. No `VibeRes.autoUpdateEnabled` key.

### Feed hosting

`https://github.com/m-moravcik/VibeRes/releases/latest/download/appcast.xml`
works mechanically — verified: `302` to the newest release's asset with
`cache-control: no-cache`, and Sparkle follows redirects.

It has one failure mode that must be handled: if any later release publishes
without the appcast asset, that URL 404s and **every client's update check fails
permanently** until the next successful release. A per-release pipeline check
cannot prevent a future release from omitting it.

Therefore: keep `appcast.xml` on a stable path that a bad release cannot break —
a file committed on `main`, served from `raw.githubusercontent.com`, which is
also what CodexBar actually does (`Scripts/package_app.sh:415`). The first draft
credited CodexBar for the releases URL; it does not use it.

A single-entry appcast is fine — Sparkle picks the best item.

### Version comparison

Sparkle compares `sparkle:version`, which is `CFBundleVersion`, i.e.
`CURRENT_PROJECT_VERSION`. `sparkle:shortVersionString` is display only.

`release.yml` verifies only `MARKETING_VERSION` against the tag, and nothing
anywhere checks `CURRENT_PROJECT_VERSION`. A forgotten build-number bump makes
every client see "no update" with zero diagnostics, so add a release guard that
`CURRENT_PROJECT_VERSION` strictly increased since the previous tag.

### What the user can still see

The first draft claimed returning `true` from
`updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` suppresses
Sparkle's UI. It does not. `SPUUpdaterDelegate.h:433`: *"In either case Sparkle
will always attempt to install the update when the app terminates."* And `:430`:
returning true *"stalls the current update cycle and prevents future update
cycles from running"* — so an ignored row means VibeRes learns about no further
release until relaunch.

CodexBar's own documentation says it too (`docs/sparkle.md:17`): *"LSUIElement:
works; updater window will show when checking."* That sentence was in front of
the first draft's author and was read past.

What the hook actually does is take over the *timing* of an install-on-quit,
which is what turns "installs whenever you happen to quit" into "installs when
you click the row" — the point for a menu-bar app that runs for weeks.

Dialogs that remain, and must be handled rather than denied:

| Situation | What appears | Handling |
| --- | --- | --- |
| Manual "Check for Updates" | Sparkle progress, then an update or no-update alert (`SPUUpdater.h:95`) | `NSApp.activate(ignoringOtherApps: true)` first — VibeRes is `LSUIElement`, so alerts otherwise open behind everything with no Dock icon to click |
| App has not quit for a long time | Sparkle's impatient reminder (`SUScheduledImpatientCheckInterval`) | Implement `SPUStandardUserDriverDelegate.supportsGentleScheduledUpdateReminders`; Sparkle's docs say background apps *must* implement it |
| `/Applications` not user-writable | Authorization prompt | Unavoidable; leave it |
| Critical or information-only update | Forced presentation | Unavoidable by design |

So implement `SPUStandardUserDriverDelegate` with
`supportsGentleScheduledUpdateReminders` and
`standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)`
returning `false`, plus `standardUserDriverWillHandleShowingUpdate` to activate
for user-initiated checks.

### Delegate state table

`isUpdateReady` drives the popover row and must be cleared on every failure path.
Method names are the real selectors — the first draft wrote
`userDidMake choice:`, a parameter-label fragment, which is a tell that the table
was transcribed rather than checked against the header.

| Callback | `isUpdateReady` |
| --- | --- |
| `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` | `true`, store the block |
| `updater(_:failedToDownloadUpdate:error:)` | `false` |
| `userDidCancelDownload(_:)` | `false` |
| `updater(_:didAbortWithError:)` | `false` |
| `updater(_:userDidMakeChoice:forUpdate:state:)` — `.install` / `.skip` | `false` |
| `updater(_:userDidMakeChoice:forUpdate:state:)` — `.dismiss` | keep if stage is `.downloaded` |
| `updater(_:didFinishUpdateCycleForUpdateCheck:error:)` | end of every cycle including `SUNoUpdateError` — the only place Settings can stop a spinner |

`UpdateStatus` is in-memory, so after a relaunch the row disappears for up to 24 h
even though the update is already downloaded. Acceptable; noted so it is not
mistaken for a bug.

### Interaction with Revert

`RevertHistory` is explicitly not persisted across restarts. The Revert row lives
in the same footer as the proposed "Update ready" row, and installing an update
quits and relaunches — so a user who just applied a bad resolution can reach for
the footer, hit the wrong row, and lose their only escape hatch.

Gate `installUpdate()` on `!store.revert.canRevert`, or consume the revert first,
and suppress install-on-quit while a revert is pending.

## Build and signing impact

`Sparkle.framework` (2.9.4, inspected) contains five signable items: `Sparkle`,
`Autoupdate` (a plain Mach-O, **not** an `.app` as the first draft said),
`Updater.app`, `XPCServices/Downloader.xpc`, `XPCServices/Installer.xpc`. The
contents do not vary with sandboxing — the XPC services are merely unused when
not sandboxed. All ship **ad-hoc signed**.

### Blocker: hardened runtime is not inert under ad-hoc signing

`project.yml` used to claim `ENABLE_HARDENED_RUNTIME` was "inert under ad-hoc
signing, so it only takes effect on the release build". Verified false, and the
comment is already corrected in commit `756d063`:

```
codesign --sign - --options runtime  →  flags=0x10002(adhoc,runtime)
```

The hardened runtime, and therefore library validation, is active in **every**
configuration. Library validation refuses to load an ad-hoc-signed framework, so
embedding Sparkle breaks every local and CI build, not just releases —
`ci.yml`'s `build-app` job builds Release ad-hoc and would hit it. A
Release-only `ENABLE_SPARKLE` does not help: it gates code, not linking, and
XcodeGen has no per-configuration dependency filter.

Required: `ENABLE_HARDENED_RUNTIME: NO` for the Debug configuration, or a
Debug-only entitlements file with
`com.apple.security.cs.disable-library-validation`. Note
`scripts/release-signed.sh:221` lists that entitlement as forbidden — that guard
is Release-only, so the two are compatible, but the spec says so explicitly to
stop someone "fixing" the contradiction later. The repo currently has no
`.entitlements` file at all.

Debug builds do still carry `Sparkle.framework`; only the call sites compile out.

### Nested signing

Sparkle's documentation recommends `xcodebuild archive` + `-exportArchive`
because *"Xcode's Archive Organizer will ensure Sparkle's helper tools are code
signed properly for distribution"*. `scripts/release-signed.sh` uses
`clean build`.

Whether Xcode's embed-and-sign phase re-signs all five nested items with the
Developer ID under plain `xcodebuild build` is **unverified** and needs a real
notarization to settle. Either way the release script must assert it, because
`codesign --verify --deep --strict` **accepts a valid ad-hoc signature** — so the
existing verification passes while notarization rejects, which is precisely the
late-remote-failure shape of the 0.8.2 coverage-entitlement incident.

`release-signed.sh` currently runs one non-recursive `codesign -d` on the
top-level bundle (`:218`) and checks authority, timestamp and runtime only for
`$APP` (`:204-212`). It must enumerate every nested Mach-O and bundle under
`Contents` and assert, per target: no forbidden entitlements, `Authority=Developer
ID Application: … (7TM9VA58W5)`, `Timestamp=`, and `flags=…runtime`.

The first draft cited CodexBar's `sparkle_signing_paths.sh` as evidence that
nested signing is hard. That script exists because `package_app.sh` hand-builds
the `.app` from SwiftPM output and signs each nested target from an enumerated
list — CodexBar has no Xcode app target and therefore no embed phase at all.
VibeRes does. The argument does not transfer; the real evidence is the ad-hoc
signatures above.

## Release pipeline

After notarization succeeds:

1. `sign_update` the notarized ZIP with the Ed25519 key.
2. Generate a single-entry `appcast.xml`, release notes as HTML from the matching
   `CHANGELOG.md` section.
3. **Sign the feed** as well (`sign_update` embeds the signature in the XML;
   Sparkle 2.9 added feed signing) and set `SURequireSignedFeed`. Without it an
   attacker who can substitute the feed cannot ship a malicious binary — the
   enclosure signature blocks that — but can pin users to an older validly
   signed release. Same key, same tool, one extra line.
4. Commit the appcast to `main` (see "Feed hosting").
5. Verify with `sign_update --verify` rather than grepping for the presence of a
   `sparkle:edSignature` attribute.

New secret `SPARKLE_EDDSA_PRIVATE_KEY`, produced by `generate_keys -x`, which
writes to a file and avoids the keychain export that the permission layer blocks.
Stored in 1Password beside the Developer ID.

**Resolved** (the first draft deferred this): the SPM distribution
`Sparkle-for-Swift-Package-Manager.zip` contains `bin/sign_update`,
`generate_appcast`, `generate_keys`, `BinaryDelta`. Fetching it inside
DerivedData is a fragile path, so download the zip directly using the version and
checksum published in Sparkle's own `Package.swift` — 2.9.4,
`cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0`. Homebrew is
not an option: its `sparkle` cask is deprecated for failing Gatekeeper and is
disabled from 2026-09-01.

`ENABLE_USER_SCRIPT_SANDBOXING: YES` (`project.yml:26`) will block a manual
codesign shell-script phase if one turns out to be needed.

## Testing

Sparkle's flow is not meaningfully unit-testable. What is:

- **The install-origin gates.** Extract a pure
  `UpdaterGate.decide(bundleURL:isDeveloperIDSigned:caskroomRoots:) -> Decision`,
  compiled in **all** configurations, with `makeUpdaterController()` as a thin
  adapter supplying `Bundle.main` and the real `SecStaticCode` check.
  Without this the test plan cannot run at all: tests execute in Debug, so with
  `ENABLE_SPARKLE` Release-only the `#else` factory returns
  `DisabledUpdaterController()` unconditionally, and the test host is ad-hoc
  signed so gate 1 would fail regardless.
- `UpdateStatus` transitions for each row of the delegate table.
- Info.plist carries the intended keys with the intended types.
- A pipeline check that the published feed verifies against the public key.

## Removals

- `VibeRes/Core/UpdateChecker.swift`, `VibeResVersion`, and
  `VibeResTests/UpdateCheckerTests.swift` — Sparkle does its own comparison and
  `grep` confirms no other caller. Removes 8 tests; the gate tests must more than
  replace them, since which build may self-update is a security decision where
  loose-semver comparison was not.
- The `VibeRes.UpdateChecker.*` `UserDefaults` keys become inert. No migration.

## UI changes

- **Popover footer** keeps a row, driven by `updateStatus.isUpdateReady`.
- **Settings → Updates** gets a real toggle, "Check for Updates Now", and the
  `unavailableReason` text when `isAvailable` is false.
- Onboarding copy already promises "update preferences" in Settings. The current
  Updates tab ships version info and a working "Check now"; what is missing is
  the toggle. Both the English and German strings need updating if the wording
  changes.

## Rollout

**The first Sparkle release cannot be delivered by Sparkle.** Users on 0.8.2 have
no updater, so that one upgrade is manual, or `brew upgrade --cask`. Automatic
from the release after.

## Risks

| Risk | Mitigation |
| --- | --- |
| Nested signing fails notarization | Assert authority/timestamp/runtime per nested target before tagging; fall back to `archive` + `-exportArchive` |
| Debug builds break on library validation | Debug `ENABLE_HARDENED_RUNTIME: NO` or a Debug entitlements file — must land in the same change as the dependency |
| Homebrew gate fails open | Silent downgrade on the next `brew upgrade`; the gate needs the Caskroom-enumeration test |
| Feed 404 breaks all clients permanently | Stable feed path on `main`, not a per-release asset |
| Build number not bumped | Release guard on `CURRENT_PROJECT_VERSION` monotonicity |
| EdDSA key lost | Sparkle can rotate the signing certificate **or** the EdDSA key, not both at once; losing the key during a certificate renewal forces every user to reinstall manually |
