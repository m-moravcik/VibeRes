import AppKit
import CoreGraphics
import Observation
import SwiftUI
import os.log

private let displayLog = Logger(subsystem: "sk.moravcik.VibeRes", category: "display")

/// Observable view-model the UI binds to. Refreshes the display list when the menu opens
/// and whenever macOS posts a reconfiguration event (display added, removed, mode changed
/// from System Settings while we're running).
@Observable
@MainActor
final class DisplayStore {
    private(set) var displays: [DisplayInfo] = []
    private(set) var lastError: String?

    /// Single-step revert history. Populated by `apply(...)` on user clicks
    /// and by ProfileStore on profile apply. Cleared when the display set
    /// changes (a captured `before` mode would reference a phantom display).
    let revert = RevertHistory()

    /// Bumps once each time the active display *set* (not just modes) changes —
    /// i.e. a monitor was added or removed. `autoApplyToken` is the UI-facing
    /// signal for profile re-evaluation.
    private(set) var setChangeToken: Int = 0

    /// Bumps when saved profiles should be re-evaluated: display set changes,
    /// and settled wake refreshes where macOS may have reset modes even though
    /// the same physical monitors are still attached.
    private(set) var autoApplyToken: Int = 0

    private var registered = false
    private var pendingRefresh: Task<Void, Never>?
    private var pendingWakeRefresh: Task<Void, Never>?
    private var wakeRefreshGeneration = 0
    /// Set of display IDs currently considered "active". Mutated only on the
    /// main actor inside `applyRefresh`; compared against the next snapshot to
    /// detect add/remove events.
    private var lastDisplayIDs: Set<CGDirectDisplayID> = []

    struct RefreshTransition: Equatable {
        let setChanged: Bool
        let mainSwapped: Bool

        var shouldBumpSetChangeToken: Bool { setChanged }
        var shouldClearRevertHistory: Bool { setChanged }
        var shouldDismissMenuBarPopover: Bool { setChanged || mainSwapped }
    }

    struct CallbackRefreshDecision: Equatable {
        let shouldCancelPendingRefresh: Bool
        let shouldScheduleDebouncedRefresh: Bool
    }

    struct CurrentModeSignature: Equatable {
        let displayID: CGDirectDisplayID
        let modeID: Int32?
    }

    struct WakeRefreshEffect: Equatable {
        let shouldClearRevertHistory: Bool
        let shouldBumpAutoApplyToken: Bool
    }

    nonisolated static func refreshTransition(
        previousIDs: Set<CGDirectDisplayID>,
        previousMainID: CGDirectDisplayID?,
        nowIDs: Set<CGDirectDisplayID>,
        nowMainID: CGDirectDisplayID?
    ) -> RefreshTransition {
        let setChanged = nowIDs != previousIDs
        let mainSwapped = previousMainID != nil
            && nowMainID != nil
            && previousMainID != nowMainID
        return RefreshTransition(setChanged: setChanged, mainSwapped: mainSwapped)
    }

    nonisolated static func callbackRefreshDecision(wakeRefreshActive: Bool) -> CallbackRefreshDecision {
        CallbackRefreshDecision(
            shouldCancelPendingRefresh: wakeRefreshActive,
            shouldScheduleDebouncedRefresh: !wakeRefreshActive
        )
    }

    nonisolated static func currentModeSignatures(_ displays: [DisplayInfo]) -> [CurrentModeSignature] {
        displays
            .map { CurrentModeSignature(displayID: $0.id, modeID: $0.currentMode?.ioDisplayModeID) }
            .sorted { $0.displayID < $1.displayID }
    }

    nonisolated static func currentModesChanged(
        previous: [CurrentModeSignature],
        now: [CurrentModeSignature]
    ) -> Bool {
        previous != now
    }

    nonisolated static func wakeRefreshEffect(
        transition: RefreshTransition,
        modesChanged: Bool
    ) -> WakeRefreshEffect {
        let sameDisplaySetModeChanged = !transition.setChanged && modesChanged
        return WakeRefreshEffect(
            shouldClearRevertHistory: sameDisplaySetModeChanged,
            shouldBumpAutoApplyToken: sameDisplaySetModeChanged
        )
    }

    init() {
        refresh()
        lastDisplayIDs = Set(displays.map(\.id))
        registerReconfigurationCallback()
        // Launch race: when the app starts via Launch-at-Login (or wakes
        // alongside the login session), WindowServer may not yet answer
        // CGGetActiveDisplayList, so the initial snapshot is empty and no
        // reconfiguration callback ever fires (nothing *changed*, displays
        // were always there from the user's POV). Retry a few times with
        // backoff to recover without requiring a manual Refresh click.
        if displays.isEmpty {
            scheduleInitialRetries()
        }
        // Belt-and-braces safety net: CGDisplayRegisterReconfigurationCallback
        // occasionally misses certain System Settings changes (notably "move
        // menu bar to other display"). NSApplication.didChangeScreenParameters
        // fires reliably for those, so we observe both and reuse the same
        // scheduleRefresh path.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Hop onto the MainActor even though `.main` queue already runs
            // here — Swift 6 strict concurrency requires the explicit boundary
            // because the observer closure itself isn't actor-isolated.
            Task { @MainActor in self?.scheduleRefresh() }
        }
        // Wake-from-sleep doesn't always fire a CG reconfiguration callback
        // (the display set is unchanged), but the same launch-race window
        // can recur — WindowServer briefly returns an empty or incomplete
        // list before settling. Re-run the retry loop in callback mode so
        // the final settled set still triggers auto-apply.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                displayLog.notice("didWakeNotification: scheduling settled refresh, displaysBefore=\(self.displays.count)")
                self.scheduleWakeRefresh()
            }
        }
    }

    /// Re-runs `refresh()` a handful of times after a moment, in case the
    /// caller hit a transient empty-list window (launch race, wake-from-sleep).
    /// Stops as soon as any display appears.
    private func scheduleInitialRetries(
        triggeredByCallback: Bool = false,
        stopWhenDisplayAppears: Bool = true
    ) {
        Task { @MainActor [weak self] in
            for delayMs in [250, 500, 1000, 2000] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard let self else { return }
                let transition = self.applyRefresh(triggeredByCallback: triggeredByCallback)
                if triggeredByCallback && transition.shouldDismissMenuBarPopover {
                    self.dismissStaleMenuBarPopover()
                }
                if stopWhenDisplayAppears && !self.displays.isEmpty { return }
            }
        }
    }

    /// Wake can expose transient empty or partial display lists. Sample for a
    /// short settle window, then commit only the last snapshot so auto-apply
    /// does not run against a known-transient setup.
    private func scheduleWakeRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        pendingWakeRefresh?.cancel()
        wakeRefreshGeneration &+= 1
        let generation = wakeRefreshGeneration
        let preWakeModes = Self.currentModeSignatures(displays)
        pendingWakeRefresh = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.wakeRefreshGeneration == generation {
                    self.pendingWakeRefresh = nil
                }
            }

            var settledDisplays: [DisplayInfo] = []
            for delayMs in [250, 500, 1000, 2000] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else { return }
                settledDisplays = DisplayManager.snapshot()
                displayLog.notice("wakeRefresh sample: displaysNow=\(settledDisplays.count) previouslyCommitted=\(self.displays.count)")
            }

            guard !Task.isCancelled else { return }
            let postWakeModes = Self.currentModeSignatures(settledDisplays)
            let transition = self.applySnapshot(settledDisplays, triggeredByCallback: true)
            let modesChanged = Self.currentModesChanged(previous: preWakeModes, now: postWakeModes)
            let wakeEffect = Self.wakeRefreshEffect(transition: transition, modesChanged: modesChanged)
            if wakeEffect.shouldClearRevertHistory {
                self.revert.clear()
            }
            if wakeEffect.shouldBumpAutoApplyToken {
                self.autoApplyToken &+= 1
                displayLog.notice("wakeRefresh auto-apply bump: token=\(self.autoApplyToken) displaysNow=\(self.displays.count)")
            } else if !transition.setChanged {
                displayLog.notice("wakeRefresh no-op: display set and current modes unchanged")
            }
            self.dismissStaleMenuBarPopover()
            displayLog.notice("wakeRefresh committed: setChanged=\(transition.setChanged) mainSwapped=\(transition.mainSwapped) displaysNow=\(self.displays.count) token=\(self.setChangeToken)")

            if self.displays.isEmpty {
                self.scheduleInitialRetries(triggeredByCallback: true, stopWhenDisplayAppears: false)
            }
        }
    }

    func refresh() {
        applyRefresh(triggeredByCallback: false)
    }

    /// Coalesces bursts of reconfiguration callbacks (macOS often fires several in rapid
    /// succession during a single mode change) into one refresh ~200ms after the last event.
    /// This also avoids briefly seeing transient/ghost displays during the change.
    fileprivate func scheduleRefresh() {
        let decision = Self.callbackRefreshDecision(wakeRefreshActive: pendingWakeRefresh != nil)
        if decision.shouldCancelPendingRefresh {
            pendingRefresh?.cancel()
            pendingRefresh = nil
        }
        guard decision.shouldScheduleDebouncedRefresh else {
            displayLog.notice("scheduleRefresh deferred: wake refresh active")
            return
        }

        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            _ = self?.applyRefresh(triggeredByCallback: true)
            self?.dismissStaleMenuBarPopover()
        }
    }

    /// Re-snapshots the display list and bumps `setChangeToken` if a display
    /// was added or removed since the last snapshot. Mode-only changes don't
    /// bump the token — we don't want auto-apply to fight the user when they
    /// manually pick a different resolution.
    ///
    /// Also detects "main display swap" — when the same monitors stay
    /// attached but the user moves the menu bar from one to the other via
    /// System Settings → Displays → Arrange. The MenuBarExtra panel's
    /// cached coordinates point at the old primary; without the swap
    /// trigger the popover appears off-screen on the new primary's edge.
    @discardableResult
    private func applyRefresh(triggeredByCallback: Bool) -> RefreshTransition {
        applySnapshot(DisplayManager.snapshot(), triggeredByCallback: triggeredByCallback)
    }

    @discardableResult
    private func applySnapshot(
        _ snapshot: [DisplayInfo],
        triggeredByCallback: Bool
    ) -> RefreshTransition {
        let previousMainID = displays.first(where: { $0.isMain })?.id
        displays = snapshot
        let nowIDs = Set(displays.map(\.id))
        let nowMainID = displays.first(where: { $0.isMain })?.id

        let transition = Self.refreshTransition(
            previousIDs: lastDisplayIDs,
            previousMainID: previousMainID,
            nowIDs: nowIDs,
            nowMainID: nowMainID
        )

        if triggeredByCallback {
            if transition.shouldBumpSetChangeToken {
                setChangeToken &+= 1
                autoApplyToken &+= 1
                displayLog.notice("applyRefresh bump: setChanged=\(transition.setChanged) mainSwapped=\(transition.mainSwapped) setToken=\(self.setChangeToken) autoApplyToken=\(self.autoApplyToken) ids=\(nowIDs.map { String($0) }.joined(separator: ","), privacy: .public)")
            } else if transition.shouldDismissMenuBarPopover {
                displayLog.notice("applyRefresh UI-only invalidation: setChanged=\(transition.setChanged) mainSwapped=\(transition.mainSwapped) ids=\(nowIDs.map { String($0) }.joined(separator: ","), privacy: .public)")
            }
            if transition.shouldClearRevertHistory {
                // A captured `before` mode might reference a display that's
                // no longer attached. Drop the revert history rather than
                // serve up an entry that would silently no-op.
                revert.clear()
            }
        }
        lastDisplayIDs = nowIDs
        return transition
    }

    /// MenuBarExtra(.window) caches its NSPanel frame from when it was first shown.
    /// After a display reconfiguration the cached origin no longer aligns with the
    /// status item, so the popover appears offset by ~50–200pt — or, worse, on
    /// the wrong monitor entirely when the user has multiple displays.
    ///
    /// Force-close every status-bar / popover window (visible or hidden) AND
    /// reset its cached frame origin so the next click rebuilds the panel
    /// with fresh coordinates derived from the updated screen geometry.
    private func dismissStaleMenuBarPopover() {
        for window in NSApp.windows {
            // MenuBarExtra panels are not standard NSWindows — they're internal
            // _NSPopoverWindow / NSStatusBarWindow subclasses. Match by class
            // name fragment so we don't depend on private types.
            let className = String(describing: type(of: window))
            guard className.contains("MenuBarExtra")
                || className.contains("StatusBar")
                || className.contains("Popover") else { continue }
            if window.isVisible {
                window.orderOut(nil)
            }
            // Reset origin to (0, 0). SwiftUI recomputes the proper anchor
            // location on the next `orderFront(...)` from the live status-item
            // position — but only if the cached origin doesn't match the old
            // primary-display geometry. Forcing it to zero guarantees the
            // recomputation runs.
            window.setFrameOrigin(.zero)
        }
    }

    func apply(_ mode: CGDisplayMode, to display: CGDirectDisplayID) {
        do {
            // Capture the pre-change mode so a follow-up Revert click can
            // restore it. Skip when the click is a no-op (mode === current).
            if let info = displays.first(where: { $0.id == display }),
               let current = info.currentMode,
               current.ioDisplayModeID != mode.ioDisplayModeID {
                revert.record(displayID: display, displayName: info.name, before: current)
            }
            try ResolutionSwitcher.apply(mode, to: display)
            lastError = nil
            refresh()
        } catch {
            lastError = error.userFacingText
        }
    }

    /// Re-apply each display's `before` mode and clear the history. Returns
    /// the count of displays touched so the caller can surface a toast.
    @discardableResult
    func performRevert() -> Int {
        let snapshot = revert.consume()
        for entry in snapshot {
            try? ResolutionSwitcher.apply(entry.before, to: entry.displayID)
        }
        if !snapshot.isEmpty { refresh() }
        return snapshot.count
    }

    private func registerReconfigurationCallback() {
        guard !registered else { return }
        registered = true
        let unmanaged = Unmanaged.passUnretained(self)
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, unmanaged.toOpaque())
    }
}

private func displayReconfigCallback(
    _: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let store = Unmanaged<DisplayStore>.fromOpaque(userInfo).takeUnretainedValue()
    // The "after" notification is the safe one to act on — "begin" fires before the change lands.
    guard !flags.contains(.beginConfigurationFlag) else { return }
    Task { @MainActor in store.scheduleRefresh() }
}
