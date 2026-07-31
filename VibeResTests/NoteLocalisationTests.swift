import Foundation
import Testing
@testable import VibeRes

/// Verifies the String Catalog carries every one of its strings in every
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
    /// Every key in the shipped catalog, read from the source of truth rather
    /// than a hand-maintained list — a list would silently stop covering keys
    /// added later, which is exactly how the catalog fell 76 strings behind.
    private static let catalogKeys: [String] = {
        // The test bundle sits inside the app bundle, so walk up to the repo.
        var dir = URL(fileURLWithPath: #filePath)
        dir.deleteLastPathComponent()          // VibeResTests
        dir.deleteLastPathComponent()          // repo root
        let url = dir.appending(path: "VibeRes/Resources/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else { return [] }
        return strings.keys.sorted()
    }()

    private static let noteKeys = catalogKeys

    /// True for identifier-style keys such as `note.detail.applied`, as opposed
    /// to keys that are themselves the English sentence.
    private static func isSymbolicKey(_ key: String) -> Bool {
        key.contains(".") && !key.contains(" ")
    }

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

            // Most of this catalog uses the English sentence as the key, so
            // value == key is correct for `en` and unremarkable elsewhere when a
            // term is the same in both languages ("HiDPI", "VibeRes"). A
            // *symbolic* key rendering as itself is different: it means the
            // lookup found nothing and fell through to the identifier.
            if Self.isSymbolicKey(key) {
                #expect(value != key, "\(language) has no value for the symbolic key \(key)")
            }
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
