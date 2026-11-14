import AppKit

/// What VoiceOver says after a global shortcut. The popover may be closed, so
/// without this a screen reader user hears a beep at most and never learns
/// whether the profile applied or what Revert undid.
///
/// Values, not prose: the words are resolved in the app's language only when
/// spoken, so tests can check what is said on any Mac.
enum ShortcutAnnouncement: Equatable {
    /// The profile ran; the note is the one the popover would show under the
    /// pills, so both say the same.
    case applied(profile: String, note: ApplyOutcomeNote)
    case noDisplayConnected(profile: String)
    case profileMissing
    case reverted
    case nothingToRevert
    /// Revert left something as it was. The problem says what, when there is
    /// one to say.
    case revertIncomplete(UserFacingProblem?)

    func localizedDescription(locale: Locale = .appLanguage) -> String {
        switch self {
        case let .applied(profile, note):
            var summary = note.localizedDescription(locale: locale)
            if let skipped = note.localizedSkipped(locale: locale) {
                summary += "; " + skipped
            }
            return String(localized: LocalizedStringResource(
                "shortcut.announce.applied",
                defaultValue: "\(profile): \(summary)",
                locale: locale,
                comment: "Spoken by VoiceOver after a profile's shortcut. 1: profile name, 2: what happened, as in the note under the pills"
            ))

        case let .noDisplayConnected(profile):
            return String(localized: LocalizedStringResource(
                "shortcut.announce.noDisplay",
                defaultValue: "\(profile): none of its displays is connected",
                locale: locale,
                comment: "Spoken by VoiceOver when a profile's shortcut found none of its displays. 1: profile name"
            ))

        case .profileMissing:
            return String(localized: LocalizedStringResource(
                "shortcut.announce.profileMissing",
                defaultValue: "The profile for this shortcut no longer exists",
                locale: locale,
                comment: "Spoken by VoiceOver when a shortcut's profile was deleted"
            ))

        case .reverted:
            return String(localized: LocalizedStringResource(
                "shortcut.announce.reverted",
                defaultValue: "Reverted the last change",
                locale: locale,
                comment: "Spoken by VoiceOver after the Revert shortcut undid the last change"
            ))

        case .nothingToRevert:
            return String(localized: LocalizedStringResource(
                "shortcut.announce.nothingToRevert",
                defaultValue: "Nothing to revert",
                locale: locale,
                comment: "Spoken by VoiceOver when the Revert shortcut had nothing to undo"
            ))

        case let .revertIncomplete(problem):
            if let problem {
                return problem.localizedDescription
            }
            return String(localized: LocalizedStringResource(
                "shortcut.announce.revertIncomplete",
                defaultValue: "Not everything could be reverted",
                locale: locale,
                comment: "Spoken by VoiceOver when the Revert shortcut could not undo the whole change"
            ))
        }
    }

    /// Asks VoiceOver to read the text; without VoiceOver running nothing
    /// happens. High priority, so it is not dropped behind whatever the
    /// screen reader is saying. Posted a moment later because a mode switch
    /// blanks the displays, and an announcement made during that is lost.
    static func post(_ announcement: ShortcutAnnouncement) {
        let text = announcement.localizedDescription()
        DispatchQueue.main.asyncAfter(deadline: .now() + postDelay) {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: text,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }

    /// About when the displays are back after a switch (see the profile
    /// pill's checkmark in `Design.Motion`).
    static let postDelay: TimeInterval = 0.6
}
