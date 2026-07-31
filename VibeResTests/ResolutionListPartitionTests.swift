import Foundation
import Testing
@testable import VibeRes

/// The per-display list shows every point size the display reports, which on a
/// 5K panel is 14–20 rows ending in sizes like 1024×576 that essentially nobody
/// picks. More options means slower choosing, so the tail collapses behind a
/// disclosure.
///
/// Operates on plain sizes rather than `ResolutionGroup` because a group carries
/// a `CGDisplayMode`, which cannot be constructed in a unit test.
@Suite("Resolution list partition")
struct ResolutionListPartitionTests {
    private let sizes = [
        (width: 3008, height: 1692),
        (width: 2560, height: 1440),
        (width: 1920, height: 1080),
        (width: 1600, height: 900),
        (width: 1280, height: 720),
        (width: 1024, height: 576),
    ]

    @Test("Sizes well below the largest are collapsed")
    func collapsesTheSmallEnd() {
        let split = ResolutionListPartition.split(sizes: sizes, currentIndex: nil)

        #expect(split.primary == [0, 1, 2])
        #expect(split.collapsed == [3, 4, 5])
    }

    @Test("The current mode is always visible, however small")
    func currentModeIsNeverCollapsed() {
        let split = ResolutionListPartition.split(sizes: sizes, currentIndex: 5)

        #expect(split.primary.contains(5), "the user must be able to see where they are")
        #expect(!split.collapsed.contains(5))
        // Order is preserved so the row does not jump around.
        #expect(split.primary == split.primary.sorted())
    }

    @Test("A short list is left entirely alone")
    func shortListNotWorthCollapsing() {
        let two = [(width: 1920, height: 1080), (width: 1280, height: 720)]
        let split = ResolutionListPartition.split(sizes: two, currentIndex: nil)

        #expect(split.collapsed.isEmpty, "hiding one row behind a disclosure helps nobody")
        #expect(split.primary == [0, 1])
    }

    @Test("An empty list produces empty halves rather than crashing")
    func empty() {
        let split = ResolutionListPartition.split(sizes: [], currentIndex: nil)

        #expect(split.primary.isEmpty)
        #expect(split.collapsed.isEmpty)
    }
}
