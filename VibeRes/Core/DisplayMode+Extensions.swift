import CoreGraphics
import Foundation

extension CGDisplayMode {
    /// True when the framebuffer is denser than the logical point grid — i.e. macOS reports
    /// this mode as "Looks like NxM" in System Settings rather than as a 1:1 native mode.
    var isHiDPI: Bool {
        pixelWidth > width
    }

    /// Logical point dimensions (what apps see).
    var pointSize: CGSize {
        CGSize(width: width, height: height)
    }

    /// Backing pixel dimensions (the real framebuffer).
    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    /// Human-readable refresh rate. Returns nil for the synthetic 0 Hz that some virtual modes report.
    var refreshHz: Int? {
        let r = refreshRate
        guard r > 0 else { return nil }
        return Int(r.rounded())
    }

    /// One-line summary suitable for a menu row, e.g. "1920 × 1080 @ 60Hz".
    var menuDescription: String {
        var parts = ["\(width) × \(height)"]
        if let hz = refreshHz {
            parts.append("@ \(hz)Hz")
        }
        return parts.joined(separator: " ")
    }
}
