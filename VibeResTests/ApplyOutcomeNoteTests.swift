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
            requestedSize: (1920, 1080),
            requestedHz: nil,
            appliedSize: (1920, 1080),
            appliedHz: nil,
            status: status
        )
    }

    @Test("A problem outranks a fallback and a success in the same batch")
    func problemTakesPrecedence() {
        let note = ApplyOutcomeNote.make(from: [
            outcome(.applied, display: "Built-in"),
            outcome(.appliedWithFallback, display: "LG"),
            outcome(.skippedNoMatch, display: "Dell"),
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
            outcome(.skippedNoMatch, display: "Dell"),
            outcome(.failed("boom"), display: "LG"),
        ])

        #expect(note?.content == .problems([
            .notConnected(display: "Dell"),
            .failed(display: "LG", message: "boom"),
        ]))
    }

    @Test("A flexible profile with no external says so without naming a display")
    func anyExternalProblemHasNoDisplayName() {
        let flexible = ProfileStore.ApplyOutcome(
            displayName: "Desk monitor",
            matcherKind: .anyExternal,
            requestedSize: (2560, 1440),
            requestedHz: nil,
            appliedSize: nil,
            appliedHz: nil,
            status: .skippedNoMatch
        )

        #expect(ApplyOutcomeNote.make(from: [flexible])?.content
                == .problems([.noExternalConnected]))
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
            requestedSize: (2560, 1440),
            requestedHz: 75,
            appliedSize: (2560, 1440),
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
}
