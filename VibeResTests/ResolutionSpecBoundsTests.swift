import Testing
@testable import VibeRes

/// CLI parser bounds tests, against the real `ResolutionSpec.parse` (moved
/// into Core so this no longer tests a private copy of it).
///
/// These tests focus on the new bounds-checking behaviour added in 0.3.0 to
/// reject pathological inputs like 99999×99999 or 0×0 before they reach the
/// scoring math.
@Suite("ResolutionSpec parser bounds")
struct ResolutionSpecBoundsTests {
    private func parse(_ s: String) -> ResolutionSpec? {
        ResolutionSpec.parse(s)
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

    @Test("Refresh rate bounds apply to a vrr rate too")
    func vrrRefreshBounds() {
        #expect(parse("1920x1080@9999vrr") == nil)
        #expect(parse("1920x1080@0vrr") == nil)
        #expect(parse("1920x1080@1000vrr")?.refreshHz == 1000)
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
