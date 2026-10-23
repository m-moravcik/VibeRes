import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// `RefreshTransition.shouldDismissMenuBarPopover` says the popover should only
/// close when the display *set* changed or the main display was swapped — a
/// mode-only change leaves it open so the user can see the outcome note and the
/// Revert row.
///
/// The wake path honours that. The debounced reconfiguration path discarded the
/// transition and dismissed unconditionally, which closed the popover roughly
/// 200 ms after every resolution change and made the 0.8.0 fallback warning
/// effectively invisible on the happy path.
///
/// These tests drive the wiring rather than the rule: `refreshTransition` is
/// already covered in DisplayStoreRefreshTests, and a test of the rule alone
/// would have passed before the fix.
@Suite("Popover dismissal wiring")
@MainActor
struct DisplayStoreDismissWiringTests {
    @Test("A refresh that changes no displays must not close the popover")
    func modeOnlyRefreshKeepsPopoverOpen() async {
        let store = DisplayStore()
        var dismissals = 0
        store.dismissStalePopoverOverride = { dismissals += 1 }

        // Nothing about the attached displays changes during the test, so the
        // transition is neither setChanged nor mainSwapped.
        store.scheduleRefresh()
        try? await Task.sleep(for: .milliseconds(400))

        #expect(dismissals == 0, "the popover was dismissed for a refresh that changed nothing")
    }

    // MARK: A main-display swap VibeRes made itself
    //
    // A profile that moves the main display used to close the popover about
    // 200 ms after the apply: the reconfiguration refresh saw the swap and
    // dismissed, and that refresh was the very one that rolls the cards'
    // numbers, moves the MAIN badge and turns the pill active.

    private static let swap = DisplayStore.RefreshTransition(setChanged: false, mainSwapped: true)

    @Test("A swap VibeRes made keeps the popover open and re-anchors it on close")
    func ownSwapKeepsPopoverOpen() {
        let store = DisplayStore()
        var dismissals = 0
        store.dismissStalePopoverOverride = { dismissals += 1 }
        store.popoverIsOpenOverride = { true }
        let now = Date()

        store.expectOwnMainChange(now: now)
        store.handlePopover(after: Self.swap, now: now.addingTimeInterval(0.4))

        #expect(dismissals == 0)
        #expect(store.popoverNeedsReanchor)

        store.popoverDidClose()
        #expect(dismissals == 1, "closing the popover did not re-anchor its window")
        #expect(!store.popoverNeedsReanchor)

        store.popoverDidClose()
        #expect(dismissals == 1, "a later close re-anchored again")
    }

    @Test("A swap VibeRes made after the popover already closed re-anchors at once")
    func ownSwapWithPopoverClosedReanchorsAtOnce() {
        let store = DisplayStore()
        var dismissals = 0
        store.dismissStalePopoverOverride = { dismissals += 1 }
        store.popoverIsOpenOverride = { false }
        let now = Date()

        store.expectOwnMainChange(now: now)
        store.handlePopover(after: Self.swap, now: now.addingTimeInterval(0.4))

        #expect(dismissals == 1, "a popover closed before the refresh kept its stale anchor")
        #expect(!store.popoverNeedsReanchor)
    }

    @Test("A swap made in System Settings still closes the popover at once")
    func foreignSwapDismisses() {
        let store = DisplayStore()
        var dismissals = 0
        store.dismissStalePopoverOverride = { dismissals += 1 }

        store.handlePopover(after: Self.swap)

        #expect(dismissals == 1)
        #expect(!store.popoverNeedsReanchor)
    }

    @Test("An expectation that has run out does not hide a later swap")
    func staleExpectationExpires() {
        let store = DisplayStore()
        var dismissals = 0
        store.dismissStalePopoverOverride = { dismissals += 1 }
        let now = Date()

        store.expectOwnMainChange(now: now)
        store.handlePopover(
            after: Self.swap,
            now: now.addingTimeInterval(DisplayStore.ownMainChangeWindow + 1)
        )

        #expect(dismissals == 1)
    }

    @Test("Each expectation covers one swap")
    func expectationIsConsumed() {
        let store = DisplayStore()
        var dismissals = 0
        store.dismissStalePopoverOverride = { dismissals += 1 }
        store.popoverIsOpenOverride = { true }
        let now = Date()

        store.expectOwnMainChange(now: now)
        store.handlePopover(after: Self.swap, now: now)
        store.handlePopover(after: Self.swap, now: now.addingTimeInterval(0.1))

        #expect(dismissals == 1, "a second swap rode on the first one's expectation")
    }

    @Test("A display set change still closes the popover, even after our own swap")
    func setChangeAlwaysDismisses() {
        let store = DisplayStore()
        var dismissals = 0
        store.dismissStalePopoverOverride = { dismissals += 1 }

        store.expectOwnMainChange()
        store.handlePopover(after: .init(setChanged: true, mainSwapped: true))

        #expect(dismissals == 1)
    }
}
