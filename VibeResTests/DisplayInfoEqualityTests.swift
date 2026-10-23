import CoreGraphics
import Testing
@testable import VibeRes

/// `DisplayInfo` equality is what SwiftUI diffs a display card by, so it has
/// to cover everything the card draws.
///
/// It compared only the ID and the modes. When the main display moved and no
/// mode changed, the old and new snapshots compared equal, SwiftUI kept the
/// cards as they were, and the MAIN badge stayed on the display that had lost
/// the menu bar.
@Suite("DisplayInfo equality")
struct DisplayInfoEqualityTests {
    private func info(isMain: Bool, name: String = "LG UltraFine") -> DisplayInfo {
        DisplayInfo(id: 2, name: name, isMain: isMain, modes: [], currentMode: nil, groups: [])
    }

    @Test("A display that gained or lost main is a different snapshot")
    func mainIsPartOfEquality() {
        #expect(info(isMain: true) != info(isMain: false))
    }

    @Test("A renamed display is a different snapshot")
    func nameIsPartOfEquality() {
        #expect(info(isMain: false, name: "LG UltraFine") != info(isMain: false, name: "LG UltraFine (2)"))
    }

    @Test("Identical snapshots stay equal")
    func identicalSnapshotsAreEqual() {
        #expect(info(isMain: true) == info(isMain: true))
    }
}
