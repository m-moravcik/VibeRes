import CoreGraphics
import Foundation

/// One row in the compact menu: a single point size with all the refresh rates available
/// for it on a given display. The UI renders the size once and surfaces refresh rates as chips.
struct ResolutionGroup: Identifiable, Hashable {
    let pointWidth: Int
    let pointHeight: Int
    let isHiDPI: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    /// Sorted ascending so chips read 60 · 120 left-to-right.
    let modesByRefresh: [(hz: Int, mode: CGDisplayMode)]

    var id: String { "\(pointWidth)x\(pointHeight)-\(isHiDPI ? "hidpi" : "native")" }

    static func == (lhs: ResolutionGroup, rhs: ResolutionGroup) -> Bool {
        lhs.id == rhs.id && lhs.modesByRefresh.map(\.hz) == rhs.modesByRefresh.map(\.hz)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func build(from modes: [CGDisplayMode]) -> [ResolutionGroup] {
        let buckets = ResolutionBucketing.bucket(modes)
        return buckets.map { bucket in
            ResolutionGroup(
                pointWidth: bucket.key.width,
                pointHeight: bucket.key.height,
                isHiDPI: bucket.key.isHiDPI,
                pixelWidth: bucket.pixelWidth,
                pixelHeight: bucket.pixelHeight,
                modesByRefresh: bucket.entries.map { (hz: $0.hz, mode: $0.mode) }
            )
        }
    }
}

/// Generic bucketing used by `ResolutionGroup.build`. Extracted so it can be unit-tested
/// against stub `DisplayModeProtocol` values without instantiating real CGDisplayModes.
enum ResolutionBucketing {
    struct Key: Hashable {
        let width: Int
        let height: Int
        let isHiDPI: Bool
    }

    struct Bucket<Mode: DisplayModeProtocol> {
        let key: Key
        let pixelWidth: Int
        let pixelHeight: Int
        let entries: [(hz: Int, mode: Mode)]
    }

    /// Group modes by (point width, point height, HiDPI) and dedup NTSC drop-frame
    /// refresh-rate variants (59.94, 47.95, ...) against their integer counterparts
    /// (60, 48). When both exist, prefer the one whose float Hz is closer to a whole
    /// integer — that's the user-visible variant in System Settings.
    static func bucket<Mode: DisplayModeProtocol>(_ modes: [Mode]) -> [Bucket<Mode>] {
        var raw: [Key: [(Int, Mode)]] = [:]
        for m in modes {
            let key = Key(width: m.width, height: m.height, isHiDPI: m.isHiDPI)
            let hz = m.refreshHz ?? 0
            raw[key, default: []].append((hz, m))
        }

        return raw.map { key, entries in
            // Dedup by rounded Hz, keeping whichever variant is closer to an integer.
            var byHz: [Int: (drift: Double, mode: Mode)] = [:]
            for (hz, mode) in entries {
                let exact = mode.refreshRate
                let drift = abs(exact - exact.rounded())
                if let prior = byHz[hz] {
                    if drift < prior.drift {
                        byHz[hz] = (drift, mode)
                    }
                } else {
                    byHz[hz] = (drift, mode)
                }
            }
            let sorted: [(hz: Int, mode: Mode)] = byHz
                .map { (hz: $0.key, mode: $0.value.mode) }
                .sorted { $0.hz < $1.hz }
            let rep = sorted.first?.mode
            return Bucket<Mode>(
                key: key,
                pixelWidth: rep?.pixelWidth ?? key.width,
                pixelHeight: rep?.pixelHeight ?? key.height,
                entries: sorted
            )
        }
        .sorted { lhs, rhs in
            if lhs.key.width != rhs.key.width { return lhs.key.width > rhs.key.width }
            if lhs.key.height != rhs.key.height { return lhs.key.height > rhs.key.height }
            return lhs.key.isHiDPI && !rhs.key.isHiDPI
        }
    }
}
