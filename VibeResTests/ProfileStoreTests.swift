import Foundation
import Testing
@testable import VibeRes

@Suite("ProfileStore persistence")
@MainActor
struct ProfileStoreTests {
    private func makeTempStore() -> (ProfileStore, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (ProfileStore(directory: tmp), tmp)
    }

    @Test("Empty store starts with no profiles")
    func startsEmpty() {
        let (store, _) = makeTempStore()
        #expect(store.profiles.isEmpty)
    }

    @Test("Adding a profile persists it to disk")
    func addPersists() {
        let (store, dir) = makeTempStore()
        let entry = Profile.Entry(
            displayVendor: 1,
            displayModel: 2,
            displaySerial: 3,
            displayName: "Test",
            pointWidth: 1920,
            pointHeight: 1080,
            refreshHz: 60,
            isHiDPI: true
        )
        let p = Profile(name: "Work", entries: [entry])
        store.add(p)

        // Reload from the same directory and check that "Work" is back.
        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles.count == 1)
        #expect(reloaded.profiles[0].name == "Work")
        #expect(reloaded.profiles[0].entries.first?.pointWidth == 1920)
    }

    @Test("Deleting a profile removes it from disk too")
    func deletePersists() {
        let (store, dir) = makeTempStore()
        let p = Profile(name: "Throwaway", entries: [])
        store.add(p)
        #expect(store.profiles.count == 1)

        store.delete(p)
        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles.isEmpty)
    }

    @Test("Updating a profile keeps the same id but new fields")
    func updateInPlace() {
        let (store, dir) = makeTempStore()
        var p = Profile(name: "Old name", entries: [])
        store.add(p)

        p.name = "New name"
        store.update(p)

        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles.count == 1)
        #expect(reloaded.profiles[0].name == "New name")
        #expect(reloaded.profiles[0].id == p.id)
    }

    @Test("Multiple profiles round-trip in stable order")
    func ordering() {
        let (store, dir) = makeTempStore()
        store.add(Profile(name: "A", entries: []))
        store.add(Profile(name: "B", entries: []))
        store.add(Profile(name: "C", entries: []))

        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles.map(\.name) == ["A", "B", "C"])
    }

    @Test("Corrupt JSON on disk is treated as an empty store")
    func corruptFileTolerated() throws {
        let (_, dir) = makeTempStore()
        let url = dir.appendingPathComponent("profiles.json")
        try "{not json}".data(using: .utf8)!.write(to: url)

        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles.isEmpty)
        #expect(reloaded.lastError != nil)
    }
}
