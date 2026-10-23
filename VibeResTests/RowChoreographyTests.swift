import SwiftUI
import Testing
@testable import VibeRes

/// How the popover moves around a row that arrives or leaves: the outcome
/// note, a problem row, the update banner, the revert countdown or the
/// footer's Revert row.
///
/// The cards used to close up over a note still fading out, and the pills
/// slid through a banner fading in, because a leaving row and an arriving one
/// moved the others the same way.
@Suite("Row choreography")
struct RowChoreographyTests {
    @Test("The rows make room at once for a row arriving")
    func arrivingRowGetsRoomFirst() {
        #expect(Design.Motion.rows(arriving: true, reduceMotion: false) == Design.Motion.layout)
    }

    @Test("The rows close up only after a leaving row has faded")
    func leavingRowFadesFirst() {
        #expect(Design.Motion.rows(arriving: false, reduceMotion: false) == Design.Motion.closeUp)
    }

    @Test("Under Reduce Motion the rows jump, after the fade, both ways")
    func reduceMotionJumps() {
        #expect(Design.Motion.rows(arriving: true, reduceMotion: true) == Design.Motion.jump)
        #expect(Design.Motion.rows(arriving: false, reduceMotion: true) == Design.Motion.jump)
    }
}
