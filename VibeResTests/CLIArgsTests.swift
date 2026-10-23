import Testing
@testable import VibeRes

/// The grammar `viberes set` accepts. The parser used to live in the CLI
/// target with a hand-copied mirror here; it is in Core now, so these pin the
/// code that actually runs.
@Suite("CLI ResolutionSpec parsing contract")
struct CLIArgsTests {
    private typealias Spec = ResolutionSpec

    private func parse(_ s: String) -> Spec? {
        ResolutionSpec.parse(s)
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

    // MARK: Variable refresh

    @Test("vrr after the rate asks for the variable refresh mode at that rate")
    func vrrAfterRate() {
        let spec = parse("2560x1440@160vrr")
        #expect(spec == Spec(width: 2560, height: 1440, refreshHz: 160, preferHiDPI: true, preferVariable: true))
    }

    @Test("@vrr alone asks for the variable mode at the highest rate")
    func bareVRR() {
        let spec = parse("2560x1440@vrr")
        #expect(spec == Spec(width: 2560, height: 1440, refreshHz: nil, preferHiDPI: true, preferVariable: true))
    }

    @Test("vrr combines with the hz unit, the scale suffix and any case")
    func vrrCombinations() {
        #expect(parse("2560x1440@160hzvrr")?.preferVariable == true)
        #expect(parse("2560x1440@160HzVRR")?.refreshHz == 160)
        let native = parse("2560x1440@160vrr-native")
        #expect(native?.preferVariable == true)
        #expect(native?.preferHiDPI == false)
    }

    @Test("Without vrr the fixed mode is preferred, as before")
    func fixedByDefault() {
        #expect(parse("2560x1440@160")?.preferVariable == false)
        #expect(parse("2560x1440")?.preferVariable == false)
    }

    @Test("vrr is only a rate suffix: a stray or misplaced one is rejected")
    func vrrMisplaced() {
        #expect(parse("2560x1440vrr") == nil)
        #expect(parse("2560x1440@vrr160") == nil)
    }
}
