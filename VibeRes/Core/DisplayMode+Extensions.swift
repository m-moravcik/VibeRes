import CoreGraphics
import Foundation

/// CGDisplayMode-specific helpers that don't fit the testable DisplayModeProtocol
/// (which intentionally stays minimal so tests can stub it).
extension CGDisplayMode {
    /// Logical point dimensions (what apps see).
    var pointSize: CGSize {
        CGSize(width: width, height: height)
    }

    /// Backing pixel dimensions (the real framebuffer).
    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }
}
