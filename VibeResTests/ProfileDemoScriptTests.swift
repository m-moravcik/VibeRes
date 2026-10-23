import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// The README hero loop's timeline (`ProfileDemo.Script`) and its demo display
/// list. The loop is rendered rarely and by hand, so what makes it seamless
/// and keeps every animation inside it is pinned here.
@Suite("Profile demo loop")
struct ProfileDemoScriptTests {
    typealias Script = ProfileDemo.Script

    let a = CGPoint(x: 40, y: 20)
    let b = CGPoint(x: 120, y: 20)

    @Test("The loop lasts 8 to 10 seconds")
    func loopLength() {
        #expect((8.0...10.0).contains(Script.loop))
    }

    @Test("Each half presses, then releases, one pill: B first, then A")
    func events() {
        let events = Script.events(loops: 2)
        #expect(events.count == 8)
        #expect(events.map(\.time) == events.map(\.time).sorted())
        #expect(events.map(\.kind) == [.mouseDown, .mouseUp, .mouseDown, .mouseUp,
                                       .mouseDown, .mouseUp, .mouseDown, .mouseUp])
        #expect(events.map(\.pill) == [1, 1, 0, 0, 1, 1, 0, 0])
    }

    @Test("The pointer starts and ends the loop on A, and rests on the pill it clicks")
    func pointerRests() {
        #expect(Script.pointer(at: 0, a: a, b: b) == a)
        #expect(Script.pointer(at: Script.loop, a: a, b: b) == a)
        #expect(Script.pointer(at: Script.Beat.press, a: a, b: b) == b)
        #expect(Script.pointer(at: Script.half + Script.Beat.press, a: a, b: b) == a)
    }

    @Test("The pointer is between the pills mid-glide")
    func pointerGlides() {
        let middle = (Script.Beat.glide.lowerBound + Script.Beat.glide.upperBound) / 2
        let p = Script.pointer(at: middle, a: a, b: b)
        #expect(p.x > a.x && p.x < b.x)
    }

    @Test("The displays are dark only around the click, and fully dark while the transaction runs")
    func darkness() {
        #expect(Script.darkness(at: 0) == 0)
        #expect(Script.darkness(at: Script.Beat.release) == 0)
        #expect(Script.darkness(at: Script.Beat.release + Script.Beat.darkIn.upperBound) == 1)
        #expect(Script.darkness(at: Script.Beat.release + Script.Beat.darkOut.upperBound) == 0)
        #expect(Script.darkness(at: Script.half - 0.01) == 0)
        #expect(Script.darkness(at: Script.loop) == 0)
    }

    @Test("The pointer gives only while the button is down")
    func pointerPress() {
        #expect(Script.pointerScale(at: Script.Beat.press - 0.01) == 1)
        #expect(Script.pointerScale(at: (Script.Beat.press + Script.Beat.release) / 2) < 1)
        #expect(Script.pointerScale(at: Script.Beat.release) == 1)
    }

    /// The seam needs every animation a click starts to have ended before the
    /// half does: the menu bar icon from when the transaction returns, the
    /// card's glow from the store's debounced refresh (200 ms) after it.
    @Test("Every animation a click starts ends inside its half")
    func animationsFit() {
        let back = Script.Beat.release + Script.Beat.blank
        #expect(back + MenuBarIcon.duration < Script.half)
        let glow = Design.Motion.changedGlowIn + Design.Motion.changedGlowHold + Design.Motion.changedGlowOut
        #expect(back + 0.2 + glow < Script.half)
    }

    @Test("A note shown by one click is replaced by the next before it would expire")
    func noteOutlivesHalf() throws {
        // Seconds an info note stays before clearing itself.
        let delay = try #require(ApplyOutcomeNote.Tone.info.autoDismissDelay)
        #expect(Double(delay.components.seconds) > Script.half)
    }

    @Test("The half and the time into it")
    func split() {
        #expect(Script.split(0) == (0, 0))
        let (index, local) = Script.split(Script.half + 1)
        #expect(index == 1)
        #expect(abs(local - 1) < 1e-9)
    }
}

@Suite("Profile demo display list")
@MainActor
struct DemoDisplaysTests {
    private func info(_ id: CGDirectDisplayID, main: Bool) -> DisplayInfo {
        DisplayInfo(id: id, name: "Display \(id)", isMain: main, modes: [], currentMode: nil, groups: [])
    }

    @Test("The display moved to (0, 0) becomes main and is listed first, as CoreGraphics lists it")
    func mainMoves() {
        let world = DemoDisplays([info(7, main: true), info(9, main: false)])
        #expect(world.snapshot().map(\.id) == [7, 9])

        world.setOrigins([7: CGPoint(x: -1800, y: 0), 9: .zero])
        #expect(world.main == 9)
        #expect(world.snapshot().map(\.id) == [9, 7])
        #expect(world.snapshot().map(\.isMain) == [true, false])
        #expect(world.arrangement.main == 9)
        #expect(world.arrangement.bounds[7]?.origin == CGPoint(x: -1800, y: 0))

        world.reset()
        #expect(world.main == 7)
        #expect(world.snapshot().map(\.id) == [7, 9])
    }
}
