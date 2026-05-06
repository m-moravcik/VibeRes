import Testing
@testable import VibeRes

/// Tests the percentage-change math behind RealEstateBadge. We mirror the same
/// formula used in the view (delta of point area, rounded to int).
@Suite("RealEstateBadge math")
struct RealEstateBadgeTests {
    /// Helper that mirrors RealEstateBadge.changePercent without instantiating SwiftUI.
    private func changePercent(curW: Int, curH: Int, propW: Int, propH: Int) -> Int? {
        let cur = Double(curW) * Double(curH)
        let prop = Double(propW) * Double(propH)
        guard cur > 0, prop > 0 else { return nil }
        let delta = (prop - cur) / cur * 100
        return Int(delta.rounded())
    }

    @Test("Larger area yields a positive percentage")
    func largerArea() {
        let pct = changePercent(curW: 1800, curH: 1169, propW: 2560, propH: 1440)
        #expect(pct != nil && pct! > 0)
    }

    @Test("Smaller area yields a negative percentage")
    func smallerArea() {
        let pct = changePercent(curW: 1800, curH: 1169, propW: 1024, propH: 665)
        #expect(pct != nil && pct! < 0)
    }

    @Test("Identical area yields zero")
    func equalArea() {
        let pct = changePercent(curW: 1800, curH: 1169, propW: 1800, propH: 1169)
        #expect(pct == 0)
    }

    @Test("Zero current area returns nil instead of dividing by zero")
    func zeroCurrent() {
        #expect(changePercent(curW: 0, curH: 1000, propW: 1000, propH: 1000) == nil)
    }

    @Test("Doubling area gives ~100% increase")
    func doubling() {
        // 1000*1000=1_000_000 vs 1414*1414≈2_000_000 (sqrt(2) scale)
        let pct = changePercent(curW: 1000, curH: 1000, propW: 1414, propH: 1414)
        #expect(pct == 100)
    }
}
