import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// The countdown after a hand-picked size, against VISION.md: "A newer action
/// never lets an older safety net act on it, and a safety net is never dropped
/// by an action that changed nothing."
///
/// A fake desk stands in for WindowServer: `applyMode` writes into it and
/// every refresh reads it back, so a second pick sees the first one's mode
/// the way it would on a real Mac. The modes are the main display's real ones
/// because `CGDisplayMode` cannot be constructed; nothing is applied to it.
@Suite("Confirmation countdown as a trial")
@MainActor
struct ConfirmationTrialTests {
    nonisolated private static let a: CGDirectDisplayID = 101
    nonisolated private static let b: CGDirectDisplayID = 102

    private final class Desk {
        var current: [CGDirectDisplayID: CGDisplayMode]
        var connected: [CGDirectDisplayID]
        var commits: [(display: CGDirectDisplayID, mode: Int32, scope: CGConfigureOption)] = []
        var originMoves = 0
        let modes: [CGDisplayMode]

        init(modes: [CGDisplayMode], start: CGDisplayMode) {
            self.modes = modes
            current = [ConfirmationTrialTests.a: start, ConfirmationTrialTests.b: start]
            connected = [ConfirmationTrialTests.a, ConfirmationTrialTests.b]
        }

        var snapshot: [DisplayInfo] {
            connected.map {
                DisplayInfo(id: $0, name: "Mon \($0)", isMain: $0 == ConfirmationTrialTests.a,
                            modes: modes, currentMode: current[$0], groups: [])
            }
        }

        func modeID(_ display: CGDirectDisplayID) -> Int32? { current[display]?.ioDisplayModeID }
    }

    /// Three sizes the main display offers: start, then two to try.
    private func threeModes() throws -> [CGDisplayMode] {
        let all = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode] ?? []
        let distinct = all.reduce(into: [CGDisplayMode]()) { acc, mode in
            if !acc.contains(where: { $0.width == mode.width && $0.height == mode.height }) {
                acc.append(mode)
            }
        }
        try #require(distinct.count >= 3, "this Mac's main display offers fewer than three sizes")
        return Array(distinct.prefix(3))
    }

    private func rig() throws -> (store: DisplayStore, desk: Desk, modes: [CGDisplayMode]) {
        let modes = try threeModes()
        let desk = Desk(modes: modes, start: modes[0])
        let store = DisplayStore.forTesting()
        store.showForDemo(desk.snapshot)
        store.demoSnapshot = { desk.snapshot }
        store.applyMode = { mode, display, scope in
            desk.current[display] = mode
            desk.commits.append((display, mode.ioDisplayModeID, scope))
        }
        store.applyOrigins = { _, _ in desk.originMoves += 1 }
        store.liveArrangement = {
            (main: ConfirmationTrialTests.a,
             bounds: [ConfirmationTrialTests.a: CGRect(x: 0, y: 0, width: 1, height: 1),
                      ConfirmationTrialTests.b: CGRect(x: 1, y: 0, width: 1, height: 1)])
        }
        store.isInMirrorSet = { _ in false }
        return (store, desk, modes)
    }

    @Test("A click on the size in use arms nothing and keeps an older Revert")
    func noOpPickKeepsOlderNet() throws {
        let (store, desk, modes) = try rig()
        store.revert.recordBatch([(id: Self.b, name: "Mon 102", before: modes[2])], beforeMain: Self.b)

        store.apply(modes[0], to: Self.a, confirmFirst: true)

        #expect(store.confirmationSecondsRemaining == nil, "nothing changed, so there is nothing to keep")
        #expect(desk.commits.isEmpty)
        #expect(store.revert.entries.map(\.displayID) == [Self.b])
        #expect(store.revert.beforeMainID == Self.b)
    }

    @Test("A pick's timeout undoes that pick alone, not an older profile's other display or main")
    func timeoutLeavesOlderActionAlone() throws {
        let (store, desk, modes) = try rig()
        // An earlier profile changed both displays and moved the menu bar.
        store.revert.recordBatch([
            (id: Self.a, name: "Mon 101", before: modes[2]),
            (id: Self.b, name: "Mon 102", before: modes[2]),
        ], beforeMain: Self.b)

        store.apply(modes[1], to: Self.a, confirmFirst: true)
        desk.commits.removeAll()
        store.updateConfirmation(at: .distantFuture)

        #expect(desk.commits.map(\.display) == [Self.a])
        #expect(desk.modeID(Self.a) == modes[0].ioDisplayModeID, "back to the mode before the pick")
        #expect(desk.modeID(Self.b) == modes[0].ioDisplayModeID, "the older profile's display is untouched")
        #expect(desk.originMoves == 0, "the older profile's main display stays where it is")
        #expect(!store.revert.canRevert)
    }

    @Test("Two quick picks on one display time out to the size before the first")
    func secondPickKeepsOriginalBefore() throws {
        let (store, desk, modes) = try rig()

        store.apply(modes[1], to: Self.a, confirmFirst: true)
        store.apply(modes[2], to: Self.a, confirmFirst: true)
        store.updateConfirmation(at: .distantFuture)

        #expect(desk.modeID(Self.a) == modes[0].ioDisplayModeID,
                "never to the first pick, which nobody kept")
        #expect(desk.commits.last?.scope == .permanently)
        #expect(store.confirmationSecondsRemaining == nil)
    }

    @Test("Keep after picks on two displays keeps both for good")
    func keepCommitsWholeTrial() throws {
        let (store, desk, modes) = try rig()

        store.apply(modes[1], to: Self.a, confirmFirst: true)
        store.apply(modes[2], to: Self.b, confirmFirst: true)
        desk.commits.removeAll()
        store.confirmDisplayChange()

        let kept = Dictionary(desk.commits.map { ($0.display, $0) }, uniquingKeysWith: { $1 })
        #expect(kept[Self.a]?.mode == modes[1].ioDisplayModeID)
        #expect(kept[Self.a]?.scope == .permanently, "the first display is kept, not left to the next reboot")
        #expect(kept[Self.b]?.mode == modes[2].ioDisplayModeID)
        #expect(kept[Self.b]?.scope == .permanently)
        #expect(store.confirmationSecondsRemaining == nil)
        #expect(!store.revert.canRevert)
    }

    @Test("The timeout after picks on two displays takes both back")
    func timeoutRevertsWholeTrial() throws {
        let (store, desk, modes) = try rig()

        store.apply(modes[1], to: Self.a, confirmFirst: true)
        store.apply(modes[2], to: Self.b, confirmFirst: true)
        store.updateConfirmation(at: .distantFuture)

        #expect(desk.modeID(Self.a) == modes[0].ioDisplayModeID)
        #expect(desk.modeID(Self.b) == modes[0].ioDisplayModeID)
    }

    @Test("Make main during a countdown ends it, so the timeout cannot undo the move")
    func makeMainSupersedesCountdown() throws {
        let (store, desk, modes) = try rig()

        store.apply(modes[1], to: Self.a, confirmFirst: true)
        store.makeMain(Self.b)
        let movesAfterMakeMain = desk.originMoves
        store.updateConfirmation(at: .distantFuture)

        #expect(store.confirmationSecondsRemaining == nil)
        #expect(desk.originMoves == movesAfterMakeMain, "the timeout moved the menu bar back")
        #expect(store.revert.beforeMainID == Self.a, "Revert undoes the move")
        #expect(store.revert.entries.isEmpty)
    }

    @Test("A display unplugged during its countdown drops out; the other keeps its countdown")
    func unpluggedDisplayLeavesTrial() throws {
        let (store, desk, modes) = try rig()

        store.apply(modes[1], to: Self.a, confirmFirst: true)
        store.apply(modes[2], to: Self.b, confirmFirst: true)
        desk.connected = [Self.a]
        store.applySnapshot(desk.snapshot, triggeredByCallback: true)

        #expect(store.confirmationSecondsRemaining != nil, "the built-in still waits for Keep")
        store.updateConfirmation(at: .distantFuture)
        #expect(desk.modeID(Self.a) == modes[0].ioDisplayModeID)
    }

    @Test("Unplugging the only display of a countdown ends it")
    func unpluggedOnlyDisplayEndsCountdown() throws {
        let (store, desk, modes) = try rig()

        store.apply(modes[1], to: Self.b, confirmFirst: true)
        desk.connected = [Self.a]
        store.applySnapshot(desk.snapshot, triggeredByCallback: true)

        #expect(store.confirmationSecondsRemaining == nil, "no Keep row for a display that is gone")
    }

    @Test("A refused pick keeps the older Revert")
    func refusedPickKeepsOlderNet() throws {
        let (store, _, modes) = try rig()
        store.revert.recordBatch([(id: Self.b, name: "Mon 102", before: modes[2])])
        store.applyMode = { _, _, _ in throw ResolutionSwitcher.Failure.applyMode(.cannotComplete) }

        store.apply(modes[1], to: Self.a, confirmFirst: true)

        #expect(store.revert.entries.map(\.displayID) == [Self.b])
        #expect(store.confirmationSecondsRemaining == nil)
        #expect(store.lastError != nil)
    }

    @Test("Auto-apply that changes something ends the countdown and is what Revert undoes")
    func autoApplySupersedesCountdown() throws {
        let (store, desk, modes) = try rig()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-trial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let profiles = ProfileStore(directory: dir)
        profiles.applyBatch = { changes, _ in
            for change in changes { desk.current[change.display] = change.mode }
            return ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
        }
        // One saved monitor per display, so the profile is an exact match for
        // the desk.
        let lg = DisplayMatcher.edid(vendor: 10, model: 11, serial: 12)
        let acer = DisplayMatcher.edid(vendor: 20, model: 21, serial: 22)
        profiles.displayMatches = { matcher, id in
            (matcher == lg && id == Self.a) || (matcher == acer && id == Self.b)
        }
        let profile = Profile(name: "Desk", entries: [lg, acer].map {
            Profile.Entry(matcher: $0, displayName: "Fake", pointWidth: modes[2].width,
                          pointHeight: modes[2].height, refreshHz: nil, isHiDPI: modes[2].isHiDPI)
        })
        profiles.add(profile)
        store.apply(modes[1], to: Self.a, confirmFirst: true)

        let result = profiles.autoApply(for: store)
        store.updateConfirmation(at: .distantFuture)

        #expect(result?.didChangeAnything == true)
        #expect(store.confirmationSecondsRemaining == nil)
        #expect(desk.modeID(Self.a) == modes[2].ioDisplayModeID, "the timeout undid what auto-apply set")
        #expect(Set(store.revert.entries.map(\.displayID)) == [Self.a, Self.b])
    }
}
