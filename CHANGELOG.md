# Changelog

All notable changes to VibeRes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/).

## [0.3.3] — 2026-05-06

### Added

- Release pipeline (`.github/workflows/release.yml`) — pushing a `vX.Y.Z` tag now builds VibeRes.app in Release configuration, packages it, attaches the ZIP to a fresh GitHub Release, and syncs the Homebrew formula and cask to the tap repo. Full setup documented in [`.github/RELEASING.md`](.github/RELEASING.md).

## [0.3.2] — 2026-05-06

### Fixed

- Launch at Login icon could show "off" even when the app was registered, after a re-launch from a freshly-built bundle. Cause: `@State` initialiser ran once and we never re-read SMAppService status when the popover re-appeared. Now re-syncs on every popover open via `.task(id:)` and waits one runloop tick after toggling so we read the post-mutation value, not the pre-mutation one.

### Added

- **Homebrew Cask** for the GUI app: `brew install --cask m-moravcik/viberes/viberes-app`. Strips the quarantine attribute on install so Gatekeeper doesn't prompt on first launch. Upgrade later via `brew upgrade --cask`. Cask lives in the existing [m-moravcik/homebrew-viberes](https://github.com/m-moravcik/homebrew-viberes) tap alongside the CLI formula.

## [0.3.1] — 2026-05-06

### Changed

- **Refresh** in the footer now also re-checks GitHub for a newer release. Display refresh is sync (fast); the update check fires off in the background, surfacing a banner at the next redraw if a newer version exists. One gesture, both data sources fresh.

## [0.3.0] — 2026-05-06

### Added

- **Update checker** — VibeRes pings GitHub Releases once a day and shows a green banner at the top of the popover when a newer version exists. Click the banner to open the release page in Safari. The footer also has a manual "Check for Updates / Up to date / Update available" row that triggers the same check on demand.
- Footer label adapts to checker state: idle → "Check for Updates", in-flight → "Checking…", post-check → "Up to date" or "Update available".

### Changed

- Trimmed popover padding — removed redundant top/bottom whitespace around `RootView` so the content hugs the popover edges (~25pt saved vertically).
- Removed the standalone `info.circle` icon next to the **PROFILES** label. It looked clickable but only fired on hover; the same tooltip is now attached to the **PROFILES** label itself.

### Tests

- 73 → 89 (+16):
  - `UpdateCheckerTests` (8) — version comparison: patch / minor / major bumps, equal versions, older versions, pre-release suffix, mismatched component counts, garbage input.
  - `ResolutionSpecBoundsTests` (8) — CLI parser bounds: zero / negative / overlarge dimensions and refresh rates rejected; boundary values 1 and 16384 still accepted.

## [0.2.0] — 2026-05-06

### Added

- Profile editing — right-click a pill for **Update with current setup**, **Make flexible / Make specific**, **Rename…**, **Delete**.
- Profile types: specific monitor (EDID-locked), any external monitor (flexible), or built-in only.
- CLI commands: `viberes profile show <name>`, `viberes profile update <name>`, `viberes profile flex <name>`, `viberes profile save --any-external`, `viberes profile save --only <display>...`.
- Apply outcome feedback — green for exact match, orange for fallback, red for skipped/missing display.
- Inline name prompt for save and rename (replaces unreliable `.alert` inside `MenuBarExtra`).
- "Now" current-mode card at the top of the per-display detail.
- Segmented refresh-rate selector replacing the previous chip group.
- FlowLayout for profile pills so they wrap to the next row instead of overflowing horizontally.
- Accessibility labels on icon-only controls; decorative icons hidden from VoiceOver.
- Pre-bucketed `ResolutionGroup`s cached in `DisplayInfo` so the menu doesn't re-bucket on every render.
- DisplayNamer abstraction so the Core layer no longer imports AppKit; the GUI installs an NSScreen-backed resolver at startup.

### Changed

- `Looks like / Pixel-perfect` toggle renamed to **Scaled / Native** to match Apple's vocabulary in System Settings.
- Footer redesigned as inline native-style menu rows (icon · label · ⌘shortcut).
- Detail view shows the full mode list directly — removed the "Show all" expander.
- Profile apply now runs on a background task so the popover stays responsive on click.
- File permissions on `profiles.json` set to `0o600` (owner-only).
- Removed `NSScreenCaptureUsageDescription` from `Info.plist` until the live screenshot preview ships.
- README rewritten as a focused user manual; screenshots inline.
- CI installs `xcbeautify` explicitly instead of relying on the runner image.

### Fixed

- NTSC drop-frame refresh-rate variants (59.94, 47.95) deduplicated against integer counterparts (60, 48).
- Popover used to drift below the menu-bar item after a display reconfiguration; reset NSPanel frame on `CGDisplayRegisterReconfigurationCallback`.
- Right-clicking a profile pill no longer dismisses the popover (filtered `NSWindow.didResignKeyNotification` while a menu is tracking).
- "Launch at Login" icon now updates immediately when toggled instead of requiring a popover restart.
- `var p` → `let p` warning in `ProfileEditTests`.
- CI smoke test could not locate the CLI binary; switched to an explicit `-derivedDataPath ./build`.
- Bounds on profile names: control characters / null bytes stripped, length capped at 128.
- ResolutionSpec parser in the CLI rejects out-of-range dimensions (>16384) and refresh rates (>1000).

### Tests

- Coverage expanded from 52 to 73 (+21):
  - `ApplyOutcomeTests` — every `ApplyOutcome.Status` branch and `summary` formatting.
  - `ProfileEdgeCaseTests` — `humanSummary` for 1/3/empty entries, name sanitiser (control chars, length cap, empty rejection), Profile.Entry decoder bounds (negative width clamped to 1, 99999 → 16384, 1MB displayName → 256 chars).
  - `ResolutionGroupTests` — id format, 0Hz mode handling, descending sort guarantees, HiDPI boundary cases (equal pixel ratio, undersized pixelWidth).

## [0.1.0] — 2026-05-06

Initial release. Native SwiftUI menubar resolution switcher targeting macOS 26 Tahoe with multi-display profiles, Shortcuts.app integration, and a sibling CLI (`viberes`).
