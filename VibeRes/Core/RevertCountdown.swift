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

    /// Starts (or restarts) the countdown. Re-arming replaces the previous
    /// deadline rather than stacking, so a run of quick changes gets one window
    /// measured from the last of them.
    mutating func arm(at now: Date, seconds: Int) {
        deadline = now.addingTimeInterval(TimeInterval(seconds))
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
}
