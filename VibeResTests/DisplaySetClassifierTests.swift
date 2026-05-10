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

    @Test("Empty profile returns .disjoint regardless of live displays")
    func emptyProfile() {
        let profile = Profile(name: "Empty", entries: [])
        let result = DisplaySetClassifier.classify(profile, against: [info(id: 1, name: "A")])
        #expect(result == .disjoint)
    }

    @Test("Profile with no live displays returns .disjoint")
    func noLiveDisplays() {
        let profile = Profile(name: "Work", entries: [
            Profile.Entry(matcher: .edid(vendor: 1, model: 2, serial: 3),
                          displayName: "External",
                          pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false)
        ])
        let result = DisplaySetClassifier.classify(profile, against: [])
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
        let result = DisplaySetClassifier.classify(profile, against: [])
        #expect(result == .disjoint)
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
