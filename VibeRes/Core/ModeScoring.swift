import Foundation

/// Shared "closest display mode" scoring for GUI, CLI, profiles, and Shortcuts.
/// Lower score wins; ties prefer the highest refresh rate when the caller did
/// not request a specific Hz.
enum ModeScoring {
    struct Request {
        let width: Int
        let height: Int
        let refreshHz: Int?
        let preferHiDPI: Bool
    }

    /// Bounds a caller-supplied request has to satisfy before it reaches
    /// scoring. Matches what the CLI has always enforced; the Shortcuts action
    /// accepted anything, which is how `Int.min` could reach the arithmetic
    /// below.
    static func isRequestInRange(width: Int, height: Int, refreshHz: Int?) -> Bool {
        guard (1...16384).contains(width), (1...16384).contains(height) else { return false }
        if let refreshHz { return (1...1000).contains(refreshHz) }
        return true
    }

    // Saturating helpers. Scoring runs on numbers a caller supplies, and a
    // comparison heuristic has no business terminating the process over one —
    // an unreachable score is a fine answer, a crash is not. Validation at the
    // boundary should stop these ever mattering; this is the second line.
    private static func absDelta(_ a: Int, _ b: Int) -> Int {
        let (difference, overflowed) = a.subtractingReportingOverflow(b)
        if overflowed { return .max }
        // abs(Int.min) has no representation.
        return difference == .min ? .max : abs(difference)
    }

    private static func saturatingAdd(_ a: Int, _ b: Int) -> Int {
        let (sum, overflowed) = a.addingReportingOverflow(b)
        return overflowed ? .max : sum
    }

    private static func saturatingMultiply(_ a: Int, by b: Int) -> Int {
        let (product, overflowed) = a.multipliedReportingOverflow(by: b)
        return overflowed ? .max : product
    }

    static func bestMatch<Mode: DisplayModeProtocol>(
        in modes: [Mode],
        request: Request
    ) -> Mode? {
        modes.min { lhs, rhs in
            isBetter(lhs, than: rhs, request: request)
        }
    }

    static func score<Mode: DisplayModeProtocol>(_ mode: Mode, request: Request) -> Int {
        let sizeDelta = saturatingAdd(
            absDelta(mode.width, request.width),
            absDelta(mode.height, request.height)
        )
        let hidpiPenalty = (mode.isHiDPI == request.preferHiDPI) ? 0 : 50
        var hzPenalty = 0
        if let want = request.refreshHz, let got = mode.refreshHz {
            hzPenalty = saturatingMultiply(absDelta(want, got), by: 2)
        } else if let want = request.refreshHz, mode.refreshHz == nil {
            // A negative request would otherwise pull the score below zero and
            // make an unusable mode look like the best match.
            hzPenalty = max(0, want)
        }
        return saturatingAdd(saturatingAdd(sizeDelta, hidpiPenalty), hzPenalty)
    }

    private static func isBetter<Mode: DisplayModeProtocol>(
        _ lhs: Mode,
        than rhs: Mode,
        request: Request
    ) -> Bool {
        let lhsScore = score(lhs, request: request)
        let rhsScore = score(rhs, request: request)
        if lhsScore != rhsScore { return lhsScore < rhsScore }

        if request.refreshHz == nil {
            let lhsHz = lhs.refreshHz ?? Int.min
            let rhsHz = rhs.refreshHz ?? Int.min
            if lhsHz != rhsHz { return lhsHz > rhsHz }
        }

        return lhs.ioDisplayModeID < rhs.ioDisplayModeID
    }
}
