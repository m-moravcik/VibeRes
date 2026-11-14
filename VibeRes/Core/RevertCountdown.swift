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

    private var deadline: Date?
    private var window: TimeInterval = 0

    /// Starts (or restarts) the countdown. Re-arming replaces the previous
    /// deadline rather than stacking, so a run of quick changes gets one window
    /// measured from the last of them.
    mutating func arm(at now: Date, seconds: Int) {
        window = TimeInterval(seconds)
        deadline = now.addingTimeInterval(window)
    }

    /// The user said the screen is fine. A confirmed change must never be undone,
    /// so this is permanent rather than a pause.
    mutating func confirm() {
        deadline = nil
    }

    func state(at now: Date) -> State {
        guard let deadline else { return .inactive }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { return .expired }
        // Rounded up: the label must never read "0 seconds" while still waiting.
        return .waiting(secondsRemaining: Int(remaining.rounded(.up)))
    }

    /// How much of the window is left, from 1 when armed to 0 at the deadline,
    /// or nil when nothing is pending. Continuous, unlike `state(at:)`, so the
    /// bar that drains with it can slide rather than step.
    func fractionRemaining(at now: Date) -> Double? {
        guard let deadline, window > 0 else { return nil }
        return min(max(deadline.timeIntervalSince(now) / window, 0), 1)
    }
}
