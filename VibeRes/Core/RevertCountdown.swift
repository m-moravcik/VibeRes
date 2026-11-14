import Foundation

/// Deadline for automatically undoing a display change the user has not
/// confirmed.
///
/// This closes the one hole in VibeRes's recoverability: a mode that produces a
/// black or unreadable screen leaves no way out, because the popover is on that
/// screen. The *timeout* is the safety net, not the button — nobody can click
/// what they cannot see. The Keep button exists so someone who can see fine is
/// not punished for walking away.
///
/// Pure and time-injected so the behaviour is testable without waiting.
struct RevertCountdown {
    enum State: Equatable {
        case inactive
        case waiting(secondsRemaining: Int)
        case expired
    }

    /// A pending window: when it reverts and how long it was. A value, so a
    /// view that is fading out can keep the one it had and go on draining.
    struct Window: Equatable {
        let deadline: Date
        let length: TimeInterval

        /// How much of the window is left, from 1 when armed to 0 at the
        /// deadline. Continuous, unlike `state(at:)`, so the bar that drains
        /// with it can slide rather than step.
        func fractionRemaining(at now: Date) -> Double {
            guard length > 0 else { return 0 }
            return min(max(deadline.timeIntervalSince(now) / length, 0), 1)
        }
    }

    /// The pending window, or nil when nothing waits for confirmation.
    private(set) var window: Window?

    /// Starts (or restarts) the countdown. Re-arming replaces the previous
    /// deadline rather than stacking, so a run of quick changes gets one window
    /// measured from the last of them.
    mutating func arm(at now: Date, seconds: Int) {
        let length = TimeInterval(seconds)
        window = Window(deadline: now.addingTimeInterval(length), length: length)
    }

    /// The user said the screen is fine. A confirmed change must never be undone,
    /// so this is permanent rather than a pause.
    mutating func confirm() {
        window = nil
    }

    func state(at now: Date) -> State {
        guard let deadline = window?.deadline else { return .inactive }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { return .expired }
        // Rounded up: the label must never read "0 seconds" while still waiting.
        return .waiting(secondsRemaining: Int(remaining.rounded(.up)))
    }
}
