import Testing
@testable import VibeRes

/// The CLI lives in its own target, so we reproduce its parser here as a small
/// pure-function copy and lock down the contract. If the CLI's parser drifts,
/// these tests will not catch it directly — they pin the spec language itself.
@Suite("CLI ResolutionSpec parsing contract")
struct CLIArgsTests {
    /// Mirrors VibeResCLI/main.swift: ResolutionSpec.parse.
    private struct Spec: Equatable {
        var width: Int
        var height: Int
        var refreshHz: Int?
        var preferHiDPI: Bool
    }

    private func parse(_ s: String) -> Spec? {
        var spec = Spec(width: 0, height: 0, refreshHz: nil, preferHiDPI: true)
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
        spec.width = w
        spec.height = h

        if parts.count == 2 {
            let hz = parts[1].replacingOccurrences(of: "hz", with: "")
            spec.refreshHz = Int(hz)
        }
        return spec
    }

    @Test("Bare WxH parses with default HiDPI preference")
    func bareSize() {
        let spec = parse("1800x1169")
        #expect(spec == Spec(width: 1800, height: 1169, refreshHz: nil, preferHiDPI: true))
    }

    @Test("Refresh rate after @ parses as integer")
    func withRefresh() {
        let spec = parse("1800x1169@120")
        #expect(spec == Spec(width: 1800, height: 1169, refreshHz: 120, preferHiDPI: true))
    }

    @Test("hz suffix on refresh rate is stripped")
    func refreshWithHzSuffix() {
        let spec = parse("1920x1080@60hz")
        #expect(spec == Spec(width: 1920, height: 1080, refreshHz: 60, preferHiDPI: true))
    }

    @Test("-native suffix forces non-HiDPI preference")
    func nativeSuffix() {
        let spec = parse("2560x1440-native")
        #expect(spec == Spec(width: 2560, height: 1440, refreshHz: nil, preferHiDPI: false))
    }

    @Test("-hidpi suffix is explicit (default-equivalent)")
    func hidpiSuffix() {
        let spec = parse("1800x1169-hidpi")
        #expect(spec == Spec(width: 1800, height: 1169, refreshHz: nil, preferHiDPI: true))
    }

    @Test("Combined refresh + native suffix parses both")
    func combinedRefreshAndNative() {
        let spec = parse("1920x1080@60-native")
        #expect(spec == Spec(width: 1920, height: 1080, refreshHz: 60, preferHiDPI: false))
    }

    @Test("Garbage input returns nil")
    func garbageRejected() {
        #expect(parse("nonsense") == nil)
        #expect(parse("1800") == nil)
        #expect(parse("1800x") == nil)
        #expect(parse("xfoo") == nil)
    }

    @Test("Lowercase normalisation: case-insensitive")
    func caseInsensitive() {
        let s1 = parse("1920X1080@60")
        let s2 = parse("1920x1080@60HZ")
        let s3 = parse("1920X1080@60Hz-NATIVE")
        #expect(s1?.width == 1920)
        #expect(s2?.refreshHz == 60)
        #expect(s3?.preferHiDPI == false)
    }
}
