import Foundation
import Testing
@testable import VibeRes

/// What VoiceOver says after a global shortcut, in the words a screen reader
/// user hears. The expected sentences are the published copy in
/// Localizable.xcstrings, in English and Slovak, resolved in the app's
/// language rather than the Mac's.
@Suite("Shortcut announcements")
struct ShortcutAnnouncementTests {
    private static let english = Locale(identifier: "en")
    private static let slovak = Locale(identifier: "sk")

    @Test("A profile's result names the profile, then says what the note says")
    func appliedNamesProfile() {
        let note = ApplyOutcomeNote(tone: .info, content: .alreadyAtSavedSettings)
        let said = ShortcutAnnouncement.applied(profile: "Desk", note: note)
        #expect(said.localizedDescription(locale: Self.english) == "Desk: Already at the saved settings.")
    }

    @Test("A display left out is said after the result, as the note's second line")
    func appliedSaysSkipped() {
        let note = ApplyOutcomeNote(
            tone: .info, content: .alreadyAtSavedSettings,
            skipped: [.notConnected(display: "LG UltraFine")]
        )
        let said = ShortcutAnnouncement.applied(profile: "Desk", note: note).localizedDescription(locale: Self.english)
        #expect(said.hasPrefix("Desk: Already at the saved settings.; "))
        #expect(said.contains("LG UltraFine"))
    }

    @Test("Each outcome is said in the app's language", arguments: [
        (ShortcutAnnouncement.noDisplayConnected(profile: "Desk"),
         "Desk: none of its displays is connected", "Desk: nie je pripojený žiadny z jeho displejov"),
        (.profileMissing, "The profile for this shortcut no longer exists", "Profil tejto skratky už neexistuje"),
        (.reverted, "Reverted the last change", "Posledná zmena je vrátená"),
        (.nothingToRevert, "Nothing to revert", "Nie je čo vrátiť"),
        (.revertIncomplete(nil), "Not everything could be reverted", "Nie všetko sa podarilo vrátiť"),
    ])
    func localised(announcement: ShortcutAnnouncement, english: String, slovak: String) {
        #expect(announcement.localizedDescription(locale: Self.english) == english)
        #expect(announcement.localizedDescription(locale: Self.slovak) == slovak)
    }

    @Test("An incomplete revert says what went wrong when the store knows")
    func revertIncompleteSaysProblem() {
        let problem = UserFacingProblem.previousMainNotRestored
        #expect(ShortcutAnnouncement.revertIncomplete(problem).localizedDescription() == problem.localizedDescription)
    }
}
