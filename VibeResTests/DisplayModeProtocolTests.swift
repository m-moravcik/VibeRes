import Testing
@testable import VibeRes

@Suite("DisplayModeProtocol extensions")
struct DisplayModeProtocolTests {
    @Test("HiDPI is detected when framebuffer pixels exceed logical points")
    func hiDPIDetection() {
        let hidpi = StubDisplayMode.hiDPI(width: 1800, height: 1169)
        let native = StubDisplayMode.native(width: 1800, height: 1169)

        #expect(hidpi.isHiDPI == true)
        #expect(native.isHiDPI == false)
    }

    @Test("HiDPI false when pixel size equals point size exactly")
    func hiDPIBoundary() {
        let mode = StubDisplayMode(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080)
        #expect(mode.isHiDPI == false)
    }

    @Test("refreshHz rounds to nearest integer")
    func refreshHzRounding() {
        #expect(StubDisplayMode(width: 1, height: 1, refreshRate: 60.0).refreshHz == 60)
        #expect(StubDisplayMode(width: 1, height: 1, refreshRate: 59.94).refreshHz == 60)
        #expect(StubDisplayMode(width: 1, height: 1, refreshRate: 47.95).refreshHz == 48)
        #expect(StubDisplayMode(width: 1, height: 1, refreshRate: 119.88).refreshHz == 120)
    }

    @Test("refreshHz returns nil for synthetic 0 Hz modes")
    func refreshHzZero() {
        let mode = StubDisplayMode(width: 1024, height: 768, refreshRate: 0)
        #expect(mode.refreshHz == nil)
    }

    @Test("menuDescription includes refresh when present")
    func menuDescriptionWithRefresh() {
        let mode = StubDisplayMode(width: 1920, height: 1080, refreshRate: 60)
        #expect(mode.menuDescription == "1920 × 1080 @ 60Hz")
    }

    @Test("menuDescription omits refresh when zero")
    func menuDescriptionWithoutRefresh() {
        let mode = StubDisplayMode(width: 1920, height: 1080, refreshRate: 0)
        #expect(mode.menuDescription == "1920 × 1080")
    }
}
