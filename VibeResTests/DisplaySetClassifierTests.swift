import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// Tests the pure classification logic that decides what to show the user
/// before a manual profile apply. The classifier does not mutate display
/// state, so we can fully test it with synthesised DisplayInfo values.
///
/// We can't construct real CGDisplayMode in unit tests, so DisplayInfo
/// instances here use empty mode lists. That's enough for classification —
/// it only inspects `id` for matcher binding, not modes.
@Suite("DisplaySetClassifier")
@MainActor
struct DisplaySetClassifierTests {

    /// Build a DisplayInfo with synthetic id; modes are empty (not needed for
    /// classification). The matcher functions inspect display IDs through
    /// CG APIs, so we can't easily forge "this id is the builtin" — instead
    /// we pick test scenarios that don't depend on `CGDisplayIsBuiltin`.
    private func info(id: CGDirectDisplayID, name: String) -> DisplayInfo {
        DisplayInfo(
            id: id,
            name: name,
            isMain: false,
            modes: [],
            currentMode: nil,
            groups: []
        )
    }

    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-classify-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    private func classify(_ profile: Profile, against displays: [DisplayInfo],
                          in store: ProfileStore? = nil) -> DisplaySetClassifier.Classification {
        let store = store ?? makeStore()
        return DisplaySetClassifier.classify(store.bindings(of: profile, to: displays), against: displays)
    }

    @Test("Empty profile returns .disjoint regardless of live displays")
    func emptyProfile() {
        let profile = Profile(name: "Empty", entries: [])
        let result = classify(profile, against: [info(id: 1, name: "A")])
        #expect(result == .disjoint)
    }

    @Test("Profile with no live displays returns .disjoint")
    func noLiveDisplays() {
        let profile = Profile(name: "Work", entries: [
            Profile.Entry(matcher: .edid(vendor: 1, model: 2, serial: 3),
                          displayName: "External",
                          pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false)
        ])
        let result = classify(profile, against: [])
        #expect(result == .disjoint)
    }

    /// `.anyExternal` against zero connected displays = disjoint.
    /// (When at least one external is connected, matches() will return true
    /// for it — that path is exercised in real integration via the app.)
    @Test("anyExternal with empty display list is .disjoint")
    func anyExternalEmpty() {
        let profile = Profile(name: "Travel", entries: [
            Profile.Entry(matcher: .anyExternal,
                          displayName: "Any external",
                          pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false)
        ])
        let result = classify(profile, against: [])
        #expect(result == .disjoint)
    }

    // MARK: - Manual apply sees the apply's own bindings

    private static let builtIn = DisplayMatcher.builtIn(vendor: 1, model: 2, serial: 3)
    private static let lg = DisplayMatcher.edid(vendor: 10, model: 11, serial: 12)
    private static let acer = DisplayMatcher.edid(vendor: 20, model: 21, serial: 22)

    /// Display 1 is the built-in, 2 the LG.
    private static func identity(_ matcher: DisplayMatcher, _ id: CGDirectDisplayID) -> Bool {
        switch (matcher, id) {
        case (.builtIn, 1), (.anyExternal, 2), (.edid(10, 11, 12), 2): return true
        default: return false
        }
    }

    private func entry(_ matcher: DisplayMatcher, _ name: String) -> Profile.Entry {
        Profile.Entry(matcher: matcher, displayName: name, pointWidth: 1920, pointHeight: 1080,
                      refreshHz: 60, isHiDPI: false)
    }

    private var builtInAndLG: [DisplayInfo] {
        [info(id: 1, name: "Built-in"), info(id: 2, name: "LG UltraFine")]
    }

    @Test("A flexible profile clicked by hand is an exact match on a monitor another profile names")
    func flexibleProfileOnKnownMonitorIsExact() {
        let store = makeStore()
        store.displayMatches = Self.identity
        _ = store.add(Profile(name: "Home Office", entries: [
            entry(Self.builtIn, "Built-in"), entry(Self.acer, "GN246HL"), entry(Self.lg, "LG UltraFine"),
        ]))
        let presentation = Profile(name: "Presentation", entries: [
            entry(Self.builtIn, "Built-in"), entry(.anyExternal, "GN246HL"),
        ])
        _ = store.add(presentation)

        #expect(classify(presentation, against: builtInAndLG, in: store) == .exactMatch)
    }

    @Test("A mixed profile whose flexible row has no free external is a partial match")
    func mixedProfileWithoutFreeExternalIsPartial() {
        let store = makeStore()
        store.displayMatches = Self.identity
        let flexible = entry(.anyExternal, "Any external")
        let desk = Profile(name: "Desk", entries: [
            entry(Self.builtIn, "Built-in"), entry(Self.lg, "LG UltraFine"), flexible,
        ])
        _ = store.add(desk)

        #expect(classify(desk, against: builtInAndLG, in: store) == .partialMatch(missing: [flexible]))
    }

    @Test("isCleanApply returns true only for .exactMatch")
    func cleanApplyFlag() {
        #expect(DisplaySetClassifier.isCleanApply(.exactMatch) == true)
        #expect(DisplaySetClassifier.isCleanApply(.disjoint) == false)
        let dummyEntry = Profile.Entry(
            matcher: .edid(vendor: 1, model: 1, serial: 1),
            displayName: "X",
            pointWidth: 100, pointHeight: 100, refreshHz: nil, isHiDPI: false
        )
        let dummyDisplay = info(id: 99, name: "Y")
        #expect(DisplaySetClassifier.isCleanApply(.partialMatch(missing: [dummyEntry])) == false)
        #expect(DisplaySetClassifier.isCleanApply(.supersetMatch(extra: [dummyDisplay])) == false)
        #expect(DisplaySetClassifier.isCleanApply(.partialWithExtras(missing: [dummyEntry], extra: [dummyDisplay])) == false)
    }
}
