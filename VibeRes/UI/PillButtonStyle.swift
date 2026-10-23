import SwiftUI

/// A small rounded pill for a secondary action in the popover, in the look of
/// the profile pills: a soft fill, the accent on hover, deeper while pressed.
/// The same style ClipShot uses for its pills, so the sibling apps' popovers
/// share one control shape.
///
/// As tall as a small segmented control, so a pill and a switch on one line
/// sit level.
struct PillButtonStyle: ButtonStyle {
    static let font: Font = .system(size: 11, weight: .medium)

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Design.Radius.chip, style: .continuous)
        }

        private var fill: Color {
            if configuration.isPressed { return Color.accentColor.opacity(0.4) }
            if hovering { return Color.accentColor.opacity(0.25) }
            return Color.secondary.opacity(0.18)
        }

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .frame(minHeight: Design.Layout.inlineControlHeight)
                .background(shape.fill(fill))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { hovering = $0 }
        }
    }
}
