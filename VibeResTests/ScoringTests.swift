import Testing
@testable import VibeRes

/// Mirrors the scoring formula from SetResolutionIntent.bestMatch so we can
/// exercise it without depending on AppIntents runtime.
@Suite("SetResolutionIntent scoring")
struct ScoringTests {
    /// Same weights as production code.
    private func score(
        mode: StubDisplayMode,
        wantW: Int,
        wantH: Int,
        wantHz: Int? = nil,
        preferHiDPI: Bool = true
    ) -> Double {
        let sizeDelta = abs(mode.width - wantW) + abs(mode.height - wantH)
        let hidpiPenalty = (mode.isHiDPI == preferHiDPI) ? 0 : 50
        var hzPenalty = 0
        if let want = wantHz, let got = mode.refreshHz {
            hzPenalty = abs(want - got) * 2
        } else if let want = wantHz, mode.refreshHz == nil {
            hzPenalty = want
        }
        return Double(sizeDelta + hidpiPenalty + hzPenalty)
    }

    private func best(
        modes: [StubDisplayMode],
        wantW: Int,
        wantH: Int,
        wantHz: Int? = nil,
        preferHiDPI: Bool = true
    ) -> StubDisplayMode? {
        modes.min { score(mode: $0, wantW: wantW, wantH: wantH, wantHz: wantHz, preferHiDPI: preferHiDPI)
                  < score(mode: $1, wantW: wantW, wantH: wantH, wantHz: wantHz, preferHiDPI: preferHiDPI) }
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

    @Test("Empty mode list returns nil")
    func emptyList() {
        #expect(best(modes: [], wantW: 1, wantH: 1) == nil)
    }
}
