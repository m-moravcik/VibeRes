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

    static func bestMatch<Mode: DisplayModeProtocol>(
        in modes: [Mode],
        request: Request
    ) -> Mode? {
        modes.min { lhs, rhs in
            isBetter(lhs, than: rhs, request: request)
        }
    }

    static func score<Mode: DisplayModeProtocol>(_ mode: Mode, request: Request) -> Int {
        let sizeDelta = abs(mode.width - request.width) + abs(mode.height - request.height)
        let hidpiPenalty = (mode.isHiDPI == request.preferHiDPI) ? 0 : 50
        var hzPenalty = 0
        if let want = request.refreshHz, let got = mode.refreshHz {
            hzPenalty = abs(want - got) * 2
        } else if let want = request.refreshHz, mode.refreshHz == nil {
            hzPenalty = want
        }
        return sizeDelta + hidpiPenalty + hzPenalty
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
