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

    @Test("anyExternal entry without externals reports skippedNoMatch")
    func anyExternalNoLiveExternal() {
        let store = makeStore()
        let p = Profile(name: "Travel", entries: [
            Profile.Entry(matcher: .anyExternal,
                          displayName: "Any external",
                          pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false),
        ])
        let outcomes = store.applyDetailed(p, displays: [])
        #expect(outcomes.count == 1)
        if case .skippedNoMatch = outcomes.first?.status {} else {
            Issue.record("expected .skippedNoMatch")
        }
        // The outcome surfaces the entry's displayName, not the matcher kind.
        // ("no external monitor connected" lives on DisplayMatcher.notConnectedDescription
        // which the UI doesn't currently use — kept for future routing.)
        #expect(outcomes.first?.summary.contains("not connected") == true)
    }

    @Test("ApplyOutcome.isProblem flags every non-applied status")
    func isProblemFlag() {
        // .applied is the only non-problem status; everything else surfaces.
        let applied = ProfileStore.ApplyOutcome(
            displayName: "X", requestedSize: (0, 0), requestedHz: nil,
            appliedSize: (0, 0), appliedHz: nil, status: .applied
        )
        let fallback = ProfileStore.ApplyOutcome(
            displayName: "X", requestedSize: (0, 0), requestedHz: nil,
            appliedSize: (0, 0), appliedHz: nil, status: .appliedWithFallback
        )
        let skip1 = ProfileStore.ApplyOutcome(
            displayName: "X", requestedSize: (0, 0), requestedHz: nil,
            appliedSize: nil, appliedHz: nil, status: .skippedNoMatch
        )
        let skip2 = ProfileStore.ApplyOutcome(
            displayName: "X", requestedSize: (0, 0), requestedHz: nil,
            appliedSize: nil, appliedHz: nil, status: .skippedNoMode
        )
        let failed = ProfileStore.ApplyOutcome(
            displayName: "X", requestedSize: (0, 0), requestedHz: nil,
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
