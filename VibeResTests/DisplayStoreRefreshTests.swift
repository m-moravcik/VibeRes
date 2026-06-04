import CoreGraphics
import Testing
@testable import VibeRes

@Suite("DisplayStore refresh transitions")
struct DisplayStoreRefreshTests {
    @Test("Main display swap invalidates the popover without triggering auto-apply")
    func mainSwapDoesNotBumpSetChangeToken() {
        let transition = DisplayStore.refreshTransition(
            previousIDs: [1, 2],
            previousMainID: 1,
            nowIDs: [1, 2],
            nowMainID: 2
        )

        #expect(transition.setChanged == false)
        #expect(transition.mainSwapped == true)
        #expect(transition.shouldBumpSetChangeToken == false)
        #expect(transition.shouldClearRevertHistory == false)
        #expect(transition.shouldDismissMenuBarPopover == true)
    }

    @Test("Display set changes trigger auto-apply and clear stale revert history")
    func displaySetChangeBumpsToken() {
        let transition = DisplayStore.refreshTransition(
            previousIDs: [1],
            previousMainID: 1,
            nowIDs: [1, 2],
            nowMainID: 1
        )

        #expect(transition.setChanged == true)
        #expect(transition.mainSwapped == false)
        #expect(transition.shouldBumpSetChangeToken == true)
        #expect(transition.shouldClearRevertHistory == true)
        #expect(transition.shouldDismissMenuBarPopover == true)
    }

    @Test("Wake refresh suppresses callback refresh commits until the settled snapshot")
    func wakeRefreshSuppressesCallbackRefresh() {
        let activeWakeDecision = DisplayStore.callbackRefreshDecision(wakeRefreshActive: true)
        #expect(activeWakeDecision.shouldCancelPendingRefresh == true)
        #expect(activeWakeDecision.shouldScheduleDebouncedRefresh == false)

        let normalDecision = DisplayStore.callbackRefreshDecision(wakeRefreshActive: false)
        #expect(normalDecision.shouldCancelPendingRefresh == false)
        #expect(normalDecision.shouldScheduleDebouncedRefresh == true)
    }

    @Test("Unchanged wake mode signatures do not trigger auto-apply")
    func unchangedWakeModesDoNotTriggerAutoApply() {
        let before = [
            DisplayStore.CurrentModeSignature(displayID: 1, modeID: 10),
            DisplayStore.CurrentModeSignature(displayID: 2, modeID: 20),
        ]
        let after = [
            DisplayStore.CurrentModeSignature(displayID: 2, modeID: 20),
            DisplayStore.CurrentModeSignature(displayID: 1, modeID: 10),
        ].sorted { $0.displayID < $1.displayID }

        #expect(DisplayStore.currentModesChanged(previous: before, now: after) == false)
    }

    @Test("Changed wake mode signatures trigger auto-apply")
    func changedWakeModesTriggerAutoApply() {
        let before = [
            DisplayStore.CurrentModeSignature(displayID: 1, modeID: 10),
            DisplayStore.CurrentModeSignature(displayID: 2, modeID: 20),
        ]
        let after = [
            DisplayStore.CurrentModeSignature(displayID: 1, modeID: 10),
            DisplayStore.CurrentModeSignature(displayID: 2, modeID: 21),
        ]

        #expect(DisplayStore.currentModesChanged(previous: before, now: after) == true)
    }

    @Test("Wake mode changes clear stale revert history before auto-apply")
    func wakeModeChangeClearsRevertBeforeAutoApply() {
        let transition = DisplayStore.RefreshTransition(setChanged: false, mainSwapped: false)
        let effect = DisplayStore.wakeRefreshEffect(transition: transition, modesChanged: true)

        #expect(effect.shouldClearRevertHistory == true)
        #expect(effect.shouldBumpAutoApplyToken == true)
    }

    @Test("Display set changes leave revert clearing to the set-change path")
    func wakeDisplaySetChangeUsesSetChangeRevertPath() {
        let transition = DisplayStore.RefreshTransition(setChanged: true, mainSwapped: false)
        let effect = DisplayStore.wakeRefreshEffect(transition: transition, modesChanged: true)

        #expect(effect.shouldClearRevertHistory == false)
        #expect(effect.shouldBumpAutoApplyToken == false)
    }
}
