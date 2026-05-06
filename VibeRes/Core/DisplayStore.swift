import AppKit
import CoreGraphics
import Observation
import SwiftUI

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
    /// i.e. a monitor was added or removed. UI/profile auto-apply observes this
    /// to know when to re-evaluate "does any saved profile match this layout?".
    private(set) var setChangeToken: Int = 0

    private var registered = false
    private var pendingRefresh: Task<Void, Never>?
    /// Set of display IDs currently considered "active". Mutated only on the
    /// main actor inside `applyRefresh`; compared against the next snapshot to
    /// detect add/remove events.
    private var lastDisplayIDs: Set<CGDirectDisplayID> = []

    init() {
        refresh()
        lastDisplayIDs = Set(displays.map(\.id))
        registerReconfigurationCallback()
    }

    func refresh() {
        applyRefresh(triggeredByCallback: false)
    }

    /// Coalesces bursts of reconfiguration callbacks (macOS often fires several in rapid
    /// succession during a single mode change) into one refresh ~200ms after the last event.
    /// This also avoids briefly seeing transient/ghost displays during the change.
    fileprivate func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.applyRefresh(triggeredByCallback: true)
            self?.dismissStaleMenuBarPopover()
        }
    }

    /// Re-snapshots the display list and bumps `setChangeToken` if a display
    /// was added or removed since the last snapshot. Mode-only changes don't
    /// bump the token — we don't want auto-apply to fight the user when they
    /// manually pick a different resolution.
    private func applyRefresh(triggeredByCallback: Bool) {
        displays = DisplayManager.snapshot()
        let nowIDs = Set(displays.map(\.id))
        if triggeredByCallback && nowIDs != lastDisplayIDs {
            setChangeToken &+= 1
            // A captured `before` mode might reference a display that's
            // no longer attached. Drop the revert history rather than
            // serve up an entry that would silently no-op.
            revert.clear()
        }
        lastDisplayIDs = nowIDs
    }

    /// MenuBarExtra(.window) caches its NSPanel frame from when it was first shown.
    /// After a display reconfiguration the cached origin no longer aligns with the
    /// status item, so the popover appears offset by ~50–200pt. Force-close any
    /// visible status-bar window so the next click rebuilds the popover with fresh
    /// coordinates derived from the updated screen geometry.
    private func dismissStaleMenuBarPopover() {
        for window in NSApp.windows where window.isVisible {
            // MenuBarExtra panels are not standard NSWindows — they're internal
            // _NSPopoverWindow / NSStatusBarWindow subclasses. Match by class
            // name fragment so we don't depend on private types.
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("StatusBar") || className.contains("Popover") {
                window.orderOut(nil)
            }
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
            lastError = "\(error)"
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
