import Testing
@testable import VibeRes

/// The detail view always opened on "Scaled", so an external monitor running
/// a native mode showed a list without its current mode in it. It opens on the
/// kind the display runs in instead.
@Suite("Detail opens on the current mode's tab")
struct DetailFilterTests {
    @Test("A display in a native mode opens on Native")
    func nativeCurrent() {
        #expect(DisplayDetailView.ModeFilter(currentIsHiDPI: false) == .allNative)
    }

    @Test("A display in a HiDPI mode opens on Scaled")
    func hiDPICurrent() {
        #expect(DisplayDetailView.ModeFilter(currentIsHiDPI: true) == .hiDPIIfAvailable)
    }

    @Test("An unknown current mode keeps the old default")
    func unknownCurrent() {
        #expect(DisplayDetailView.ModeFilter(currentIsHiDPI: nil) == .hiDPIIfAvailable)
    }
}
