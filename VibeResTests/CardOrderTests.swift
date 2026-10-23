import CoreGraphics
import Testing
@testable import VibeRes

/// The popover lists the built-in first and the externals by ID, whatever is
/// main. In the system's order (main first) a main display that moved made
/// the two cards swap places, sliding through each other.
@Suite("Display card order")
struct CardOrderTests {
    private func info(_ id: CGDirectDisplayID, main: Bool) -> DisplayInfo {
        DisplayInfo(id: id, name: "\(id)", isMain: main, modes: [], currentMode: nil, groups: [])
    }

    private let builtIn: (CGDirectDisplayID) -> Bool = { $0 == 1 }

    @Test("The built-in comes first even when an external is main")
    func builtInFirst() {
        // The system lists the main display first.
        let system = [info(5, main: true), info(1, main: false), info(3, main: false)]

        #expect(system.inCardOrder(isBuiltIn: builtIn).map(\.id) == [1, 3, 5])
    }

    @Test("Moving main does not reorder the cards")
    func mainMoveKeepsOrder() {
        let before = [info(1, main: true), info(3, main: false)]
        let after = [info(3, main: true), info(1, main: false)]

        #expect(before.inCardOrder(isBuiltIn: builtIn).map(\.id)
                == after.inCardOrder(isBuiltIn: builtIn).map(\.id))
    }
}
