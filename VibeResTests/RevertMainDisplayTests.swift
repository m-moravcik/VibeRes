import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// Reverting a main-display change is not "replay stored origins" — stored
/// origins would cover only the displays that changed mode, which is the
/// partial arrangement statement spike F1 mangles. It is the same operation
/// as setting main: a fresh full-coverage translation of the live
/// arrangement, targeting the old main.
@Suite("Revert restores the previous main display")
@MainActor
struct RevertMainDisplayTests {
    @Test("performRevert translates the live arrangement back to the old main")
    func revertsMain() {
        let store = DisplayStore()
        var plans: [[CGDirectDisplayID: CGPoint]] = []
        store.applyMode = { _, _, _ in }
        store.liveArrangement = {
            (main: 7, bounds: [
                5: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
                7: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            ])
        }
        store.applyOrigins = { plan, _ in plans.append(plan) }
        store.revert.recordBatch([], beforeMain: 5)

        let restored = store.performRevert()

        #expect(plans.count == 1)
        #expect(plans.first?[5] == .zero)
        #expect(plans.first?[7] == CGPoint(x: 1800, y: 0))
        #expect(restored == 1)
        #expect(!store.revert.canRevert)
    }

    @Test("An old main that is no longer active is skipped, not guessed at")
    func staleMainSkipped() {
        let store = DisplayStore()
        var originCalled = false
        store.applyMode = { _, _, _ in }
        store.liveArrangement = { (main: 7, bounds: [7: .zero]) }
        store.applyOrigins = { _, _ in originCalled = true }
        store.revert.recordBatch([], beforeMain: 5)

        _ = store.performRevert()

        #expect(!originCalled)
        #expect(!store.revert.canRevert, "nothing left to restore onto — history clears")
    }

    @Test("A failed origin restore keeps the way back armed")
    func failedRestoreStaysArmed() {
        let store = DisplayStore()
        store.applyMode = { _, _, _ in }
        store.liveArrangement = {
            (main: 7, bounds: [5: CGRect(x: -1800, y: 0, width: 1800, height: 1169), 7: .zero])
        }
        store.applyOrigins = { _, _ in throw ResolutionSwitcher.Failure.originCoverage }
        store.revert.recordBatch([], beforeMain: 5)

        let restored = store.performRevert()

        #expect(restored == 0)
        #expect(store.revert.canRevert, "the display is still not where the user wanted it")
        #expect(store.revert.consume().beforeMain == 5)
    }
}
