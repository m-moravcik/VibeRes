# In-app updates via Sparkle

**Status:** approved, not implemented
**Date:** 2026-07-31

## Goal

Replace the current manual update path with a one-click in-app update, without
subjecting a menu-bar app to modal update dialogs.

Today a user who wants to update goes: banner → "Open release" → browser →
download ZIP → unzip → drag to `/Applications` → confirm replace → quit the
still-running old copy → relaunch. Eight steps, and replacing a running app is
where people give up.

After this change: Sparkle checks and downloads in the background, and the
popover shows one row — "Update ready, restart now?". One click installs and
relaunches.

## Non-goals

- Delta updates. The app is 1.8 MB; the machinery is not worth it.
- Beta/pre-release channels. Sparkle supports them via `sparkle:channel`; add
  later if there is ever a beta to ship.
- Silent installation without consent. The user always decides *when* the
  restart happens, because a restart mid-session on a tool that changes screen
  resolution is a bad surprise.

## Prior art

The design follows [`steipete/CodexBar`](https://github.com/steipete/CodexBar)
(MIT), a menu-bar app with the same constraints. Its approach is adopted
deliberately rather than reinvented: the protocol/factory split, the
delegate-driven "update ready" state, and the four install-origin gates below
are all its ideas. We write our own implementation; the `Updater.swift` header
comment credits the source. Nothing is transcribed verbatim.

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
  `SPUUpdaterDelegate`. Compiled only under `#if canImport(Sparkle) && ENABLE_SPARKLE`.
- `DisabledUpdaterController` — no-op, carries an `unavailableReason` string the
  Settings UI displays verbatim.
- `UpdateStatus` — `@Observable`, holds `isUpdateReady`. This is what drives the
  popover row.

`unavailableReason` matters: when updates are off, the user is told *why* and
what to do instead, rather than seeing a dead control.

### Install-origin gates

`makeUpdaterController()` decides which implementation to build, in order:

| Gate | Condition | Result |
| --- | --- | --- |
| 1 | Bundle path extension is not `.app` | Disabled — "Updates unavailable in this build." |
| 2 | Installed by Homebrew cask | Disabled — "Updates managed by Homebrew. Run: `brew upgrade --cask m-moravcik/viberes/viberes-app`" |
| 3 | Not signed with our Developer ID | Disabled — "Updates unavailable in this build." |
| 4 | Otherwise | `SparkleUpdaterController` |

**Gate 3 is the security boundary.** An updater that downloads and executes a
binary without verifying who signed it is remote code execution. A debug or
ad-hoc-signed build must never self-update. The check verifies the running
bundle carries a `Developer ID Application` authority for team `7TM9VA58W5`.
Sparkle's EdDSA appcast signature is a second, independent check on the
downloaded archive — neither replaces the other.

**Gate 2 keeps Homebrew authoritative** for users who installed that way. The
cask therefore does **not** get `auto_updates true`: with Sparkle disabled under
Homebrew and `brew upgrade` skipping the cask, nothing would ever update it.

## Sparkle configuration

```
SUFeedURL                 https://github.com/m-moravcik/VibeRes/releases/latest/download/appcast.xml
SUPublicEDKey             <generated>
SUEnableAutomaticChecks   YES
SUScheduledCheckInterval  86400
```

`automaticallyChecksForUpdates` and `automaticallyDownloadsUpdates` are both
bound to one user preference, `VibeRes.autoUpdateEnabled`, defaulting to `true`
on first launch. Downloading ahead of time is what makes the install click
instant.

`releases/latest/download/appcast.xml` is a stable GitHub URL that always
redirects to the newest release's asset, so no GitHub Pages site, no extra
branch, and no separate publish step.

### Suppressing the dialogs

Sparkle would normally show its own window. Returning `true` from
`updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` tells Sparkle
the delegate will time the installation itself, which suppresses that UI. The
handler is stored and `updateStatus.isUpdateReady` flips to `true`; the popover
row calls the stored handler when clicked.

Install-on-quit alone would be wrong here: a `LSUIElement` menu-bar app in login
items runs for weeks, so a queued update would never install. Converting the
hook into a user-triggered install is the point.

The delegate must clear `isUpdateReady` on every failure path, or the row keeps
advertising an update that is not there:

| Delegate callback | `isUpdateReady` |
| --- | --- |
| `willInstallUpdateOnQuit` | `true` |
| `failedToDownloadUpdate` | `false` |
| `userDidCancelDownload` | `false` |
| `didAbortWithError` | `false` |
| `userDidMake choice:` `.install` / `.skip` | `false` |
| `userDidMake choice:` `.dismiss` | keep, if stage is `.downloaded` |

Under `SWIFT_STRICT_CONCURRENCY: complete` these callbacks are `nonisolated` and
hop to the main actor via `Task { @MainActor in }`. The install closure crosses
that boundary inside a small `@unchecked Sendable` box — required, not stylistic.

## UI changes

- **Popover footer** keeps a row, now driven by `updateStatus.isUpdateReady`
  instead of our own GitHub polling. Label: "Update ready, restart now?".
- **Settings → Updates** gets a real toggle for automatic updates, a "Check for
  Updates Now" button, and, when `isAvailable` is false, the
  `unavailableReason` text. This fixes existing onboarding copy that already
  promises update preferences in Settings — a promise the current build does not
  keep.

## Removals

- `VibeRes/Core/UpdateChecker.swift` — Sparkle subsumes checking, comparison,
  caching, and the release URL.
- `VibeResVersion` and `VibeResTests/UpdateCheckerTests.swift` — Sparkle does its
  own version comparison, and `grep` confirms no other caller. This removes 8
  tests (119 → 111). The new gate tests below must more than replace them: which
  build is allowed to self-update is a security decision, where loose-semver
  comparison was not.
- The GitHub API poll, and its `UserDefaults` keys
  (`VibeRes.UpdateChecker.*`). No migration: the keys become inert.

## Build and signing impact

Sparkle embeds `Sparkle.framework`, which for a non-sandboxed app contains
`Autoupdate.app` and `Updater.app`. The bundle stops being a single Mach-O, and
nested code signing is where notarization rejections come from.

Consequences:

1. `scripts/release-signed.sh` currently inspects entitlements on the top-level
   bundle only. It must walk nested code too, or a debug entitlement in a helper
   will slip through exactly as coverage instrumentation slipped through before
   0.8.2.
2. `codesign --verify --deep --strict` already covers nested code; keep it.
3. The framework's `Versions/Current` symlink needs careful resolution when
   signing. CodexBar ships a dedicated script for this, including a
   path-traversal guard — evidence that it is not a one-liner.
4. `ENABLE_SPARKLE` is set for Release only, so debug builds carry no updater.

## Release pipeline

Added to `release.yml` after notarization succeeds:

1. Sign the notarized ZIP with the Ed25519 key (`sign_update`).
2. Generate a single-entry `appcast.xml`, embedding release notes as HTML
   converted from the matching `CHANGELOG.md` section.
3. Attach `appcast.xml` to the GitHub Release alongside the ZIP.
4. Assert the appcast exists and contains a `sparkle:edSignature`, so a release
   can never publish a feed Sparkle will reject.

New secret: `SPARKLE_EDDSA_PRIVATE_KEY`, generated with `generate_keys -x`,
which writes the key to a file directly and avoids exporting from the keychain.
Stored in 1Password alongside the Developer ID.

**Unresolved:** whether `sign_update` ships inside the Sparkle SwiftPM artifact
bundle, or must be fetched separately. If separate, the download must be
version-pinned and checksum-verified — Sparkle's Homebrew cask is deprecated for
failing Gatekeeper and is disabled from 2026-09-01, so it is not an option.
Resolve during implementation before writing the workflow step.

## Testing

Sparkle's own flow is not meaningfully unit-testable. What is:

- The install-origin gates: given a bundle path and signing state, the factory
  returns the expected implementation and `unavailableReason`. This is the
  security-critical logic and deserves direct coverage.
- `UpdateStatus` transitions for each delegate callback in the table above.
- Info.plist carries the intended policy keys and a well-formed `SUFeedURL`.
- Pipeline check that the published appcast has a signature.

## Rollout

**The first Sparkle release cannot be delivered by Sparkle.** Users on 0.8.2
have no updater, so that one upgrade is manual, or `brew upgrade --cask` for
cask users. From the following release onward it is automatic.

## Risks

| Risk | Mitigation |
| --- | --- |
| Nested signing breaks notarization | Extend the entitlements check to nested code; verify with a real notarization before tagging |
| Third-party binary in the release path | Pin the version and verify its checksum |
| Homebrew detection is path-based and brittle | Failing the check falls back to Sparkle enabled, which still verifies signatures; the cost is a possible double-update, not a security hole |
| Second private key to manage | 1Password plus a GitHub secret, same handling as the Developer ID |
