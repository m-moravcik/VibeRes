import Foundation
import Testing
@testable import VibeRes

/// A `.edid` matcher identifies a monitor by vendor, model and serial. Two
/// identical monitors — the common dual-monitor purchase — can report the same
/// three values, and then one saved entry binds to both: `applyDetailed` does
/// `displays.filter { entry.matcher.matches($0.id) }` and applies the entry to
/// every match.
///
/// 0.8.0 fixed the equivalent collision for `.anyExternal` by allowing at most
/// one such entry per profile. This is the same problem for specific matchers,
/// and it cannot be fixed by rejecting the profile — the displays really are
/// indistinguishable — so the user has to be told.
@Suite("Display identity ambiguity")
struct DisplayIdentityAmbiguityTests {
    private func identity(_ vendor: UInt32, _ model: UInt32, _ serial: UInt32) -> DisplayIdentity {
        DisplayIdentity(vendor: vendor, model: model, serial: serial)
    }

    @Test("Distinct monitors are not ambiguous")
    func distinctMonitors() {
        let found = DisplayIdentity.ambiguous([
            identity(1, 10, 100),
            identity(1, 20, 200),
            identity(2, 30, 300),
        ])
        #expect(found.isEmpty)
    }

    @Test("Two monitors reporting the same identity are flagged once")
    func identicalPair() {
        let twin = identity(0x1E6D, 0x5B11, 0)
        let found = DisplayIdentity.ambiguous([
            identity(0x610, 0xA050, 0x1234),
            twin,
            twin,
        ])
        #expect(found == [twin])
    }

    @Test("Three of a kind is still one report, not two")
    func triple() {
        let twin = identity(1, 1, 0)
        #expect(DisplayIdentity.ambiguous([twin, twin, twin]) == [twin])
    }

    @Test("A serial number is enough to tell two same-model monitors apart")
    func serialsDisambiguate() {
        let found = DisplayIdentity.ambiguous([
            identity(0x1E6D, 0x5B11, 0xAAA),
            identity(0x1E6D, 0x5B11, 0xBBB),
        ])
        #expect(found.isEmpty, "different serials are distinguishable")
    }

    @Test("An empty or single-display setup is never ambiguous")
    func trivialCases() {
        #expect(DisplayIdentity.ambiguous([]).isEmpty)
        #expect(DisplayIdentity.ambiguous([identity(1, 1, 1)]).isEmpty)
    }
}
