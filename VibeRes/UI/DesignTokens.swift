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
        /// A 13pt line plus 4 + 4 is 24pt, the height of a native menu item on
        /// macOS 26 (measured with `NSMenu.size`), as Eject Guard uses too.
        static let footerRowVerticalPadding: CGFloat = 4
        /// Space a native menu keeps around a separator and at its edges.
        static let menuInset: CGFloat = 5
        /// The height of a small segmented control on macOS 26, which a pill
        /// on the same line matches so the two sit level.
        static let inlineControlHeight: CGFloat = 20
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
        /// Behind a note that asks to be read: a warm wash for a warning (and
        /// the revert countdown), a red one for a failure, as Eject Guard and
        /// ClipShot draw their attention rows. The words on them stay in label
        /// colours; only the symbol takes the hue.
        static let warningFill = Color.orange.opacity(0.12)
        static let problemFill = Color.red.opacity(0.10)
    }

    /// Motion in the popover. Every animation here has one job, said next to
    /// it, and a Reduce Motion behaviour: movement becomes a `quick` crossfade
    /// or the end state, while a fade of colour (which moves nothing) stays.
    /// Calm rather than playful: springs settle without a visible bounce
    /// except where something lands, and everything is interruptible, so a
    /// second click never waits for the first animation.
    ///
    /// The vocabulary is ClipShot's (`Design.Motion` there), so the sibling
    /// apps move alike.
    enum Motion {
        /// Hover tints and small state changes: a crossfade, not a pop. Also
        /// what every movement below becomes under Reduce Motion.
        static let quick: Animation = .easeInOut(duration: 0.18)
        /// Rows that make room for something new, or close up after it.
        static let layout: Animation = .smooth(duration: 0.25)
        /// A size or rate that changed rolls its digits to the new value, so
        /// the eye sees what changed and to what.
        static let number: Animation = .smooth(duration: 0.35)

        /// A press: the control gives under the pointer, confirming the click
        /// before the displays blank for the mode change.
        static let press: Animation = .snappy(duration: 0.14)
        static let pillPressScale: CGFloat = 0.95
        static let cardPressScale: CGFloat = 0.985

        /// The chevron of a display card leans towards where a click takes
        /// you.
        static let chevronLean: CGFloat = 2

        /// The note under the pills drops in from just above, a beat after
        /// the rows under it start making room, so it never lands on a card
        /// still moving out of its way. It leaves by fading, faster, as exits
        /// should.
        static let noteIn: Animation = .spring(duration: 0.3, bounce: 0.2).delay(0.08)
        static let noteDrop: CGFloat = 6
        static let leave: Animation = .smooth(duration: 0.2)

        /// A row or panel that takes a place the others make room for (the
        /// inline panels swapping with the pills, the footer's Revert row)
        /// fades in once they mostly have, and leaves by fading before they
        /// close up over it (`closeUp`), so no text crosses another.
        static let rowIn: Animation = .easeInOut(duration: 0.18).delay(0.2)
        static let rowOut: Animation = .easeOut(duration: 0.1)
        /// Rows closing up after something left: `layout`, a beat later.
        static let closeUp: Animation = layout.delay(0.08)

        /// The highlighted refresh rate slides to the one just picked, so the
        /// row reads as one control that changed its value.
        static let chip: Animation = .snappy(duration: 0.28)
        /// The MAIN badge travels to the display that became main.
        static let badge: Animation = .spring(duration: 0.45, bounce: 0.15)

        /// A display card whose mode just changed lights up and fades back,
        /// pointing at the one of several displays a profile actually
        /// changed. A fade of colour, so it stays under Reduce Motion.
        static let changedGlowOpacity: Double = 0.16
        static let changedGlowIn: TimeInterval = 0.15
        static let changedGlowHold: TimeInterval = 0.35
        static let changedGlowOut: TimeInterval = 0.9

        // A profile pill that becomes active swaps its symbol for a checkmark
        // and bounces it once, with the system's own symbol bounce. It needs
        // no delay of its own: the pill turns active on the refresh after the
        // displays come back, around 0.4 to 0.8 s after the click, which is
        // when the menu bar icon's window springs out (`MenuBarIcon`, from
        // 0.6 s). Reduce Motion: the swap crossfades, no bounce.
    }
}
