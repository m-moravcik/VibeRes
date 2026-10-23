import SwiftUI

/// The note under the profile pills, and how long it stays.
///
/// A value rather than loose view state, so the lifetime rules can be tested
/// without a view:
///  - A reassuring note clears itself after `Tone.autoDismissDelay`.
///  - A warning or a problem stays while the popover is open, until it is
///    dismissed or replaced: it is the only explanation the user gets for a
///    monitor that did not get what was asked.
///  - Every note goes when the popover closes. Each open is a fresh task, as
///    the navigation path already is (see `MenuContent`). The note used to
///    live in view state that outlives a closed popover, because a
///    MenuBarExtra's window is ordered out rather than torn down, so a
///    warning from one click greeted every later open.
struct PopoverNote<Body: Equatable>: Equatable {
    struct Entry: Equatable {
        let body: Body
        let tone: ApplyOutcomeNote.Tone
        /// Which `show` put it there. A timer clears only its own note, so a
        /// second note with the same words is not cut short by the first one's
        /// timer, which is what matching on the content used to do.
        let generation: Int
    }

    private(set) var current: Entry?
    private var lastGeneration = 0

    /// Shows `body` and returns its generation, for `expire`.
    @discardableResult
    mutating func show(_ body: Body, tone: ApplyOutcomeNote.Tone) -> Int {
        lastGeneration += 1
        current = Entry(body: body, tone: tone, generation: lastGeneration)
        return lastGeneration
    }

    /// Clears the note when it is still the one `generation` showed.
    mutating func expire(_ generation: Int) {
        if current?.generation == generation { current = nil }
    }

    mutating func dismiss() {
        current = nil
    }
}

extension ApplyOutcomeNote.Tone {
    /// How long a note in this tone stays before it clears itself; nil keeps
    /// it until it is dismissed or the popover closes.
    var autoDismissDelay: Duration? {
        self == .info ? .seconds(6) : nil
    }

    var symbol: String {
        self == .info ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    /// The symbol's colour. Only the symbol: words in red or green on the
    /// popover's vibrant material read badly in both appearances, and red
    /// text said "error" about a display that was simply not plugged in.
    var tint: Color {
        switch self {
        case .info: return .green
        case .fallback: return .orange
        case .problem: return .red
        }
    }

    /// The wash behind a note that asks to be read; none for a confirmation.
    var fill: Color? {
        switch self {
        case .info: return nil
        case .fallback: return Design.Palette.warningFill
        case .problem: return Design.Palette.problemFill
        }
    }
}

/// One note in the popover: the outcome under the profile pills, or a display
/// problem at the top. The tinted symbol says how it went; the words stay in
/// label colours, primary for a note that asks to be read, secondary for a
/// confirmation. A warning sits on a wash of its colour, the way Eject Guard
/// and ClipShot draw their attention rows, and says Dismiss with a button.
struct NoteRow: View {
    let tone: ApplyOutcomeNote.Tone
    let text: Text
    /// A quieter second line, such as the displays a profile skipped.
    var detail: Text?
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: tone.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tone.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                text
                    .foregroundStyle(tone == .info ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                if let detail {
                    detail.foregroundStyle(.secondary)
                }
            }
            .font(Design.Typography.note)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            if tone != .info {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .help("Dismiss")
            }
        }
        // On a wash the symbol keeps the column it has without one, the
        // pills' leading edge: 8 pt outside the wash plus 4 pt inside is the
        // 12 pt the pills sit at.
        .padding(.horizontal, tone.fill == nil ? 0 : Design.Spacing.s)
        .padding(.vertical, tone.fill == nil ? 0 : 5)
        .background {
            if let fill = tone.fill {
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(fill)
            }
        }
        .padding(.horizontal, tone.fill == nil ? Design.Spacing.l : Design.Spacing.m)
        // Contain, not combine: the Dismiss button stays its own element.
        .accessibilityElement(children: .contain)
    }
}

extension EnvironmentValues {
    /// Goes up by one each time the popover closes, so views below
    /// `MenuContent` can drop what belonged to the last open. The window
    /// outlives a closed popover, so their own appear and disappear do not
    /// say it.
    @Entry var popoverSession = 0
}
