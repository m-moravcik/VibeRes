# VibeRes — náhrada za EasyRes

Menubar resolution switcher pre macOS. Open-source, natívny Swift, žiadne závislosti.

---

## 1. Stav EasyRes (rešerš)

EasyRes (autor Chris Miles, MAS bundle id `info.chrismiles.easyres`) bol jediný free menubar switcher s **animovanými náhľadmi** rozlíšení. Posledná verzia 1.1.4 (~2017), zmizol z Mac App Store, web `easyres.softwar.io` ešte existuje ale download je offline. Vendor sa odmlčal — žiadne Apple Silicon ani macOS 14+ podpora.

### Existujúce alternatívy a prečo nestačia

| Nástroj | Typ | Cena | Limit |
|---|---|---|---|
| **SwitchResX** | GUI + menubar | ~$16 | Najsilnejší, ale platený a feature-overload |
| **Resolutionator** | menubar | $3 | Funkčný, zatvorený, žiadny preview |
| **QuickRes** | menubar | $7 | Toggle medzi dvoma módmi, nie full picker |
| **BetterDisplay** | GUI + menubar | free/paid | Skvelý pre HiDPI override, ale iný use-case (DDC, virtuálne displeje) |
| **displaymodemenu** (peaz, OSS) | menubar | free | **Najbližšie tomu, čo chceme**. Apache 2.0, Swift, Shortcuts integration |
| **ResolutionMenu** (robbertkl, OSS) | menubar | free | MIT, ObjC, posledný update Jan 2023, používa private APIs |
| **displayplacer** (jakehilborn, OSS) | CLI | free | MIT, len CLI — ale referenčná implementácia |

**Záver:** `displaymodemenu` je 90% toho, čo chceme — ale nemá animované náhľady (kľúčová EasyRes feature) a UX je suchšia. Náš cieľ: zobrať jeho jadro, pridať preview a vlastný styling.

### Čo chceme replikovať z EasyRes
1. Menubar ikona s aktuálnym rozlíšením (voliteľne).
2. Klik → zoznam dostupných rozlíšení per displej, s **HiDPI badge**.
3. Hover → live preview ako sa desktop preusporiada (animácia, alebo aspoň preview rámik s rozmermi).
4. Klik → okamžitý prepnutie.
5. **Bonus oproti EasyRes**: keyboard shortcuts (global hotkeys), Shortcuts.app actions, profily ("Práca", "Prezentácia").

---

## 2. Technická architektúra

### Stack
- **Jazyk:** Swift 5.10+ (čistý, bez Obj-C bridginu okrem private API headers ak treba)
- **UI framework:** SwiftUI vnútri `NSPopover` hostovaného `NSStatusItem` (NIE `MenuBarExtra` — limity v styling menu)
- **Min target:** macOS 13 Ventura (kvôli `MenuBarExtra` a moderným SwiftUI API; macOS 14+ pre Shortcuts kvalitu)
- **Build:** Xcode project, jeden target, žiadne SPM dependencies (cieľom je single-binary lightweight app)
- **Distribúcia:** Notarized .app, GitHub Releases, voliteľne Homebrew Cask. **Žiadny App Store** — sandbox by zabránil potrebným private API pre HiDPI módy.

### Kľúčové APIs

```swift
// Enumerácia displejov
var displayCount: UInt32 = 0
CGGetActiveDisplayList(0, nil, &displayCount)
var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
CGGetActiveDisplayList(displayCount, &displays, &displayCount)

// Listing módov (vrátane HiDPI scaled)
let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(displayID, opts) as! [CGDisplayMode])
    .filter { $0.isUsableForDesktopGUI() }

// Detekcia HiDPI (scale factor)
let isHiDPI = mode.pixelWidth > mode.width  // pixelWidth = framebuffer, width = logical points

// Atómové prepnutie módu
var config: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&config)
CGConfigureDisplayWithDisplayMode(config, displayID, newMode, nil)
CGCompleteDisplayConfiguration(config, .permanently)  // alebo .forSession pre dočasné
```

### Známe pasce
1. **`CGDisplayCopyAllDisplayModes` bez `kCGDisplayShowDuplicateLowResolutionModes` vracia neúplný zoznam.** System Settings ukazuje viac módov než API by inak vrátilo.
2. **HiDPI detekcia cez `pixelWidth > width`** je správny spôsob — `width` je logický bod, `pixelWidth` je fyzický pixel.
3. **`mode.isUsableForDesktopGUI()`** filtruje out modes, ktoré sú iba na vnútorné použitie (TV-out, atď).
4. **Notch na MacBook Pro 14"/16"** — niektoré "looks like" rozlíšenia sú pod notch, iné nad. To môže byť feature (umožniť používateľovi prepnúť na "nad-notch" mód, ktorý EasyRes nemal).
5. **macOS 14+ Stage Manager** môže rezistovať voči live preview animáciám — testovať.
6. **Multi-display setup**: keď používateľ zmení rozlíšenie main displeja, NSScreen indexovanie sa môže zmeniť. Riešenie: identifikovať displej cez `CGDisplaySerialNumber` + `CGDisplayVendorNumber`, nie cez index.

### Architektúra súborov
```
VibeRes/
├── VibeRes.xcodeproj
├── VibeRes/
│   ├── VibeResApp.swift              # @main, App lifecycle, NSStatusItem setup
│   ├── AppDelegate.swift             # NSApplicationDelegate (LSUIElement = true)
│   ├── Core/
│   │   ├── DisplayManager.swift      # CGDisplay enumerácia, observer pre hot-plug
│   │   ├── DisplayMode+Extensions.swift  # human-readable description, HiDPI flag
│   │   ├── ResolutionSwitcher.swift  # transactional CGBegin/Configure/Complete
│   │   └── Profile.swift             # uložené predvoľby ("Práca" → 1440p, "Prezentácia" → 1080p)
│   ├── UI/
│   │   ├── StatusBarController.swift # NSStatusItem + NSPopover wiring
│   │   ├── PopoverView.swift         # SwiftUI root view
│   │   ├── DisplayRow.swift          # jeden displej v zozname
│   │   ├── ModeRow.swift             # jeden mód, hover → preview
│   │   └── PreviewWindow.swift       # transparent overlay window pre live preview
│   ├── Shortcuts/
│   │   └── SetResolutionIntent.swift # AppIntents framework, Shortcuts.app integration
│   ├── Settings/
│   │   ├── SettingsView.swift        # SwiftUI Settings scene
│   │   └── HotkeyManager.swift       # global hotkeys (cez MASShortcut alebo vlastný NSEvent monitor)
│   └── Resources/
│       ├── Assets.xcassets           # menu bar ikona (template image)
│       └── Info.plist                # LSUIElement=YES, NSAppleEventsUsageDescription
└── VibeResTests/
    └── DisplayModeTests.swift        # unit testy pre formátovanie, HiDPI detekciu
```

---

## 3. Plán implementácie (fázy)

### Fáza 0: Setup (30 min)
- [ ] `git init`, prázdny GitHub repo `m-moravcik/VibeRes` (private until release)
- [ ] Xcode → New macOS App, SwiftUI lifecycle, target macOS 13
- [ ] `Info.plist`: `LSUIElement = YES` (skrytie z Docku)
- [ ] README skeleton, MIT LICENSE

### Fáza 1: Core CGDisplay layer (2-3h)
- [ ] `DisplayManager`: enumerácia displejov, callback pre hot-plug (`CGDisplayRegisterReconfigurationCallback`)
- [ ] `DisplayMode+Extensions`: parsing rozmerov, refresh rate, HiDPI flag, ľudský popis ("1920×1080 @ 60Hz · HiDPI")
- [ ] `ResolutionSwitcher.apply(_ mode: CGDisplayMode, to display: CGDirectDisplayID)`
- [ ] **Test ručne:** spustiť ako CLI binary cez `swift run`, overiť že vidí všetky módy z System Settings.

### Fáza 2: Menu bar shell (1-2h)
- [ ] `StatusBarController`: vytvorí `NSStatusItem`, set template image
- [ ] `NSPopover` s `NSHostingController` pre SwiftUI root
- [ ] Klik na ikonu → toggle popover, click-outside → dismiss
- [ ] `LSUIElement` overiť — žiadny Dock icon, žiadny `Cmd+Tab`

### Fáza 3: Popover UI (3-4h)
- [ ] Per displej sekcia (názov displeja, aktuálny mód v hlavičke)
- [ ] Zoznam módov, group by HiDPI vs. non-HiDPI, sort by width desc
- [ ] Aktuálny mód: checkmark
- [ ] Klik → `ResolutionSwitcher.apply()` → animovaný feedback
- [ ] **Známy/nezjavný refresh rate ratio**: zobraziť @60, @120, @ProMotion correctly

### Fáza 4: Live preview (4-6h, najťažšie)
- [ ] Hover na mode row → otvoriť transparent overlay window v rozmere target rozlíšenia (proporcionálne škálované do rohu obrazovky)
- [ ] Animovaný resize cez `NSAnimationContext` alebo SwiftUI `withAnimation`
- [ ] **Alternatíva ak overlay je flaky**: in-popover mini-render desktopu (screenshot cez `CGDisplayCreateImage` + scale do náhľadového rámčeka). Toto je presne čo robil EasyRes.
- [ ] Mouse-out alebo iný hover → cancel preview

### Fáza 5: Profily a hotkeys (2-3h)
- [ ] `Profile`: pomenovaná sada (display → mode) v `UserDefaults` (alebo `.json` v Application Support)
- [ ] Settings okno: pridať/mazať profily, priradiť global hotkey
- [ ] `HotkeyManager` — globálne klávesy (Carbon `RegisterEventHotKey` cez Swift wrapper, alebo MASShortcut SPM dep ak chceš zjednodušiť)

### Fáza 6: Shortcuts.app integration (1h)
- [ ] `AppIntents` framework: `SetResolutionIntent` action s parametrami (display name, width, height, refresh, HiDPI bool)
- [ ] Test v Shortcuts.app, overiť že action sa zjaví

### Fáza 7: Polish a release (2-3h)
- [ ] Launch at login (cez `SMAppService.mainApp.register()` — moderný API od macOS 13)
- [ ] Auto-update (Sparkle framework — voliteľné)
- [ ] App icon, menu bar template image v 16×16 + 32×32
- [ ] Sign + notarize: `codesign` + `xcrun notarytool submit`
- [ ] GitHub Release, Homebrew Cask submission

**Celkový odhad: 16-25 hodín čistej práce** (1-2 víkendy), bez auto-update infrastructure.

---

## 4. Otvorené rozhodnutia (vyžadujú confirm pred kódením)

1. **Apple Silicon only, alebo Universal binary?** Tip: Universal stojí 0 navyše, daj universal.
2. **Min macOS verzia?** Návrh: macOS 13 Ventura. Ak chceš max kompatibilitu → macOS 12.
3. **Live preview ako overlay window vs. in-popover screenshot scale?** Overlay je impressive, screenshot je robust. Návrh: začať screenshot variantom (rýchlejší MVP), overlay neskôr.
4. **Distribúcia:** GitHub Releases iba, alebo aj Mac App Store? **MAS = sandbox = nemôžeme volať `kCGDisplayShowDuplicateLowResolutionModes`.** Návrh: **iba mimo MAS**, free + open-source.
5. **Branding meno:** `VibeRes` (z aktuálneho názvu projektu) alebo niečo iné? `VibeRes` je fajn; prípadne `MenuRes`, `ResMate`, `Resly`.
6. **License:** MIT (najpermissivnejší) alebo Apache 2.0 (kompatibilný s `displaymodemenu` ak chceš code-borrow)?

---

## 5. Referenčné zdroje

### Open-source kód (priamo študovať)
- [peaz/displaymodemenu](https://github.com/peaz/displaymodemenu) — Swift, Apache 2.0, najbližší vzor
- [robbertkl/ResolutionMenu](https://github.com/robbertkl/ResolutionMenu) — ObjC, MIT, private API trick pre HiDPI
- [th507/screen-resolution-switcher](https://github.com/th507/screen-resolution-switcher) — `scres.swift`, čistá Swift CLI implementácia
- [jakehilborn/displayplacer](https://github.com/jakehilborn/displayplacer) — C, MIT, mature CLI
- [waydabber/BetterDisplay](https://github.com/waydabber/BetterDisplay) — komplexný, ale wiki o HiDPI je zlato

### Apple dokumentácia
- [`CGDisplayCopyAllDisplayModes`](https://developer.apple.com/documentation/coregraphics/cgdisplaycopyalldisplaymodes(_:_:))
- `CGDirectDisplay.h` headers (CGBeginDisplayConfiguration family)
- AppIntents framework (Shortcuts integration)
- `SMAppService` (login items, macOS 13+)

### Alternatívy (pre UX inšpiráciu, nie code)
- [SwitchResX](https://www.madrau.com/) — feature reference
- [QuickRes](https://www.thnkdev.com/QuickRes/) — minimalistický UX

---

## 6. Riziká

| Riziko | Pravdepodobnosť | Mitigácia |
|---|---|---|
| Apple zablokuje `kCGDisplayShowDuplicateLowResolutionModes` v budúcom macOS | Nízka | API je stabilné od 10.8, používa BetterDisplay; v krajnom prípade fallback na neúplný zoznam |
| Live preview je technicky neuskutočniteľný bez screen recording permission | Stredná | `CGDisplayCreateImage` vyžaduje Screen Recording permission od macOS 10.15. Treba prompt. Alternatíva: pure geometric preview (rámček s rozmermi, žiadny obsah). |
| Notarization friction | Nízka | $99/rok Apple Developer; bez toho používateľ musí Cmd+klik → Open |
| Konflikty s SwitchResX/QuickRes ak sú zapnuté | Stredná | Odporučiť v README ich vypnúť, detekovať za behu? |

---

## 7. Next step

**Tvoje slovo:** schválim tento plan a poviem _"poď"_, alebo dáme menšie/iné scope (napr. začneme len CLI bez UI, alebo skip live preview)?

Ak ideme: prvý commit bude Xcode skeleton + `DisplayManager` enumerácia + manuálny test cez logging. To je real progress za 1-2 hodiny.
