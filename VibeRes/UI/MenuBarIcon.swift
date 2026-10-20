import AppKit
import SwiftUI

/// The menu bar icon: the app icon in miniature, a display on a stand with a
/// smaller window in its top-left corner. When a resolution switch goes
/// through, the window springs out to fill the screen, overshoots a little and
/// settles back into its corner.
///
/// Drawn in code rather than shipped as a bitmap, so it stays sharp at every
/// backing scale and every frame of the switch animation comes from the same
/// paths. Every image is a template, so the menu bar tints it the way it tints
/// a system symbol: on light, dark, highlighted and tinted-wallpaper bars.
///
/// The geometry is in points on a 22 x 16 canvas, origin top left. The canvas
/// is the menu bar's limit: MenuBarExtra scales down a label taller than 16 pt.
/// The ink is about 13 pt tall with a 1.4 pt line, which is the optical size
/// and stroke weight of a regular SF Symbol at 15 pt, the size its neighbours
/// in the menu bar draw at.
enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 16)

    /// Length of the switch animation, in seconds. It waits out the moment the
    /// displays go dark while the new mode is applied, grows slowly enough to
    /// catch the eye, holds, and is back in its corner by 2.3 s, so the last
    /// frames are the idle icon and stopping is invisible.
    static let duration: Double = 2.4

    /// The beats of the animation, in seconds.
    private enum Beat {
        /// The displays usually flicker while a mode is applied; start after.
        static let growOut = 0.6...1.35
        static let settleBack = 1.75...2.3
    }

    /// The idle icon. One instance for the app's lifetime; the drawing handler
    /// re-runs for each backing scale it is asked for.
    @MainActor static let image: NSImage = make(phase: nil)

    /// The icon at `phase` seconds into the switch animation; nil is idle, and
    /// so is every frame with the window in its corner.
    @MainActor static func image(at phase: Double?) -> NSImage {
        guard let phase, growth(at: phase) != 0 else { return image }
        return make(phase: phase)
    }

    static func make(phase: Double?) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, phase: phase)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "VibeRes"
        return image
    }

    /// How far the inner window has grown towards filling the screen at
    /// `phase`: 0 in its corner, 1 filling the screen, a little over 1 at the
    /// overshoot.
    static func growth(at phase: Double?) -> Double {
        guard let t = phase else { return 0 }
        let out = Motion.spring(Motion.progress(t, Beat.growOut.lowerBound, Beat.growOut.upperBound), cycles: 1.0)
        let back = Motion.easeInOut(Motion.progress(t, Beat.settleBack.lowerBound, Beat.settleBack.upperBound))
        return out * (1 - back)
    }

    /// Template ink is black; only the alpha is used.
    static func draw(in cg: CGContext, phase: Double? = nil) {
        cg.saveGState()
        defer { cg.restoreGState() }

        cg.setFillColor(NSColor.black.cgColor)
        cg.setStrokeColor(NSColor.black.cgColor)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        // The whole figure at 95 %, about the canvas centre, so the line clears
        // the edges and the ink height lands on the neighbours'.
        cg.translateBy(x: 11, y: 8)
        cg.scaleBy(x: 0.95, y: 0.95)
        cg.translateBy(x: -11, y: -8)

        // Screen.
        let screen = CGRect(x: 3.2, y: 1.6, width: 15.6, height: 10.2)
        stroke(Path(roundedRect: screen, cornerRadius: 2.1, style: .continuous), width: 1.4, in: cg)

        // Stand: a short trapezoid under the screen, filled and outlined so its
        // corners round off like the screen's.
        var stand = Path()
        stand.addLines([CGPoint(x: 10.0, y: 12.2), CGPoint(x: 12.0, y: 12.2),
                        CGPoint(x: 12.7, y: 14.4), CGPoint(x: 9.3, y: 14.4)])
        stand.closeSubpath()
        fill(stand, in: cg)
        stroke(stand, width: 0.7, in: cg)

        // The window, anchored at its top-left corner: from its idle size it
        // grows towards one that fills the screen.
        let small = CGSize(width: 6.6, height: 4.4)
        let big = CGSize(width: 11.2, height: 6.0)
        let u = CGFloat(growth(at: phase))
        let window = CGRect(x: 5.4, y: 3.8,
                            width: small.width + (big.width - small.width) * u,
                            height: small.height + (big.height - small.height) * u)
        fill(Path(roundedRect: window, cornerRadius: 1.0, style: .continuous), in: cg)
    }

    private static func stroke(_ path: Path, width: CGFloat, in cg: CGContext) {
        cg.setLineWidth(width)
        cg.addPath(path.cgPath)
        cg.strokePath()
    }

    private static func fill(_ path: Path, in cg: CGContext) {
        cg.addPath(path.cgPath)
        cg.fillPath()
    }

    private enum Motion {
        static func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
        static func easeInOut(_ u: Double) -> Double { u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2 }
        /// A damped spring from 0 to 1 that overshoots before it settles.
        static func spring(_ u: Double, cycles: Double) -> Double {
            1 - (1 - u) * exp(-3 * u) * cos(2 * .pi * cycles * u)
        }
    }
}
