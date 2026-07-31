import Foundation
import Testing
@testable import VibeRes

/// The save form pre-fills a profile name. It used to offer "Setup 2", which
/// tells the user nothing and gives them nothing to react to — they either keep
/// a meaningless label or retype the whole field. Naming the actual hardware
/// makes the suggestion worth keeping and cheap to adjust.
@Suite("Profile name suggestions")
struct ProfileNameSuggestionTests {
    @Test("A single display is named after itself")
    func singleDisplay() {
        #expect(Profile.suggestedName(displayNames: ["LG UltraFine"], existingNames: []) == "LG UltraFine")
    }

    @Test("Two displays are joined so the pill says what it covers")
    func twoDisplays() {
        let name = Profile.suggestedName(
            displayNames: ["Built-in", "LG UltraFine"],
            existingNames: []
        )
        #expect(name == "Built-in + LG UltraFine")
    }

    @Test("Many or long names collapse rather than overflowing the pill")
    func longNamesCollapse() {
        let name = Profile.suggestedName(
            displayNames: ["Built-in Retina Display", "LG UltraFine 5K", "DELL U2720Q"],
            existingNames: []
        )
        #expect(name == "Built-in Retina Display +2")
    }

    @Test("A clash with an existing profile is disambiguated, not duplicated")
    func uniquifies() {
        #expect(Profile.suggestedName(displayNames: ["Built-in"], existingNames: ["Built-in"])
                == "Built-in 2")
        #expect(Profile.suggestedName(displayNames: ["Built-in"], existingNames: ["Built-in", "Built-in 2"])
                == "Built-in 3")
    }

    @Test("No displays still yields a usable name instead of an empty field")
    func noDisplays() {
        #expect(!Profile.suggestedName(displayNames: [], existingNames: []).isEmpty)
    }
}
