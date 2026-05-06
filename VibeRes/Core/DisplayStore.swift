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

    private var registered = false
    private var pendingRefresh: Task<Void, Never>?

    init() {
        refresh()
        registerReconfigurationCallback()
    }

    func refresh() {
        displays = DisplayManager.snapshot()
    }

    /// Coalesces bursts of reconfiguration callbacks (macOS often fires several in rapid
    /// succession during a single mode change) into one refresh ~200ms after the last event.
    /// This also avoids briefly seeing transient/ghost displays during the change.
    fileprivate func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func apply(_ mode: CGDisplayMode, to display: CGDirectDisplayID) {
        do {
            try ResolutionSwitcher.apply(mode, to: display)
            lastError = nil
            refresh()
        } catch {
            lastError = "\(error)"
        }
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
