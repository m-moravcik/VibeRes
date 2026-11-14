import Foundation
import Testing
@testable import VibeRes

/// The words around a profile in the popover: the pill's tooltip, the hint on
/// a pill that is waiting for its displays, and the apply confirmation. The
/// expected sentences are the published copy in Localizable.xcstrings, in
/// English and Slovak, resolved in the app's language rather than the Mac's.
@Suite("Profile copy")
@MainActor
struct ProfileCopyTests {
    private static let english = Locale(identifier: "en")
    // Slovak typography keeps a one-letter conjunction off the end of a line,
    // so the list formatter puts a no-break space after "a".
    private static let slovak = Locale(identifier: "sk")

    private func entry(_ matcher: DisplayMatcher, _ name: String) -> Profile.Entry {
        Profile.Entry(matcher: matcher, displayName: name, pointWidth: 1920, pointHeight: 1080,
                      refreshHz: 60, isHiDPI: false)
    }

    private var desk: Profile {
        Profile(name: "Desk", entries: [
            entry(.edid(vendor: 1, model: 2, serial: 3), "LG UltraFine"),
            entry(.edid(vendor: 4, model: 5, serial: 6), "Dell U2720Q"),
        ])
    }

    @Test("A profile with nothing connected waits for its displays, by name")
    func waitingNamesDisplays() throws {
        let names = try #require(ProfilePill.waitingFor(desk, classification: .disjoint, locale: Self.english))
        #expect(ProfilePill.waitingLine(for: names, locale: Self.english) == "Waiting for LG UltraFine and Dell U2720Q")
        #expect(ProfilePill.waitingLine(for: names, locale: Self.slovak) == "Čaká na LG UltraFine a\u{00A0}Dell U2720Q")
    }

    @Test("A profile that can apply something is not waiting",
          arguments: [DisplaySetClassifier.Classification.exactMatch, .partialMatch(missing: []), .supersetMatch(extra: [])])
    func notWaiting(classification: DisplaySetClassifier.Classification) {
        #expect(ProfilePill.waitingFor(desk, classification: classification) == nil)
    }

    @Test("An any-external entry is named as such, and a name is said once")
    func displayNames() {
        let profile = Profile(name: "Talk", entries: [
            entry(.anyExternal, "Projector"),
            entry(.edid(vendor: 1, model: 2, serial: 3), "LG UltraFine"),
            entry(.edid(vendor: 1, model: 2, serial: 4), "LG UltraFine"),
        ])
        #expect(profile.localizedDisplayNames(locale: Self.english) == ["any external monitor", "LG UltraFine"])
        #expect(profile.localizedDisplayNames(locale: Self.slovak) == ["ľubovoľný externý monitor", "LG UltraFine"])
        #expect(profile.localizedSummary(locale: Self.english) == "any external monitor + LG UltraFine")
    }

    @Test("The confirmation names the missing displays in the app's language")
    func partialHeadline() {
        let missing = desk.entries
        #expect(ProfileApplyConfirmation.headline(for: .partialMatch(missing: missing), locale: Self.english)
                == "Not connected: LG UltraFine and Dell U2720Q. The other displays will apply as saved.")
        #expect(ProfileApplyConfirmation.headline(for: .partialMatch(missing: missing), locale: Self.slovak)
                == "Nepripojené: LG UltraFine a\u{00A0}Dell U2720Q. Ostatné displeje sa nastavia podľa profilu.")
    }

    @Test("Nothing connected: the panel and the waiting pill give the same reason")
    func disjointHeadline() {
        #expect(ProfileApplyConfirmation.headline(for: .disjoint, locale: Self.english)
                == "None of this profile's displays is connected, so there is nothing to apply.")
        #expect(ProfileApplyConfirmation.disjointHeadline(locale: Self.slovak)
                == "Nie je pripojený žiadny displej z tohto profilu, takže nie je čo použiť.")
    }

    @Test("The button says Apply anyway only when something will be skipped or left alone")
    func applyButton() {
        #expect(ProfileApplyConfirmation.applyButtonLabel(for: .exactMatch, locale: Self.slovak) == "Použiť")
        #expect(ProfileApplyConfirmation.applyButtonLabel(for: .partialMatch(missing: []), locale: Self.english) == "Apply anyway")
        #expect(ProfileApplyConfirmation.applyButtonLabel(for: .partialMatch(missing: []), locale: Self.slovak) == "Napriek tomu použiť")
    }
}
