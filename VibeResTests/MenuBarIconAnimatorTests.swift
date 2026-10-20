import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// The switch animation runs on a ticker that must exist only while it plays.
/// Clock and ticker are injected, so these step it frame by frame without
/// waiting and without a real timer.
@Suite("Menu bar icon animation")
@MainActor
struct MenuBarIconAnimatorTests {
    /// A fake clock and ticker: `fire()` is one frame.
    @MainActor
    final class Rig {
        var time: TimeInterval = 100
        var started = 0
        var cancelled = 0
        var tick: (@MainActor @Sendable () -> Void)?
        var reduceMotion = false

        func animator() -> MenuBarIconAnimator {
            MenuBarIconAnimator(
                now: { self.time },
                reduceMotion: { self.reduceMotion },
                startTicker: { _, tick in
                    self.started += 1
                    self.tick = tick
                    return { self.cancelled += 1; self.tick = nil }
                }
            )
        }

        func fire(after seconds: TimeInterval) {
            time += seconds
            tick?()
        }
    }

    @Test("Playing starts one ticker and advances the phase")
    func playsAndAdvances() {
        let rig = Rig()
        let animator = rig.animator()
        #expect(!animator.isTicking, "no ticker at rest")

        animator.play()
        #expect(animator.isTicking)
        #expect(animator.phase == 0)
        rig.fire(after: 0.25)
        #expect(animator.phase == 0.25)
        #expect(rig.started == 1)
    }

    @Test("The animation ends at rest with no ticker left")
    func endsWithoutTicker() {
        let rig = Rig()
        let animator = rig.animator()
        animator.play()
        for _ in 0..<40 { rig.fire(after: MenuBarIconAnimator.frameInterval) }

        #expect(animator.phase == nil)
        #expect(!animator.isTicking)
        #expect(rig.started == 1)
        #expect(rig.cancelled == 1)
        #expect(rig.tick == nil)
    }

    @Test("A burst of switches restarts the animation instead of stacking tickers")
    func burstRestarts() {
        let rig = Rig()
        let animator = rig.animator()
        animator.play()
        rig.fire(after: 0.6)
        animator.play()
        #expect(animator.phase == 0, "the second switch starts the animation over")
        animator.play()
        rig.fire(after: 0.5)

        #expect(rig.started == 1, "one ticker, however many switches")
        #expect(animator.phase == 0.5)
        rig.fire(after: 0.6)
        #expect(animator.phase == nil)
        #expect(rig.cancelled == 1)
    }

    @Test("Reduce Motion keeps the icon at rest")
    func reduceMotionSkips() {
        let rig = Rig()
        rig.reduceMotion = true
        let animator = rig.animator()
        animator.play()

        #expect(animator.phase == nil)
        #expect(!animator.isTicking)
        #expect(rig.started == 0)
    }

    // MARK: - What triggers it

    private func aRealMode() throws -> CGDisplayMode {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        return try #require(modes?.first, "no display modes available on this machine")
    }

    @Test("A successful switch from the menu plays it")
    func successfulApplyPlays() throws {
        let rig = Rig()
        let animator = rig.animator()
        let store = DisplayStore()
        store.onModeSwitch = { animator.play() }
        store.applyMode = { _, _, _ in }

        store.apply(try aRealMode(), to: 4242)

        #expect(animator.isTicking)
        #expect(animator.phase == 0)
    }

    @Test("A failed switch, a refresh or a hover does not play it")
    func noSwitchNoAnimation() throws {
        let rig = Rig()
        let animator = rig.animator()
        let store = DisplayStore()
        store.onModeSwitch = { animator.play() }
        store.applyMode = { _, _, _ in throw ResolutionSwitcher.Failure.applyMode(.cannotComplete) }

        store.apply(try aRealMode(), to: 4242)
        // A hover preview never reaches the store: it only captures the
        // desktop. A refresh is the one store call that follows any display
        // event, and it must not count as a switch.
        store.refresh()

        #expect(!animator.isTicking)
        #expect(rig.started == 0)
    }

    @Test("Clicking the mode already in use does not play it")
    func currentModeClickDoesNotPlay() throws {
        let rig = Rig()
        let animator = rig.animator()
        let store = DisplayStore()
        store.onModeSwitch = { animator.play() }
        store.applyMode = { _, _, _ in }
        let display = try #require(store.displays.first, "no active display on this machine")
        let current = try #require(display.currentMode)

        store.apply(current, to: display.id)

        #expect(!animator.isTicking)
        #expect(rig.started == 0)
    }

    @Test("A revert that only moves the menu bar back does not play it")
    func mainOnlyRevertDoesNotPlay() {
        let rig = Rig()
        let animator = rig.animator()
        let store = DisplayStore()
        store.onModeSwitch = { animator.play() }
        var currentMain: CGDirectDisplayID = 7
        store.liveArrangement = {
            (main: currentMain, bounds: [
                5: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
                7: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            ])
        }
        store.applyOrigins = { _, _ in currentMain = 5 }
        store.revert.recordBatch([], beforeMain: 5)

        #expect(store.performRevert() == 1, "the menu bar did come back")
        #expect(!animator.isTicking)
    }

    @Test("A successful revert plays it")
    func revertPlays() throws {
        let rig = Rig()
        let animator = rig.animator()
        let store = DisplayStore()
        store.onModeSwitch = { animator.play() }
        store.revert.record(displayID: 1, displayName: "Built-in", before: try aRealMode())
        store.applyMode = { _, _, _ in }

        #expect(store.performRevert() == 1)
        #expect(animator.isTicking)
    }

    @Test("A profile apply that switched a display plays it; one that changed nothing does not")
    func profileApply() throws {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode] ?? []
        let distinct = modes.reduce(into: [CGDisplayMode]()) { acc, mode in
            if !acc.contains(where: { $0.width == mode.width && $0.height == mode.height }) { acc.append(mode) }
        }
        try #require(distinct.count >= 2, "need two differently-sized modes")
        let target = distinct[0], current = distinct[1]

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-icon-anim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let profiles = ProfileStore(directory: dir)
        let rig = Rig()
        let animator = rig.animator()
        profiles.onModeSwitch = { animator.play() }
        profiles.applyBatch = { changes, _ in
            ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
        }

        // An EDID matcher of all ones binds to fake display IDs; see
        // BatchApplyTests for why.
        let profile = Profile(name: "Desk", entries: [
            Profile.Entry(matcher: .edid(vendor: .max, model: .max, serial: .max),
                          displayName: "Fake monitor", pointWidth: target.width,
                          pointHeight: target.height, refreshHz: nil, isHiDPI: target.isHiDPI)
        ])
        func display(_ mode: CGDisplayMode) -> DisplayInfo {
            DisplayInfo(id: 101, name: "Mon", isMain: false, modes: distinct, currentMode: mode, groups: [])
        }

        profiles.applyDetailed(profile, displays: [display(target)])
        #expect(!animator.isTicking, "already in that mode: nothing switched")

        profiles.applyDetailed(profile, displays: [display(current)])
        #expect(animator.isTicking)
    }
}
