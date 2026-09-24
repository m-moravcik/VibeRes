# Screenshots

These are the pictures the root [README](../../README.md) embeds. They are
rendered from the app, not captured by hand, and named with a version suffix so
a refresh does not silently replace a picture the README still describes in
the old terms.

| File | Shows |
|---|---|
| `icon.png` | App icon at 512 px, as macOS draws it; the README header |
| `hero-{light,dark}.png` | The popover open under its menu bar icon |
| `root-v3-{light,dark}.png` | Root popover: profile pills and display cards |
| `detail-v3-{light,dark}.png` | Per-display detail: current-mode card, Scaled/Native toggle, size rows, hover preview |
| `save-v3-{light,dark}.png` | Inline "Save profile" form with per-display checkboxes |

## Retaking them

```sh
scripts/screenshots.sh        # English, into build/screenshots/en
scripts/screenshots.sh sk     # Slovak, for the web.pexelo portfolio
```

The script builds Debug and runs the harness in
`VibeRes/Preview/ScreenshotHarness.swift`, which renders the real views at 2x
and exits. It also writes `banner-{light,dark}.png`, the 1920x1080 portfolio
image, which is not used here.

- The displays are the ones connected to the Mac that renders. Their names and
  modes are hardware, not personal data, but plug in the same pair (a Retina
  built-in and one external) or the pictures stop matching the text.
- The profiles are invented and live in a throwaway directory, so your own
  catalog never shows up.
- Copy the files you need over the ones here, or bump the suffix (`-v4`) and
  update the `<img>` tags in the root README so the two cannot drift apart.
