import CoreGraphics
import Testing
@testable import VibeRes

/// The planner is the pure half of the main-display feature: which display the
/// matcher means, how every origin must move so it lands at (0,0), and whether
/// the window server actually did what was asked (spike F5: the return code is
/// not evidence). The expected origins below are the spike's F2 measurement.
@Suite("Main display planning")
struct MainDisplayPlannerTests {
    // Fake IDs, per BatchApplyTests: EDID fields of an unknown ID read all-ones,
    // so the all-ones matcher binds to every fake ID; a non-all-ones one to none.
    private let allOnes = DisplayMatcher.edid(vendor: .max, model: .max, serial: .max)

    @Test("Matcher binding exactly one active display resolves to it")
    func exactlyOne() {
        #expect(MainDisplayPlanner.resolveTarget(allOnes, activeIDs: [101]) == .target(101))
    }

    @Test("Matcher binding several displays is ambiguous, not a coin flip")
    func ambiguous() {
        #expect(MainDisplayPlanner.resolveTarget(allOnes, activeIDs: [101, 102, 103])
            == .ambiguous(count: 3))
    }

    @Test("Matcher binding nothing reports noMatch")
    func noMatch() {
        let unmatched = DisplayMatcher.edid(vendor: 1, model: 2, serial: 3)
        #expect(MainDisplayPlanner.resolveTarget(unmatched, activeIDs: [101, 102]) == .noMatch)
    }

    @Test("Plan is a pure translation putting the target at (0,0) — spike F2 layout")
    func translationMatchesSpikeF2() {
        let bounds: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            2: CGRect(x: 1074, y: -1080, width: 1920, height: 1080),
            3: CGRect(x: -1486, y: -1440, width: 2560, height: 1440),
        ]
        let plan = MainDisplayPlanner.plan(bounds: bounds, target: 2)
        #expect(plan?[1] == CGPoint(x: -1074, y: 1080))
        #expect(plan?[2] == .zero)
        #expect(plan?[3] == CGPoint(x: -2560, y: -360))
        #expect(plan?.count == 3, "every active display gets an origin (F1)")
    }

    @Test("Plan for a target with no bounds entry is refused")
    func planNeedsTargetBounds() {
        #expect(MainDisplayPlanner.plan(bounds: [1: .zero], target: 2) == nil)
    }

    @Test("Verification accepts the exact arrangement and nothing else")
    func verification() {
        let plan: [CGDirectDisplayID: CGPoint] = [1: .zero, 2: CGPoint(x: -1280, y: 0)]
        let exact: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            2: CGRect(x: -1280, y: 0, width: 1280, height: 720),
        ]
        #expect(MainDisplayPlanner.verified(plan: plan, actualBounds: exact))

        var snapped = exact
        snapped[2] = CGRect(x: -1920, y: 0, width: 1280, height: 720)
        #expect(!MainDisplayPlanner.verified(plan: plan, actualBounds: snapped))

        #expect(!MainDisplayPlanner.verified(plan: plan, actualBounds: [1: exact[1]!]),
                "a display missing from the read-back is a failed verification")
    }
}
