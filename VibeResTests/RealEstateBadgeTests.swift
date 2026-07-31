import Testing
@testable import VibeRes

/// Tests the percentage-change math used to describe how much screen real estate
/// a proposed mode gains or loses.
///
/// These used to call a private copy of the formula defined in the test file
/// itself, with a comment saying it "mirrors" the view — so they passed no matter
/// what the app actually computed. The formula existed three times: in
/// `RealEstateBadge`, in the row's tooltip, and here. Now there is one
/// implementation and these tests exercise it.
@Suite("Screen real-estate math")
struct RealEstateBadgeTests {
    @Test("Larger area yields a positive percentage")
    func largerArea() {
        let pct = RealEstateBadge.percentChange(currentWidth: 1800, currentHeight: 1169,
                                               proposedWidth: 2560, proposedHeight: 1440)
        #expect(pct != nil && pct! > 0)
    }

    @Test("Smaller area yields a negative percentage")
    func smallerArea() {
        let pct = RealEstateBadge.percentChange(currentWidth: 1800, currentHeight: 1169,
                                               proposedWidth: 1024, proposedHeight: 665)
        #expect(pct != nil && pct! < 0)
    }

    @Test("Identical area yields zero")
    func equalArea() {
        let pct = RealEstateBadge.percentChange(currentWidth: 1800, currentHeight: 1169,
                                               proposedWidth: 1800, proposedHeight: 1169)
        #expect(pct == 0)
    }

    @Test("Zero current area returns nil instead of dividing by zero")
    func zeroCurrent() {
        #expect(RealEstateBadge.percentChange(currentWidth: 0, currentHeight: 1000,
                                              proposedWidth: 1000, proposedHeight: 1000) == nil)
    }

    @Test("Zero proposed area returns nil")
    func zeroProposed() {
        #expect(RealEstateBadge.percentChange(currentWidth: 1000, currentHeight: 1000,
                                              proposedWidth: 0, proposedHeight: 1000) == nil)
    }

    @Test("Doubling area gives ~100% increase")
    func doubling() {
        // 1000*1000 = 1_000_000 vs 1414*1414 ≈ 2_000_000 (sqrt(2) scale)
        let pct = RealEstateBadge.percentChange(currentWidth: 1000, currentHeight: 1000,
                                                proposedWidth: 1414, proposedHeight: 1414)
        #expect(pct == 100)
    }
}
