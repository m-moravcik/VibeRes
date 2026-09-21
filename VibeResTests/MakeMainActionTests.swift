import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// `DisplayStore.makeMain` is the one-off sibling of
/// `ProfileStore.applyMainDisplay`: same full-coverage translation, same
/// guard rules, same F5 read-back. These tests drive it entirely through the
/// injected seams — never a real display reconfiguration.
@Suite("Make main display action")
@MainActor
struct MakeMainActionTests {
    private let fake: CGDirectDisplayID = 5
    private let real: CGDirectDisplayID = 7

    /// Wires `liveArrangement`/`applyOrigins` over a mutable fake arrangement,
    /// same pattern as `MainDisplayApplyTests.arrange`: `applyOrigins` plays
    /// an honest window server, honouring the plan exactly, so the F5
    /// read-back after commit reflects it.
    private func arrange(
        _ store: DisplayStore,
        main: CGDirectDisplayID,
        bounds: [CGDirectDisplayID: CGRect],
        mirrored: Bool = false,
        failWith: Error? = nil
    ) -> (calls: () -> [[CGDirectDisplayID: CGPoint]], currentMain: () -> CGDirectDisplayID) {
        var liveMain = main
        var liveBounds = bounds
        var calls: [[CGDirectDisplayID: CGPoint]] = []
        store.isInMirrorSet = { _ in mirrored }
        store.liveArrangement = { (main: liveMain, bounds: liveBounds) }
        store.applyOrigins = { plan, _ in
            if let failWith { throw failWith }
            calls.append(plan)
            for (id, origin) in plan {
                if var r = liveBounds[id] { r.origin = origin; liveBounds[id] = r }
            }
            if let newMain = plan.first(where: { $0.value == .zero })?.key {
                liveMain = newMain
            }
        }
        return ({ calls }, { liveMain })
    }

    @Test("Making a non-main display main commits a full-coverage translation and arms revert")
    func happyPath() {
        let store = DisplayStore()
        let probes = arrange(store, main: real, bounds: [
            fake: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
            real: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ])

        store.makeMain(fake)

        #expect(probes.calls().count == 1)
        let plan = probes.calls().first
        #expect(plan?[fake] == .zero)
        #expect(plan?[real] == CGPoint(x: 1800, y: 0))
        #expect(plan?.count == 2, "the plan covers every active display")
        #expect(store.revert.beforeMainID == real)
        #expect(store.lastError == nil)
    }

    @Test("Already main is a no-op — no transaction, revert not armed")
    func alreadyMain() {
        let store = DisplayStore()
        let probes = arrange(store, main: real, bounds: [
            fake: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
            real: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ])

        store.makeMain(real)

        #expect(probes.calls().isEmpty)
        #expect(!store.revert.canRevert)
    }

    @Test("A display that is not active is a no-op")
    func notActive() {
        let store = DisplayStore()
        let probes = arrange(store, main: real, bounds: [
            fake: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
            real: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ])

        store.makeMain(99)

        #expect(probes.calls().isEmpty)
        #expect(!store.revert.canRevert)
    }

    @Test("A mirrored arrangement refuses the change and reports why")
    func mirrored() {
        let store = DisplayStore()
        let probes = arrange(store, main: real, bounds: [
            fake: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
            real: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ], mirrored: true)

        store.makeMain(fake)

        #expect(probes.calls().isEmpty)
        #expect(store.lastError == .mirroredArrangement)
    }

    @Test("A throwing transaction is reported and revert is not armed")
    func transactionThrows() {
        let store = DisplayStore()
        _ = arrange(store, main: real, bounds: [
            fake: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
            real: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ], failWith: ResolutionSwitcher.Failure.originCoverage)

        store.makeMain(fake)

        #expect(store.lastError != nil)
        #expect(!store.revert.canRevert)
    }

    @Test("A commit that lands off the planned origin is reported as adjusted (F5), but revert still arms")
    func adjusted() {
        let store = DisplayStore()
        var liveMain = real
        var liveBounds: [CGDirectDisplayID: CGRect] = [
            fake: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
            real: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ]
        var calls: [[CGDirectDisplayID: CGPoint]] = []
        store.isInMirrorSet = { _ in false }
        store.liveArrangement = { (main: liveMain, bounds: liveBounds) }
        // A dishonest window server: the commit does not throw and the target
        // does land at (0,0) — but `real` settles one point off the planned
        // origin. Only the F5 read-back comparison against the plan catches it.
        store.applyOrigins = { plan, _ in
            calls.append(plan)
            for (id, origin) in plan {
                guard var r = liveBounds[id] else { continue }
                r.origin = id == real ? CGPoint(x: origin.x + 1, y: origin.y) : origin
                liveBounds[id] = r
            }
            if let newMain = plan.first(where: { $0.value == .zero })?.key {
                liveMain = newMain
            }
        }

        store.makeMain(fake)

        #expect(calls.count == 1, "the transaction did commit")
        #expect(store.revert.beforeMainID == real, "the commit did happen, so revert must still know who was main before")
        #expect(store.lastError == .mainDisplayAdjusted)
    }
}
