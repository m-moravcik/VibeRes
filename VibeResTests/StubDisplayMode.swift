import Foundation
@testable import VibeRes

/// Test stub for DisplayModeProtocol since CGDisplayMode is a CF class we can't
/// instantiate from Swift. Identical surface, all values controllable.
struct StubDisplayMode: DisplayModeProtocol, Equatable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let ioDisplayModeID: Int32

    init(
        width: Int,
        height: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        refreshRate: Double = 60,
        ioDisplayModeID: Int32 = 0
    ) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth ?? width
        self.pixelHeight = pixelHeight ?? height
        self.refreshRate = refreshRate
        self.ioDisplayModeID = ioDisplayModeID
    }

    /// Convenience builder for an HiDPI mode at a logical size with 2× scaling.
    static func hiDPI(width: Int, height: Int, hz: Double = 60, id: Int32 = 0) -> StubDisplayMode {
        StubDisplayMode(
            width: width,
            height: height,
            pixelWidth: width * 2,
            pixelHeight: height * 2,
            refreshRate: hz,
            ioDisplayModeID: id
        )
    }

    /// Convenience builder for a native (1:1) mode.
    static func native(width: Int, height: Int, hz: Double = 60, id: Int32 = 0) -> StubDisplayMode {
        StubDisplayMode(
            width: width,
            height: height,
            pixelWidth: width,
            pixelHeight: height,
            refreshRate: hz,
            ioDisplayModeID: id
        )
    }
}
