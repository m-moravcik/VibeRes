import Foundation
import Testing
@testable import VibeRes

/// Verifies the String Catalog actually carries the note strings in every
/// language the bundle advertises, and that the placeholders agree.
///
/// A missing translation is invisible at runtime — Foundation quietly falls
/// back to the development language, so the app looks "localised" while showing
/// English. A *mismatched* placeholder count is worse: it produces garbage or
/// crashes only in the language nobody on the team runs.
///
/// This reads the compiled `.lproj` tables from the app bundle, not the
/// `.xcstrings` source, so it fails if the catalog is edited but not built.
@Suite("Note string catalog coverage")
struct NoteLocalisationTests {
    /// Keys introduced by ApplyOutcomeNote. Kept explicit rather than derived
    /// so that deleting a key from the catalog fails a test instead of silently
    /// shrinking the checked set.
    private static let noteKeys = [
        "note.detail.applied",
        "note.detail.fallback",
        "note.detail.notConnected",
        "note.detail.noExternalConnected",
        "note.detail.noUsableMode",
        "note.detail.failed",
        "note.moreDisplays",
        "note.alreadyAtSavedSettings",
    ]

    private func bundle(for language: String) throws -> Bundle {
        let path = try #require(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "no \(language).lproj in the app bundle — is CFBundleLocalizations still listing it?"
        )
        return try #require(Bundle(path: path))
    }

    /// Counts `%@`, `%lld` and positional `%1$@` style specifiers.
    private func placeholderCount(_ value: String) -> Int {
        value.ranges(of: /%(\d+\$)?(@|lld|ld|d|f)/).count
    }

    @Test("Every note key is translated in every advertised language", arguments: ["en", "sk", "de"])
    func keysArePresent(language: String) throws {
        let bundle = try bundle(for: language)

        for key in Self.noteKeys {
            let value = bundle.localizedString(forKey: key, value: "\u{0}MISSING", table: nil)
            #expect(value != "\u{0}MISSING", "\(language) is missing \(key)")
            #expect(value != key, "\(language) has \(key) untranslated (value equals the key)")
        }
    }

    @Test("Placeholders agree across languages so no locale renders garbage")
    func placeholdersMatchEnglish() throws {
        let english = try bundle(for: "en")

        for language in ["sk", "de"] {
            let translated = try bundle(for: language)
            for key in Self.noteKeys {
                let base = english.localizedString(forKey: key, value: nil, table: nil)
                let other = translated.localizedString(forKey: key, value: nil, table: nil)
                #expect(
                    placeholderCount(base) == placeholderCount(other),
                    "\(key): en has \(placeholderCount(base)) placeholders, \(language) has \(placeholderCount(other))"
                )
            }
        }
    }
}
