import Foundation
import Testing
@testable import VibeRes

/// Tests for the aggregation that turns a batch of per-display apply outcomes
/// into the single note shown under the profile pills.
///
/// This logic used to live inline in `ProfilesSection`, where it was
/// unreachable from tests. It is also the layer where localisation has to
/// happen: `ProfileStore.ApplyOutcome.summary` stays English on purpose because
/// `VibeRes/Core` is compiled into the bundle-less `viberes` CLI, which prints
/// it verbatim (`VibeResCLI/main.swift:310`).
@Suite("ApplyOutcomeNote aggregation")
struct ApplyOutcomeNoteTests {
    private func outcome(
        _ status: ProfileStore.ApplyOutcome.Status,
        display: String = "Display"
    ) -> ProfileStore.ApplyOutcome {
        ProfileStore.ApplyOutcome(
            displayName: display,
            matcherKind: .specific,
            requestedSize: PointSize(width: 1920, height: 1080),
            requestedHz: nil,
            appliedSize: PointSize(width: 1920, height: 1080),
            appliedHz: nil,
            status: status
        )
    }

    @Test("A problem outranks a fallback and a success in the same batch")
    func problemTakesPrecedence() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.applied, display: "Built-in"),
            outcome(.appliedWithFallback, display: "LG"),
            outcome(.failed(.other("boom")), display: "Dell"),
        ])

        #expect(note?.tone == .problem)
    }

    @Test("A fallback outranks a success when nothing is broken")
    func fallbackOutranksSuccess() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.applied, display: "Built-in"),
            outcome(.appliedWithFallback, display: "LG"),
        ])

        #expect(note?.tone == .fallback)
    }

    @Test("A clean batch reports the first success and counts the rest")
    func successCountsTheRest() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.applied, display: "Built-in"),
            outcome(.applied, display: "LG"),
            outcome(.applied, display: "Dell"),
        ])

        #expect(note?.tone == .info)
        #expect(note?.content == .applied(
            .applied(display: "Built-in", width: 1920, height: 1080, hz: nil),
            extraCount: 2
        ))
    }

    @Test("A batch that changed nothing says so instead of naming a display")
    func alreadyAtSavedSettings() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.alreadyApplied, display: "Built-in"),
            outcome(.alreadyApplied, display: "LG"),
        ])

        #expect(note?.tone == .info)
        #expect(note?.content == .alreadyAtSavedSettings)
    }

    @Test("No outcomes produces no note")
    func emptyBatch() {
        #expect(ApplyOutcomeNote.make(from: []) == nil)
    }

    @Test("Every problem is carried, not just the first")
    func problemsCarryAllDetails() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.skippedNoMode, display: "Dell"),
            outcome(.failed(.other("boom")), display: "LG"),
        ])

        #expect(note?.content == .problems([
            .noUsableMode(display: "Dell", width: 1920, height: 1080),
            .failed(display: "LG", problem: .other("boom")),
        ]))
    }

    // MARK: Displays that are not connected
    //
    // A manual apply only gets this far for a missing display after the
    // confirmation panel has listed it and the user chose Apply Anyway, and
    // auto-apply only ever applies a profile whose every display is present.
    // So a skip is something the user already knows: it is said, on a line of
    // its own, but it does not paint the note as a failure. It used to: the
    // note read "GN246HL not connected" in red, with a warning triangle, and
    // nothing else, over a profile whose other two displays were fine.

    @Test("A display that is not connected does not raise the tone")
    func skippedDisplayKeepsInfoTone() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.alreadyApplied, display: "Built-in"),
            outcome(.alreadyApplied, display: "LG UltraFine"),
            outcome(.skippedNoMatch, display: "GN246HL"),
        ])

        #expect(note?.tone == .info)
        #expect(note?.content == .alreadyAtSavedSettings)
        #expect(note?.skipped == [.notConnected(display: "GN246HL")])
    }

    @Test("A skipped display rides along with what did apply")
    func skippedDisplayRidesAlongWithSuccess() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.applied, display: "LG"),
            outcome(.skippedNoMatch, display: "Dell"),
        ])

        #expect(note?.tone == .info)
        #expect(note?.content == .applied(
            .applied(display: "LG", width: 1920, height: 1080, hz: nil),
            extraCount: 0
        ))
        #expect(note?.skipped == [.notConnected(display: "Dell")])
    }

    @Test("A real failure still sets the tone when a display is also missing")
    func failureOutranksSkip() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.failed(.other("boom")), display: "LG"),
            outcome(.skippedNoMatch, display: "Dell"),
        ])

        #expect(note?.tone == .problem)
        #expect(note?.content == .problems([.failed(display: "LG", problem: .other("boom"))]))
        #expect(note?.skipped == [.notConnected(display: "Dell")])
    }

    @Test("When every display was skipped, nothing applied is a warning")
    func everythingSkippedIsFallback() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.skippedNoMatch, display: "Dell"),
            outcome(.skippedNoMatch, display: "GN246HL"),
        ])

        #expect(note?.tone == .fallback)
        #expect(note?.content == .skippedOnly([
            .notConnected(display: "Dell"),
            .notConnected(display: "GN246HL"),
        ]))
        // Said once, as the content, not again on the skipped line.
        #expect(note?.skipped == [])
    }

    @Test("A flexible profile with no external says so without naming a display")
    func anyExternalProblemHasNoDisplayName() {
        let flexible = ProfileStore.ApplyOutcome(
            displayName: "Desk monitor",
            matcherKind: .anyExternal,
            requestedSize: PointSize(width: 2560, height: 1440),
            requestedHz: nil,
            appliedSize: nil,
            appliedHz: nil,
            status: .skippedNoMatch
        )

        #expect(ApplyOutcomeNote.make(from: [flexible])?.content
                == .skippedOnly([.noExternalConnected]))
    }

    @Test("Mode strings stay numeric so they need no translation")
    func modeFormatting() {
        // These go into localised sentences as arguments. They must not contain
        // prose, or every language would have to re-format the numbers.
        #expect(ApplyOutcomeNote.modeString(width: 2560, height: 1440, hz: 60) == "2560×1440 @60Hz")
        #expect(ApplyOutcomeNote.modeString(width: 1920, height: 1080, hz: nil) == "1920×1080")
    }

    @Test("Fallback detail keeps both what was wanted and what was used")
    func fallbackDetailKeepsBothModes() {
        let outcome = ProfileStore.ApplyOutcome(
            displayName: "LG UltraFine",
            matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440),
            requestedHz: 75,
            appliedSize: PointSize(width: 2560, height: 1440),
            appliedHz: 60,
            status: .appliedWithFallback
        )

        #expect(ApplyOutcomeNote.make(from: [outcome])?.content == .fallbacks([
            .fallback(
                display: "LG UltraFine",
                wantedWidth: 2560, wantedHeight: 1440, wantedHz: 75,
                usedWidth: 2560, usedHeight: 1440, usedHz: 60
            )
        ]))
    }

    @Test("A verified main change rides along on an info note")
    func mainChangeOnInfoNote() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440), requestedHz: 60,
            appliedSize: PointSize(width: 2560, height: 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .changed(displayName: "LG"))
        #expect(note?.tone == .info)
        #expect(note?.mainDetail == .mainChanged(display: "LG"))
    }

    @Test("A skipped main change lowers a clean apply to fallback tone")
    func skippedMainIsFallback() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440), requestedHz: 60,
            appliedSize: PointSize(width: 2560, height: 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .skippedAmbiguous(count: 2))
        #expect(note?.tone == .fallback)
        #expect(note?.mainDetail == .mainAmbiguous(count: 2))
    }

    @Test("A failed main change makes the note a problem")
    func failedMainIsProblem() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440), requestedHz: 60,
            appliedSize: PointSize(width: 2560, height: 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .failed(.other("boom")))
        #expect(note?.tone == .problem)
        #expect(note?.mainDetail == .mainFailed(problem: .other("boom")))
    }

    @Test("A changed-but-adjusted main reports mainAdjusted at fallback tone")
    func changedButAdjustedIsFallback() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440), requestedHz: 60,
            appliedSize: PointSize(width: 2560, height: 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .changedButAdjusted(displayName: "LG"))
        #expect(note?.tone == .fallback)
        #expect(note?.mainDetail == .mainAdjusted(display: "LG"))
    }

    @Test("A main matcher with no live display reports mainNotConnected at fallback tone")
    func skippedNoMatchIsFallback() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440), requestedHz: 60,
            appliedSize: PointSize(width: 2560, height: 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .skippedNoMatch)
        #expect(note?.tone == .fallback)
        #expect(note?.mainDetail == .mainNotConnected)
    }

    @Test("A mirrored arrangement reports mainMirrored at fallback tone")
    func skippedMirroredIsFallback() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440), requestedHz: 60,
            appliedSize: PointSize(width: 2560, height: 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .skippedMirrored)
        #expect(note?.tone == .fallback)
        #expect(note?.mainDetail == .mainMirrored)
    }

    @Test("alreadyMain adds nothing to the note")
    func alreadyMainSilent() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440), requestedHz: 60,
            appliedSize: PointSize(width: 2560, height: 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .alreadyMain)
        #expect(note?.mainDetail == nil)
        #expect(note?.tone == .info)
    }
}
