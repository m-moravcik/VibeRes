import Foundation

/// A mode request typed on the command line: `viberes set <display> <spec>`.
///
/// Lives in Core rather than in the CLI target so the tests exercise the real
/// parser. They used to carry two hand-copied mirrors of it, which is how a
/// grammar change would have been tested against a parser nobody runs.
struct ResolutionSpec: Equatable {
    var width: Int
    var height: Int
    var refreshHz: Int?
    var preferHiDPI: Bool
    /// `vrr` after the rate: prefer the variable refresh (Adaptive Sync) mode
    /// over its fixed twin. See `ModeScoring.Request.preferVariable`.
    var preferVariable: Bool = false

    /// Parse strings like:
    ///   "1800x1169"          → 1800×1169, no refresh, default HiDPI prefer
    ///   "1800x1169@120"      → with refresh
    ///   "1920x1080@60-native" → native (non-HiDPI)
    ///   "1920x1080-hidpi"    → HiDPI
    ///   "2560x1440@160vrr"   → the variable refresh mode at 160 Hz
    ///   "2560x1440@vrr"      → the variable refresh mode at the highest rate
    static func parse(_ s: String) -> ResolutionSpec? {
        var spec = ResolutionSpec(width: 0, height: 0, refreshHz: nil, preferHiDPI: true)
        var rest = s.lowercased()

        if rest.hasSuffix("-native") {
            spec.preferHiDPI = false
            rest.removeLast("-native".count)
        } else if rest.hasSuffix("-hidpi") {
            spec.preferHiDPI = true
            rest.removeLast("-hidpi".count)
        }

        let parts = rest.split(separator: "@", maxSplits: 1).map(String.init)
        guard let dim = parts.first else { return nil }
        let dims = dim.split(separator: "x", maxSplits: 1).map(String.init)
        guard dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]) else { return nil }
        // Clamp to sane physical-display limits to keep scoring math safe even
        // when the user feeds the CLI a number outside the realistic range.
        guard (1...16384).contains(w), (1...16384).contains(h) else { return nil }
        spec.width = w
        spec.height = h

        if parts.count == 2 {
            var rate = parts[1]
            if rate.hasSuffix("vrr") {
                spec.preferVariable = true
                rate.removeLast("vrr".count)
            }
            let hz = rate.replacingOccurrences(of: "hz", with: "")
            // A bare "@vrr" leaves no rate: highest available, variable.
            if hz.isEmpty, spec.preferVariable {
                return spec
            }
            if let value = Int(hz), (1...1000).contains(value) {
                spec.refreshHz = value
            } else {
                return nil
            }
        }
        return spec
    }
}
