import Foundation
import Testing
@testable import VibeRes

/// Plural forms must follow the language the app runs in, not the system
/// locale. With Czech chosen for VibeRes alone on an English-locale Mac,
/// `Locale.current` is English, whose rules have no "few" category, so Czech
/// 2–4 used to render as "3 displejů" instead of "3 displeje".
///
/// The locale here is built from an English base region on purpose, so the
/// result does not depend on the test host's own language or region.
@Suite("App language locale")
struct AppLocaleTests {
    private static let englishRegion = Locale(identifier: "en_US@rg=skzzzz")
    private static let czech = Locale.appLanguage("cs", region: englishRegion)

    @Test("Takes the language from the app and keeps the user's region")
    func combinesLanguageAndRegion() {
        #expect(Self.czech.language.languageCode == "cs")
        #expect(Self.czech.region == Self.englishRegion.region)
    }

    @Test("Without a resolved localisation the base locale is kept")
    func fallsBackToBase() {
        #expect(Locale.appLanguage(nil, region: Self.englishRegion) == Self.englishRegion)
    }

    @Test(
        "Czech plural of the ambiguous-main note follows the app language",
        arguments: [
            (1, "odpovídá mu 1 připojený displej"),
            (2, "odpovídají mu 2 připojené displeje"),
            (3, "odpovídají mu 3 připojené displeje"),
            (4, "odpovídají mu 4 připojené displeje"),
            (5, "odpovídá mu 5 připojených displejů"),
        ]
    )
    func mainAmbiguousPlural(count: Int, expected: String) {
        let text = ApplyOutcomeNote.Detail.mainAmbiguous(count: count).localizedDescription(locale: Self.czech)
        #expect(text.hasSuffix(expected), "\(count): \(text)")
    }

    @Test(
        "Czech plural of the further-displays suffix follows the app language",
        arguments: [(1, " (+1 další)"), (2, " (+2 další)"), (4, " (+4 další)"), (5, " (+5 dalších)")]
    )
    func moreDisplaysPlural(extraCount: Int, expected: String) {
        let note = ApplyOutcomeNote(
            tone: .info,
            content: .applied(.noExternalConnected, extraCount: extraCount),
            mainDetail: nil,
            skipped: []
        )
        #expect(note.localizedDescription(locale: Self.czech).hasSuffix(expected))
    }
}
