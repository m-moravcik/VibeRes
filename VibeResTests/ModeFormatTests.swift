import Foundation
import Testing
@testable import VibeRes

/// Every user-facing size and rate goes through `ModeFormat`. These pin the one
/// shape, and pin that the surfaces which used to write their own dialect
/// ("2560×1440 @75Hz", "@ 60Hz", "2560×1440 · 60 Hz") now agree, in a non-English
/// locale as well.
@Suite("ModeFormat: one format for sizes and refresh rates")
struct ModeFormatTests {
    private static let size = "2\u{202F}560 \u{00D7} 1\u{202F}440"

    @Test("Size, rate and mode have one shape")
    func shape() {
        #expect(ModeFormat.size(width: 2560, height: 1440) == Self.size)
        #expect(ModeFormat.size(width: 800, height: 600) == "800 \u{00D7} 600")
        #expect(ModeFormat.size(width: 1_000_000, height: 12) == "1\u{202F}000\u{202F}000 \u{00D7} 12")
        #expect(ModeFormat.rate(60) == "60 Hz")
        #expect(ModeFormat.rate(160, vrr: true) == "160 Hz VRR")
        #expect(ModeFormat.mode(width: 2560, height: 1440, hz: 60) == Self.size + " \u{00B7} 60 Hz")
        #expect(ModeFormat.mode(width: 2560, height: 1440, hz: nil) == Self.size)
        #expect(ModeFormat.mode(width: 2560, height: 1440, hz: 120, vrr: true, hiDPI: true)
            == Self.size + " \u{00B7} 120 Hz VRR \u{00B7} HiDPI")
    }

    @Test("Apply notes use the shared format in a non-English locale")
    func notesInSlovak() {
        let sk = Locale(identifier: "sk")
        let applied = ApplyOutcomeNote.Detail.applied(display: "LG", width: 2560, height: 1440, hz: 75, vrr: false)
        #expect(applied.localizedDescription(locale: sk).contains(Self.size + " \u{00B7} 75 Hz"))

        let fallback = ApplyOutcomeNote.Detail.fallback(
            display: "LG", wantedWidth: 2560, wantedHeight: 1440, wantedHz: 75,
            usedWidth: 2560, usedHeight: 1440, usedHz: 60, wantedVRR: false, usedVRR: false)
        let text = fallback.localizedDescription(locale: sk)
        #expect(text.contains(Self.size + " \u{00B7} 75 Hz"))
        #expect(text.contains(Self.size + " \u{00B7} 60 Hz"))
        #expect(!text.contains("@"))
    }

    @Test("Hover preview and confirmation rows use the shared format")
    func previewRows() {
        let row = ProfileApplyPreview.Row(
            id: UUID(), displayName: "LG",
            action: .willApplyFallback(targetWidth: 2560, targetHeight: 1440, targetHz: 60),
            savedWidth: 2560, savedHeight: 1440, savedHz: 75, savedIsHiDPI: false)
        let text = row.detailText
        #expect(text.contains(Self.size + " \u{00B7} 75 Hz"))
        #expect(text.contains(Self.size + " \u{00B7} 60 Hz"))
        #expect(!text.contains("@"))
    }

    @Test("Revert and outcome summaries use the shared format")
    func summaries() {
        let outcome = ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440), requestedHz: 75,
            appliedSize: PointSize(width: 2560, height: 1440), appliedHz: 60,
            status: .appliedWithFallback)
        #expect(outcome.summary == "LG: wanted \(Self.size) \u{00B7} 75 Hz, used \(Self.size) \u{00B7} 60 Hz (closest available)")
        #expect(PointSize(width: 2560, height: 1440).formatted == Self.size)
    }
}
