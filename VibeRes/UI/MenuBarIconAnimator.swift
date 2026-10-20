import AppKit
import Observation

/// Plays the menu bar icon's switch animation.
///
/// A MenuBarExtra label is rasterised into the status item, so SwiftUI effects
/// do not run there. Instead the label redraws the icon for `phase`, and a
/// ~30 Hz ticker advances it. The ticker exists only while the animation
/// plays: none at rest, none outliving the animation, and a burst of switches
/// restarts the one that is running rather than starting another.
@Observable
@MainActor
final class MenuBarIconAnimator {
    /// Cancels a running ticker.
    typealias Cancel = () -> Void
    /// Starts a repeating ticker and returns how to stop it.
    typealias StartTicker = (_ interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void) -> Cancel

    static let frameInterval: TimeInterval = 1.0 / 30

    /// Seconds into the animation; nil at rest.
    private(set) var phase: Double?

    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let reduceMotion: () -> Bool
    @ObservationIgnored private let startTicker: StartTicker
    @ObservationIgnored private var cancelTicker: Cancel?
    @ObservationIgnored private var startedAt: TimeInterval = 0

    /// The clock, the Reduce Motion setting and the ticker are injected so a
    /// test can step the animation frame by frame.
    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        startTicker: @escaping StartTicker = MenuBarIconAnimator.timerTicker
    ) {
        self.now = now
        self.reduceMotion = reduceMotion
        self.startTicker = startTicker
    }

    var isTicking: Bool { cancelTicker != nil }

    /// Starts the animation, or restarts it if it is already playing. With
    /// Reduce Motion on, the icon stays at rest.
    func play() {
        guard !reduceMotion() else {
            stop()
            return
        }
        startedAt = now()
        phase = 0
        if cancelTicker == nil {
            cancelTicker = startTicker(Self.frameInterval) { [weak self] in self?.tick() }
        }
    }

    func tick() {
        let elapsed = now() - startedAt
        if elapsed >= MenuBarIcon.duration {
            stop()
        } else {
            phase = elapsed
        }
    }

    func stop() {
        cancelTicker?()
        cancelTicker = nil
        phase = nil
    }

    /// A main run loop timer in the common modes, so the animation keeps
    /// running while a menu is tracking.
    nonisolated static func timerTicker(
        interval: TimeInterval,
        tick: @escaping @MainActor @Sendable () -> Void
    ) -> Cancel {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}
