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

    /// Returns groups sorted largest → smallest. Modes whose refresh rate the API reports as 0
    /// (synthetic / virtual) are kept under a single nil-equivalent slot we represent as 0Hz.
    static func build(from modes: [CGDisplayMode]) -> [ResolutionGroup] {
        // Bucket by (width, height, isHiDPI). Refresh rate is the only varying axis inside a bucket.
        struct Key: Hashable {
            let w: Int
            let h: Int
            let hidpi: Bool
        }
        var buckets: [Key: [(Int, CGDisplayMode)]] = [:]
        for m in modes {
            let key = Key(w: m.width, h: m.height, hidpi: m.isHiDPI)
            let hz = m.refreshHz ?? 0
            buckets[key, default: []].append((hz, m))
        }

        return buckets.map { key, entries in
            let sorted = entries.sorted { $0.0 < $1.0 }
            // Pick a representative mode for pixel size (all entries in a bucket share it).
            let rep = sorted.first?.1
            return ResolutionGroup(
                pointWidth: key.w,
                pointHeight: key.h,
                isHiDPI: key.hidpi,
                pixelWidth: rep?.pixelWidth ?? key.w,
                pixelHeight: rep?.pixelHeight ?? key.h,
                modesByRefresh: sorted.map { (hz: $0.0, mode: $0.1) }
            )
        }
        .sorted { lhs, rhs in
            // Primary: width desc; tie-break by height desc; HiDPI before non-HiDPI at same size.
            if lhs.pointWidth != rhs.pointWidth { return lhs.pointWidth > rhs.pointWidth }
            if lhs.pointHeight != rhs.pointHeight { return lhs.pointHeight > rhs.pointHeight }
            return lhs.isHiDPI && !rhs.isHiDPI
        }
    }
}
