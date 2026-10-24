import AppKit
import Testing
@testable import VibeRes

/// Accent-coloured words have to read whichever accent the user picked. The
/// accent itself does not: blue measured 3.2:1 on the CURRENT badge.
@Suite("Accent text")
struct AccentTextTests {
    /// macOS's accent colours, light and dark, in sRGB.
    static let accents: [(name: String, light: NSColor, dark: NSColor)] = [
        ("blue", rgb(0x007AFF), rgb(0x0A84FF)),
        ("purple", rgb(0x953D96), rgb(0xA550A7)),
        ("pink", rgb(0xF74F9E), rgb(0xF74F9E)),
        ("red", rgb(0xE0383E), rgb(0xFF5257)),
        ("orange", rgb(0xF7821B), rgb(0xF7821B)),
        ("yellow", rgb(0xFFC600), rgb(0xFFC600)),
        ("green", rgb(0x62BA46), rgb(0x62BA46)),
        ("graphite", rgb(0x8C8C8C), rgb(0x8C8C8C)),
    ]

    static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    @Test func theAccentAloneDoesNotReadOnTheBadge() {
        let blue = Self.accents[0].light
        #expect(AccentText.contrast(blue, AccentText.badge(accent: blue, dark: false)) < AccentText.minimumContrast)
    }

    /// WCAG 2.x's own figures: black on white is 21:1, and #767676 is the
    /// lightest grey that passes AA on white (4.54:1) where #777777 fails
    /// (4.48:1).
    @Test func contrastMatchesWCAG() {
        let white = Self.rgb(0xFFFFFF)
        #expect(abs(AccentText.contrast(Self.rgb(0x000000), white) - 21) < 1e-9)
        #expect(abs(AccentText.contrast(Self.rgb(0x767676), white) - 4.54) < 0.005)
        #expect(abs(AccentText.contrast(Self.rgb(0x777777), white) - 4.48) < 0.005)
    }

    @Test(arguments: [false, true])
    func everyAccentReadsWhereverAccentWordsSit(dark: Bool) {
        for accent in Self.accents {
            let base = dark ? accent.dark : accent.light
            let text = AccentText.color(for: base, dark: dark)
            let places = [
                ("hovered pill", AccentText.hoveredPill(accent: base, dark: dark)),
                ("badge", AccentText.badge(accent: base, dark: dark)),
                ("popover", AccentText.popover(dark: dark)),
            ]
            for (place, background) in places {
                let ratio = AccentText.contrast(text, background)
                #expect(ratio >= AccentText.minimumContrast, "\(accent.name) on the \(place): \(ratio)")
            }
        }
    }

    /// Shaded only as far as it takes, so blue still looks like the accent:
    /// one 2% step less would not read on a hovered pill, and an accent that
    /// already reads is left as it is.
    @Test(arguments: [false, true])
    func shadesNoFurtherThanNeeded(dark: Bool) {
        for accent in Self.accents {
            let base = (dark ? accent.dark : accent.light).usingColorSpace(.sRGB)!
            let pill = AccentText.hoveredPill(accent: base, dark: dark)
            let text = AccentText.color(for: base, dark: dark).usingColorSpace(.sRGB)!
            if AccentText.contrast(base, pill) >= AccentText.minimumContrast {
                #expect(text == base, "\(accent.name) already reads")
                continue
            }
            let toward: CGFloat = dark ? 1 : 0
            let channels = [(base.redComponent, text.redComponent), (base.greenComponent, text.greenComponent),
                            (base.blueComponent, text.blueComponent)]
            let (from, to) = channels.max { abs(toward - $0.0) < abs(toward - $1.0) }!
            let step = ((to - from) / (toward - from) * 50).rounded()
            let lessShaded = Self.blend(base, toward: toward, (step - 1) / 50)
            let ratio = AccentText.contrast(lessShaded, pill)
            #expect(ratio < AccentText.minimumContrast, "\(accent.name) at step \(step - 1): \(ratio)")
        }
    }

    static func blend(_ color: NSColor, toward value: CGFloat, _ amount: CGFloat) -> NSColor {
        func channel(_ c: CGFloat) -> CGFloat { c * (1 - amount) + value * amount }
        return NSColor(srgbRed: channel(color.redComponent), green: channel(color.greenComponent),
                       blue: channel(color.blueComponent), alpha: 1)
    }

    @Test func keepsTheHue() {
        for accent in Self.accents where accent.name != "graphite" {
            for dark in [false, true] {
                let base = (dark ? accent.dark : accent.light).usingColorSpace(.sRGB)!
                let text = AccentText.color(for: base, dark: dark).usingColorSpace(.sRGB)!
                let shift = abs(text.hueComponent - base.hueComponent)
                #expect(min(shift, 1 - shift) < 0.02, "\(accent.name) \(dark ? "dark" : "light")")
            }
        }
    }

    @Test func darkensInLightModeAndLightensInDarkMode() {
        let blue = Self.accents[0]
        let light = AccentText.color(for: blue.light, dark: false).usingColorSpace(.sRGB)!
        let dark = AccentText.color(for: blue.dark, dark: true).usingColorSpace(.sRGB)!
        #expect(light.brightnessComponent < blue.light.brightnessComponent)
        #expect(dark.brightnessComponent >= blue.dark.brightnessComponent)
        #expect(dark.saturationComponent < blue.dark.saturationComponent)
    }
}
