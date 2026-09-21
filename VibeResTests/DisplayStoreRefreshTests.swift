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

    // MARK: Settle-loop early exit
    //
    // The loop used to run all four samples every time, so every lid-open cost
    // a fixed 3.75 s of stale display list and an equally delayed auto-apply,
    // even when the setup had settled at the first sample.

    @Test("Two identical samples in a row mean the display set has settled")
    func settledAfterTwoIdenticalSamples() {
        let sample = [
            DisplayStore.CurrentModeSignature(displayID: 1, modeID: 10),
            DisplayStore.CurrentModeSignature(displayID: 2, modeID: 20),
        ]
        #expect(DisplayStore.wakeSettled(previous: sample, now: sample) == true)
    }

    @Test("The first sample can never settle — there is nothing to compare it to")
    func firstSampleNeverSettles() {
        let sample = [DisplayStore.CurrentModeSignature(displayID: 1, modeID: 10)]
        #expect(DisplayStore.wakeSettled(previous: nil, now: sample) == false)
    }

    @Test("A display still arriving keeps the loop running")
    func changingSampleDoesNotSettle() {
        let first = [DisplayStore.CurrentModeSignature(displayID: 1, modeID: 10)]
        let second = first + [DisplayStore.CurrentModeSignature(displayID: 2, modeID: 20)]
        #expect(DisplayStore.wakeSettled(previous: first, now: second) == false)
    }

    @Test("A mode still changing on the same monitors keeps the loop running")
    func changingModeDoesNotSettle() {
        let first = [DisplayStore.CurrentModeSignature(displayID: 1, modeID: 10)]
        let second = [DisplayStore.CurrentModeSignature(displayID: 1, modeID: 11)]
        #expect(DisplayStore.wakeSettled(previous: first, now: second) == false)
    }

    @Test("Two empty samples are the transient window, not a settled state")
    func emptySampleNeverSettles() {
        // Riding this out is the whole reason the loop exists: WindowServer
        // briefly answers with no displays at all after a wake.
        #expect(DisplayStore.wakeSettled(previous: [], now: []) == false)
    }

    @Test("The settle window still has a ceiling")
    func settleWindowIsBounded() {
        #expect(DisplayStore.wakeSettleDelaysMs.reduce(0, +) == 3750)
    }
}
