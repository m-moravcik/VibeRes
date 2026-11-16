import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// Two monitors that report the same vendor, model and serial bind to both
/// `.edid` entries of a profile. When those entries ask for different modes
/// there is no way to say which monitor gets which, and applying used to stage
/// each display twice and report success for both rows. Apply now refuses to
/// guess and says so (VISION.md: "reported, never hidden").
@Suite("Identical twin monitors on apply")
@MainActor
struct IdenticalTwinApplyTests {
    private func realModes() throws -> [CGDisplayMode] {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        let all = try #require(modes, "no display modes available on this machine")
        let distinct = all.reduce(into: [CGDisplayMode]()) { acc, mode in
            if !acc.contains(where: { $0.width == mode.width && $0.height == mode.height }) {
                acc.append(mode)
            }
        }
        try #require(distinct.count >= 3, "need three differently-sized modes")
        return distinct
    }

    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-twins-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ProfileStore(directory: dir)
        // Every fake display answers to the one matcher: they are twins.
        store.displayMatches = { _, _ in true }
        return store
    }

    private let twin = DisplayMatcher.edid(vendor: 1, model: 2, serial: 0)

    private func entry(_ mode: CGDisplayMode) -> Profile.Entry {
        Profile.Entry(matcher: twin, displayName: "Twin", pointWidth: mode.width,
                      pointHeight: mode.height, refreshHz: nil, isHiDPI: mode.isHiDPI)
    }

    private func displays(modes: [CGDisplayMode], current: CGDisplayMode) -> [DisplayInfo] {
        [201, 202].map {
            DisplayInfo(id: $0, name: "Twin \($0)", isMain: false, modes: modes,
                        currentMode: current, groups: [])
        }
    }

    @Test("Entries for twins at different modes are not applied, and say why")
    func differentModesAreReported() throws {
        let modes = try realModes()
        let store = makeStore()
        var staged: [[ResolutionSwitcher.BatchChange]] = []
        store.applyBatch = { changes, _ in
            staged.append(changes)
            return ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
        }
        let profile = Profile(name: "Twins", entries: [entry(modes[0]), entry(modes[1])])

        let result = store.applyDetailed(profile, displays: displays(modes: modes, current: modes[2]))

        #expect(staged.flatMap { $0 }.isEmpty, "nothing may be staged when it would be a guess")
        #expect(!result.outcomes.isEmpty)
        for outcome in result.outcomes {
            #expect(outcome.status == .skippedIndistinguishable)
            #expect(outcome.isProblem)
        }
        #expect(result.didChangeAnything == false)
    }

    @Test("Twins asked for the same mode are applied as before")
    func sameModeStillApplies() throws {
        let modes = try realModes()
        let store = makeStore()
        var staged: [ResolutionSwitcher.BatchChange] = []
        store.applyBatch = { changes, _ in
            staged += changes
            return ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
        }
        let profile = Profile(name: "Twins", entries: [entry(modes[0])])

        let result = store.applyDetailed(profile, displays: displays(modes: modes, current: modes[2]))

        #expect(Set(staged.map(\.display)) == [201, 202])
        #expect(result.outcomes.allSatisfy { $0.status == .applied })
    }
}
