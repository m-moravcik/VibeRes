import CoreGraphics
import Foundation

/// One refresh-rate choice at a size: a fixed rate, or a variable refresh
/// (VRR) mode that ranges up to `hz`.
struct RefreshOption<Mode: DisplayModeProtocol> {
    let hz: Int
    let isVariable: Bool
    /// Variable, and the same size also offers a *fixed* option at `hz`. Only
    /// such an option needs its own "VRR" label; a variable rate without a
    /// twin (ProMotion's 120 Hz) is simply that rate to the user.
    let isVRRTwin: Bool
    let mode: Mode
}

/// One row in the compact menu: a single point size with all the refresh rates available
/// for it on a given display. The UI renders the size once and surfaces refresh rates as chips.
struct ResolutionGroup: Identifiable, Hashable {
    let pointWidth: Int
    let pointHeight: Int
    let isHiDPI: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    /// Sorted ascending so chips read 60 · 120 left-to-right, with VRR twins
    /// after every numbered rate (see `ResolutionBucketing.bucket`).
    let modesByRefresh: [RefreshOption<CGDisplayMode>]

    var id: String { "\(pointWidth)x\(pointHeight)-\(isHiDPI ? "hidpi" : "native")" }

    /// The kind takes part: toggling Adaptive Sync can turn a fixed 160 into
    /// a variable one without changing a single rate, and a group that only
    /// compared rates would let SwiftUI keep showing the stale chips.
    static func == (lhs: ResolutionGroup, rhs: ResolutionGroup) -> Bool {
        lhs.id == rhs.id
            && lhs.modesByRefresh.map(\.hz) == rhs.modesByRefresh.map(\.hz)
            && lhs.modesByRefresh.map(\.isVariable) == rhs.modesByRefresh.map(\.isVariable)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// The option a one-click apply picks: the row in Simple Mode, the size
    /// label in Advanced Mode. See `VariableRefresh.preferredIndex`.
    func preferredOption(currentIsVariable: Bool) -> RefreshOption<CGDisplayMode>? {
        ResolutionBucketing.preferredOption(in: modesByRefresh, currentIsVariable: currentIsVariable)
    }

    static func build(
        from modes: [CGDisplayMode],
        isVariable: (CGDisplayMode) -> Bool = { _ in false }
    ) -> [ResolutionGroup] {
        let buckets = ResolutionBucketing.bucket(modes, isVariable: isVariable)
        return buckets.map { bucket in
            ResolutionGroup(
                pointWidth: bucket.key.width,
                pointHeight: bucket.key.height,
                isHiDPI: bucket.key.isHiDPI,
                pixelWidth: bucket.pixelWidth,
                pixelHeight: bucket.pixelHeight,
                modesByRefresh: bucket.entries
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

    /// Dedup key within a bucket: one survivor per rate *and* kind.
    private struct RateKey: Hashable {
        let hz: Int
        let isVariable: Bool
    }

    struct Bucket<Mode: DisplayModeProtocol> {
        let key: Key
        let pixelWidth: Int
        let pixelHeight: Int
        let entries: [RefreshOption<Mode>]
    }

    /// Group modes by (point width, point height, HiDPI) and dedup NTSC drop-frame
    /// refresh-rate variants (59.94, 47.95, ...) against their integer counterparts
    /// (60, 48). When both exist, prefer the one whose float Hz is closer to a whole
    /// integer — that's the user-visible variant in System Settings.
    ///
    /// The dedup runs within each refresh kind and never across: a variable
    /// 160 Hz and a fixed 160 Hz are as alike as CoreGraphics can describe two
    /// modes, and merging them is what used to lose one of them (issue #7).
    /// `isVariable` defaults to "every mode is fixed", today's behaviour.
    static func bucket<Mode: DisplayModeProtocol>(
        _ modes: [Mode],
        isVariable: (Mode) -> Bool = { _ in false }
    ) -> [Bucket<Mode>] {
        var raw: [Key: [(Int, Bool, Mode)]] = [:]
        for m in modes {
            let key = Key(width: m.width, height: m.height, isHiDPI: m.isHiDPI)
            let hz = m.refreshHz ?? 0
            raw[key, default: []].append((hz, isVariable(m), m))
        }

        return raw.map { key, entries in
            // Dedup by rounded Hz and kind, keeping whichever variant is closer to an integer.
            var byRate: [RateKey: (drift: Double, mode: Mode)] = [:]
            for (hz, variable, mode) in entries {
                let exact = mode.refreshRate
                let drift = abs(exact - exact.rounded())
                let rate = RateKey(hz: hz, isVariable: variable)
                if let prior = byRate[rate] {
                    if drift < prior.drift {
                        byRate[rate] = (drift, mode)
                    }
                } else {
                    byRate[rate] = (drift, mode)
                }
            }
            let fixedRates = Set(byRate.keys.filter { !$0.isVariable }.map(\.hz))
            // Numbered chips ascending, then the VRR twins: "60 · 144 · 160 · VRR"
            // reads as rates followed by the one choice that is not a rate.
            let sorted: [RefreshOption<Mode>] = byRate
                .map { rate, value in
                    RefreshOption(
                        hz: rate.hz,
                        isVariable: rate.isVariable,
                        isVRRTwin: rate.isVariable && fixedRates.contains(rate.hz),
                        mode: value.mode
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.isVRRTwin != rhs.isVRRTwin { return !lhs.isVRRTwin }
                    if lhs.hz != rhs.hz { return lhs.hz < rhs.hz }
                    // Only reachable for twins of a twin: one rate, both kinds.
                    return !lhs.isVariable && rhs.isVariable
                }
            // Pixel size from the lowest numbered rate, as before VRR support,
            // so a VRR twin never decides it.
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

    /// Generic body of `ResolutionGroup.preferredOption`, so the Simple Mode
    /// rule is tested against stub modes.
    static func preferredOption<Mode: DisplayModeProtocol>(
        in options: [RefreshOption<Mode>],
        currentIsVariable: Bool
    ) -> RefreshOption<Mode>? {
        VariableRefresh.preferredIndex(
            options.map { (hz: $0.hz, isVariable: $0.isVariable) },
            stayVariable: currentIsVariable
        ).map { options[$0] }
    }
}
