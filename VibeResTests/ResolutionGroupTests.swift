import Foundation
import Testing
@testable import VibeRes

@Suite("ResolutionGroup wrapper + DisplayMode extensions edge cases")
struct ResolutionGroupExtraTests {
    // MARK: ResolutionGroup.id

    @Test("id encodes width × height + HiDPI flag")
    func idFormat() {
        let modes = [StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60, id: 1)]
        let groups = ResolutionBucketing.bucket(modes)
        #expect(groups[0].key.width == 1800)
        #expect(groups[0].key.height == 1169)
        #expect(groups[0].key.isHiDPI == true)
    }

    @Test("Single mode with 0Hz refresh still ends up in a group")
    func zeroHzIncluded() {
        let modes = [StubDisplayMode(width: 1024, height: 768, refreshRate: 0, ioDisplayModeID: 1)]
        let groups = ResolutionBucketing.bucket(modes)
        #expect(groups.count == 1)
        #expect(groups[0].entries.count == 1)
        #expect(groups[0].entries[0].hz == 0)
    }

    @Test("All-HiDPI modes sorted strictly by descending size")
    func sortByDescendingSize() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1024, height: 640, id: 1),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, id: 2),
            StubDisplayMode.hiDPI(width: 1352, height: 878, id: 3),
        ]
        let groups = ResolutionBucketing.bucket(modes)
        let widths = groups.map(\.key.width)
        #expect(widths == [1800, 1352, 1024])
    }

    @Test("Builds zero groups from an empty input list")
    func emptyInput() {
        #expect(ResolutionBucketing.bucket([StubDisplayMode]()).isEmpty)
    }

    // MARK: DisplayMode extensions

    @Test("menuDescription includes Hz only for non-zero refresh")
    func menuDescriptionHz() {
        let withHz = StubDisplayMode(width: 1920, height: 1080, refreshRate: 60)
        let zeroHz = StubDisplayMode(width: 1920, height: 1080, refreshRate: 0)
        #expect(withHz.menuDescription.contains("60Hz"))
        #expect(zeroHz.menuDescription.contains("Hz") == false)
    }

    @Test("isHiDPI compares pixelWidth vs width strictly greater")
    func isHiDPIBoundary() {
        // Equal pixel:point ratio is NOT HiDPI
        let equal = StubDisplayMode(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080)
        // pixelWidth > width is HiDPI
        let scaled = StubDisplayMode(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160)
        // pixelWidth < width should not happen, but defensively returns false
        let oddballSmaller = StubDisplayMode(width: 1920, height: 1080, pixelWidth: 1280, pixelHeight: 720)
        #expect(equal.isHiDPI == false)
        #expect(scaled.isHiDPI == true)
        #expect(oddballSmaller.isHiDPI == false)
    }
}
