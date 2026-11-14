import AppKit
import Observation

/// Keeps `HotkeyCenter` registered for whatever the profiles and the
/// preferences currently ask for.
@MainActor
enum HotkeySync {
    /// Revert first: on a clash in a hand-edited file it keeps its shortcut,
    /// as the one action that undoes whatever the others did.
    static func bindings(profiles: [Profile], revert: KeyCombo?) -> [HotkeyBinding] {
        var result: [HotkeyBinding] = []
        if let revert {
            result.append(HotkeyBinding(owner: .revert, combo: revert, name: "Revert"))
        }
        for profile in profiles {
            guard let hotkey = profile.hotkey else { continue }
            result.append(HotkeyBinding(owner: .profile(profile.id), combo: hotkey, name: profile.name))
        }
        return result
    }

    /// Registers the current bindings and re-arms itself on every change to
    /// the fields they read.
    static func keepInSync(_ center: HotkeyCenter, profiles: ProfileStore, preferences: Preferences) {
        let current = withObservationTracking {
            bindings(profiles: profiles.profiles, revert: preferences.revertHotkey)
        } onChange: { [weak center, weak profiles, weak preferences] in
            Task { @MainActor in
                guard let center, let profiles, let preferences else { return }
                keepInSync(center, profiles: profiles, preferences: preferences)
            }
        }
        center.setBindings(current)
    }
}

/// What a global shortcut does when pressed. The popover may be closed, so
/// there is nobody to ask: these follow `viberes profile apply`, not the
/// popover's confirmation panel.
@MainActor
enum ShortcutActions {
    /// The system alert sound. A seam so a test can count alerts without
    /// sounding one on the machine running it.
    static var alert: () -> Void = { NSSound.beep() }
    /// What VoiceOver hears afterwards. A seam so a test can read what would
    /// be said without speaking.
    static var announce: (ShortcutAnnouncement) -> Void = ShortcutAnnouncement.post

    static func perform(_ owner: HotkeyOwner, displays: DisplayStore, profiles: ProfileStore) {
        switch owner {
        case .revert:
            revert(displays: displays)
        case .profile(let id):
            applyProfile(id, displays: displays, profiles: profiles)
        }
    }

    /// Undoes the last change, as the popover's Revert row does. With nothing
    /// to undo, the alert sound says the press was heard and did nothing.
    private static func revert(displays: DisplayStore) {
        Log.apply.info("shortcut: revert")
        let restored = displays.performRevert()
        if displays.revert.canRevert {
            // What failed stays armed for another try; the store just said why.
            alert()
            announce(.revertIncomplete(displays.lastError))
        } else if restored == 0 {
            alert()
            announce(.nothingToRevert)
        } else {
            announce(.reverted)
        }
    }

    /// Applies what the profile can apply to the displays connected now, and
    /// records it for Revert. A profile that binds no connected display does
    /// nothing; a missing display or a failed switch sounds the alert, since
    /// no note can reach a popover that is not open.
    private static func applyProfile(_ id: UUID, displays: DisplayStore, profiles: ProfileStore) {
        guard let profile = profiles.profiles.first(where: { $0.id == id }) else {
            alert()
            announce(.profileMissing)
            return
        }
        let live = displays.liveSnapshot()
        let classification = DisplaySetClassifier.classify(
            profiles.bindings(of: profile, to: live), against: live
        )
        if classification == .disjoint {
            Log.apply.info("shortcut: profile matches no connected display", detail: "profile '\(profile.name)'")
            alert()
            announce(.noDisplayConnected(profile: profile.name))
            return
        }
        Log.apply.info("shortcut: applying profile", detail: "profile '\(profile.name)'")
        let result = profiles.applyDetailed(profile, displays: live, revert: displays.revert)
        if result.didChangeAnything {
            displays.endPendingConfirmation()
        }
        if result.mainChange?.didChange == true {
            displays.expectOwnMainChange()
        }
        // A fallback rate is the profile working as designed (an "any
        // external" entry on a slower monitor), so it stays quiet; a display
        // left out or a switch that failed does not.
        let missedSomething = result.outcomes.contains { outcome in
            switch outcome.status {
            case .applied, .alreadyApplied, .appliedWithFallback: return false
            case .skippedNoMatch, .skippedNoMode, .failed: return true
            }
        }
        if missedSomething || result.mainChange?.problemSummary != nil {
            alert()
        }
        // Said only when the popover would show a note for it too.
        if let note = ApplyOutcomeNote.make(from: result.outcomes, mainChange: result.mainChange) {
            announce(.applied(profile: profile.name, note: note))
        }
    }
}
