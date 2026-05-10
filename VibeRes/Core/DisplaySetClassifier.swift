import CoreGraphics
import Foundation

/// Classifies how well a saved Profile fits the currently-connected display set.
/// Used by the manual-apply flow to warn the user *before* a profile mangles a
/// setup it wasn't designed for, and by the hover preview to show "what would
/// happen" without committing the change.
///
/// Auto-apply (display-change event) bypasses classification — it only fires
/// when `profileMatchingExactly()` already found a clean fit.
enum DisplaySetClassifier {

    /// Outcome of comparing a Profile's entries against the live display set.
    /// `.exactMatch` is the only fully-clean state; the rest signal trade-offs
    /// the user should see before the apply runs.
    enum Classification: Equatable {
        /// Every profile entry binds to a live display AND every live display
        /// is covered by some profile entry. Apply runs without warning.
        case exactMatch

        /// Profile has entries whose matcher binds nothing in the live set.
        /// `missing` lists the entries that will be skipped.
        case partialMatch(missing: [Profile.Entry])

        /// Every profile entry binds, but the live set has extra displays the
        /// profile doesn't mention. Those displays are left untouched.
        case supersetMatch(extra: [DisplayInfo])

        /// Both: some entries miss, AND some live displays aren't covered.
        case partialWithExtras(missing: [Profile.Entry], extra: [DisplayInfo])

        /// No entry binds anything — applying would do nothing.
        case disjoint
    }

    /// Compute the classification for a profile against the live display set.
    /// `.anyExternal` matchers can bind multiple externals, which complicates
    /// the "extras" detection — we count any display matched by *any* entry
    /// as covered, even if multiple entries claim the same display.
    static func classify(_ profile: Profile, against displays: [DisplayInfo]) -> Classification {
        // Empty profile is semantically nothing to apply — surface as
        // `.disjoint` so the UI shows the "nothing to apply" path rather
        // than "every live display is an extra".
        if profile.entries.isEmpty { return .disjoint }

        // Bucket entries into matched vs missing.
        var missingEntries: [Profile.Entry] = []
        var matchedDisplayIDs: Set<CGDirectDisplayID> = []

        for entry in profile.entries {
            let matches = displays.filter { entry.matcher.matches($0.id) }
            if matches.isEmpty {
                missingEntries.append(entry)
            } else {
                for d in matches { matchedDisplayIDs.insert(d.id) }
            }
        }

        // Anything live but not claimed by a profile entry is an "extra".
        let extras = displays.filter { !matchedDisplayIDs.contains($0.id) }

        switch (missingEntries.isEmpty, extras.isEmpty) {
        case (true, true):
            return .exactMatch
        case (true, false):
            return .supersetMatch(extra: extras)
        case (false, true):
            // No extras, but some entries missing. If literally nothing
            // matched at all, surface as `.disjoint` instead of `.partialMatch`
            // with an empty bind list — the user gets a clearer message.
            return matchedDisplayIDs.isEmpty
                ? .disjoint
                : .partialMatch(missing: missingEntries)
        case (false, false):
            return matchedDisplayIDs.isEmpty
                ? .disjoint
                : .partialWithExtras(missing: missingEntries, extra: extras)
        }
    }

    /// True when applying the profile is safe to do silently (no surprises).
    /// Auto-apply already only fires on `profileMatchingExactly()`, so this
    /// is primarily used by the UI to decide whether to short-circuit the
    /// confirmation panel for a manual apply.
    static func isCleanApply(_ classification: Classification) -> Bool {
        if case .exactMatch = classification { return true }
        return false
    }
}

/// Pre-computed preview of what would happen if a profile is applied right now.
/// Used by the hover tooltip and by the partial-match confirmation panel to
/// show the user the exact set of changes before they commit. Computed purely
/// from snapshot data — no display state is mutated.
struct ProfileApplyPreview: Equatable {
    /// One row per (entry, bound-display) pair. An entry that binds to two
    /// externals via `.anyExternal` produces two rows.
    struct Row: Equatable, Identifiable {
        enum Action: Equatable {
            /// Mode will be applied exactly as saved.
            case willApplyExact
            /// Closest match will be used (rate or size differs).
            case willApplyFallback(targetWidth: Int, targetHeight: Int, targetHz: Int?)
            /// Already at the saved mode — nothing to do.
            case alreadyApplied
            /// Matcher binds nothing — entry will be skipped.
            case skippedNotConnected
            /// No usable mode for this resolution on the bound display.
            case skippedNoMode
        }

        let id: UUID
        let displayName: String
        let action: Action
        /// Originally requested mode from the profile entry.
        let savedWidth: Int
        let savedHeight: Int
        let savedHz: Int?
        let savedIsHiDPI: Bool
    }

    let rows: [Row]
    /// Live displays NOT touched by this profile — informational only.
    let untouched: [String]
}
