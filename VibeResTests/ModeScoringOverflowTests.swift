import Foundation
import Testing
@testable import VibeRes

/// `ModeScoring.score` did trapping arithmetic on caller-supplied numbers:
/// `abs(mode.width - request.width)`, then `* 2`, then sums. The Shortcuts
/// action accepts an unbounded `Int`, so a malformed automation could hand it
/// `Int.min` and terminate the process — `abs(1920 - Int.min)` traps.
///
/// Two defences, because either alone is one forgetful caller away from the
/// same crash: the intent rejects out-of-range values, and scoring survives
/// them anyway.
@Suite("Mode scoring overflow safety")
struct ModeScoringOverflowTests {
    private struct StubMode: DisplayModeProtocol {
        let width: Int
        let height: Int
        var pixelWidth: Int
        var pixelHeight: Int
        let refreshRate: Double
        let ioDisplayModeID: Int32 = 0

        /// `isHiDPI` and `refreshHz` are derived by the protocol extension, so a
        /// stub sets the underlying pixel size and refresh rate instead.
        init(width: Int, height: Int, refreshHz: Int?, isHiDPI: Bool) {
            self.width = width
            self.height = height
            self.pixelWidth = isHiDPI ? width &* 2 : width
            self.pixelHeight = isHiDPI ? height &* 2 : height
            self.refreshRate = Double(refreshHz ?? 0)
        }
    }

    private let mode = StubMode(width: 1920, height: 1080, refreshHz: 60, isHiDPI: false)

    @Test("Extreme requested sizes score without trapping")
    func extremeSizes() {
        for value in [Int.min, Int.max, Int.min + 1, Int.max - 1] {
            let request = ModeScoring.Request(
                width: value, height: value, refreshHz: nil, preferHiDPI: false
            )
            let score = ModeScoring.score(mode, request: request)
            #expect(score >= 0, "score must stay usable for width/height \(value)")
        }
    }

    @Test("Extreme requested refresh rates score without trapping")
    func extremeRefresh() {
        for value in [Int.min, Int.max] {
            let request = ModeScoring.Request(
                width: 1920, height: 1080, refreshHz: value, preferHiDPI: false
            )
            #expect(ModeScoring.score(mode, request: request) >= 0)
        }
    }

    @Test("Picking a best match from extreme input still returns a mode")
    func bestMatchSurvives() {
        let modes = [mode, StubMode(width: 1280, height: 720, refreshHz: nil, isHiDPI: true)]
        let request = ModeScoring.Request(
            width: Int.min, height: Int.max, refreshHz: Int.min, preferHiDPI: true
        )
        #expect(ModeScoring.bestMatch(in: modes, request: request) != nil)
    }

    @Test("Ordinary requests are scored exactly as before")
    func ordinaryScoringUnchanged() {
        // Saturation must not perturb real numbers: 1920x1080@60 against
        // 1900x1000@60 is 20 + 80 of size delta and nothing else.
        let request = ModeScoring.Request(
            width: 1900, height: 1000, refreshHz: 60, preferHiDPI: false
        )
        #expect(ModeScoring.score(mode, request: request) == 100)
    }

    @Test("The Shortcuts action refuses values outside the CLI's own bounds")
    func intentBoundsMatchTheCLI() {
        // The CLI has always clamped to 1...16384 and 1...1000; the Shortcuts
        // action accepted anything.
        #expect(ModeScoring.isRequestInRange(width: 1920, height: 1080, refreshHz: 60))
        #expect(ModeScoring.isRequestInRange(width: 1, height: 1, refreshHz: nil))
        #expect(!ModeScoring.isRequestInRange(width: 0, height: 1080, refreshHz: nil))
        #expect(!ModeScoring.isRequestInRange(width: 16385, height: 1080, refreshHz: nil))
        #expect(!ModeScoring.isRequestInRange(width: 1920, height: 1080, refreshHz: 0))
        #expect(!ModeScoring.isRequestInRange(width: 1920, height: 1080, refreshHz: 1001))
        #expect(!ModeScoring.isRequestInRange(width: Int.min, height: Int.max, refreshHz: Int.min))
    }
}
