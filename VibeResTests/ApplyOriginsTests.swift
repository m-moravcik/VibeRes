import CoreGraphics
import Testing
@testable import VibeRes

/// Only the guard is unit-testable — everything past it is a live WindowServer
/// transaction (covered by the manual checklist in the plan's final task).
/// The guard is also the safety property: an origin plan that does not cover
/// every active display must never reach CGBeginDisplayConfiguration, because
/// a partial arrangement statement is silently mangled (spike F1) and a
/// vanished display kills the commit outright (F6).
@Suite("Origin transaction coverage guard")
struct ApplyOriginsTests {
    @Test("A plan missing an active display is refused before any CG call")
    func partialPlanRefused() {
        #expect(throws: ResolutionSwitcher.Failure.originCoverage) {
            try ResolutionSwitcher.applyOrigins(
                [101: .zero],
                activeIDs: [101, 102]
            )
        }
    }

    @Test("A plan naming a display that is not active is refused")
    func stalePlanRefused() {
        #expect(throws: ResolutionSwitcher.Failure.originCoverage) {
            try ResolutionSwitcher.applyOrigins(
                [101: .zero, 102: CGPoint(x: 1800, y: 0)],
                activeIDs: [101]
            )
        }
    }

    @Test("An empty plan is refused")
    func emptyPlanRefused() {
        #expect(throws: ResolutionSwitcher.Failure.originCoverage) {
            try ResolutionSwitcher.applyOrigins([:], activeIDs: [])
        }
    }

    @Test("Coverage failure explains itself without a numeric code")
    func coverageCopy() {
        let text = ResolutionSwitcher.Failure.originCoverage.userFacingDescription
        #expect(text.contains("arrangement"))
    }
}
