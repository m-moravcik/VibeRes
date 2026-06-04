import Testing
@testable import VibeRes

/// Mirrors the scoring formula from SetResolutionIntent.bestMatch so we can
/// exercise it without depending on AppIntents runtime.
@Suite("SetResolutionIntent scoring")
struct ScoringTests {
    private func best(
        modes: [StubDisplayMode],
        wantW: Int,
        wantH: Int,
        wantHz: Int? = nil,
        preferHiDPI: Bool = true
    ) -> StubDisplayMode? {
        ModeScoring.bestMatch(
            in: modes,
            request: ModeScoring.Request(
                width: wantW,
                height: wantH,
                refreshHz: wantHz,
                preferHiDPI: preferHiDPI
            )
        )
    }

    @Test("Exact match wins over near matches")
    func exactWins() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1800, height: 1169, id: 1),
            StubDisplayMode.hiDPI(width: 1512, height: 982, id: 2),
        ]
        #expect(best(modes: modes, wantW: 1800, wantH: 1169)?.ioDisplayModeID == 1)
    }

    @Test("Closest size is chosen when no exact match exists")
    func closestSize() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1024, height: 665, id: 1),
            StubDisplayMode.hiDPI(width: 1280, height: 800, id: 2),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, id: 3),
        ]
        // Asking for 1300x800 should pick the 1280x800 mode (id=2)
        #expect(best(modes: modes, wantW: 1300, wantH: 800)?.ioDisplayModeID == 2)
    }

    @Test("HiDPI preference breaks tie at the same size")
    func hiDPITieBreak() {
        let modes = [
            StubDisplayMode.native(width: 1920, height: 1080, id: 1),
            StubDisplayMode.hiDPI(width: 1920, height: 1080, id: 2),
        ]
        #expect(best(modes: modes, wantW: 1920, wantH: 1080, preferHiDPI: true)?.ioDisplayModeID == 2)
        #expect(best(modes: modes, wantW: 1920, wantH: 1080, preferHiDPI: false)?.ioDisplayModeID == 1)
    }

    @Test("Refresh rate distance is honoured when specified")
    func refreshDistance() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60, id: 1),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 120, id: 2),
        ]
        #expect(best(modes: modes, wantW: 1800, wantH: 1169, wantHz: 120)?.ioDisplayModeID == 2)
        #expect(best(modes: modes, wantW: 1800, wantH: 1169, wantHz: 60)?.ioDisplayModeID == 1)
    }

    @Test("Highest refresh wins when refresh is omitted and size/scale are tied")
    func highestRefreshWinsWhenOmitted() {
        let modes = [
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60, id: 1),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 120, id: 2),
        ]
        #expect(best(modes: modes, wantW: 1800, wantH: 1169)?.ioDisplayModeID == 2)
    }

    @Test("Empty mode list returns nil")
    func emptyList() {
        #expect(best(modes: [], wantW: 1, wantH: 1) == nil)
    }
}
