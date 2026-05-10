# Changelog

All notable changes to VibeRes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/).

## [0.8.0] — 2026-05-10

**Highlights:** Apply preview on hover, partial-match warnings for multi-monitor setups, and impossible-to-misconfigure flexible profiles.

### Added

- **Hover preview on profile pills.** Move the pointer over any profile and a tooltip appears showing exactly what an apply would do — per display, with one of five outcomes: will apply exactly, will fall back to the closest available mode, already at the saved mode, will skip (not connected), or no usable mode. Lets you see what will happen before you click instead of finding out after.
- **Display set classification before apply.** When you click a profile, VibeRes first checks how well it fits the currently-connected displays. A clean match applies immediately. A partial match (some saved displays missing), superset match (extra monitors connected), or disjoint set (nothing matches) opens an inline confirmation panel listing every change with an Apply Anyway / Cancel choice. Auto-apply (after a monitor is plugged or unplugged) keeps its silent flow — the panel only appears for manual clicks.
- **Edit form mode picker covers every connected external** when an entry is `.anyExternal`. Previously the picker only listed modes from the first matched monitor, so on a dual-external setup you couldn't pick a resolution that only the second monitor supported. The picker now unions all external monitors' modes and deduplicates, so a flexible "Presentation" entry can target 2560×1440 even if one of the externals only does 1920×1080 (at apply time the lower-spec monitor falls back to its closest available mode).

### Changed

- **Profiles can have at most one "any external" entry.** A profile with two flexible externals at runtime applied both modes to *every* external in sequence — the last entry won after the earlier ones briefly took effect, causing visible flicker and order-dependent results. The Save and Edit forms now disable the second "Match any external monitor" checkbox automatically, and the store rejects any save that slips through with a clear error. The CLI's `viberes profile save --any-external` likewise exits with an explanation when used on more than one monitor.
- `ProfileStore.captureCurrent` and `ProfileStore.replaceEntries` now return a `SaveResult` enum (`saved | rejectedEmpty | rejectedMultipleAnyExternal`) so callers can distinguish a save from a refused one. Internal API change only — JSON profiles on disk are untouched.

### Tests

- 104 → 110 (+6): `DisplaySetClassifier` exact / partial / superset / disjoint cases (4), `replaceEntries` rejects 2+ `.anyExternal` entries, `hasMultipleAnyExternal` helper covers built-in + flex, two-flex, all-specific shapes.

## [0.7.0] — 2026-05-08

**Highlights:** First-launch welcome tour and full localisation (en/sk/de). Profiles can now be edited inline.

### Added

- **Welcome tour** — three-step onboarding shown the first time the menu-bar popover opens after a fresh install. Steps cover what VibeRes does, how profiles work, and where Simple Mode / Settings live (`⌘,`). Skipped or completed once, the tour does not re-appear; replay from Settings → General → "Replay welcome tour".
- **Localisation** — VibeRes now ships in **English, Slovak, and German**. Built on Apple's String Catalog (`Localizable.xcstrings`) so future translations can drop in without code changes. Onboarding, Settings tab labels, and General preferences are fully translated; the rest of the UI auto-extracts at build time and falls back to English where translations are still pending.
- **Profile editor** — right-click any profile pill → **Edit…** opens an inline form letting you toggle individual entries (built-in vs external), flip `specific ↔ any external` per entry, change the recorded resolution / Hz / HiDPI from a dropdown, or remove an entry entirely. Keeps id/name/createdAt stable so the rest of the app sees the "same" profile after a tweak.

### Changed

- **Lock-to-current-monitors** is now refused (with a clear orange note) when the user asks to lock a flexible profile but no external monitor is currently connected. Previously the action silently did nothing — you got a `*` flex pill that misled you into thinking it was specific. The new behaviour: *"Connect the external monitor first to lock 'Presentation' to it."*
- **Apply outcome copy** for flexible profiles no longer surfaces stale display names. A profile that was saved when *Q3279WG5B* was connected and later toggled to `.anyExternal` now reads as *"no external monitor connected"* on apply with no external present, instead of the misleading *"Q3279WG5B not connected"*.

### Tests

- 102 → 104 (+2): `replaceEntries` preserves identity / refuses empty input. The `anyExternal` skip-no-match summary is locked down with strict-equality so the bug above can't regress silently.

## [0.6.0] — 2026-05-07

### Added

- **Settings window** (open via `⌘,` or the footer's Settings… row). Three tabs:
  - **General** — Launch at login, Auto-apply matching profile.
  - **Display** — Simple Mode toggle, Live Preview on Hover.
  - **Updates** — current version, latest on GitHub, last-checked timestamp, manual Check now button.
  Always opens on the General tab to keep behaviour predictable across re-opens.
- **Simple Mode** (default ON for fresh installs). Hides the per-row refresh-rate chip group and applies the highest available rate when the user clicks the row. Power users turn it off in Settings → Display to get the chip group back.
- **Click anywhere on a resolution row** to apply the highest available refresh rate for that size. Works in both Simple and Advanced Mode — particularly important on displays with a single rate (M2 Air's built-in, plain 60 Hz externals) where the chip group is a tiny target. Explicit chip clicks still pick a specific rate.
- **Live Preview** moved to a floating overlay in the top-right corner of the resolution list. Several earlier attempts at "popover next to the hovered row" tripped on SwiftUI popover dismiss/recreate behaviour — corner overlay is stable, no flicker, no first-click-eaten bug.

### Changed

- Footer trimmed to five entries (Revert, Settings, Refresh, About, Quit). Auto-apply, Live Preview, and Launch at Login moved to Settings → General/Display where there's room for descriptions.
- Hover state on the current-mode row no longer triggers the preview banner — fixed an oscillation where the appearing/disappearing preview shifted layout and re-triggered hover on adjacent rows.

### Tests

- 100 → 102 (+2): Simple Mode default-on and persistence across `Preferences` instances.

## [0.5.0] — 2026-05-06

### Added

- **Revert last change** (single-step undo). When you click a resolution and immediately realise it was the wrong call — text too small, refresh rate too low, anything — the menu-bar footer now shows a **Revert last change** row with `⌘Z`. One click puts every display the apply touched back where it was. Profile applies snapshot all affected displays atomically, so reverting an "applied Presentation" undoes the whole profile in one move, not just the last entry.
- Auto-apply (display add/remove) deliberately does **not** create a revert entry — system events shouldn't be queued for undo.
- Display set changes (a monitor unplugged, etc.) clear the history, since a saved "before" mode would otherwise reference a phantom display.

### Tests

- 97 → 100 (+3): `RevertHistoryTests` for empty state, no-op clear, no-op consume.

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
