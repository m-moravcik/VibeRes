import Foundation

/// The one way the app writes a size and a refresh rate for a person to read:
/// "2 560 × 1 440 · 60 Hz", "120 Hz VRR".
///
/// Display cards, the profile forms, apply notes, the hover preview and Revert
/// notes used to write three dialects of this ("2 560 × 1 440", "2560×1440",
/// "2560×1440 @60Hz"). Every one of them now calls this, so they cannot drift.
///
/// Deliberate exemptions, because scripts consume them: Shortcuts output
/// (`SetResolutionIntent`) keeps "1800 × 1169 @ 120 Hz" so existing Shortcut
/// conditions keep matching, and `viberes` CLI text keeps "2560x1440 @60Hz",
/// the syntax `viberes set` reads (`ProfileStore.ApplyOutcome.cliMode`).
///
/// Deliberately independent of the locale: digits, a narrow no-break space as
/// the thousands separator, the multiplication sign, and the unit symbol "Hz"
/// read the same in en, sk, cs, de, es and fr. Grouping by hand rather than
/// through `NumberFormatter` keeps a German "2.560" or a Spanish "2560" from
/// leaking in, and lets the type live in `VibeRes/Core`, which the bundle-less
/// `viberes` tool compiles too. "VRR" is an acronym and stays as it is.
enum ModeFormat {
    /// Between a size and a rate, and between either and a flag such as HiDPI.
    /// U+00A0 before the dot, so a wrapped line never starts with "·".
    static let separator = "\u{00A0}\u{00B7} "

    /// "2 560 × 1 440". The spaces inside a number are U+202F, so a line break
    /// never lands in the middle of one.
    static func size(width: Int, height: Int) -> String {
        "\(number(width)) \u{00D7} \(number(height))"
    }

    /// "60 Hz", or "60 Hz VRR" for a variable mode that has a fixed twin.
    /// U+00A0 joins the number and "Hz", so a line never breaks between them.
    static func rate(_ hz: Int, vrr: Bool = false) -> String {
        vrr ? "\(hz)\u{00A0}Hz VRR" : "\(hz)\u{00A0}Hz"
    }

    /// "2 560 × 1 440 · 60 Hz"; just the size when the mode reports no rate.
    /// `hiDPI` appends " · HiDPI".
    static func mode(width: Int, height: Int, hz: Int?, vrr: Bool = false, hiDPI: Bool = false) -> String {
        var parts = [size(width: width, height: height)]
        if let hz { parts.append(rate(hz, vrr: vrr)) }
        if hiDPI { parts.append("HiDPI") }
        return parts.joined(separator: separator)
    }

    /// A non-negative integer with U+202F between groups of three digits.
    /// Four digits are grouped too ("1 920"), as the display cards always did.
    static func number(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append("\u{202F}") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}
