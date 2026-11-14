import Foundation
import Testing
@testable import VibeRes

/// The one place VibeRes could leave someone stuck: a mode that produces a black
/// or unreadable screen has no way out, because the popover is *on* that screen.
/// `ResolutionSwitcher.apply(scope:)` has always accepted `.forSession` and was
/// never passed it.
///
/// The countdown is what makes a bad mode survivable: apply for the session only,
/// and revert unless the user confirms. A dialog alone would not help — nobody
/// can click what they cannot see — so the timeout, not the button, is the safety
/// net. The button just avoids punishing people who walk away.
@Suite("Revert countdown")
struct RevertCountdownTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("An armed countdown waits, reporting whole seconds left")
    func waitsAndCountsDown() {
        var countdown = RevertCountdown()
        countdown.arm(at: start, seconds: 12)

        #expect(countdown.state(at: start) == .waiting(secondsRemaining: 12))
        #expect(countdown.state(at: start.addingTimeInterval(3.4)) == .waiting(secondsRemaining: 9))
        // Rounds up, so the display never shows "0 seconds" while still waiting.
        #expect(countdown.state(at: start.addingTimeInterval(11.6)) == .waiting(secondsRemaining: 1))
    }

    @Test("Reaching the deadline expires, which is what reverts the screen")
    func expiresAtDeadline() {
        var countdown = RevertCountdown()
        countdown.arm(at: start, seconds: 12)

        #expect(countdown.state(at: start.addingTimeInterval(12)) == .expired)
        #expect(countdown.state(at: start.addingTimeInterval(99)) == .expired)
    }

    @Test("Confirming ends the countdown for good")
    func confirmWins() {
        var countdown = RevertCountdown()
        countdown.arm(at: start, seconds: 12)
        countdown.confirm()

        #expect(countdown.state(at: start.addingTimeInterval(1)) == .inactive)
        // Even past the old deadline: a confirmed change must never be undone.
        #expect(countdown.state(at: start.addingTimeInterval(999)) == .inactive)
    }

    @Test("An unarmed countdown is inactive, not expired")
    func idleIsNotExpiry() {
        let countdown = RevertCountdown()
        #expect(countdown.state(at: start) == .inactive)
    }

    @Test("Re-arming replaces the previous deadline instead of stacking")
    func reArmingReplaces() {
        var countdown = RevertCountdown()
        countdown.arm(at: start, seconds: 12)
        countdown.arm(at: start.addingTimeInterval(5), seconds: 12)

        // Would already be expired under the first deadline.
        #expect(countdown.state(at: start.addingTimeInterval(13)) == .waiting(secondsRemaining: 4))
    }

    @Test("The bar's share of the window falls linearly from full to empty")
    func fractionDrainsLinearly() {
        var countdown = RevertCountdown()
        #expect(countdown.window == nil)

        countdown.arm(at: start, seconds: 12)
        #expect(countdown.window?.fractionRemaining(at: start) == 1)
        // A quarter of 12 s gone leaves three quarters, at any instant rather
        // than whole seconds, or the bar could not slide.
        #expect(countdown.window?.fractionRemaining(at: start.addingTimeInterval(3)) == 0.75)
        #expect(countdown.window?.fractionRemaining(at: start.addingTimeInterval(10.5)) == 0.125)
        // Never below empty, even if the revert runs a moment late.
        #expect(countdown.window?.fractionRemaining(at: start.addingTimeInterval(20)) == 0)
    }

    @Test("Re-arming refills the bar; confirming removes it")
    func fractionFollowsArmAndConfirm() {
        var countdown = RevertCountdown()
        countdown.arm(at: start, seconds: 12)
        countdown.arm(at: start.addingTimeInterval(6), seconds: 12)
        #expect(countdown.window?.fractionRemaining(at: start.addingTimeInterval(6)) == 1)

        countdown.confirm()
        #expect(countdown.window == nil)
    }
}
