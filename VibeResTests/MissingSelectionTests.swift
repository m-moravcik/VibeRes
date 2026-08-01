import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// `captureCurrent` walks the *live* displays and keeps the ones the user
/// selected. If a monitor is unplugged between opening the save form and
/// pressing Save, it is not in that list any more — so its entry never gets
/// built and the profile saves one display short, with nothing said.
///
/// The user picked three displays and got two. That is the kind of quiet
/// wrongness that surfaces weeks later as "this profile doesn't do anything to
/// my second monitor".
@Suite("Missing selections at save time")
struct MissingSelectionTests {
    private let builtIn: CGDirectDisplayID = 1
    private let external: CGDirectDisplayID = 2
    private let unplugged: CGDirectDisplayID = 3

    @Test("Nothing is missing when every selected display is still attached")
    func allPresent() {
        #expect(ProfileStore.missingSelections(
            selection: [builtIn: .specific, external: .specific],
            liveDisplayIDs: [builtIn, external]
        ) == 0)
    }

    @Test("A display unplugged before saving is counted")
    func oneUnplugged() {
        #expect(ProfileStore.missingSelections(
            selection: [builtIn: .specific, external: .specific, unplugged: .specific],
            liveDisplayIDs: [builtIn, external]
        ) == 1)
    }

    @Test("Live displays the user did not select are not 'missing'")
    func unselectedLiveDisplaysAreIgnored() {
        // Leaving a monitor out is a choice, not a loss.
        #expect(ProfileStore.missingSelections(
            selection: [builtIn: .specific],
            liveDisplayIDs: [builtIn, external, unplugged]
        ) == 0)
    }

    @Test("An empty selection has nothing to lose")
    func emptySelection() {
        #expect(ProfileStore.missingSelections(selection: [:], liveDisplayIDs: [builtIn]) == 0)
    }
}
