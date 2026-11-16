import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// VISION.md: "a field the app cannot read is dropped, never the whole
/// catalog", and "One core, every surface": the app and the CLI share one
/// catalog on disk, so neither may write back a stale copy over the other.
@Suite("Profile catalog resilience")
@MainActor
struct ProfileCatalogResilienceTests {
    // MARK: - Fixtures

    private func makeDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-catalog-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func catalogURL(in dir: URL) -> URL {
        dir.appendingPathComponent("profiles.json")
    }

    private func entry(_ matcher: DisplayMatcher, _ name: String, width: Int = 1920) -> Profile.Entry {
        Profile.Entry(matcher: matcher, displayName: name, pointWidth: width, pointHeight: 1080,
                      refreshHz: 60, isHiDPI: false)
    }

    /// The catalog as JSON objects, so a test can damage one field the way a
    /// newer version of the app or a hand edit would.
    private func jsonCatalog(_ profiles: [Profile]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(profiles)
        return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func write(_ object: Any, to dir: URL) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: catalogURL(in: dir))
        return data
    }

    /// Copies of a damaged catalog the store kept aside, by name.
    private func keptCopies(in dir: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "profiles.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private let lg = DisplayMatcher.edid(vendor: 10, model: 11, serial: 12)
    private let acer = DisplayMatcher.edid(vendor: 20, model: 21, serial: 22)

    // MARK: - Lenient decoding

    @Test("An entry with a matcher kind from a newer version drops only that entry")
    func unknownMatcherKindDropsOneEntry() throws {
        let dir = makeDirectory()
        let desk = Profile(name: "Desk", entries: [entry(lg, "LG"), entry(acer, "Acer")])
        let travel = Profile(name: "Travel", entries: [entry(.anyExternal, "Any")])
        var json = try jsonCatalog([desk, travel])
        var entries = try #require(json[0]["entries"] as? [[String: Any]])
        entries[1]["matcher"] = ["kind": "airPlay", "receiver": "Living room"]
        json[0]["entries"] = entries
        let original = try write(json, to: dir)

        let store = ProfileStore(directory: dir)

        #expect(store.profiles.map(\.name) == ["Desk", "Travel"])
        #expect(store.profiles[0].entries == [entry(lg, "LG")])
        #expect(store.profiles[1] == travel)
        guard case .profilesPartlyUnreadable(let keptAs?) = store.lastError else {
            Issue.record("Dropping part of the catalog must be reported, with the copy's name")
            return
        }
        let copies = try keptCopies(in: dir)
        #expect(copies.map(\.lastPathComponent) == [keptAs])
        #expect(try Data(contentsOf: copies[0]) == original)
    }

    @Test("Profiles past the limit are kept aside and reported, not lost quietly")
    func profilesPastLimitKeptAside() throws {
        let dir = makeDirectory()
        let many = (0..<(ProfileStore.maximumProfiles + 3)).map {
            Profile(name: "P\($0)", entries: [entry(lg, "LG")])
        }
        let original = try write(try jsonCatalog(many), to: dir)

        let store = ProfileStore(directory: dir)

        #expect(store.profiles.count == ProfileStore.maximumProfiles)
        guard case .profilesPartlyUnreadable(let keptAs?) = store.lastError else {
            Issue.record("Profiles past the limit must be reported, with the copy's name")
            return
        }
        let copies = try keptCopies(in: dir)
        #expect(copies.map(\.lastPathComponent) == [keptAs])
        let copy = try #require(copies.first)
        #expect(try Data(contentsOf: copy) == original)
    }

    @Test("Saving after a capped read leaves the full original beside the catalog")
    func cappedCatalogSaveKeepsOriginal() throws {
        let dir = makeDirectory()
        let many = (0..<(ProfileStore.maximumProfiles + 1)).map {
            Profile(name: "P\($0)", entries: [entry(lg, "LG")])
        }
        let original = try write(try jsonCatalog(many), to: dir)
        let store = ProfileStore(directory: dir)

        if let victim = store.profiles.first { _ = store.delete(victim) }

        let copies = try keptCopies(in: dir)
        #expect(copies.count == 1)
        let copy = try #require(copies.first)
        #expect(try Data(contentsOf: copy) == original)
    }

    @Test("Two profiles with one id: the first stays, the second is reported as left out")
    func duplicateIdsKeepFirstAndReport() throws {
        let dir = makeDirectory()
        let first = Profile(name: "First", entries: [entry(lg, "LG")])
        var second = Profile(name: "Second", entries: [entry(acer, "Acer")])
        second.id = first.id
        let other = Profile(name: "Other", entries: [entry(acer, "Acer")])
        let original = try write(try jsonCatalog([first, second, other]), to: dir)

        let store = ProfileStore(directory: dir)

        #expect(store.profiles.map(\.name) == ["First", "Other"])
        #expect(Set(store.profiles.map(\.id)).count == store.profiles.count)
        guard case .profilesPartlyUnreadable(let keptAs?) = store.lastError else {
            Issue.record("A profile dropped for its id must be reported, with the copy's name")
            return
        }
        let copies = try keptCopies(in: dir)
        #expect(copies.map(\.lastPathComponent) == [keptAs])
        let copy = try #require(copies.first)
        #expect(try Data(contentsOf: copy) == original)
    }

    @Test("A profile with no readable entry is dropped; the others stay")
    func profileWithoutReadableEntriesDropped() throws {
        let dir = makeDirectory()
        let broken = Profile(name: "Broken", entries: [entry(lg, "LG")])
        let fine = Profile(name: "Fine", entries: [entry(acer, "Acer")])
        var json = try jsonCatalog([broken, fine])
        json[0]["entries"] = [["matcher": ["kind": "hologram"]]]
        _ = try write(json, to: dir)

        let store = ProfileStore(directory: dir)

        #expect(store.profiles == [fine])
        if case .profilesPartlyUnreadable = store.lastError {} else {
            Issue.record("A dropped profile must be reported")
        }
    }

    @Test("A profile saved with no entries is still read back")
    func emptyProfileStillReads() throws {
        let dir = makeDirectory()
        let bare = Profile(name: "Bare", entries: [])
        _ = try write(try jsonCatalog([bare]), to: dir)

        let store = ProfileStore(directory: dir)

        #expect(store.profiles == [bare])
        #expect(store.lastError == nil)
        #expect(try keptCopies(in: dir).isEmpty)
    }

    @Test("An unreadable main display or date drops the field, not the profile")
    func unreadableFieldsFallBack() throws {
        let dir = makeDirectory()
        let desk = Profile(name: "Desk", entries: [entry(lg, "LG")], mainDisplay: lg)
        let other = Profile(name: "Other", entries: [entry(acer, "Acer")])
        var json = try jsonCatalog([desk, other])
        json[0]["mainDisplay"] = ["kind": "whicheverIsBiggest"]
        json[1]["createdAt"] = "yesterday"
        _ = try write(json, to: dir)

        let store = ProfileStore(directory: dir)

        #expect(store.profiles.map(\.name) == ["Desk", "Other"])
        #expect(store.profiles[0].mainDisplay == nil)
        #expect(store.profiles[0].entries == desk.entries)
        #expect(store.profiles[1].entries == other.entries)
        if case .profilesPartlyUnreadable = store.lastError {} else {
            Issue.record("A dropped field must be reported")
        }
    }

    @Test("A shortcut the app cannot read is dropped and reported, and the file is kept")
    func unreadableHotkeyKeptAside() throws {
        let dir = makeDirectory()
        let desk = Profile(name: "Desk", entries: [entry(lg, "LG")])
        var json = try jsonCatalog([desk])
        json[0]["hotkey"] = ["chord": "hyper-space"]
        let original = try write(json, to: dir)

        let store = ProfileStore(directory: dir)

        #expect(store.profiles == [desk])
        let copies = try keptCopies(in: dir)
        #expect(copies.count == 1)
        let copy = try #require(copies.first)
        #expect(try Data(contentsOf: copy) == original)
    }

    @Test("A catalog where every profile was dropped is unreadable, not partly readable")
    func everyProfileDroppedIsUnreadable() throws {
        let dir = makeDirectory()
        var json = try jsonCatalog([Profile(name: "Only", entries: [entry(lg, "LG")])])
        json[0]["entries"] = [["matcher": ["kind": "hologram"]]]
        let original = try write(json, to: dir)

        let store = ProfileStore(directory: dir)

        #expect(store.profiles.isEmpty)
        guard case .profilesUnreadable(let keptAs?) = store.lastError else {
            Issue.record("Nothing readable must be reported as unreadable, got \(String(describing: store.lastError))")
            return
        }
        let copies = try keptCopies(in: dir)
        #expect(copies.map(\.lastPathComponent) == [keptAs])
        #expect(try Data(contentsOf: copies[0]) == original)
    }

    @Test("A symlinked catalog is read through the link, and a damaged one is kept as a real copy")
    func symlinkedCatalogFollowed() throws {
        let dir = makeDirectory()
        let elsewhere = makeDirectory()
        let target = elsewhere.appendingPathComponent("profiles.json")
        let desk = Profile(name: "Desk", entries: [entry(lg, "LG")])
        try JSONEncoder().encode([desk]).write(to: target)
        try FileManager.default.createSymbolicLink(at: catalogURL(in: dir), withDestinationURL: target)

        let store = ProfileStore(directory: dir)
        #expect(store.profiles == [desk])
        #expect(store.lastError == nil)
        #expect(store.add(Profile(name: "Sofa", entries: [entry(acer, "Acer")])) == .saved)

        let damaged = Data("not json at all".utf8)
        try FileManager.default.removeItem(at: catalogURL(in: dir))
        try damaged.write(to: target)
        try FileManager.default.createSymbolicLink(at: catalogURL(in: dir), withDestinationURL: target)
        let reread = ProfileStore(directory: dir)
        guard case .profilesUnreadable(let keptAs?) = reread.lastError else {
            Issue.record("A damaged symlinked catalog must be kept aside, got \(String(describing: reread.lastError))")
            return
        }
        let copy = dir.appendingPathComponent(keptAs)
        let type = try FileManager.default.attributesOfItem(atPath: copy.path)[.type] as? FileAttributeType
        #expect(type == .typeRegular)
        #expect(try Data(contentsOf: copy) == damaged)
    }

    @Test("A symlink to nothing reads as no catalog yet")
    func danglingSymlinkIsMissing() throws {
        let dir = makeDirectory()
        try FileManager.default.createSymbolicLink(
            at: catalogURL(in: dir),
            withDestinationURL: dir.appendingPathComponent("nowhere.json"))

        let store = ProfileStore(directory: dir)

        #expect(store.profiles.isEmpty)
        #expect(store.lastError == nil)
    }

    // MARK: - Never save over what could not be read

    @Test("A wholly unreadable file is kept aside before the first save replaces it")
    func unreadableFileKeptBeforeSave() throws {
        let dir = makeDirectory()
        let garbage = Data("{\"profiles\": \"from the future\"}".utf8)
        try garbage.write(to: catalogURL(in: dir))

        let store = ProfileStore(directory: dir)
        #expect(store.profiles.isEmpty)
        guard case .profilesUnreadable(let keptAs?) = store.lastError else {
            Issue.record("An unreadable catalog must be reported with the copy's name")
            return
        }

        #expect(store.add(Profile(name: "New", entries: [entry(lg, "LG")])) == .saved)

        let copies = try keptCopies(in: dir)
        #expect(copies.map(\.lastPathComponent) == [keptAs])
        #expect(try Data(contentsOf: copies[0]) == garbage)
        #expect(ProfileStore(directory: dir).profiles.map(\.name) == ["New"])
    }

    @Test("A damaged file read again is not copied twice")
    func identicalDamageCopiedOnce() throws {
        let dir = makeDirectory()
        try Data("[{\"broken\": true}]".utf8).write(to: catalogURL(in: dir))

        _ = ProfileStore(directory: dir)
        _ = ProfileStore(directory: dir)
        let store = ProfileStore(directory: dir)
        store.load()

        #expect(try keptCopies(in: dir).count == 1)
    }

    @Test("A different damaged file never overwrites an earlier copy")
    func earlierCopyNeverOverwritten() throws {
        let dir = makeDirectory()
        let first = Data("not json at all".utf8)
        try first.write(to: catalogURL(in: dir))
        _ = ProfileStore(directory: dir)

        let second = Data("still not json".utf8)
        try second.write(to: catalogURL(in: dir))
        _ = ProfileStore(directory: dir)

        let contents = try keptCopies(in: dir).map { try Data(contentsOf: $0) }
        #expect(Set(contents) == [first, second])
    }

    @Test("A catalog file that exists but cannot be read is never saved over")
    func unreadableExistingFileNotSavedOver() throws {
        let dir = makeDirectory()
        let url = catalogURL(in: dir)
        let desk = Profile(name: "Desk", entries: [entry(lg, "LG")])
        let original = try write(try jsonCatalog([desk]), to: dir)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }

        let store = ProfileStore(directory: dir)
        if case .profilesUnreadable = store.lastError {} else {
            Issue.record("A file that cannot be opened must be reported, not read as empty")
        }
        #expect(store.add(Profile(name: "New", entries: [entry(acer, "Acer")])) == .failedToSave)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #expect(try Data(contentsOf: url) == original)
    }

    // MARK: - Another process changes the catalog

    @Test("A mutation re-reads the catalog, so another process's change survives it")
    func mutationsReadModifyWrite() throws {
        let dir = makeDirectory()
        let app = ProfileStore(directory: dir)
        #expect(app.add(Profile(name: "Desk", entries: [entry(lg, "LG")])) == .saved)

        // The CLI, a separate process, saves a profile while the app runs.
        let cli = ProfileStore(directory: dir)
        #expect(cli.add(Profile(name: "Travel", entries: [entry(.anyExternal, "Any")])) == .saved)

        #expect(app.add(Profile(name: "Sofa", entries: [entry(acer, "Acer")])) == .saved)

        #expect(ProfileStore(directory: dir).profiles.map(\.name) == ["Desk", "Travel", "Sofa"])
        #expect(app.profiles.map(\.name) == ["Desk", "Travel", "Sofa"])
    }

    @Test("A profile the CLI deleted is not written back by the app's next save")
    func deletionByAnotherProcessSticks() throws {
        let dir = makeDirectory()
        let app = ProfileStore(directory: dir)
        let doomed = Profile(name: "Old", entries: [entry(lg, "LG")])
        let kept = Profile(name: "Kept", entries: [entry(acer, "Acer")])
        #expect(app.add(doomed) == .saved)
        #expect(app.add(kept) == .saved)

        let cli = ProfileStore(directory: dir)
        #expect(cli.delete(doomed) == .saved)

        var renamed = kept
        renamed.name = "Renamed"
        #expect(app.update(renamed) == .saved)

        #expect(ProfileStore(directory: dir).profiles.map(\.name) == ["Renamed"])
    }

    @Test("The name check sees a profile another process just saved")
    func nameCheckSeesOtherProcess() throws {
        let dir = makeDirectory()
        let app = ProfileStore(directory: dir)
        let cli = ProfileStore(directory: dir)
        #expect(cli.add(Profile(name: "Work", entries: [entry(lg, "LG")])) == .saved)

        #expect(app.add(Profile(name: "work", entries: [entry(acer, "Acer")]))
            == .rejectedDuplicateName("work"))
    }

    @Test("The running app picks up a change another process wrote")
    func watcherReloadsExternalChange() async throws {
        let dir = makeDirectory()
        let app = ProfileStore(directory: dir)
        app.watchForExternalChanges()

        let cli = ProfileStore(directory: dir)
        #expect(cli.add(Profile(name: "Travel", entries: [entry(.anyExternal, "Any")])) == .saved)

        let deadline = ContinuousClock.now + .seconds(5)
        while app.profiles.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(app.profiles.map(\.name) == ["Travel"])
    }

    // MARK: - Flexible toggle and update bind like apply does

    private static func fakeIdentity(_ id: CGDirectDisplayID) -> DisplayIdentity {
        switch id {
        case 2: return DisplayIdentity(vendor: 10, model: 11, serial: 12)   // LG
        case 3: return DisplayIdentity(vendor: 20, model: 21, serial: 22)   // Acer
        default: return DisplayIdentity(vendor: 1, model: 2, serial: 3)     // built-in
        }
    }

    private static func fakeMatches(_ matcher: DisplayMatcher, _ id: CGDirectDisplayID) -> Bool {
        switch matcher {
        case .anyExternal: return id != 1
        case .builtIn: return id == 1
        case let .edid(vendor, model, serial):
            guard id != 1 else { return false }
            return fakeIdentity(id) == DisplayIdentity(vendor: vendor, model: model, serial: serial)
        }
    }

    private func display(_ id: CGDirectDisplayID, _ name: String, mode: CGDisplayMode? = nil) -> DisplayInfo {
        DisplayInfo(id: id, name: name, isMain: false, modes: mode.map { [$0] } ?? [],
                    currentMode: mode, groups: [])
    }

    /// `CGDisplayMode` has no public initialiser, so the modes come from the
    /// real main display. Nothing is applied to it.
    private func twoRealModes() throws -> (CGDisplayMode, CGDisplayMode) {
        let all = try #require(CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode])
        let first = try #require(all.first)
        let second = try #require(all.first { $0.width != first.width })
        return (first, second)
    }

    private func fakedStore() -> ProfileStore {
        let store = ProfileStore(directory: makeDirectory())
        store.displayMatches = Self.fakeMatches
        store.displayIdentity = Self.fakeIdentity
        return store
    }

    @Test("Locking a flexible entry captures the external the profile does not already name")
    func lockCapturesUnnamedExternal() {
        let store = fakedStore()
        let profile = Profile(name: "Desk", entries: [entry(lg, "LG"), entry(.anyExternal, "Any")],
                              mainDisplay: .anyExternal)
        #expect(store.add(profile) == .saved)
        // The LG is listed first among the connected monitors.
        let live = [display(2, "LG"), display(3, "Acer")]

        #expect(store.toggleFlexible(profile, displays: live) == .madeSpecific)

        let locked = store.profiles[0]
        #expect(locked.entries.map(\.matcher) == [lg, acer])
        #expect(locked.entries[1].displayName == "Acer")
        #expect(locked.mainDisplay == acer)
    }

    @Test("Locking is refused when the only external is one the profile already names")
    func lockNeedsAnUnnamedExternal() {
        let store = fakedStore()
        let profile = Profile(name: "Desk", entries: [entry(lg, "LG"), entry(.anyExternal, "Any")])
        #expect(store.add(profile) == .saved)

        let result = store.toggleFlexible(profile, displays: [display(2, "LG")])

        #expect(result == .blockedNoExternal)
        #expect(store.profiles[0] == profile)
    }

    @Test("Making a profile flexible moves its main display along")
    func flexKeepsMainDisplay() {
        let store = fakedStore()
        let profile = Profile(name: "Desk", entries: [entry(.builtIn(vendor: 1, model: 2, serial: 3), "Built-in"),
                                                     entry(lg, "LG")],
                              mainDisplay: lg)
        #expect(store.add(profile) == .saved)

        #expect(store.toggleFlexible(profile, displays: []) == .madeFlexible)

        #expect(store.profiles[0].entries[1].matcher == .anyExternal)
        #expect(store.profiles[0].mainDisplay == .anyExternal)
    }

    @Test("Making a two-monitor profile flexible is refused rather than saving two 'any external' entries")
    func flexRefusedForSeveralExternals() {
        let store = fakedStore()
        let profile = Profile(name: "Desk", entries: [entry(lg, "LG"), entry(acer, "Acer")])
        #expect(store.add(profile) == .saved)

        #expect(store.toggleFlexible(profile, displays: []) == .blockedSeveralExternals)
        #expect(store.profiles[0] == profile)
    }

    @Test("Update with current setup reads each entry from the display it binds to")
    func updateReadsBoundDisplays() throws {
        let store = fakedStore()
        let profile = Profile(name: "Desk", entries: [entry(lg, "LG", width: 1000),
                                                     entry(.anyExternal, "Any", width: 1000)])
        #expect(store.add(profile) == .saved)
        let (lgMode, acerMode) = try twoRealModes()
        let live = [display(2, "LG", mode: lgMode), display(3, "Acer", mode: acerMode)]

        let updated = try #require(store.updateFromCurrent(profile, displays: live))

        #expect(updated.entries.map(\.pointWidth) == [lgMode.width, acerMode.width])
        #expect(updated.entries.map(\.displayName) == ["LG", "Acer"])
    }
}
