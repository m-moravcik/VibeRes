import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// The Shortcuts.app actions go through the same stores as the popover and the
/// global shortcuts, so Revert in the popover takes their change back. The
/// stores are real; the display transaction is injected, so nothing here
/// changes a real display mode, and the profile catalog is a temporary
/// directory, never the owner's.
@Suite("App Intents path", .serialized)
@MainActor
struct IntentPathTests {
    private func realModes() throws -> [CGDisplayMode] {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        let all = try #require(modes, "no display modes available on this machine")
        let distinct = all.reduce(into: [CGDisplayMode]()) { acc, mode in
            if !acc.contains(where: { $0.width == mode.width && $0.height == mode.height }) {
                acc.append(mode)
            }
        }
        try #require(distinct.count >= 2, "need two differently-sized modes")
        return distinct
    }

    /// Display IDs above any real one, so nothing here can name a live display.
    private let ids: [CGDirectDisplayID] = [101, 102]

    /// Unknown display IDs read every EDID field as 0xFFFFFFFF, so this
    /// matcher binds the fake displays and nothing real (see BatchApplyTests).
    private func entry(_ mode: CGDisplayMode) -> Profile.Entry {
        Profile.Entry(matcher: .edid(vendor: .max, model: .max, serial: .max), displayName: "Fake",
                      pointWidth: mode.width, pointHeight: mode.height, refreshHz: nil, isHiDPI: mode.isHiDPI)
    }

    private struct Rig {
        let displays: DisplayStore
        let profiles: ProfileStore
        var modeSwitches: () -> [(mode: CGDisplayMode, display: CGDirectDisplayID)]
        var batches: () -> Int
    }

    private func rig(current: CGDisplayMode, modes: [CGDisplayMode]) -> Rig {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-intent-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let profiles = ProfileStore(directory: dir)
        let displays = DisplayStore.forTesting()
        displays.showForDemo(ids.map {
            DisplayInfo(id: $0, name: "Mon \($0)", isMain: false, modes: modes, currentMode: current, groups: [])
        })
        var switches: [(mode: CGDisplayMode, display: CGDirectDisplayID)] = []
        displays.applyMode = { mode, display, _ in switches.append((mode, display)) }
        var batches = 0
        profiles.applyBatch = { changes, _ in
            batches += 1
            return ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
        }
        return Rig(displays: displays, profiles: profiles, modeSwitches: { switches }, batches: { batches })
    }

    // MARK: - Set Resolution

    @Test("Set Resolution applies the size and arms Revert with the mode it replaced")
    func setResolutionRecordsRevert() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)

        let said = try IntentActions.setResolution(
            displayID: 101, width: modes[0].width, height: modes[0].height,
            refreshHz: nil, preferHiDPI: modes[0].isHiDPI, variableRefresh: false,
            displays: r.displays
        )

        #expect(r.modeSwitches().map(\.display) == [101])
        #expect(r.displays.revert.canRevert)
        #expect(r.displays.revert.entries.map(\.displayID) == [101])
        #expect(r.displays.revert.entries.first?.before.ioDisplayModeID == modes[1].ioDisplayModeID)
        #expect(said.hasPrefix("\(modes[0].width) × \(modes[0].height)"))
    }

    @Test("Revert in the popover takes a Set Resolution back")
    func setResolutionCanBeReverted() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        _ = try IntentActions.setResolution(
            displayID: 101, width: modes[0].width, height: modes[0].height,
            refreshHz: nil, preferHiDPI: modes[0].isHiDPI, variableRefresh: false,
            displays: r.displays
        )

        let restored = r.displays.performRevert()

        #expect(restored == 1)
        #expect(r.modeSwitches().last?.display == 101)
        #expect(r.modeSwitches().last?.mode.ioDisplayModeID == modes[1].ioDisplayModeID)
        #expect(!r.displays.revert.canRevert)
    }

    @Test("A Set Resolution the system refuses throws and leaves the armed Revert alone")
    func setResolutionFailure() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        r.displays.revert.recordBatch([(id: 102, name: "Mon 102", before: modes[0])])
        r.displays.applyMode = { _, _, _ in throw ResolutionSwitcher.Failure.applyMode(.failure) }

        #expect(throws: IntentProblem.self) {
            try IntentActions.setResolution(
                displayID: 101, width: modes[0].width, height: modes[0].height,
                refreshHz: nil, preferHiDPI: modes[0].isHiDPI, variableRefresh: false,
                displays: r.displays
            )
        }
        #expect(r.displays.revert.entries.map(\.displayID) == [102])
    }

    @Test("A stale error from the popover does not fail a Set Resolution that went through")
    func setResolutionIgnoresStaleError() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        r.displays.applyMode = { _, _, _ in throw ResolutionSwitcher.Failure.applyMode(.failure) }
        r.displays.apply(modes[0], to: 101)
        #expect(r.displays.lastError != nil)
        r.displays.applyMode = { _, _, _ in }

        _ = try IntentActions.setResolution(
            displayID: 101, width: modes[0].width, height: modes[0].height,
            refreshHz: nil, preferHiDPI: modes[0].isHiDPI, variableRefresh: false,
            displays: r.displays
        )

        #expect(r.displays.revert.canRevert)
    }

    @Test("Set Resolution reads the display as it is now, not the store's last refresh")
    func setResolutionRefreshesStaleList() throws {
        let modes = try realModes()
        let r = rig(current: modes[0], modes: modes)
        let moved = ids.map {
            DisplayInfo(id: $0, name: "Mon \($0)", isMain: false, modes: modes, currentMode: modes[1], groups: [])
        }
        r.displays.demoSnapshot = { moved }

        _ = try IntentActions.setResolution(
            displayID: 101, width: modes[0].width, height: modes[0].height,
            refreshHz: nil, preferHiDPI: modes[0].isHiDPI, variableRefresh: false,
            displays: r.displays
        )

        #expect(r.modeSwitches().map(\.display) == [101])
        #expect(r.modeSwitches().first?.mode.ioDisplayModeID == modes[0].ioDisplayModeID)
        #expect(r.displays.revert.entries.first?.before.ioDisplayModeID == modes[1].ioDisplayModeID)
    }

    @Test("Set Resolution for a display that is gone throws and changes nothing")
    func setResolutionDisplayGone() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)

        #expect(throws: IntentProblem.displayNotConnected) {
            try IntentActions.setResolution(
                displayID: 999, width: modes[0].width, height: modes[0].height,
                refreshHz: nil, preferHiDPI: true, variableRefresh: false,
                displays: r.displays
            )
        }
        #expect(r.modeSwitches().isEmpty)
        #expect(!r.displays.revert.canRevert)
    }

    @Test("Set Resolution rejects out-of-range values before touching a display",
          arguments: [(0, 800, nil), (800, 99_999, nil), (800, 600, 0)] as [(Int, Int, Int?)])
    func setResolutionRange(width: Int, height: Int, hz: Int?) throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)

        #expect(throws: IntentProblem.self) {
            try IntentActions.setResolution(
                displayID: 101, width: width, height: height, refreshHz: hz,
                preferHiDPI: true, variableRefresh: false, displays: r.displays
            )
        }
        #expect(r.modeSwitches().isEmpty)
    }

    // MARK: - Apply Profile

    @Test("Apply Profile applies through the profile store and arms Revert")
    func applyProfileRecordsRevert() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)

        let said = try IntentActions.applyProfile(id: profile.id, displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == 1)
        #expect(r.displays.revert.canRevert)
        #expect(r.displays.revert.entries.map(\.displayID).sorted() == ids)
        #expect(said.hasPrefix("Desk: "))
    }

    @Test("Revert in the popover takes an Apply Profile back")
    func applyProfileCanBeReverted() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)
        _ = try IntentActions.applyProfile(id: profile.id, displays: r.displays, profiles: r.profiles)

        let restored = r.displays.performRevert()

        #expect(restored == ids.count)
        #expect(r.modeSwitches().map(\.display).sorted() == ids)
        #expect(r.modeSwitches().allSatisfy { $0.mode.ioDisplayModeID == modes[1].ioDisplayModeID })
    }

    @Test("Apply Profile for a deleted profile throws and changes nothing")
    func applyProfileMissing() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)

        #expect(throws: IntentProblem.profileMissing) {
            try IntentActions.applyProfile(id: UUID(), displays: r.displays, profiles: r.profiles)
        }
        #expect(r.batches() == 0)
        #expect(!r.displays.revert.canRevert)
    }

    @Test("Apply Profile for a profile with no connected display throws and arms no Revert")
    func applyProfileNoDisplay() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let away = Profile(name: "Away", entries: [
            Profile.Entry(matcher: .edid(vendor: 1, model: 2, serial: 3), displayName: "Gone",
                          pointWidth: modes[0].width, pointHeight: modes[0].height,
                          refreshHz: nil, isHiDPI: modes[0].isHiDPI),
        ])
        r.profiles.add(away)

        #expect(throws: IntentProblem.noDisplayConnected(profile: "Away")) {
            try IntentActions.applyProfile(id: away.id, displays: r.displays, profiles: r.profiles)
        }
        #expect(r.batches() == 0)
        #expect(!r.displays.revert.canRevert)
    }

    @Test("Apply Profile whose switch fails throws and arms no Revert")
    func applyProfileSwitchFails() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)
        r.profiles.applyBatch = { changes, _ in
            ResolutionSwitcher.BatchOutcome(
                applied: [], rejected: Dictionary(uniqueKeysWithValues: changes.map { ($0.display, .applyMode(.failure)) })
            )
        }

        #expect(throws: IntentProblem.self) {
            try IntentActions.applyProfile(id: profile.id, displays: r.displays, profiles: r.profiles)
        }
        #expect(!r.displays.revert.canRevert)
    }

    @Test("A profile already at its saved settings succeeds and says so")
    func applyProfileAlreadyApplied() throws {
        let modes = try realModes()
        let r = rig(current: modes[0], modes: modes)
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)

        let said = try IntentActions.applyProfile(id: profile.id, displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == 0)
        #expect(said.hasPrefix("Desk: "))
    }

    /// A profile that pins the main display to fake 101, which is already
    /// main. The live arrangement holds 101 and the real main display, whose
    /// EDID is not all-ones, so the pin binds to exactly one display.
    private func pinnedToCurrentMain(_ r: Rig, mode: CGDisplayMode) -> Profile {
        r.profiles.isInMirrorSet = { _ in false }
        r.profiles.liveArrangement = {
            (main: 101, bounds: [
                101: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                CGMainDisplayID(): CGRect(x: -1800, y: 0, width: 1800, height: 1169),
            ])
        }
        r.profiles.applyOrigins = { _, _ in Issue.record("main is already main; no origin change expected") }
        let profile = Profile(name: "Desk", entries: [entry(mode)],
                              mainDisplay: .edid(vendor: .max, model: .max, serial: .max))
        r.profiles.add(profile)
        return profile
    }

    @Test("A main-pinned profile whose main is already main and whose switches all fail throws")
    func applyProfilePinnedMainSwitchesFail() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = pinnedToCurrentMain(r, mode: modes[0])
        r.profiles.applyBatch = { changes, _ in
            ResolutionSwitcher.BatchOutcome(
                applied: [], rejected: Dictionary(uniqueKeysWithValues: changes.map { ($0.display, .applyMode(.failure)) })
            )
        }

        #expect(throws: IntentProblem.self) {
            try IntentActions.applyProfile(id: profile.id, displays: r.displays, profiles: r.profiles)
        }
        #expect(!r.displays.revert.canRevert)
    }

    @Test("A main-pinned profile already at its saved settings succeeds")
    func applyProfilePinnedMainAlreadyApplied() throws {
        let modes = try realModes()
        let r = rig(current: modes[0], modes: modes)
        let profile = pinnedToCurrentMain(r, mode: modes[0])

        let said = try IntentActions.applyProfile(id: profile.id, displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == 0)
        #expect(said.hasPrefix("Desk: "))
    }

    // MARK: - Profile entity

    @Test("The profile picker lists the saved profiles and resolves them by id")
    func profileEntityQuery() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let desk = Profile(name: "Desk", entries: [entry(modes[0])])
        let present = Profile(name: "Presentation", entries: [entry(modes[1])])
        r.profiles.add(desk)
        r.profiles.add(present)
        let saved = IntentRuntime.profiles
        defer { IntentRuntime.profiles = saved }
        IntentRuntime.profiles = r.profiles

        let query = ProfileQuery()
        let listed = try query.suggestedEntitiesNow()
        #expect(listed.map(\.name) == ["Desk", "Presentation"])
        #expect(listed.map(\.id) == [desk.id, present.id])
        #expect(try query.entitiesNow(for: [present.id]).map(\.name) == ["Presentation"])
        #expect(try query.entitiesNow(for: [UUID()]).isEmpty)
    }

    @Test("Before the app has started the actions say so instead of guessing")
    func runtimeNotReady() throws {
        let savedDisplays = IntentRuntime.displays
        let savedProfiles = IntentRuntime.profiles
        defer { IntentRuntime.displays = savedDisplays; IntentRuntime.profiles = savedProfiles }
        IntentRuntime.displays = nil
        IntentRuntime.profiles = nil

        #expect(throws: IntentProblem.appNotReady) { try IntentRuntime.requireDisplays() }
        #expect(throws: IntentProblem.appNotReady) { try IntentRuntime.requireProfiles() }
    }

    @Test("Every problem has copy in the app's language, and none uses an em dash")
    func problemCopy() {
        let problems: [IntentProblem] = [
            .displayNotConnected, .profileMissing, .noDisplayConnected(profile: "Desk"),
            .appNotReady, .switchFailed("boom"), .noCloseMode(width: 800, height: 600, display: "Mon"),
            .widthOutOfRange, .heightOutOfRange, .refreshOutOfRange,
            .notApplied(.applied(profile: "Desk", note: ApplyOutcomeNote(tone: .info, content: .alreadyAtSavedSettings))),
        ]
        for problem in problems {
            let text = problem.localizedDescription(locale: Locale(identifier: "en"))
            #expect(!text.isEmpty)
            #expect(!text.contains("\u{2014}"))
        }
        #expect(IntentProblem.profileMissing.localizedDescription(locale: Locale(identifier: "sk"))
            == ShortcutAnnouncement.profileMissing.localizedDescription(locale: Locale(identifier: "sk")))
    }
}
