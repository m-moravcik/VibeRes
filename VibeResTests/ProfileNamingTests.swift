import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// Names are the profile's public handle: the CLI, Shortcuts and any script
/// built on them address a profile by name, while the GUI addresses it by id.
/// So the store has to guarantee two things the 0.9.0 code did not — that a
/// refused save is *reported* as refused, and that a name identifies at most
/// one profile.
@Suite("Profile naming and lookup")
@MainActor
struct ProfileNamingTests {
    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-naming-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    private func entry(_ name: String = "Built-in") -> Profile.Entry {
        Profile.Entry(
            matcher: .builtIn(vendor: 1, model: 2, serial: 3),
            displayName: name,
            pointWidth: 1800,
            pointHeight: 1169,
            refreshHz: 120,
            isHiDPI: true
        )
    }

    /// Same trick the capture tests use: a real CGDisplayMode borrowed from
    /// this machine, because the type cannot be constructed from Swift.
    private func info(_ id: CGDirectDisplayID) -> DisplayInfo {
        let mode = (CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode])?.first
        return DisplayInfo(id: id, name: "Mon \(id)", isMain: false,
                           modes: mode.map { [$0] } ?? [], currentMode: mode, groups: [])
    }

    // MARK: A refused save says so

    @Test("A name that sanitises away is refused, and add says which way it went")
    func addReportsEmptyName() {
        let store = makeStore()
        #expect(store.add(Profile(name: "   \n\t", entries: [entry()])) == .rejectedEmptyName)
        #expect(store.add(Profile(name: "\u{0000}", entries: [entry()])) == .rejectedEmptyName)
        #expect(store.profiles.isEmpty)
    }

    @Test("captureCurrent reports the refusal instead of claiming it saved")
    func captureCurrentReportsEmptyName() {
        let store = makeStore()
        // The exact shape that made `viberes profile save "   "` print
        // `saved profile` while storing nothing.
        let result = store.captureCurrent(
            name: "   ",
            displays: [info(101)],
            selection: [101: .specific]
        )
        #expect(result == .rejectedEmptyName)
        #expect(store.profiles.isEmpty)
    }

    // MARK: A name identifies one profile

    @Test("A second profile cannot take a name that is already in use")
    func addRefusesDuplicate() {
        let store = makeStore()
        #expect(store.add(Profile(name: "Work", entries: [entry()])) == .saved)
        #expect(store.add(Profile(name: "Work", entries: [entry()])) == .rejectedDuplicateName("Work"))
        #expect(store.profiles.count == 1)
    }

    @Test("Uniqueness is judged the way a person reads it, not byte by byte")
    func duplicateCheckIsCaseInsensitive() {
        let store = makeStore()
        #expect(store.add(Profile(name: "Work", entries: [entry()])) == .saved)
        #expect(store.add(Profile(name: "WORK", entries: [entry()])) == .rejectedDuplicateName("WORK"))
        // Surrounding whitespace is sanitised off before the comparison, so
        // " Work " is the same handle too.
        #expect(store.add(Profile(name: " Work ", entries: [entry()])) == .rejectedDuplicateName("Work"))
        #expect(store.profiles.count == 1)
    }

    @Test("Renaming onto another profile's name is refused")
    func updateRefusesDuplicate() {
        let store = makeStore()
        #expect(store.add(Profile(name: "Work", entries: [entry()])) == .saved)
        #expect(store.add(Profile(name: "Presentation", entries: [entry()])) == .saved)

        var second = try! #require(store.profiles.first { $0.name == "Presentation" })
        second.name = "Work"
        #expect(store.update(second) == .rejectedDuplicateName("Work"))
        #expect(store.profiles.first { $0.id == second.id }?.name == "Presentation")
    }

    @Test("A profile keeping its own name updates normally")
    func updateAllowsOwnName() {
        let store = makeStore()
        #expect(store.add(Profile(name: "Work", entries: [entry()])) == .saved)

        var only = store.profiles[0]
        only.entries = [entry("Renamed display")]
        #expect(store.update(only) == .saved)
        #expect(store.profiles[0].entries.first?.displayName == "Renamed display")

        // Including a case-only change of its own name, which is a rename the
        // user is entitled to make.
        only = store.profiles[0]
        only.name = "WORK"
        #expect(store.update(only) == .saved)
        #expect(store.profiles[0].name == "WORK")
    }

    @Test("Updating a profile the store no longer holds is refused, not silent")
    func updateRefusesUnknownProfile() {
        let store = makeStore()
        #expect(store.update(Profile(name: "Ghost", entries: [entry()])) == .rejectedNotFound)
    }

    // MARK: Lookup

    @Test("A name resolves case-insensitively to its one profile")
    func resolveByName() {
        let store = makeStore()
        store.add(Profile(name: "Work", entries: [entry()]))
        #expect(store.resolve("work") == .found(store.profiles[0]))
        #expect(store.resolve("WORK") == .found(store.profiles[0]))
    }

    @Test("A profile also resolves by the id that `profile list` prints")
    func resolveByID() {
        let store = makeStore()
        store.add(Profile(name: "Work", entries: [entry()]))
        let saved = store.profiles[0]
        #expect(store.resolve(saved.id.uuidString) == .found(saved))
    }

    @Test("An unknown handle resolves to nothing")
    func resolveNotFound() {
        let store = makeStore()
        store.add(Profile(name: "Work", entries: [entry()]))
        #expect(store.resolve("Presentation") == .notFound)
        #expect(store.resolve(UUID().uuidString) == .notFound)
    }

    @Test("A catalog that already contains duplicates resolves as ambiguous, never at random")
    func resolveAmbiguous() throws {
        // `add` refuses to create this state, but a profiles.json written by
        // 0.9.0 or edited by hand can already be in it, and picking the first
        // match would make `viberes profile apply Work` a coin flip.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-naming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let twins = [
            Profile(name: "Work", entries: [entry()]),
            Profile(name: "Work", entries: [entry()]),
        ]
        try JSONEncoder().encode(twins)
            .write(to: dir.appendingPathComponent("profiles.json"))

        let store = ProfileStore(directory: dir)
        #expect(store.profiles.count == 2)
        #expect(store.resolve("Work") == .ambiguous(count: 2))
        // Addressing one of them by id still works, which is the way out.
        #expect(store.resolve(store.profiles[0].id.uuidString) == .found(store.profiles[0]))
    }
}
