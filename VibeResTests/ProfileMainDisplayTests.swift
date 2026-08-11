import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// `mainDisplay` is the 0.9.0 arrangement field. Pre-0.9 profile JSON has no
/// such key, and hand-written JSON may add one — both must round-trip.
@Suite("Profile.mainDisplay coding")
struct ProfileMainDisplayTests {
    @Test("Legacy JSON without mainDisplay decodes to nil")
    func legacyDecodesNil() throws {
        let json = Data("""
        {"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"Desk","createdAt":0,
         "entries":[{"matcher":{"kind":"anyExternal"},"displayName":"LG",
                     "pointWidth":2560,"pointHeight":1440,"isHiDPI":false}]}
        """.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.mainDisplay == nil)
    }

    @Test("mainDisplay survives an encode/decode round trip")
    func roundTrip() throws {
        let profile = Profile(
            name: "Desk",
            entries: [Profile.Entry(
                matcher: .anyExternal, displayName: "LG",
                pointWidth: 2560, pointHeight: 1440, refreshHz: 60, isHiDPI: false
            )],
            mainDisplay: .edid(vendor: 1, model: 2, serial: 3)
        )
        let data = try JSONEncoder().encode(profile)
        let back = try JSONDecoder().decode(Profile.self, from: data)
        #expect(back.mainDisplay == .edid(vendor: 1, model: 2, serial: 3))
    }

    @Test("Default init leaves mainDisplay nil")
    func defaultNil() {
        let profile = Profile(name: "Desk", entries: [])
        #expect(profile.mainDisplay == nil)
    }
}

@Suite("captureCurrent with a main selection")
@MainActor
struct CaptureMainSelectionTests {
    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-capture-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    private func info(_ id: CGDirectDisplayID) -> DisplayInfo {
        let mode = (CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode])?.first
        return DisplayInfo(id: id, name: "Mon \(id)", isMain: false,
                           modes: mode.map { [$0] } ?? [], currentMode: mode, groups: [])
    }

    /// A display with no current mode — the entry loop in `captureCurrent`
    /// skips these, so nothing anchors a `mainDisplay` matcher to them.
    private func infoWithNoCurrentMode(_ id: CGDirectDisplayID) -> DisplayInfo {
        DisplayInfo(id: id, name: "Mon \(id)", isMain: false, modes: [], currentMode: nil, groups: [])
    }

    @Test("The chosen display's matcher is stored as mainDisplay")
    func mainSelectionStored() {
        let store = makeStore()
        let displays = [info(101), info(102)]
        let result = store.captureCurrent(
            name: "Desk", displays: displays,
            selection: [101: .specific, 102: .specific],
            mainSelection: 102
        )
        #expect(result == .saved)
        let profile = store.profiles.first
        #expect(profile?.mainDisplay != nil)
        // Consistency beats hardcoding EDID reads for fake IDs: main must be
        // built the same way as that display's entry matcher.
        #expect(profile?.mainDisplay == profile?.entries.first(where: { $0.displayName == "Mon 102" })?.matcher)
    }

    @Test("No selection leaves mainDisplay nil — the pre-0.9 shape")
    func noSelectionNil() {
        let store = makeStore()
        _ = store.captureCurrent(
            name: "Desk", displays: [info(101)],
            selection: [101: .specific]
        )
        #expect(store.profiles.first?.mainDisplay == nil)
    }

    @Test("A main selection pointing at an unselected display is ignored")
    func unselectedMainIgnored() {
        let store = makeStore()
        _ = store.captureCurrent(
            name: "Desk", displays: [info(101), info(102)],
            selection: [101: .specific],
            mainSelection: 102
        )
        #expect(store.profiles.first?.mainDisplay == nil)
    }

    @Test("A main selection with no current mode has no entry to anchor to")
    func mainSelectionWithNilCurrentModeIgnored() {
        let store = makeStore()
        let displays = [info(101), infoWithNoCurrentMode(102)]
        let result = store.captureCurrent(
            name: "Desk", displays: displays,
            selection: [101: .specific, 102: .specific],
            mainSelection: 102
        )
        #expect(result == .saved)
        #expect(store.profiles.first?.mainDisplay == nil)
    }

    @Test("A main selection for a display that's no longer connected is ignored")
    func mainSelectionForUnpluggedDisplayIgnored() {
        let store = makeStore()
        let result = store.captureCurrent(
            name: "Desk", displays: [info(101)],
            selection: [101: .specific, 102: .specific],
            mainSelection: 102
        )
        #expect(result == .savedWithMissingDisplays(count: 1))
        #expect(store.profiles.first?.mainDisplay == nil)
    }
}
