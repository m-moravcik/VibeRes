import CoreGraphics
import Foundation
import Observation

/// Single-step undo for resolution changes. Captures every display's mode
/// immediately before a user-initiated apply, so one click on Revert
/// returns the affected displays to their pre-change state. After the
/// revert, history is empty — there is no redo, no stack, no toggle.
///
/// Not persisted across restarts. A user who quit and reopened the app
/// implicitly accepted whatever state was active at quit time.
@Observable
@MainActor
final class RevertHistory {
    struct Entry: Equatable {
        let displayID: CGDirectDisplayID
        let displayName: String
        let before: CGDisplayMode
    }

    private(set) var entries: [Entry] = []

    /// The display that was main before the last recorded batch, when that
    /// batch also moved the menu bar. Restoring it is a fresh translation of
    /// the live arrangement at revert time — no origins are stored here,
    /// because a stored partial plan is exactly what spike F1 mangles.
    private(set) var beforeMainID: CGDirectDisplayID?

    /// True when there's at least one captured change to undo.
    var canRevert: Bool { !entries.isEmpty || beforeMainID != nil }

    /// Human-readable description of what Revert will do, e.g.
    /// "Built-in → 1800×1169" or "Built-in, LG UltraFine".
    var summary: String {
        if entries.isEmpty, beforeMainID != nil { return "main display" }
        let mainSuffix = beforeMainID != nil ? " + main display" : ""
        switch entries.count {
        case 0: return ""
        case 1:
            let e = entries[0]
            return "\(e.displayName) → \(e.before.width)×\(e.before.height)\(mainSuffix)"
        default:
            return entries.map(\.displayName).joined(separator: ", ") + mainSuffix
        }
    }

    /// Adds one display to the history without dropping the others. Used
    /// when a pick joins a running countdown trial, and only for a display
    /// the trial has not touched yet, so it keeps its pre-trial mode.
    /// Replaces any pending entry for the same display.
    func record(displayID: CGDirectDisplayID, displayName: String, before: CGDisplayMode) {
        entries.removeAll { $0.displayID == displayID }
        entries.append(Entry(displayID: displayID, displayName: displayName, before: before))
    }

    /// Capture a new action atomically: a profile apply, auto-apply, Make
    /// main display, or a hand-pick outside a running trial. Replaces any
    /// prior history so Revert undoes "the last action" alone.
    func recordBatch(
        _ batch: [(id: CGDirectDisplayID, name: String, before: CGDisplayMode)],
        beforeMain: CGDirectDisplayID? = nil
    ) {
        entries = batch.map { Entry(displayID: $0.id, displayName: $0.name, before: $0.before) }
        beforeMainID = beforeMain
    }

    /// Returns the captured entries and clears history. Caller is responsible
    /// for actually re-applying the `before` modes; on success there's
    /// nothing left to revert.
    func consume() -> (entries: [Entry], beforeMain: CGDirectDisplayID?) {
        let snapshot = (entries, beforeMainID)
        entries.removeAll()
        beforeMainID = nil
        return snapshot
    }

    /// Drops the entries for displays that are no longer connected, and the
    /// previous main when it is one of them. Used while a trial of hand-picked
    /// sizes is pending, so the displays still here keep their way back.
    func forget(displaysOtherThan connected: Set<CGDirectDisplayID>) {
        entries.removeAll { !connected.contains($0.displayID) }
        if let main = beforeMainID, !connected.contains(main) {
            beforeMainID = nil
        }
    }

    /// Drop history without applying anything. Called when external display
    /// state changes make a saved `before` mode stale.
    func clear() {
        entries.removeAll()
        beforeMainID = nil
    }
}
