# VibeRes

A modern, native menubar resolution switcher for macOS — spiritual successor to the discontinued [EasyRes](http://easyres.softwar.io/).

> **Status:** early development. macOS 26 Tahoe and later.

## Why

EasyRes was the only free Mac menubar resolution switcher with live previews. It hasn't been updated since ~2017 and no longer runs on Apple Silicon / modern macOS. Existing alternatives are either paid (SwitchResX, QuickRes), closed-source, or focused on a different use-case (BetterDisplay).

VibeRes aims to be:

- **Free** and MIT-licensed.
- **Native:** pure SwiftUI on macOS 26+, no Electron, no Catalyst.
- **Lightweight:** single-binary app, no dependencies.
- **Familiar:** menubar dropdown with all resolutions per display, including HiDPI scaled modes.
- **Useful:** in-popover live preview, named profiles, global hotkeys, and Shortcuts.app integration.

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open VibeRes.xcodeproj
```

Or build from CLI:

```bash
xcodebuild -project VibeRes.xcodeproj -scheme VibeRes -configuration Release
```

## License

MIT — see [LICENSE](./LICENSE).
