import Testing
@testable import VibeRes

/// CLI parser bounds tests. The parser lives in VibeResCLI/main.swift and is
/// duplicated here for unit-test reachability — the CLI is its own target
/// without a public API. The parser shape is small enough that drift is
/// catchable by the existing CLIArgsTests behavioural suite.
///
/// These tests focus on the new bounds-checking behaviour added in 0.3.0 to
/// reject pathological inputs like 99999×99999 or 0×0 before they reach the
/// scoring math.
@Suite("ResolutionSpec parser bounds")
struct ResolutionSpecBoundsTests {
    /// Mirror of the production parser. Kept private to this test file so it
    /// can never accidentally be relied on from app code.
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
        guard (1...16384).contains(w), (1...16384).contains(h) else { return nil }
        spec.width = w
        spec.height = h

        if parts.count == 2 {
            let hz = parts[1].replacingOccurrences(of: "hz", with: "")
            if let rate = Int(hz), (1...1000).contains(rate) {
                spec.refreshHz = rate
            } else {
                return nil
            }
        }
        return spec
    }

    @Test("Realistic resolution still parses")
    func realisticResolution() {
        let s = parse("1800x1169@120")
        #expect(s?.width == 1800)
        #expect(s?.height == 1169)
        #expect(s?.refreshHz == 120)
    }

    @Test("Zero width or height rejected")
    func zeroDimensions() {
        #expect(parse("0x100") == nil)
        #expect(parse("100x0") == nil)
    }

    @Test("Width above 16384 rejected (8K-class is the practical ceiling)")
    func tooLargeWidth() {
        #expect(parse("99999x1080") == nil)
    }

    @Test("Height above 16384 rejected")
    func tooLargeHeight() {
        #expect(parse("1920x99999") == nil)
    }

    @Test("Refresh rate above 1000 Hz rejected")
    func tooLargeRefresh() {
        #expect(parse("1920x1080@9999") == nil)
    }

    @Test("Refresh rate of 0 rejected")
    func zeroRefresh() {
        // 0Hz is allowed in CGDisplayMode for synthetic modes but the user
        // can't ask for it via CLI — they'd be telling us nothing useful.
        #expect(parse("1920x1080@0") == nil)
    }

    @Test("Negative dimensions rejected")
    func negativeDimensions() {
        // Int(...) succeeds for "-100", but the bounds check catches it.
        #expect(parse("-100x1080") == nil)
        #expect(parse("1920x-100") == nil)
    }

    @Test("Boundary values 1 and 16384 are accepted")
    func boundaryValuesAccepted() {
        #expect(parse("1x1") != nil)
        #expect(parse("16384x16384") != nil)
    }
}
