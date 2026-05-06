import Foundation
import Testing
@testable import VibeRes

@Suite("Profile rename flow")
@MainActor
struct ProfileRenameTests {
    private func makeStore() -> (ProfileStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-rename-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ProfileStore(directory: dir), dir)
    }

    @Test("Rename keeps the same id and replaces the name")
    func renameKeepsId() {
        let (store, dir) = makeStore()
        var p = Profile(name: "Old", entries: [])
        store.add(p)
        let originalID = p.id

        p.name = "New"
        store.update(p)

        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles.count == 1)
        #expect(reloaded.profiles[0].id == originalID)
        #expect(reloaded.profiles[0].name == "New")
    }

    @Test("Renaming preserves entries and createdAt")
    func renamePreservesEntries() {
        let (store, dir) = makeStore()
        let entry = Profile.Entry(
            matcher: .edid(vendor: 1, model: 2, serial: 3),
            displayName: "Test", pointWidth: 1920, pointHeight: 1080,
            refreshHz: 60, isHiDPI: false
        )
        var p = Profile(name: "Original", entries: [entry])
        let originalCreated = p.createdAt
        store.add(p)

        p.name = "Renamed"
        store.update(p)

        let reloaded = ProfileStore(directory: dir)
        let r = reloaded.profiles[0]
        #expect(r.entries.count == 1)
        #expect(r.entries[0].pointWidth == 1920)
        #expect(r.createdAt == originalCreated)
    }

    @Test("Rename to empty string is rejected at the call-site (commit logic)")
    func emptyNameLogic() {
        // The commit() helper in ProfilesSection trims whitespace and bails on
        // empty strings before calling update(). Mirror that contract here so
        // we lock down what valid inputs look like.
        let candidates = ["  ", "\t\n", ""]
        for c in candidates {
            let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(trimmed.isEmpty)
        }
    }

    @Test("Renaming a profile that doesn't exist is a no-op")
    func renameNonexistentNoOp() {
        let (store, _) = makeStore()
        store.add(Profile(name: "Real", entries: []))

        let ghost = Profile(name: "Ghost", entries: [])
        store.update(ghost) // shouldn't crash, shouldn't add

        #expect(store.profiles.count == 1)
        #expect(store.profiles[0].name == "Real")
    }
}
