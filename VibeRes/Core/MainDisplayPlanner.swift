import CoreGraphics
import Foundation

/// Pure planning for "main display in a profile".
///
/// Setting the main display on macOS is not an API call — it is a statement
/// about the whole arrangement: whichever display sits at (0,0) is main. The
/// spike (docs/display-arrangement-spike-2026-08-01.md) measured that a
/// partial origin change is silently mangled (F1) while a complete translated
/// arrangement applies exactly (F2). Everything here is therefore a
/// full-coverage translation of the live arrangement, derived at apply time —
/// no geometry is ever stored.
enum MainDisplayPlanner {
    enum Resolution: Equatable {
        case target(CGDirectDisplayID)
        case noMatch
        case ambiguous(count: Int)
    }

    /// The single active display the profile's main matcher binds to.
    ///
    /// Exactly-one is a hard rule: zero means the monitor is not there; two or
    /// more (an `.anyExternal` matcher with two externals attached, or twin
    /// monitors with identical EDID) means the user's intent is unknowable,
    /// and guessing would move their menu bar on a coin flip.
    static func resolveTarget(
        _ matcher: DisplayMatcher,
        activeIDs: [CGDirectDisplayID]
    ) -> Resolution {
        let matches = activeIDs.filter { matcher.matches($0) }
        switch matches.count {
        case 0: return .noMatch
        case 1: return .target(matches[0])
        default: return .ambiguous(count: matches.count)
        }
    }

    /// Translates every display's origin so `target` lands at (0,0).
    ///
    /// A pure translation preserves relative topology by construction — no
    /// stored geometry, no reflow, no gaps. Nil when the target has no bounds
    /// entry, because a plan that does not include its own target is exactly
    /// the partial statement F1 warns about.
    static func plan(
        bounds: [CGDirectDisplayID: CGRect],
        target: CGDirectDisplayID
    ) -> [CGDirectDisplayID: CGPoint]? {
        guard let t = bounds[target] else { return nil }
        var out: [CGDirectDisplayID: CGPoint] = [:]
        for (id, r) in bounds {
            out[id] = CGPoint(x: r.origin.x - t.origin.x, y: r.origin.y - t.origin.y)
        }
        return out
    }

    /// F5: a successful commit is not evidence that the request was honoured.
    /// Compare what was asked for with what the window server actually did.
    static func verified(
        plan: [CGDirectDisplayID: CGPoint],
        actualBounds: [CGDirectDisplayID: CGRect]
    ) -> Bool {
        plan.allSatisfy { id, origin in
            guard let r = actualBounds[id] else { return false }
            return r.origin.x == origin.x && r.origin.y == origin.y
        }
    }
}
