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

    /// True when there's at least one captured change to undo.
    var canRevert: Bool { !entries.isEmpty }

    /// Human-readable description of what Revert will do, e.g.
    /// "Built-in → 1800×1169" or "Built-in, LG UltraFine".
    var summary: String {
        switch entries.count {
        case 0: return ""
        case 1:
            let e = entries[0]
            return "\(e.displayName) → \(e.before.width)×\(e.before.height)"
        default:
            return entries.map(\.displayName).joined(separator: ", ")
        }
    }

    /// Capture the current state of one display before a user-initiated
    /// apply. Replaces any pending entry for the same display so we always
    /// undo the most recent action, never an older one.
    func record(displayID: CGDirectDisplayID, displayName: String, before: CGDisplayMode) {
        entries.removeAll { $0.displayID == displayID }
        entries.append(Entry(displayID: displayID, displayName: displayName, before: before))
    }

    /// Capture multiple displays atomically — used when a single click
    /// changes several monitors (profile apply). Replaces any prior history
    /// so Revert undoes "the last action" not "the last single switch".
    func recordBatch(_ batch: [(id: CGDirectDisplayID, name: String, before: CGDisplayMode)]) {
        entries = batch.map { Entry(displayID: $0.id, displayName: $0.name, before: $0.before) }
    }

    /// Returns the captured entries and clears history. Caller is responsible
    /// for actually re-applying the `before` modes; on success there's
    /// nothing left to revert.
    func consume() -> [Entry] {
        let snapshot = entries
        entries.removeAll()
        return snapshot
    }

    /// Drop history without applying anything. Called when displays change
    /// set composition (a new monitor would make a saved `before` mode
    /// reference a display that's no longer there).
    func clear() {
        entries.removeAll()
    }
}
