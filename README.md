# VibeRes

A modern, native menubar resolution switcher for macOS — spiritual successor to the discontinued [EasyRes](http://easyres.softwar.io/).

> Requires **macOS 26 Tahoe** or later. Apple Silicon native.

![Status](https://img.shields.io/badge/status-beta-orange) ![Tests](https://img.shields.io/badge/tests-30%20passing-brightgreen) ![License](https://img.shields.io/badge/license-MIT-blue)

---

## Why VibeRes

EasyRes was the only free menubar resolution switcher with live previews, but it has been abandoned since 2017 and no longer runs on Apple Silicon. The alternatives are either paid (SwitchResX, QuickRes), closed-source, or focused on a different use case (BetterDisplay).

VibeRes brings back fast resolution switching from the menu bar with a native SwiftUI interface, multi-display profiles, and Shortcuts.app integration — all in a single ~600 KB binary, MIT-licensed.

---

## Quick start

1. Download `VibeRes-x.y.z.zip` from [Releases](https://github.com/m-moravcik/VibeRes/releases) and unzip into `/Applications`.
2. First launch — Gatekeeper will block the ad-hoc signed build. Either right-click the app → **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/VibeRes.app
   ```
3. Click the rectangle icon in your menu bar.

---

## User manual

### The popover at a glance

Clicking the menu bar icon opens a compact popover with three sections:

```
┌──────────────────────────────────────┐
│  PROFILES  ⓘ                         │  ← saved multi-display presets
│  [Work] [Presentation] [+ Save]      │
├──────────────────────────────────────┤
│  🖥  Built-in Retina Display    MAIN │  ← your displays
│      1 800 × 1 169 @ 120 Hz · HiDPI ›│
│                                       │
│  📺  Q3279WG5B                     › │
│      2 560 × 1 440 @ 75 Hz           │
├──────────────────────────────────────┤
│  ↻  Refresh              ⌘R          │  ← actions footer
│  ✓  Launch at Login                  │
│  ⓘ  About VibeRes                    │
│  ⏻  Quit                  ⌘Q          │
└──────────────────────────────────────┘
```

### Switching the resolution of one display

1. Click the menu bar icon.
2. Click on a display card. The popover navigates to a detail screen.
3. The detail shows every available resolution, with refresh rates as inline pill chips.

   ```
   ┌──────────────────────────────────────┐
   │  ‹ Back   Built-in Retina Display    │
   │           [HiDPI │ Native]           │  ← filter HiDPI vs native
   ├──────────────────────────────────────┤
   │  ✓ 1 800 × 1 169         48 50 60 120│  ← current mode (highlighted)
   │    1 512 × 982    +12%   48 50 60 120│  ← real-estate badge
   │    1 352 × 878   +27%    48 50 60 120│
   │    1 024 × 665   +51%    48 50 60 120│
   └──────────────────────────────────────┘
   ```

4. **Click anywhere on a row** to switch to its highest available refresh rate.
5. **Click a specific refresh chip** (e.g. `60` or `120`) to pick that exact rate.
6. The current size is highlighted, has a filled checkmark, and bold text. The active refresh chip is filled with the accent color.

#### What the badges and chips mean

| Element | Meaning |
|---|---|
| **HiDPI / Native toggle** | HiDPI ("Looks like" modes) trade pixels for clarity — typical on Retina. Native = 1 framebuffer pixel per logical point. Switch between them with the segmented control. |
| **Refresh chips** (`60`, `120`) | Available refresh rates for that resolution. Click to apply that rate. NTSC drop-frame variants (59.94, 47.95) are deduplicated against integer counterparts (60, 48) — the cleaner variant wins. |
| **Real-estate badge** (`+12%`, `−16%`) | How much more or less screen space a resolution gives you compared to the current mode. Green = more, orange = less. |
| **Hover preview** | Hovering a non-current row pops out a small geometric preview: the outer outline is the current mode, the accent-filled inner rectangle is the proposed mode at the same point scale. |

### Profiles — switching multiple displays at once

A **profile** is a named preset that captures the resolution + refresh rate + HiDPI flag of every connected display. Tap a profile pill to apply it across all of them in one click.

#### Why profiles are useful

| Scenario | MacBook | External monitor |
|---|---|---|
| **Work** | 1800 × 1169 @ 120 Hz HiDPI (max real estate) | 2560 × 1440 @ 75 Hz native (sharp text) |
| **Presentation** | 1280 × 800 @ 60 Hz (large fonts, readable from across the room) | 1920 × 1080 @ 60 Hz |
| **Gaming** | 1512 × 982 @ 120 Hz | 1920 × 1080 @ 60 Hz |
| **Code** | 1800 × 1169 @ 60 Hz HiDPI | 2560 × 1440 @ 60 Hz |

Without profiles, switching from "Work" to "Presentation" means clicking through both displays and picking modes manually. With profiles, it's one click on the pill.

#### How to create and use profiles

1. **Configure both displays** the way you want them (resolution, refresh rate, HiDPI).
2. Open the popover and click **+ Save** in the PROFILES section.
3. Type a name in the inline prompt and press **Enter** (or **Esc** to cancel).
4. The profile appears as a pill button.
5. **Click the pill** any time to re-apply that exact configuration on all connected displays.
6. **Right-click a pill** → **Delete** to remove it.

#### EDID-stable matching

Profiles store displays by EDID (vendor + model + serial number) rather than by `CGDirectDisplayID`. This means a profile named "Work" works correctly even after:

- A reboot
- Unplugging and reconnecting the USB-C cable
- Switching the cable from one Thunderbolt port to another
- A macOS update

If a profile references a display that's not currently connected, that display is skipped silently and an error message is shown below the pill bar.

### Footer actions

| Item | Shortcut | What it does |
|---|---|---|
| **Refresh** | ⌘R | Re-reads the display list. Useful if you connected a new monitor and want it to appear immediately. |
| **Launch at Login** | — | Toggles whether VibeRes starts automatically when you log in. Uses the modern `SMAppService.mainApp` registration (no helper bundle, no admin prompt). The icon updates instantly to reflect the current state. |
| **About VibeRes** | — | Standard macOS About panel with the version and the GitHub link. |
| **Quit** | ⌘Q | Quits VibeRes. |

---

## Shortcuts.app integration

VibeRes registers two AppIntents that surface in **Shortcuts.app**, **Spotlight**, and **Siri** automatically — no setup required.

### Available actions

#### `Set Display Resolution`

Switches a chosen display to the requested resolution.

**Parameters:**
- **Display** — picker of currently connected displays
- **Width** — in points (logical pixels), e.g. `1800`
- **Height** — in points, e.g. `1169`
- **Refresh Rate** *(optional)* — e.g. `120`. If omitted, picks the highest available for that size.
- **Prefer HiDPI** *(default true)* — when both HiDPI and native modes exist for the size, prefer the HiDPI variant.

If the exact requested mode doesn't exist, VibeRes picks the **closest match** using a weighted score over (size delta, HiDPI mismatch, refresh-rate delta).

#### `Get Current Resolution`

Returns the current resolution of a display as a string like `"1800 × 1169 @ 120 Hz (HiDPI)"`. Useful in conditional Shortcut workflows.

### Example workflows

**Presentation Mode** — large fonts for screen-share or projector:

1. Open Shortcuts.app and create a new shortcut named "Presentation Mode".
2. Add **Set Display Resolution**: Display = `Built-in Retina Display`, Width = `1280`, Height = `800`.
3. (Optional) Add **Set Display Resolution** for the external monitor too.
4. Assign a global hotkey via Shortcuts.app's settings (e.g. `⌃⌥⌘P`).
5. Now `⌃⌥⌘P` from anywhere in the system flips you into presentation mode.

**Spotlight invocation** — the registered phrases are:

- `Set resolution in VibeRes`
- `Change resolution with VibeRes`
- `Get current resolution from VibeRes`

**Siri** — the same phrases work as voice commands.

**Stream Deck / Loupedeck / BetterTouchTool** — any tool that can trigger a Shortcut can now switch resolutions through VibeRes.

---

## Tips and tricks

- **Two-level navigation**: the popover is intentionally compact. Click a display card to drill into its full mode list, click **‹ Back** to return.
- **Hover for preview**: hover over any non-current resolution to see a geometric preview of how that mode compares to the current one in size.
- **HiDPI vs Native toggle**: in the detail view, the segmented control filters between HiDPI scaled modes ("Looks like…") and 1:1 native modes. Most external monitors don't have HiDPI variants — VibeRes auto-falls-back to whichever set is non-empty.
- **The list scrolls**: if a display has 20+ resolutions, scroll the detail view. The footer disappears in detail mode so the full list is reachable.
- **Status bar icon refreshes**: when you switch resolutions, the popover briefly closes and the icon stays in place. The next click will rebuild the popover at its correct screen-anchored position. (This avoids a SwiftUI quirk where `MenuBarExtra(.window)` caches its frame across reconfigurations.)
- **Profiles don't appear?** Make sure you saved at least one profile via **+ Save**. The store is a JSON file at `~/Library/Application Support/VibeRes/profiles.json` — you can inspect or edit it manually if needed.

---

## Build from source

Requires **Xcode 26+**, the **macOS 26 SDK**, and [**XcodeGen**](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project VibeRes.xcodeproj -scheme VibeRes \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build
```

The `.app` bundle ends up in `~/Library/Developer/Xcode/DerivedData/VibeRes-*/Build/Products/Release/`.

### Run the tests

```bash
xcodebuild -project VibeRes.xcodeproj -scheme VibeRes test
```

30 unit tests across 5 suites cover bucketing, NTSC dedup, scoring, real-estate math, and profile persistence. The test target uses Swift Testing (`@Test` / `@Suite` / `#expect`), not XCTest.

SwiftUI views are intentionally not unit-tested — they integrate with the render system and are better exercised manually.

---

## Architecture

```
VibeRes/
├── Core/
│   ├── DisplayModeProtocol.swift   # Testable surface over CGDisplayMode
│   ├── DisplayManager.swift        # Active displays + NSScreen-derived names
│   ├── DisplayMode+Extensions.swift
│   ├── ResolutionGroup.swift       # Bucketing by point size + NTSC dedup
│   ├── ResolutionSwitcher.swift    # Atomic CGBegin/Configure/Complete
│   ├── DisplayStore.swift          # @Observable state + reconfig debounce
│   ├── Profile.swift               # Named multi-display preset model
│   ├── ProfileStore.swift          # JSON persistence + EDID-stable apply
│   └── LoginItem.swift             # SMAppService.mainApp wrapper
├── UI/
│   ├── DesignTokens.swift          # Spacing, radii, typography, palette
│   ├── MenuContent.swift           # NavigationStack + MenuBarExtra root
│   ├── ProfilesSection.swift       # Horizontal pill bar + inline name prompt
│   └── PreviewBox.swift            # Geometric hover preview + real-estate badge
├── Shortcuts/
│   ├── DisplayEntity.swift         # AppIntents entity for connected displays
│   ├── SetResolutionIntent.swift   # Set + Get resolution intents
│   └── AppShortcuts.swift          # Spotlight/Siri phrases provider
└── VibeResApp.swift                # @main + MenuBarExtra scene
```

`project.yml` is the source of truth — `VibeRes.xcodeproj` is regenerated by XcodeGen on every build and is **not** committed.

### Key design decisions

- **`kCGDisplayShowDuplicateLowResolutionModes`** unlocks scaled HiDPI modes that the default `CGDisplayCopyAllDisplayModes` call hides — the same ones System Settings shows.
- **NSScreen.localizedName** for display naming. CoreGraphics has no public name API; AppKit's NSScreen pulls names from EDID + macOS's display database.
- **`@Observable` macro** (Swift 5.9+) instead of `ObservableObject` — finer-grained change tracking, less re-render thrash.
- **MenuBarExtra(.window) + NavigationStack** instead of NSMenu. Trade-off: avoids 200+ lines of AppKit boilerplate at the cost of some quirks (modal alerts inside the popover are unreliable, hence the inline name prompt).
- **EDID-stable profile matching** via `CGDisplayVendorNumber + ModelNumber + SerialNumber`. `CGDirectDisplayID` rotates across reboots and reconnects.

---

## Limitations

- **Ad-hoc signed only.** No Apple Developer account → no notarization. Gatekeeper will require a one-time `xattr -d` or right-click → Open.
- **Live preview is geometric, not screenshot-based.** A future version may add an opt-in screenshot preview using ScreenCaptureKit (which requires a Screen Recording permission prompt).
- **macOS 26+ only.** Apps using `MenuBarExtra(.window)` style with `NavigationStack` are noticeably less polished on older versions; supporting them isn't worth the regression risk.
- **No global hotkeys built-in.** Use Shortcuts.app + global hotkey assignment instead — that path also covers Stream Deck, BTT, voice activation, etc.

---

## Contributing

1. Fork and clone.
2. `xcodegen generate`, open in Xcode 26+.
3. Make your change. Add or update unit tests where the logic is pure (anything in `Core/` other than the I/O paths).
4. Run `xcodebuild ... test` and make sure all 30+ tests pass.
5. Open a PR.

Please don't introduce dependencies — the project is intentionally a single binary with zero external SPM packages.

---

## License

MIT — see [LICENSE](./LICENSE).

---

## Credits

- Inspired by [EasyRes](http://easyres.softwar.io/) by Chris Miles (RIP).
- Reference implementations studied: [`peaz/displaymodemenu`](https://github.com/peaz/displaymodemenu), [`robbertkl/ResolutionMenu`](https://github.com/robbertkl/ResolutionMenu), [`th507/screen-resolution-switcher`](https://github.com/th507/screen-resolution-switcher), [`jakehilborn/displayplacer`](https://github.com/jakehilborn/displayplacer).
- Built with Claude Code.
