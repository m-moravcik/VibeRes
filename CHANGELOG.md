# Changelog

All notable changes to VibeRes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

## [0.1.0] — 2026-05-06

Initial release. Native SwiftUI menubar resolution switcher targeting macOS 26 Tahoe with multi-display profiles, Shortcuts.app integration, and a sibling CLI (`viberes`).
