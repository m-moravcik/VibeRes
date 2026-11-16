import Foundation
import Testing
@testable import VibeRes

/// The house style for VibeRes copy has no dash between clauses: a reason
/// gets its own sentence or a colon. That covers the em dash and the spaced en
/// dash German and Czech use in its place. Checked against what the app
/// actually ships, the compiled string tables of every language, so a new
/// string or translation cannot bring one back unnoticed.
@Suite("Copy punctuation")
struct CopyPunctuationTests {
    private static let emDash = "\u{2014}"
    private static let spacedEnDash = " \u{2013} "

    private static func hasClauseDash(_ text: String) -> Bool {
        text.contains(emDash) || text.contains(spacedEnDash)
    }

    /// Every string in a compiled table, plural variants included.
    private static func strings(in object: Any) -> [String] {
        switch object {
        case let text as String: return [text]
        case let dictionary as [String: Any]: return dictionary.values.flatMap(strings(in:))
        case let array as [Any]: return array.flatMap(strings(in:))
        default: return []
        }
    }

    @Test("No shipped string in any language joins clauses with a dash")
    func noClauseDashInTables() throws {
        let languages = Bundle.main.localizations.filter { $0 != "Base" }
        try #require(languages.count >= 6)
        var offenders: [String] = []
        for language in languages {
            for type in ["strings", "stringsdict"] {
                guard let url = Bundle.main.url(forResource: "Localizable", withExtension: type,
                                                subdirectory: nil, localization: language),
                      let table = NSDictionary(contentsOf: url) as? [String: Any]
                else { continue }
                for (key, value) in table {
                    let texts = [key] + Self.strings(in: value)
                    if texts.contains(where: Self.hasClauseDash) {
                        offenders.append("\(language): \(key)")
                    }
                }
            }
        }
        #expect(offenders.sorted() == [])
    }

    @Test("Both profile forms write a rate as \"120 Hz\"")
    func modeSummarySpacesTheUnit() {
        #expect(ModeSummary.text(width: 1800, height: 1169, refreshHz: 120, isVRR: false, isHiDPI: true)
            == "1 800 × 1 169 · 120 Hz · HiDPI")
        #expect(ModeSummary.text(width: 2560, height: 1440, refreshHz: 160, isVRR: true, isHiDPI: false)
            == "2 560 × 1 440 · 160 Hz VRR")
        #expect(ModeSummary.text(width: 1920, height: 1080, refreshHz: nil, isVRR: false, isHiDPI: false)
            == "1 920 × 1 080")
    }

    @Test("The English problem text the CLI prints has no clause dash")
    func noClauseDashInEnglishProblems() {
        let problems: [UserFacingProblem] = [
            .mirroredArrangement, .mainDisplayAdjusted, .previousMainNotRestored,
            .profilesNotSaved,
            .switchFailed(.applyMode(.failure)),
            .switchFailed(.applyMode(.cannotComplete)),
            .switchFailed(.originCoverage),
        ]
        for problem in problems {
            #expect(!Self.hasClauseDash(problem.englishDescription), "\(problem)")
        }
    }
}
