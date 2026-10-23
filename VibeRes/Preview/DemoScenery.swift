#if DEBUG
import AppKit
import SwiftUI

// Scenery shared by the README loops (`MotionDemo`, `ProfileDemo`): the
// desktop, the menu bar strip, a window, the pointer and the loupe. None of it
// is app UI; every part that carries information is captured from the app's
// own views or drawn by `MenuBarIcon`.

/// A calm desktop gradient, the same one the screenshots use.
struct DemoWallpaper: View {
    let scheme: ColorScheme

    var body: some View {
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.11, green: 0.09, blue: 0.26), Color(red: 0.05, green: 0.22, blue: 0.25)]
                       : [Color(red: 0.80, green: 0.78, blue: 0.96), Color(red: 0.74, green: 0.92, blue: 0.90)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// The rounded corners, hairline and shadow of a popover window.
    func demoPopoverChrome(_ scheme: ColorScheme) -> some View {
        let dark = scheme == .dark
        return clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(dark ? 0.5 : 0.22), radius: 24, y: 12)
    }
}

/// The right end of the menu bar: the app's icon, highlighted because its
/// window is open, then Wi-Fi and the clock.
struct DemoMenuBarStrip: View {
    let phase: Double?
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            Image(nsImage: MenuBarIcon.image(at: phase))
                .renderingMode(.template)
                .frame(width: 30, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.14)))
            Image(systemName: "wifi")
                .font(.system(size: 13, weight: .medium))
            Text(verbatim: "9:41")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .background(scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45))
    }
}

/// A plain document window behind the popover. No app in particular: lines
/// stand in for text.
struct DemoWindow: View {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34),
                         Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { c in
                    Circle().fill(c).frame(width: 12, height: 12)
                }
            }
            .padding(.leading, 14)
            .frame(height: 36)

            VStack(alignment: .leading, spacing: 11) {
                RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.55)).frame(width: 150, height: 9)
                    .padding(.bottom, 4)
                ForEach(Array([210, 236, 198, 224, 120, 0, 230, 204, 218, 160].enumerated()), id: \.offset) { _, w in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(w == 0 ? 0 : 0.16))
                        .frame(width: CGFloat(w), height: 7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer()
        }
        .frame(width: 320, height: 280, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(dark ? Color(red: 0.17, green: 0.17, blue: 0.19) : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(dark ? 0.4 : 0.12), radius: 16, y: 8)
    }
}

/// The system arrow, tip at the point.
struct DemoPointer: View {
    let scale: Double

    var body: some View {
        let cursor = NSCursor.arrow
        Image(nsImage: cursor.image)
            .scaleEffect(scale, anchor: UnitPoint(x: cursor.hotSpot.x / cursor.image.size.width,
                                                  y: cursor.hotSpot.y / cursor.image.size.height))
            .offset(x: -cursor.hotSpot.x, y: -cursor.hotSpot.y)
    }
}

/// The menu bar icon enlarged, so the 22 x 16 pt glyph reads in a README: a
/// slice of the menu bar only, the icon centred in its highlight, drawn by
/// `MenuBarIcon.draw` at the frame's phase on a canvas `zoom` times larger
/// rather than scaled up from a small bitmap. Framed like the popover.
struct DemoLoupe: View {
    let phase: Double?
    let scheme: ColorScheme

    static let zoom: CGFloat = 3.5
    /// The menu bar's height, and the highlight's width plus a margin of
    /// 9 pt of menu bar either side, all at `zoom`.
    static let size = CGSize(width: (30 + 18) * zoom, height: 24 * zoom)

    private var dark: Bool { scheme == .dark }

    var body: some View {
        let k = Self.zoom
        Image(nsImage: Self.glyph(phase: phase, zoom: k))
            .renderingMode(.template)
            .frame(width: 30 * k, height: 22 * k)
            .background(RoundedRectangle(cornerRadius: 5 * k, style: .continuous)
                .fill(Color.primary.opacity(0.14)))
            .frame(width: Self.size.width, height: Self.size.height)
            .foregroundStyle(dark ? Color.white : Color.black)
            // The menu bar strip over the wallpaper under it, as one fill.
            .background(dark ? Color(red: 0.05, green: 0.10, blue: 0.17) : Color(red: 0.87, green: 0.92, blue: 0.97))
            .demoPopoverChrome(scheme)
    }

    static func glyph(phase: Double?, zoom k: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: MenuBarIcon.size.width * k, height: MenuBarIcon.size.height * k),
                            flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.scaleBy(x: k, y: k)
            MenuBarIcon.draw(in: cg, phase: phase)
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
