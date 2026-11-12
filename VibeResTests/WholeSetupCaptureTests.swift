import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// The welcome tour offers to save "what you have now" as the first profile in
/// one click, with no form. These pin what that one click stores.
@Suite("captureWholeSetup")
@MainActor
struct WholeSetupCaptureTests {
    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-whole-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    private func info(_ id: CGDirectDisplayID) -> DisplayInfo {
        let mode = (CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode])?.first
        return DisplayInfo(id: id, name: "Mon \(id)", isMain: false,
                           modes: mode.map { [$0] } ?? [], currentMode: mode, groups: [])
    }

    @Test("Every connected display is saved, each bound to that exact monitor")
    func savesEveryDisplaySpecifically() {
        let store = makeStore()
        let result = store.captureWholeSetup(name: "Desk", displays: [info(101), info(102)])

        #expect(result == .saved)
        let entries = store.profiles.first?.entries ?? []
        #expect(entries.map(\.displayName) == ["Mon 101", "Mon 102"])
        // "Any external" is a choice the user makes in the full form; a profile
        // saved without asking must not quietly match a different monitor.
        #expect(!entries.contains { if case .anyExternal = $0.matcher { true } else { false } })
    }

    @Test("Which display is main is left alone, as the full form does by default")
    func leavesMainDisplayAlone() {
        let store = makeStore()
        _ = store.captureWholeSetup(name: "Desk", displays: [info(101), info(102)])
        #expect(store.profiles.first?.mainDisplay == nil)
    }

    @Test("No displays means nothing is saved")
    func noDisplaysRejected() {
        let store = makeStore()
        #expect(store.captureWholeSetup(name: "Desk", displays: []) == .rejectedEmpty)
        #expect(store.profiles.isEmpty)
    }

    @Test("A taken name is refused, not overwritten")
    func duplicateNameRefused() {
        let store = makeStore()
        _ = store.captureWholeSetup(name: "Desk", displays: [info(101)])
        #expect(store.captureWholeSetup(name: "desk", displays: [info(101)]) == .rejectedDuplicateName("desk"))
        #expect(store.profiles.count == 1)
    }
}
