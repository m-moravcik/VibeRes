import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// The popover used to render `"\(error)"` straight from a thrown
/// `ResolutionSwitcher.Failure`, which produces text like
/// `applyMode(__C.CGError(rawValue: 1004))`. That tells the user nothing and
/// looks like a crash report.
///
/// This copy lives in Core rather than the UI because `viberes` prints failures
/// too, and stays English for the same reason `ApplyOutcome.summary` does: a
/// command-line tool has no bundle to resolve a String Catalog against.
@Suite("Resolution failure copy")
struct ResolutionFailureCopyTests {
    @Test("A refused change explains itself and keeps the code for support")
    func cannotComplete() {
        let message = ResolutionSwitcher.Failure.applyMode(.cannotComplete).userFacingDescription

        #expect(message.contains("try again"))
        #expect(message.contains("1004"))
        #expect(!message.contains("CGError"))
        #expect(!message.contains("rawValue"))
    }

    @Test("An invalid mode says so rather than blaming the system")
    func invalidMode() {
        let message = ResolutionSwitcher.Failure.applyMode(.rangeCheck).userFacingDescription

        #expect(message.lowercased().contains("not supported"))
        #expect(!message.contains("rawValue"))
    }

    @Test("Any error reaching the UI is humanised, with a fallback for foreign ones")
    func errorHelperCoversBothPaths() {
        struct Other: Error {}

        let known: any Error = ResolutionSwitcher.Failure.applyMode(.cannotComplete)
        #expect(known.userFacingText == ResolutionSwitcher.Failure.applyMode(.cannotComplete).userFacingDescription)

        // Anything we do not recognise still has to render as *something*.
        #expect(!Other().userFacingText.isEmpty)
    }

    @Test("An unmapped code still produces a sentence, never a struct dump")
    func unknownCode() {
        let message = ResolutionSwitcher.Failure.completeConfig(.invalidConnection).userFacingDescription

        #expect(!message.isEmpty)
        #expect(!message.contains("rawValue"))
        #expect(message.contains("\(CGError.invalidConnection.rawValue)"))
    }
}
