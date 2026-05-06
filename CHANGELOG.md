# Changelog

All notable changes to VibeRes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/).

## [0.4.2] — 2026-05-06

### Changed

- **Live Preview self-detects a TCC drift loop** and gives up gracefully. After a `brew upgrade --cask` macOS sometimes ends up with multiple stale Screen Recording grant entries (ad-hoc signed bundles cycle their code-signature hash on every replacement). The classic symptom: every hover re-prompts even though Screen Recording is checked in System Settings. `DesktopCapture` now tracks consecutive denials, flips to a `.stuckLoop` status after the second failed grant, and stops calling ScreenCaptureKit for the rest of the session — the geometric preview takes over silently. Toggling Live Preview off and back on resets the counter.
- README has a Troubleshooting section pointing at `tccutil reset ScreenCapture sk.moravcik.VibeRes` for users who want to break the loop on the spot.

## [0.4.1] — 2026-05-06

### Fixed

- CI was building VibeRes.app fine but Build CLI (Release) failed because the new `.alreadyApplied` outcome status was not handled in `viberes profile apply`'s switch. Added the missing case (renders as `=` next to the display name in CLI output).
- Live Preview was re-prompting for Screen Recording permission on every hover. Cause: `SCShareableContent.current` re-evaluates TCC on each call, and on ad-hoc signed builds the grant occasionally appears to TCC as "different app" between accesses, triggering the prompt again. Now we cache the permission verdict per process, switch to `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)` (more stable on macOS 26), and only request permission once via `CGRequestScreenCaptureAccess`. Toggling Live Preview off and back on resets the cache so a stale verdict from a previous session is not held against the user.

## [0.4.0] — 2026-05-06

### Added

- **Auto-apply matching profile on display change.** When you plug or unplug a monitor, VibeRes finds the saved profile that best fits the new layout and applies it silently. Mode-only changes (you manually pick a different resolution) don't trigger this — it's specifically for add/remove events. Toggle in the footer; on by default.
- **Specificity hierarchy** when several profiles match the same setup: `.edid` external entries (3 points, locked to a specific monitor) > `.builtIn` (2 points) > `.anyExternal` (1 point). So if both "Work" (Built-in EDID + Q3279 EDID, score 6) and "Presentation" (Built-in EDID + any external, score 3) match the current setup, Work wins because it's the more precise match. Recency breaks ties at equal score.
- **Live screenshot preview on hover.** Opt-in feature — turn it on in the footer to grant Screen Recording permission once. Then hovering a non-current resolution shows a real desktop snapshot scaled into the proposed mode's frame. Off by default so the macOS permission prompt only fires for users who asked for the feature.
- New `Preferences` store backing both toggles via `UserDefaults`.

### Changed

- Apply behaviour skips the no-op case. When the chosen mode is already the display's current mode, `ResolutionSwitcher.apply` is no longer called and the entry reports `.alreadyApplied`. Auto-apply stays silent if every display is already at its target; manual clicks surface a quiet *"Already at the saved settings."* note.

### Tests

- 89 → 97 (+8): `AutoApplyTests` for specificity ranking and profile-level score sums; `PreferencesTests` for defaults and persistence.

## [0.3.5] — 2026-05-06

### Changed

- App icon re-rendered through `librsvg` instead of `sips`. The first cut had visible gradient banding, blurry drop shadows, and rough edges at small sizes — `sips`'s CoreSVG backend doesn't fully implement SVG filter primitives. Now each `.iconset` size is rendered directly from the source SVG at its target resolution. Cleaner across the board, especially the 16×16 and 32×32 menu/Finder thumbnails.

## [0.3.4] — 2026-05-06

### Added

- App icon. Squircle with a violet → teal gradient, two stacked monitor screens with subtle pixel grids — visualises the multi-display, multi-resolution premise. Source SVG lives in `icon-build/icon.svg`; rendered to a full `.icns` set wired through `Assets.xcassets/AppIcon.appiconset/`. Surfaces in the Dock during About panel, in `Cmd+Tab`, and on the Cask install in Launchpad.

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
