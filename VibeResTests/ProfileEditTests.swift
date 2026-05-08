import Foundation
import Testing
@testable import VibeRes

@Suite("Profile editing — toggle flexible")
@MainActor
struct ProfileEditTests {
    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-edit-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    @Test("toggleFlexible flips edid externals to anyExternal")
    func toggleSpecificToFlexible() {
        let store = makeStore()
        let p = Profile(name: "Work", entries: [
            Profile.Entry(matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                          displayName: "Built-in", pointWidth: 1800, pointHeight: 1169, refreshHz: 120, isHiDPI: true),
            Profile.Entry(matcher: .edid(vendor: 99, model: 99, serial: 99),
                          displayName: "External", pointWidth: 2560, pointHeight: 1440, refreshHz: 60, isHiDPI: false),
        ])
        store.add(p)

        let result = store.toggleFlexible(p, displays: [])
        #expect(result == .madeFlexible)
        let updated = store.profiles[0]

        // Built-in stays as is
        if case .builtIn = updated.entries[0].matcher {} else {
            Issue.record("Built-in matcher should not change")
        }
        // External flips to anyExternal
        if case .anyExternal = updated.entries[1].matcher {} else {
            Issue.record("External matcher should be .anyExternal after toggle")
        }
    }

    @Test("toggleFlexible blocks lock when no external is connected")
    func toggleFlexibleWithoutLiveDisplay() {
        let store = makeStore()
        let p = Profile(name: "Travel", entries: [
            Profile.Entry(matcher: .anyExternal,
                          displayName: "Any external", pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false),
        ])
        store.add(p)

        let result = store.toggleFlexible(p, displays: [])
        #expect(result == .blockedNoExternal)
        let updated = store.profiles[0]
        // No live external to capture EDID from — entry kept as-is.
        if case .anyExternal = updated.entries[0].matcher {} else {
            Issue.record("Without live display, entry should stay flexible")
        }
    }

    @Test("toggleFlexible on a built-in-only profile flips semantically (no entry mutation)")
    func toggleFlexibleBuiltInOnly() {
        let store = makeStore()
        let p = Profile(name: "Code", entries: [
            Profile.Entry(matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                          displayName: "Built-in", pointWidth: 1800, pointHeight: 1169, refreshHz: 120, isHiDPI: true),
        ])
        store.add(p)

        // No anyExternal entries → not currently flexible → result should be .madeFlexible
        // even though built-in entries don't actually mutate.
        let result = store.toggleFlexible(p, displays: [])
        #expect(result == .madeFlexible)
        if case .builtIn = store.profiles[0].entries[0].matcher {} else {
            Issue.record("Built-in entry should remain unchanged")
        }
    }

    @Test("replaceEntries swaps profile entries while preserving id/name/createdAt")
    func replaceEntriesPreservesIdentity() {
        let store = makeStore()
        let originalID = UUID()
        let p = Profile(id: originalID, name: "Editable", entries: [
            Profile.Entry(matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                          displayName: "Built-in",
                          pointWidth: 1800, pointHeight: 1169, refreshHz: 120, isHiDPI: true),
            Profile.Entry(matcher: .edid(vendor: 99, model: 99, serial: 99),
                          displayName: "External",
                          pointWidth: 2560, pointHeight: 1440, refreshHz: 60, isHiDPI: false),
        ])
        store.add(p)

        // Drop the external, downgrade Hz on the built-in, save.
        let newEntries = [
            Profile.Entry(matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                          displayName: "Built-in",
                          pointWidth: 1800, pointHeight: 1169, refreshHz: 60, isHiDPI: true),
        ]
        let updated = store.replaceEntries(p, with: newEntries)
        #expect(updated?.id == originalID)
        #expect(updated?.name == "Editable")
        #expect(updated?.entries.count == 1)
        #expect(updated?.entries[0].refreshHz == 60)
    }

    @Test("replaceEntries refuses an empty entry list")
    func replaceEntriesRejectsEmpty() {
        let store = makeStore()
        let p = Profile(name: "Keep", entries: [
            Profile.Entry(matcher: .anyExternal,
                          displayName: "Any external",
                          pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false),
        ])
        store.add(p)

        let result = store.replaceEntries(p, with: [])
        #expect(result == nil)
        // Original profile unaffected.
        #expect(store.profiles[0].entries.count == 1)
    }

    @Test("updateFromCurrent preserves matcher policy + name + id")
    func updateFromCurrentPreservesIdentity() {
        let store = makeStore()
        let originalID = UUID()
        let p = Profile(id: originalID, name: "Stable", entries: [
            Profile.Entry(matcher: .anyExternal,
                          displayName: "Any external",
                          pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false),
        ])
        store.add(p)

        // No live displays — entry should be kept as-is (no panic, no zeroing).
        let updated = store.updateFromCurrent(p, displays: [])
        #expect(updated?.id == originalID)
        #expect(updated?.name == "Stable")
        #expect(updated?.entries.count == 1)
        // Matcher policy preserved
        if case .anyExternal = updated?.entries[0].matcher {} else {
            Issue.record("Matcher policy should survive updateFromCurrent")
        }
        // No live display → snapshot stays the original
        #expect(updated?.entries[0].pointWidth == 1920)
    }
}
