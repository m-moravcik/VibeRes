import Foundation
import Testing
@testable import VibeRes

@Suite("Profile edge cases")
@MainActor
struct ProfileEdgeCaseTests {
    private func makeStore() -> (ProfileStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-edge-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ProfileStore(directory: dir), dir)
    }

    // MARK: humanSummary

    @Test("humanSummary with single built-in entry")
    func humanSummarySingleBuiltIn() {
        let p = Profile(name: "Code", entries: [
            Profile.Entry(matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                          displayName: "Built-in", pointWidth: 1800, pointHeight: 1169,
                          refreshHz: 120, isHiDPI: true),
        ])
        #expect(p.humanSummary == "Built-in")
    }

    @Test("humanSummary with single anyExternal entry")
    func humanSummarySingleAnyExternal() {
        let p = Profile(name: "Slot", entries: [
            Profile.Entry(matcher: .anyExternal,
                          displayName: "Any external", pointWidth: 1920, pointHeight: 1080,
                          refreshHz: 60, isHiDPI: false),
        ])
        #expect(p.humanSummary == "any external")
    }

    @Test("humanSummary with three mixed entries reads in order")
    func humanSummaryMixedThreeEntries() {
        let p = Profile(name: "Big", entries: [
            Profile.Entry(matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                          displayName: "Built-in", pointWidth: 1800, pointHeight: 1169,
                          refreshHz: 120, isHiDPI: true),
            Profile.Entry(matcher: .edid(vendor: 10, model: 20, serial: 30),
                          displayName: "Studio Display", pointWidth: 2560, pointHeight: 1440,
                          refreshHz: 60, isHiDPI: false),
            Profile.Entry(matcher: .anyExternal,
                          displayName: "Any external", pointWidth: 1920, pointHeight: 1080,
                          refreshHz: 60, isHiDPI: false),
        ])
        #expect(p.humanSummary == "Built-in + Studio Display + any external")
    }

    @Test("humanSummary with empty entries is empty string")
    func humanSummaryEmpty() {
        let p = Profile(name: "Bare", entries: [])
        #expect(p.humanSummary.isEmpty)
    }

    // MARK: ProfileStore name sanitisation

    @Test("Profile names with control characters are stripped on add")
    func nameSanitiserStripsControlChars() {
        let (store, _) = makeStore()
        let raw = "Work\u{0000}\u{0007}\u{007F}\nfoo"
        let p = Profile(name: raw, entries: [])
        store.add(p)
        #expect(store.profiles.count == 1)
        #expect(store.profiles[0].name == "Workfoo") // newline + null + bell + DEL stripped
    }

    @Test("Profile names longer than 128 characters are truncated")
    func nameSanitiserTruncates() {
        let (store, _) = makeStore()
        let long = String(repeating: "a", count: 200)
        store.add(Profile(name: long, entries: []))
        #expect(store.profiles[0].name.count == 128)
    }

    @Test("Empty / whitespace-only names refuse to add")
    func nameSanitiserRejectsEmpty() {
        let (store, _) = makeStore()
        store.add(Profile(name: "   \n\t", entries: []))
        store.add(Profile(name: "", entries: []))
        store.add(Profile(name: "\u{0000}", entries: []))
        #expect(store.profiles.isEmpty)
    }

    // MARK: Profile.Entry decoder bounds

    @Test("Profile.Entry decoder clamps extreme dimensions")
    func entryDecoderClamps() throws {
        let json = """
        {
            "matcher": {
                "kind": "edid",
                "vendor": 1,
                "model": 2,
                "serial": 3
            },
            "displayName": "X",
            "pointWidth": 99999,
            "pointHeight": -50,
            "refreshHz": 100000,
            "isHiDPI": false
        }
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(Profile.Entry.self, from: json)
        #expect(entry.pointWidth == 16384) // capped
        #expect(entry.pointHeight == 1)    // floored to 1 from negative
        #expect(entry.refreshHz == 1000)   // capped
    }

    @Test("Profile.Entry decoder truncates 1MB displayName to 256 chars")
    func entryDecoderTruncatesName() throws {
        let huge = String(repeating: "X", count: 1024 * 1024)
        let payload: [String: Any] = [
            "matcher": ["kind": "anyExternal"],
            "displayName": huge,
            "pointWidth": 1920,
            "pointHeight": 1080,
            "isHiDPI": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let entry = try JSONDecoder().decode(Profile.Entry.self, from: data)
        #expect(entry.displayName.count == 256)
    }

    // MARK: hasMatchingDisplay

    @Test("hasMatchingDisplay returns false for an empty profile")
    func hasMatchingEmpty() {
        let p = Profile(name: "Bare", entries: [])
        #expect(p.hasMatchingDisplay(in: []) == false)
    }
}
