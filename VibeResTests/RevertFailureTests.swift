import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// Revert is the safety net for a mode that made the screen unusable, so it is
/// the one path that must not fail quietly.
///
/// It used to `consume()` the history first, apply every entry through `try?`,
/// and return `snapshot.count` regardless — so a failed restore left the display
/// wrong, the undo state gone, no error, and a success count that was a lie.
///
/// The modes come from the real display because `CGDisplayMode` cannot be
/// constructed; nothing is applied to it, because the apply itself is injected.
@Suite("Revert failure handling")
@MainActor
struct RevertFailureTests {
    private func aRealMode() throws -> CGDisplayMode {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        return try #require(modes?.first, "no display modes available on this machine")
    }

    @Test("A failed restore keeps the entry so the user can try again")
    func failureRetainsHistory() throws {
        let store = DisplayStore()
        let mode = try aRealMode()
        store.revert.record(displayID: 1, displayName: "Built-in", before: mode)
        store.applyMode = { _, _, _ in throw ResolutionSwitcher.Failure.applyMode(.cannotComplete) }

        let restored = store.performRevert()

        #expect(restored == 0, "nothing was restored, so nothing should be reported as restored")
        #expect(store.revert.canRevert, "the only way back must survive a failed attempt")
        #expect(store.lastError != nil, "a failed revert has to say something")
    }

    @Test("A successful restore clears the history and counts once")
    func successConsumesHistory() throws {
        let store = DisplayStore()
        let mode = try aRealMode()
        store.revert.record(displayID: 1, displayName: "Built-in", before: mode)
        store.applyMode = { _, _, _ in }

        #expect(store.performRevert() == 1)
        #expect(!store.revert.canRevert)
    }

    @Test("A partial restore keeps only what failed and counts only what worked")
    func partialRestore() throws {
        let store = DisplayStore()
        let mode = try aRealMode()
        store.revert.record(displayID: 1, displayName: "Built-in", before: mode)
        store.revert.record(displayID: 2, displayName: "LG", before: mode)
        store.applyMode = { _, display, _ in
            if display == 2 { throw ResolutionSwitcher.Failure.applyMode(.cannotComplete) }
        }

        #expect(store.performRevert() == 1)
        #expect(store.revert.entries.map(\.displayID) == [2], "only the display still in the wrong mode")
    }

    @Test("Confirming a change that cannot be made permanent keeps the safety net")
    func failedConfirmationKeepsRecovery() throws {
        let store = DisplayStore()
        let mode = try aRealMode()
        store.revert.record(displayID: 1, displayName: "Built-in", before: mode)
        store.armConfirmationForTesting(mode: mode, display: 1)
        store.applyMode = { _, _, _ in throw ResolutionSwitcher.Failure.completeConfig(.cannotComplete) }

        store.confirmDisplayChange()

        // The mode is still session-scoped and the screen may be unreadable;
        // dropping the countdown here would remove the only automatic way back.
        #expect(store.confirmationSecondsRemaining != nil, "the countdown must stay armed")
        #expect(store.revert.canRevert, "the undo must survive")
        #expect(store.lastError != nil)
    }
}
