import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// The decisions the Save and Edit forms make.
///
/// These used to be private methods inside a 1600-line view, reachable only by
/// looking at the screen: whether Save is enabled, which "match any external"
/// checkbox is blocked, what the size picker offers, and what a row calls
/// itself. Splitting the forms out moved them onto their own state types,
/// where a test can reach them.
@Suite("Profile form logic")
@MainActor
struct ProfileFormLogicTests {
    private func choice(
        _ id: CGDirectDisplayID,
        included: Bool = true,
        anyExternal: Bool = false,
        builtIn: Bool = false
    ) -> ProfilesSection.DisplayChoice {
        ProfilesSection.DisplayChoice(
            displayID: id,
            displayName: "Mon \(id)",
            isBuiltIn: builtIn,
            currentModeDescription: "1920×1080",
            isIncluded: included,
            matchAnyExternal: anyExternal
        )
    }

    private func entry(
        _ id: UUID = UUID(),
        included: Bool = true,
        kind: ProfilesSection.MatcherKind = .specific,
        width: Int = 1920,
        height: Int = 1080,
        hz: Int? = 60,
        hiDPI: Bool = false,
        modes: [ProfilesSection.LiveMode] = []
    ) -> ProfilesSection.EntryEdit {
        ProfilesSection.EntryEdit(
            id: id,
            matcherKind: kind,
            isBuiltIn: false,
            vendor: 1, model: 2, serial: 3,
            displayName: "LG UltraFine",
            pointWidth: width, pointHeight: height,
            refreshHz: hz, isHiDPI: hiDPI,
            isIncluded: included,
            availableModes: modes
        )
    }

    private func mode(_ w: Int, _ h: Int, _ hz: Int?, hiDPI: Bool = false) -> ProfilesSection.LiveMode {
        ProfilesSection.LiveMode(pointWidth: w, pointHeight: h, refreshHz: hz, isHiDPI: hiDPI)
    }

    // MARK: Save form

    @Test("Save needs a name and at least one display")
    func saveFormValidity() {
        var state = ProfilesSection.SaveFormState()
        state.perDisplay = [choice(1)]

        state.name = ""
        #expect(state.isSavable == false)

        // Whitespace is not a name: the store sanitises it away and would
        // refuse the save after the fact.
        state.name = "   "
        #expect(state.isSavable == false)

        state.name = "Work"
        #expect(state.isSavable == true)

        state.perDisplay = [choice(1, included: false)]
        #expect(state.isSavable == false, "a profile with nothing in it has nothing to apply")
    }

    @Test("Only one display at a time may match any external")
    func saveFormAnyExternalIsExclusive() {
        let choices = [choice(1, anyExternal: true), choice(2), choice(3)]
        // The one that already holds it is not blocked by itself.
        #expect(ProfilesSection.SaveFormState.anyExternalTakenByAnother(than: 1, in: choices) == false)
        #expect(ProfilesSection.SaveFormState.anyExternalTakenByAnother(than: 2, in: choices) == true)
    }

    @Test("An excluded display does not hold the any-external slot")
    func excludedDisplayDoesNotBlock() {
        let choices = [choice(1, included: false, anyExternal: true), choice(2)]
        #expect(ProfilesSection.SaveFormState.anyExternalTakenByAnother(than: 2, in: choices) == false)
    }

    // MARK: Edit form

    @Test("Save needs a name and at least one kept entry")
    func editFormValidity() {
        let row = entry()
        var state = ProfilesSection.EditFormState(profileID: UUID(), name: "Work", entries: [row])
        #expect(state.isSavable == true)

        state.name = "  "
        #expect(state.isSavable == false)

        state.name = "Work"
        state.entries = [entry(included: false)]
        #expect(state.isSavable == false)
    }

    @Test("Only one kept entry at a time may match any external")
    func editFormAnyExternalIsExclusive() {
        let flexible = UUID(), specific = UUID()
        let entries = [
            entry(flexible, kind: .anyExternal),
            entry(specific),
        ]
        #expect(ProfilesSection.EditFormState.anyExternalTakenByAnother(than: flexible, in: entries) == false)
        #expect(ProfilesSection.EditFormState.anyExternalTakenByAnother(than: specific, in: entries) == true)
    }

    @Test("A flexible row names its role, not the monitor it was saved from")
    func flexibleRowTitle() {
        // "LG UltraFine" on a row that matches any external is a lie about
        // what the row will do.
        #expect(entry(kind: .anyExternal).rowTitle == "Any external")
        #expect(entry(kind: .specific).rowTitle == "LG UltraFine")
    }

    @Test("A row with nothing connected still describes the mode it will apply")
    func savedModeDescriptionReadsCompletely() {
        #expect(entry(width: 2560, height: 1440, hz: 75, hiDPI: true).savedModeDescription
                == "2560×1440 · 75 Hz · HiDPI")
        #expect(entry(width: 1920, height: 1080, hz: nil, hiDPI: false).savedModeDescription
                == "1920×1080")
    }

    // MARK: The mode picker

    @Test("Sizes are offered largest first, HiDPI before native at the same size")
    func bucketOrdering() {
        let buckets = ProfilesSection.LiveMode.buckets(in: [
            mode(1920, 1080, 60),
            mode(2560, 1440, 60),
            mode(2560, 1440, 60, hiDPI: true),
            mode(2560, 1440, 120),
        ])
        #expect(buckets.map(\.label) == ["2560×1440 HiDPI", "2560×1440", "1920×1080"])
    }

    @Test("A size appears once however many rates it has")
    func bucketsAreDeduplicated() {
        let buckets = ProfilesSection.LiveMode.buckets(in: [
            mode(1920, 1080, 60),
            mode(1920, 1080, 120),
            mode(1920, 1080, 144),
        ])
        #expect(buckets.count == 1)
    }

    @Test("Refresh rates are those of the chosen size only, ascending")
    func refreshOptionsAreScopedToTheSize() {
        let modes = [
            mode(2560, 1440, 120),
            mode(2560, 1440, 60),
            mode(1920, 1080, 144),
        ]
        let bucket = ProfilesSection.LiveMode.Bucket(pointWidth: 2560, pointHeight: 1440, isHiDPI: false)
        #expect(ProfilesSection.LiveMode.refreshOptions(in: modes, bucket: bucket) == [60, 120])
    }

    @Test("A size that reports no rate sorts first rather than disappearing")
    func refreshOptionsKeepTheUnknownRate() {
        let modes = [mode(1920, 1080, nil), mode(1920, 1080, 60)]
        let bucket = ProfilesSection.LiveMode.Bucket(pointWidth: 1920, pointHeight: 1080, isHiDPI: false)
        #expect(ProfilesSection.LiveMode.refreshOptions(in: modes, bucket: bucket) == [nil, 60])
    }

    @Test("HiDPI and native at the same size are different buckets")
    func refreshOptionsDistinguishScaling() {
        let modes = [mode(2560, 1440, 60, hiDPI: true), mode(2560, 1440, 120)]
        let hidpi = ProfilesSection.LiveMode.Bucket(pointWidth: 2560, pointHeight: 1440, isHiDPI: true)
        let native = ProfilesSection.LiveMode.Bucket(pointWidth: 2560, pointHeight: 1440, isHiDPI: false)
        #expect(ProfilesSection.LiveMode.refreshOptions(in: modes, bucket: hidpi) == [60])
        #expect(ProfilesSection.LiveMode.refreshOptions(in: modes, bucket: native) == [120])
    }

    @Test("An entry reports the bucket it currently points at")
    func entryBucket() {
        let row = entry(width: 2560, height: 1440, hiDPI: true)
        #expect(row.bucket == ProfilesSection.LiveMode.Bucket(
            pointWidth: 2560, pointHeight: 1440, isHiDPI: true
        ))
    }
}
