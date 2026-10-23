import SwiftUI

// Shared motion pieces for the popover. The timings and the job of each live
// in `Design.Motion`; these only apply them, with the Reduce Motion fallback
// in the same place as the movement.

/// A plain button that gives under the pointer: it shrinks a touch while it is
/// pressed and springs back on release. Reduce Motion: it dims instead.
struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Pressed(label: configuration.label, isPressed: configuration.isPressed, scale: scale)
    }

    private struct Pressed: View {
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .scaleEffect(isPressed && !reduceMotion ? scale : 1)
                .opacity(isPressed && reduceMotion ? 0.75 : 1)
                .animation(reduceMotion ? Design.Motion.quick : Design.Motion.press, value: isPressed)
        }
    }
}

extension View {
    /// Lights the view up in the accent colour when `value` changes, and fades
    /// it back: "this is the one that changed". Not on first appearance, only
    /// on a change. Colour only, so Reduce Motion keeps it.
    func changedGlow(on value: some Equatable, cornerRadius: CGFloat) -> some View {
        keyframeAnimator(initialValue: 0.0, trigger: value) { content, glow in
            content.overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(Design.Motion.changedGlowOpacity * glow))
                    .allowsHitTesting(false)
            }
        } keyframes: { _ in
            CubicKeyframe(1, duration: Design.Motion.changedGlowIn)
            LinearKeyframe(1, duration: Design.Motion.changedGlowHold)
            CubicKeyframe(0, duration: Design.Motion.changedGlowOut)
        }
    }

    /// Digits that roll to their new value when `value` changes. Reduce
    /// Motion: a crossfade.
    func rollingNumbers(on value: some Equatable, reduceMotion: Bool) -> some View {
        contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(reduceMotion ? Design.Motion.quick : Design.Motion.number, value: value)
    }
}

extension AnyTransition {
    /// A note that drops in from just above and fades out, faster. Reduce
    /// Motion: a crossfade both ways.
    static func note(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity.animation(Design.Motion.quick) }
        return .asymmetric(
            insertion: .offset(y: -Design.Motion.noteDrop).combined(with: .opacity)
                .animation(Design.Motion.noteIn),
            removal: .opacity.animation(Design.Motion.leave)
        )
    }

    /// A row or panel that fades in once the rows around it have made room,
    /// and fades out before they close up. Reduce Motion: the same order
    /// around the rows' `jump`.
    static func row(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(reduceMotion ? Design.Motion.rowInReduced : Design.Motion.rowIn),
            removal: .opacity.animation(Design.Motion.rowOut)
        )
    }
}
