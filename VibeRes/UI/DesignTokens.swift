import SwiftUI

/// Single source of truth for spacing, radii, typography and colors.
/// Centralised so future tweaks don't sprawl across views.
enum Design {
    enum Spacing {
        static let xs: CGFloat = 2
        static let s: CGFloat = 4
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
    }

    enum Radius {
        static let chip: CGFloat = 5
        static let card: CGFloat = 8
        static let popover: CGFloat = 10
    }

    enum Layout {
        static let popoverWidth: CGFloat = 300
        static let popoverMaxHeight: CGFloat = 600
        static let rowVerticalPadding: CGFloat = 4
        static let chipMinWidth: CGFloat = 24
        static let footerRowVerticalPadding: CGFloat = 3
    }

    enum Typography {
        static let cardTitle: Font = .system(size: 13, weight: .semibold)
        static let cardSubtitle: Font = .system(size: 11).monospacedDigit()
        static let badge: Font = .system(size: 9, weight: .bold)
        static let navTitle: Font = .system(size: 13, weight: .semibold)
        static let footer: Font = .system(size: 11)
        /// Outcome notes and other secondary annotations under a control.
        ///
        /// 11pt, not 10: macOS treats 11pt as the floor for text that carries
        /// meaning, and these sizes were being rendered in `.secondary` and
        /// `.tertiary`, which takes the contrast down with them.
        static let note: Font = .system(size: 11)
        /// All-caps section labels ("PROFILES", "ENTRIES").
        static let sectionHeader: Font = .system(size: 10, weight: .semibold, design: .rounded)
        /// Inline buttons and pickers inside the popover.
        static let control: Font = .system(size: 12, weight: .medium)
    }

    enum Palette {
        /// Subtle surface tint that adapts to light/dark.
        static let cardFill = Color.secondary.opacity(0.10)
        static let cardFillHover = Color.secondary.opacity(0.18)
        static let chipFill = Color.secondary.opacity(0.16)
        static let rowSelectedFill = Color.accentColor.opacity(0.12)
        static let rowSelectedTint = Color.accentColor
        static let separator = Color.secondary.opacity(0.15)
    }
}
