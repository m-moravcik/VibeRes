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

    @Test(arguments: [false, true])
    func everyAccentReadsOnTheBadgeAndThePopover(dark: Bool) {
        for accent in Self.accents {
            let base = dark ? accent.dark : accent.light
            let text = AccentText.color(for: base, dark: dark)
            let onBadge = AccentText.contrast(text, AccentText.badge(accent: base, dark: dark))
            let onPopover = AccentText.contrast(text, AccentText.popover(dark: dark))
            #expect(onBadge >= AccentText.minimumContrast, "\(accent.name) on the badge: \(onBadge)")
            #expect(onPopover >= AccentText.minimumContrast, "\(accent.name) on the popover: \(onPopover)")
        }
    }

    /// Shaded only as far as it takes, so blue still looks like the accent,
    /// and an accent that already reads is left as it is.
    @Test(arguments: [false, true])
    func shadesNoFurtherThanNeeded(dark: Bool) {
        for accent in Self.accents {
            let base = dark ? accent.dark : accent.light
            let badge = AccentText.badge(accent: base, dark: dark)
            let text = AccentText.color(for: base, dark: dark)
            if AccentText.contrast(base, badge) >= AccentText.minimumContrast {
                #expect(text == base.usingColorSpace(.sRGB), "\(accent.name) already reads")
            } else {
                let onBadge = AccentText.contrast(text, badge)
                #expect(onBadge < AccentText.minimumContrast + 0.6, "\(accent.name): \(onBadge)")
            }
        }
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
