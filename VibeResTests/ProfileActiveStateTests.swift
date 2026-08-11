import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// `isCurrentState` is the read-only check the pill bar uses to mark the
/// profile that already matches the desktop, as opposed to `✱` which only
/// says "flexible". It must never touch CoreGraphics — everything is judged
/// against the `displays` snapshot handed in by the caller.
///
/// Fake-ID constraint (same as BatchApplyTests/MainDisplayApplyTests): EDID
/// fields of an unknown ID read all-ones, so an all-ones `.edid` matcher
/// binds to every fake ID here, while a normal, non-all-ones `.edid` matcher
/// binds to none of them. `CGDisplayIsBuiltin` on a fake ID answers -1, so
/// `.anyExternal` never matches a fake ID either — irrelevant here since
/// every test below uses `.edid`.
@Suite("ProfileStore.isCurrentState")
@MainActor
struct ProfileActiveStateTests {
    private let allOnes = DisplayMatcher.edid(vendor: .max, model: .max, serial: .max)
    private let ids: [CGDirectDisplayID] = [101, 102, 103]

    /// `CGDisplayMode` has no public initialiser, so modes come from the real
    /// main display. Nothing here is applied to it.
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

    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-active-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    private func info(
        id: CGDirectDisplayID,
        name: String,
        modes: [CGDisplayMode],
        current: CGDisplayMode?,
        isMain: Bool = false
    ) -> DisplayInfo {
        DisplayInfo(id: id, name: name, isMain: isMain, modes: modes, currentMode: current, groups: [])
    }

    /// Saved values are always taken from the real mode's own
    /// width/height/isHiDPI so the comparisons in the test are honest.
    /// `refreshHz` is a required argument (not defaulted from the mode) so
    /// each call site states plainly whether it wants an exact-Hz match or
    /// the "any Hz" nil case.
    private func entry(matcher: DisplayMatcher, mode: CGDisplayMode, refreshHz: Int?) -> Profile.Entry {
        Profile.Entry(
            matcher: matcher,
            displayName: "Fake monitor",
            pointWidth: mode.width,
            pointHeight: mode.height,
            refreshHz: refreshHz,
            isHiDPI: mode.isHiDPI
        )
    }

    @Test("Every entry at its saved mode reads as active")
    func allEntriesAtSavedModeIsActive() throws {
        let modes = try realModes()
        let mode = modes[0]
        let store = makeStore()
        let profile = Profile(name: "Desk", entries: [
            entry(matcher: allOnes, mode: mode, refreshHz: mode.refreshHz),
        ])
        let displays = [info(id: ids[0], name: "Mon 101", modes: modes, current: mode)]

        #expect(store.isCurrentState(profile, displays: displays))
    }

    @Test("A bound display at a different mode is not active")
    func differentModeIsNotActive() throws {
        let modes = try realModes()
        let target = modes[0], other = modes[1]
        let store = makeStore()
        let profile = Profile(name: "Desk", entries: [
            entry(matcher: allOnes, mode: target, refreshHz: target.refreshHz),
        ])
        // Same entry binds both fake IDs; one is at the saved mode, the other
        // is not — the mismatch on either must sink the whole check.
        let displays = [
            info(id: ids[0], name: "Mon 101", modes: modes, current: target),
            info(id: ids[1], name: "Mon 102", modes: modes, current: other),
        ]

        #expect(!store.isCurrentState(profile, displays: displays))
    }

    @Test("An entry that binds no live display is not active")
    func unmatchedEntryIsNotActive() throws {
        let modes = try realModes()
        let mode = modes[0]
        let store = makeStore()
        // A normal, non-all-ones matcher — binds none of the fake IDs.
        let noMatch = DisplayMatcher.edid(vendor: 1, model: 2, serial: 3)
        let profile = Profile(name: "Desk", entries: [
            entry(matcher: noMatch, mode: mode, refreshHz: mode.refreshHz),
        ])
        let displays = [info(id: ids[0], name: "Mon 101", modes: modes, current: mode)]

        #expect(!store.isCurrentState(profile, displays: displays))
    }

    @Test("A saved nil refresh rate matches any current Hz")
    func nilRefreshHzMatchesAnyHz() throws {
        let modes = try realModes()
        let mode = modes[0]
        let store = makeStore()
        let profile = Profile(name: "Desk", entries: [
            entry(matcher: allOnes, mode: mode, refreshHz: nil),
        ])
        let displays = [info(id: ids[0], name: "Mon 101", modes: modes, current: mode)]

        #expect(store.isCurrentState(profile, displays: displays))
    }

    @Test("A pinned main display that is currently main is active")
    func mainPinnedAndIsMainIsActive() throws {
        let modes = try realModes()
        let mode = modes[0]
        let store = makeStore()
        let profile = Profile(
            name: "Desk",
            entries: [entry(matcher: allOnes, mode: mode, refreshHz: mode.refreshHz)],
            mainDisplay: allOnes
        )
        let displays = [info(id: ids[0], name: "Mon 101", modes: modes, current: mode, isMain: true)]

        #expect(store.isCurrentState(profile, displays: displays))
    }

    @Test("A pinned main display that is not currently main is not active")
    func mainPinnedButNotMainIsNotActive() throws {
        let modes = try realModes()
        let mode = modes[0]
        let store = makeStore()
        let profile = Profile(
            name: "Desk",
            entries: [entry(matcher: allOnes, mode: mode, refreshHz: mode.refreshHz)],
            mainDisplay: allOnes
        )
        let displays = [info(id: ids[0], name: "Mon 101", modes: modes, current: mode, isMain: false)]

        #expect(!store.isCurrentState(profile, displays: displays))
    }

    @Test("A main matcher that binds two live displays is ambiguous, not active")
    func ambiguousMainIsNotActive() throws {
        let modes = try realModes()
        let mode = modes[0]
        let store = makeStore()
        let profile = Profile(
            name: "Desk",
            entries: [entry(matcher: allOnes, mode: mode, refreshHz: mode.refreshHz)],
            mainDisplay: allOnes
        )
        // Both displays satisfy the entry loop (same saved mode), so only the
        // main-display ambiguity can be what fails this.
        let displays = [
            info(id: ids[0], name: "Mon 101", modes: modes, current: mode, isMain: true),
            info(id: ids[1], name: "Mon 102", modes: modes, current: mode, isMain: false),
        ]

        #expect(!store.isCurrentState(profile, displays: displays))
    }

    @Test("A profile with no entries is never active")
    func emptyEntriesIsNotActive() {
        let store = makeStore()
        let profile = Profile(name: "Empty", entries: [])

        #expect(!store.isCurrentState(profile, displays: []))
    }
}
