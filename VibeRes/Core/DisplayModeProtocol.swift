import CoreGraphics
import Foundation

/// Minimal abstraction over CGDisplayMode so the bucketing/scoring/formatting code
/// can be unit-tested without spinning up a real display. CGDisplayMode itself is a
/// Core Foundation class we can't instantiate from Swift, so the test target uses
/// a struct conforming to this protocol instead.
protocol DisplayModeProtocol {
    var width: Int { get }
    var height: Int { get }
    var pixelWidth: Int { get }
    var pixelHeight: Int { get }
    var refreshRate: Double { get }
    var ioDisplayModeID: Int32 { get }
}

extension CGDisplayMode: DisplayModeProtocol {}

extension DisplayModeProtocol {
    var isHiDPI: Bool { pixelWidth > width }

    var refreshHz: Int? {
        guard refreshRate > 0 else { return nil }
        return Int(refreshRate.rounded())
    }

    var menuDescription: String {
        var parts = ["\(width) × \(height)"]
        if let hz = refreshHz {
            parts.append("@ \(hz)Hz")
        }
        return parts.joined(separator: " ")
    }
}
