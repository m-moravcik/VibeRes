import Testing
@testable import VibeRes

@Suite("ResolutionBucketing")
struct ResolutionBucketingTests {
    @Test("Empty input yields no buckets")
    func emptyInput() {
        let buckets = ResolutionBucketing.bucket([StubDisplayMode]())
        #expect(buckets.isEmpty)
    }

    @Test("Modes with same point size and HiDPI are grouped into one bucket")
    func sameSizeGrouped() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60, id: 1),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 120, id: 2),
        ]
        let buckets = ResolutionBucketing.bucket(modes)
        #expect(buckets.count == 1)
        #expect(buckets[0].entries.count == 2)
        #expect(buckets[0].entries.map(\.hz) == [60, 120])
    }

    @Test("HiDPI and native modes at the same size go to separate buckets")
    func hidpiAndNativeSplit() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1920, height: 1080, hz: 60, id: 1),
            StubDisplayMode.native(width: 1920, height: 1080, hz: 60, id: 2),
        ]
        let buckets = ResolutionBucketing.bucket(modes)
        #expect(buckets.count == 2)
    }

    @Test("NTSC drop-frame variants are deduplicated to a single chip")
    func ntscDedup() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60.0, id: 1),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 59.94, id: 2),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 48.0, id: 3),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 47.95, id: 4),
        ]
        let buckets = ResolutionBucketing.bucket(modes)
        #expect(buckets.count == 1)
        #expect(buckets[0].entries.map(\.hz).sorted() == [48, 60])
    }

    @Test("NTSC dedup keeps the variant closer to a whole integer")
    func ntscPreferIntegerVariant() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 59.94, id: 99),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60.0, id: 100),
        ]
        let buckets = ResolutionBucketing.bucket(modes)
        #expect(buckets.count == 1)
        #expect(buckets[0].entries.count == 1)
        // The integer-variant mode (id 100, refreshRate 60.0) wins because its
        // drift from the rounded value is 0, vs 0.06 for the NTSC sibling.
        #expect(buckets[0].entries[0].mode.ioDisplayModeID == 100)
    }

    @Test("Buckets are sorted largest first, HiDPI before native at the same size")
    func sortOrder() {
        let modes = [
            StubDisplayMode.native(width: 1280, height: 720, id: 1),
            StubDisplayMode.hiDPI(width: 1920, height: 1080, id: 2),
            StubDisplayMode.native(width: 1920, height: 1080, id: 3),
            StubDisplayMode.hiDPI(width: 2560, height: 1440, id: 4),
        ]
        let buckets = ResolutionBucketing.bucket(modes)
        let order = buckets.map { ($0.key.width, $0.key.isHiDPI) }
        #expect(order[0] == (2560, true))
        #expect(order[1] == (1920, true))
        #expect(order[2] == (1920, false))
        #expect(order[3] == (1280, false))
    }

    @Test("Pixel size of bucket reflects the underlying mode")
    func pixelSizePropagated() {
        let modes = [StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60, id: 1)]
        let buckets = ResolutionBucketing.bucket(modes)
        #expect(buckets[0].pixelWidth == 3600)
        #expect(buckets[0].pixelHeight == 2338)
    }

    @Test("Refresh rates within a bucket are sorted ascending")
    func refreshSortedAscending() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 120, id: 1),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 48, id: 2),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60, id: 3),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 50, id: 4),
        ]
        let buckets = ResolutionBucketing.bucket(modes)
        #expect(buckets[0].entries.map(\.hz) == [48, 50, 60, 120])
    }
}
