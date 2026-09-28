import Testing
@testable import VibeRes

/// An `.anyExternal` entry's saved refresh rate was measured on whichever
/// monitor happened to be attached when the profile was saved. Forcing it onto
/// a different external is how a 4K TV behind a USB-C→HDMI adapter got
/// switched to 60 Hz: CoreGraphics lists 60 Hz as valid, the link cannot carry
/// it, and the TV went dark. The external's own current rate, which macOS
/// remembers per display, is the ceiling instead.
@Suite("Refresh rate requested per display")
struct AnyExternalRefreshTests {
    private func entry(_ matcher: DisplayMatcher, hz: Int?) -> Profile.Entry {
        Profile.Entry(
            matcher: matcher,
            displayName: "Saved on another monitor",
            pointWidth: 1920,
            pointHeight: 1080,
            refreshHz: hz,
            isHiDPI: false
        )
    }

    private let specific = DisplayMatcher.edid(vendor: 1, model: 2, serial: 3)
    private let builtIn = DisplayMatcher.builtIn(vendor: 1, model: 2, serial: 3)

    @Test("Any external never asks for more than the display runs at now")
    func anyExternalCappedByCurrent() {
        #expect(entry(.anyExternal, hz: 60).requestedHz(currentHz: 30) == 30)
    }

    @Test("Any external keeps the saved rate when the display runs faster")
    func anyExternalKeepsLowerSaved() {
        #expect(entry(.anyExternal, hz: 60).requestedHz(currentHz: 144) == 60)
    }

    @Test("Any external falls back to whichever rate is known")
    func anyExternalPartialKnowledge() {
        #expect(entry(.anyExternal, hz: 60).requestedHz(currentHz: nil) == 60)
        #expect(entry(.anyExternal, hz: nil).requestedHz(currentHz: 30) == 30)
        #expect(entry(.anyExternal, hz: nil).requestedHz(currentHz: nil) == nil)
    }

    @Test("A monitor-locked entry keeps its saved rate", arguments: [
        DisplayMatcher.edid(vendor: 1, model: 2, serial: 3),
        DisplayMatcher.builtIn(vendor: 1, model: 2, serial: 3),
    ])
    func lockedEntriesUnchanged(matcher: DisplayMatcher) {
        // Saved on this very panel, so the rate is known to work on it.
        #expect(entry(matcher, hz: 60).requestedHz(currentHz: 30) == 60)
        #expect(entry(matcher, hz: nil).requestedHz(currentHz: 30) == nil)
    }

    /// The reported case: Samsung TV at 1920×1080 HiDPI 30 Hz, profile saved
    /// as 1920×1080 native 60 Hz on another monitor. Every rate below is one
    /// CoreGraphics really listed for that TV.
    @Test("The TV stays at 30 Hz instead of being pushed to 60 Hz")
    func samsungOverAdapter() {
        let modes: [StubDisplayMode] = [
            .native(width: 1920, height: 1080, hz: 60, id: 92),
            .hiDPI(width: 1920, height: 1080, hz: 60, id: 93),
            .native(width: 1920, height: 1080, hz: 50, id: 94),
            .native(width: 1920, height: 1080, hz: 30, id: 96),
            .hiDPI(width: 1920, height: 1080, hz: 30, id: 97),
            .native(width: 1920, height: 1080, hz: 24, id: 100),
        ]
        let hz = entry(.anyExternal, hz: 60).requestedHz(currentHz: 30)
        let picked = ModeScoring.bestMatch(
            in: modes,
            request: ModeScoring.Request(width: 1920, height: 1080, refreshHz: hz, preferHiDPI: false)
        )
        #expect(picked?.refreshHz == 30)
    }
}
