# VibeRes

A modern menubar resolution switcher for macOS. Native SwiftUI, multi-display profiles, Shortcuts.app integration, and a sibling CLI. Spiritual successor to the abandoned [EasyRes](http://easyres.softwar.io/).

> Requires **macOS 26 Tahoe**, Apple Silicon. See [Older macOS](#older-macos) for backporting notes.

[![CI](https://github.com/m-moravcik/VibeRes/actions/workflows/ci.yml/badge.svg)](https://github.com/m-moravcik/VibeRes/actions/workflows/ci.yml)
![Tests](https://img.shields.io/badge/tests-52%20passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## Install

Download `VibeRes-*.zip` from [Releases](https://github.com/m-moravcik/VibeRes/releases), unzip into `/Applications`, and on first launch right-click the app → **Open** (the build is ad-hoc signed, so Gatekeeper asks once). Or:

```bash
xattr -dr com.apple.quarantine /Applications/VibeRes.app
```

---

## Switching resolution

Click the menu-bar icon. The popover shows every connected display with its current mode.

<p align="center"><img src="docs/screenshots/root-v2.png" width="320" alt="Root popover with profile pills and display cards"></p>

Click a display card to drill in. Each row is one logical size; refresh rates appear as a segmented control on the right. Click anywhere on the row to apply the highest available rate, or click a specific rate. The current size is highlighted in accent colour with a **CURRENT** pill at the top.

<p align="center"><img src="docs/screenshots/detail-v2.png" width="320" alt="Per-display detail with current mode card and segmented refresh selector"></p>

**Scaled vs Native.** The toggle at the top switches between two families of modes:

- **Scaled** is the default for built-in Retina displays. macOS renders at high DPI and downsamples to the panel's physical pixel grid, so text stays sharp at any "Looks like" size. This is what System Settings → Displays calls "Looks like 1800 × 1169" — the number is the *visual* size, not the framebuffer.
- **Native** is 1:1 pixel mapping — one logical point per physical pixel. Useful for non-Retina externals where scaling adds nothing but wastes GPU time.

VibeRes deduplicates NTSC drop-frame variants (59.94, 47.95) against their integer counterparts (60, 48) automatically.

---

## Profiles

A profile is a named multi-display preset. Save once, switch with one click. The save form is a per-display checklist:

<p align="center"><img src="docs/screenshots/save-v2.png" width="320" alt="Save profile inline form with per-display checkboxes"></p>

For each external display you choose:

- **Specific monitor** *(default)* — locked to that exact monitor by EDID. Survives reboots and USB-C reconnects on the same physical hardware.
- **Match any external monitor** — the entry binds by role, not identity. Use it for a "Presentation" profile that should work with whatever projector or hotel TV you plug into.

Built-in is always specific. Excluded displays are left untouched, so a "Code" profile can touch only the laptop and ignore externals.

Pill icons telegraph the type at a glance. `[🖥 Work]` is locked to specific monitors, `[🖥 Presentation ✱]` carries the small `✱` badge that means *"this profile travels"*, `[💻 Code]` uses the laptop icon when the profile only touches the built-in.

When you click a pill, a coloured note shows the outcome: green for an exact match, orange when the closest available mode was used as a fallback (e.g. *"LG UltraFine: wanted 2560 × 1440 @ 75 Hz, used 2560 × 1440 @ 60 Hz (closest available)"*), red when a target display isn't connected.

### Editing a profile

Right-click any pill to apply, update, rename, or delete. **Update with current setup** rewrites the profile's saved resolutions from whatever the displays are currently doing — useful when you've fine-tuned the setup and want to overwrite the snapshot without losing the profile's identity. **Make flexible / Make specific** flips external entries between EDID-locked and "any external" without recreating the profile.

---

## Command-line companion

VibeRes ships with `viberes`, a sibling executable that links the same Core code as the GUI. Same profile store, same `CGDisplay` APIs, same scoring.

```bash
brew install xcodegen
make install-cli   # → /usr/local/bin/viberes
```

Reference:

```text
viberes list                              List displays + current mode
viberes modes <display>                   Show available modes
viberes current [<display>]               Print current mode (one or all)
viberes set <display> <WxH[@Hz][-hidpi|-native]>
                                          Switch to closest matching mode

viberes profile list
viberes profile show <name>
viberes profile save <name> [--any-external] [--only <display>...]
viberes profile apply <name>              Per-display outcome (exit 2 on fallback)
viberes profile update <name>             Refresh from current state
viberes profile flex <name>               Toggle specific ↔ flexible externals
viberes profile rename <old> <new>
viberes profile delete <name>
```

`<display>` is a case-insensitive substring of the display name *or* its numeric ID (`1`, `3`, etc.). Examples:

```bash
viberes set "Built-in" 1800x1169@120
viberes set LG 2560x1440-native
viberes profile save Presentation --any-external
viberes profile save Code --only Built-in
viberes profile apply Presentation
# # applied profile "Presentation"
#   ✓ Built-in Retina Display → 1280×800 @60Hz
#   ~ LG UltraFine: wanted 1920×1080 @60Hz, used 1920×1080 @60Hz (closest available)
```

Exit code is `0` for full success, `2` if anything fell back or was skipped. Easy to drop into shell pipelines or git hooks.

---

## Shortcuts.app

Two AppIntents auto-register with Shortcuts, Spotlight, and Siri:

- **Set Display Resolution** — pick a display + width + height (+ optional refresh and HiDPI preference). Closest-match scoring.
- **Get Current Resolution** — for conditional workflows ("if my MacBook is at 1800×1169, switch to 1280×800").

Once registered, you can assign a global hotkey to any Shortcut from Shortcuts.app's settings — pressing it from anywhere in the system flips the relevant displays. Stream Deck, BetterTouchTool, and Loupedeck inherit it for free since they all trigger Shortcuts.

---

## Build

```bash
brew install xcodegen
make app          # GUI
make cli          # viberes binary
make test         # 52 tests, 9 suites, Swift Testing
```

`project.yml` is the source of truth. `*.xcodeproj` is regenerated and not committed.

---

## Older macOS

The current code targets macOS 26 because it leans on every modern API at once. Lowering the deployment target is mostly a one-line change in `project.yml` for **macOS 15 Sequoia** — everything compiles. **macOS 14 Sonoma** should also work as-is. **macOS 13 Ventura** needs a small refactor (~30 lines): `@Observable` is macOS 14+, so `DisplayStore` and `ProfileStore` would have to fall back to `ObservableObject` + `@Published`. **macOS 12 Monterey** and older would be a rewrite — `MenuBarExtra(.window)`, `NavigationStack`, `SMAppService.mainApp`, and AppIntents all arrived in 13.

---

## License

MIT — see [LICENSE](./LICENSE). Inspired by EasyRes by Chris Miles.
