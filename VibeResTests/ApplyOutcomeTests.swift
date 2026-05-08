import Foundation
import Testing
@testable import VibeRes

/// Tests the ApplyOutcome surface of ProfileStore.applyDetailed for the
/// branches that don't require a real CGDisplay state change. We don't
/// exercise the .applied / .appliedWithFallback / .failed paths because those
/// require ResolutionSwitcher to actually mutate the display, which the unit
/// tests deliberately avoid.
@Suite("ProfileStore.applyDetailed branches")
@MainActor
struct ApplyOutcomeTests {
    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-apply-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    @Test("Empty profile yields no outcomes")
    func emptyProfile() {
        let store = makeStore()
        let p = Profile(name: "Empty", entries: [])
        let outcomes = store.applyDetailed(p, displays: [])
        #expect(outcomes.isEmpty)
    }

    @Test("Entry with no matching display reports skippedNoMatch")
    func skippedNoMatch() {
        let store = makeStore()
        let p = Profile(name: "Ghost", entries: [
            Profile.Entry(matcher: .edid(vendor: 999, model: 999, serial: 999),
                          displayName: "Phantom Monitor",
                          pointWidth: 2560, pointHeight: 1440, refreshHz: 60, isHiDPI: false),
        ])
        let outcomes = store.applyDetailed(p, displays: [])
        #expect(outcomes.count == 1)
        if case .skippedNoMatch = outcomes.first?.status {} else {
            Issue.record("expected .skippedNoMatch, got \(String(describing: outcomes.first?.status))")
        }
        #expect(outcomes.first?.summary == "Phantom Monitor not connected")
    }

    @Test("anyExternal skip says 'no external monitor connected', not the saved label")
    func anyExternalNoLiveExternal() {
        let store = makeStore()
        // Snapshotted displayName here is "Q3279WG5B" — what the user saw
        // when the profile was first saved. After they toggled the entry to
        // `.anyExternal`, that label is misleading: the entry now matches
        // *any* external. The summary must reflect the matcher, not the
        // stale snapshot, otherwise users see "Q3279WG5B not connected" on
        // a flexible profile where Q3279WG5B is no longer the binding.
        let p = Profile(name: "Travel", entries: [
            Profile.Entry(matcher: .anyExternal,
                          displayName: "Q3279WG5B",
                          pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false),
        ])
        let outcomes = store.applyDetailed(p, displays: [])
        #expect(outcomes.count == 1)
        if case .skippedNoMatch = outcomes.first?.status {} else {
            Issue.record("expected .skippedNoMatch")
        }
        #expect(outcomes.first?.summary == "no external monitor connected")
        #expect(outcomes.first?.summary.contains("Q3279WG5B") == false)
    }

    @Test("ApplyOutcome.isProblem flags every non-applied status")
    func isProblemFlag() {
        // .applied is the only non-problem status; everything else surfaces.
        let applied = ProfileStore.ApplyOutcome(
            displayName: "X", matcherKind: .specific, requestedSize: (0, 0), requestedHz: nil,
            appliedSize: (0, 0), appliedHz: nil, status: .applied
        )
        let fallback = ProfileStore.ApplyOutcome(
            displayName: "X", matcherKind: .specific, requestedSize: (0, 0), requestedHz: nil,
            appliedSize: (0, 0), appliedHz: nil, status: .appliedWithFallback
        )
        let skip1 = ProfileStore.ApplyOutcome(
            displayName: "X", matcherKind: .specific, requestedSize: (0, 0), requestedHz: nil,
            appliedSize: nil, appliedHz: nil, status: .skippedNoMatch
        )
        let skip2 = ProfileStore.ApplyOutcome(
            displayName: "X", matcherKind: .specific, requestedSize: (0, 0), requestedHz: nil,
            appliedSize: nil, appliedHz: nil, status: .skippedNoMode
        )
        let failed = ProfileStore.ApplyOutcome(
            displayName: "X", matcherKind: .specific, requestedSize: (0, 0), requestedHz: nil,
            appliedSize: nil, appliedHz: nil, status: .failed("boom")
        )
        #expect(applied.isProblem == false)
        #expect(fallback.isProblem == true)
        #expect(skip1.isProblem == true)
        #expect(skip2.isProblem == true)
        #expect(failed.isProblem == true)
    }

    @Test("ApplyOutcome.summary formats fallback case with both wanted and used")
    func summaryFallbackText() {
        let outcome = ProfileStore.ApplyOutcome(
            displayName: "LG UltraFine",
            matcherKind: .specific,
            requestedSize: (2560, 1440),
            requestedHz: 75,
            appliedSize: (2560, 1440),
            appliedHz: 60,
            status: .appliedWithFallback
        )
        // Looser assertions — we want the user-meaningful info present
        // without locking down exact punctuation.
        #expect(outcome.summary.contains("2560×1440"))
        #expect(outcome.summary.contains("75"))
        #expect(outcome.summary.contains("60"))
        #expect(outcome.summary.contains("closest"))
    }
}
