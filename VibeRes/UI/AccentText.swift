import AppKit

/// The accent colour for words.
///
/// The accent is made for fills and symbols. As text it measured 3.2:1 on the
/// CURRENT badge and 3.6:1 on the popover, light and dark, under the 4.5:1
/// WCAG asks for. This keeps the hue the user picked and moves it towards
/// black in light mode and towards white in dark mode, only as far as it takes
/// to read wherever accent words sit: a hovered profile pill, the most tinted
/// place; a resting pill, whose grey is harder still for some accents; the
/// CURRENT badge and the popover. A fixed shade would not do: darkened by a
/// third, blue reads, yellow does not.
enum AccentText {
    static let minimumContrast = 4.5

    static func color(for accent: NSColor, dark: Bool) -> NSColor {
        let accent = srgb(accent)
        let backgrounds = places(accent: accent, dark: dark)
        let toward = dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
                          : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        for step in 0...50 {
            let candidate = mix(toward, CGFloat(step) / 50, over: accent)
            if backgrounds.allSatisfy({ contrast(candidate, $0) >= minimumContrast }) { return candidate }
        }
        return toward
    }

    /// The backgrounds accent words sit on.
    static func places(accent: NSColor, dark: Bool) -> [NSColor] {
        [hoveredPill(accent: accent, dark: dark), restingPill(dark: dark),
         badge(accent: accent, dark: dark), popover(dark: dark)]
    }

    /// A hovered profile pill: the accent at `pillHoverAccentOpacity` on the
    /// popover.
    static func hoveredPill(accent: NSColor, dark: Bool) -> NSColor {
        mix(srgb(accent), CGFloat(Design.Palette.pillHoverAccentOpacity), over: popover(dark: dark))
    }

    /// A profile pill at rest: the secondary label colour at
    /// `pillRestSecondaryOpacity` on the popover. Grey, so in dark mode it can
    /// be lighter than a hovered pill, and in light mode darker than a hovered
    /// pill tinted with a light accent such as yellow.
    static func restingPill(dark: Bool) -> NSColor {
        var secondary = NSColor.secondaryLabelColor
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            secondary = NSColor.secondaryLabelColor.usingColorSpace(.sRGB) ?? secondary
        }
        let opacity = secondary.alphaComponent * CGFloat(Design.Palette.pillRestSecondaryOpacity)
        return mix(secondary, opacity, over: popover(dark: dark))
    }

    /// The CURRENT badge: the accent at 15% on the current-mode card, which is
    /// the accent at 8% on the popover.
    static func badge(accent: NSColor, dark: Bool) -> NSColor {
        let card = mix(srgb(accent), 0.08, over: popover(dark: dark))
        return mix(srgb(accent), 0.15, over: card)
    }

    /// The popover's resting colour, as the screenshot harness fills it.
    static func popover(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
             : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    }

    /// WCAG contrast ratio, 1 to 21.
    static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    private static func luminance(_ color: NSColor) -> Double {
        let c = srgb(color)
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent)
            + 0.0722 * channel(c.blueComponent)
    }

    private static func mix(_ top: NSColor, _ alpha: CGFloat, over bottom: NSColor) -> NSColor {
        let (t, b) = (srgb(top), srgb(bottom))
        func blend(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x * alpha + y * (1 - alpha) }
        return NSColor(srgbRed: blend(t.redComponent, b.redComponent),
                       green: blend(t.greenComponent, b.greenComponent),
                       blue: blend(t.blueComponent, b.blueComponent), alpha: 1)
    }

    private static func srgb(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }
}
