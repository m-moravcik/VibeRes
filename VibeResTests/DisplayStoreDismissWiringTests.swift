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
}
