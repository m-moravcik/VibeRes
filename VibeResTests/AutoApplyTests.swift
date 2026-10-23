import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

@Suite("Profile auto-apply matcher")
@MainActor
struct AutoApplyTests {
    // MARK: - Specificity scoring

    @Test("Specificity ranking: .edid > .builtIn > .anyExternal")
    func specificityRanking() {
        let edid = DisplayMatcher.edid(vendor: 1, model: 2, serial: 3)
        let builtIn = DisplayMatcher.builtIn(vendor: 4, model: 5, serial: 6)
        let any = DisplayMatcher.anyExternal

        let edidScore = ProfileStore.specificity(of: edid)
        let builtInScore = ProfileStore.specificity(of: builtIn)
        let anyScore = ProfileStore.specificity(of: any)

        #expect(edidScore > builtInScore)
        #expect(builtInScore > anyScore)
        #expect(anyScore > 0)
    }

    @Test("Profile-level specificity is the sum of entry specificities")
    func profileLevelSpecificityIsSum() {
        // Work: 2 EDID externals → 3 + 3 = 6
        let workScore =
            ProfileStore.specificity(of: .edid(vendor: 1, model: 2, serial: 3)) +
            ProfileStore.specificity(of: .edid(vendor: 4, model: 5, serial: 6))
        // Presentation: builtIn + anyExternal → 2 + 1 = 3
        let presentationScore =
            ProfileStore.specificity(of: .builtIn(vendor: 7, model: 8, serial: 9)) +
            ProfileStore.specificity(of: .anyExternal)
        // Code: builtIn only → 2
        let codeScore = ProfileStore.specificity(of: .builtIn(vendor: 7, model: 8, serial: 9))

        #expect(workScore > presentationScore)
        #expect(presentationScore > codeScore)
        #expect(workScore == 6)
        #expect(presentationScore == 3)
        #expect(codeScore == 2)
    }

    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-auto-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

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

    @Test("No profiles → no match")
    func emptyStoreNoMatch() {
        let store = makeStore()
        let result = store.profileMatchingExactly([])
        #expect(result == nil)
    }

    @Test("Profile with no matchable display → no match")
    func nonMatchingProfile() {
        let store = makeStore()
        store.add(Profile(name: "Phantom", entries: [
            Profile.Entry(matcher: .edid(vendor: 999, model: 999, serial: 999),
                          displayName: "Ghost", pointWidth: 1920, pointHeight: 1080,
                          refreshHz: 60, isHiDPI: false),
        ]))
        // Empty live displays — nothing matches.
        let result = store.profileMatchingExactly([])
        #expect(result == nil)
    }

    @Test("Most-recently-saved profile wins on tie")
    func recencyTieBreaker() {
        let store = makeStore()
        let older = Profile(
            id: UUID(),
            name: "Older",
            entries: [
                Profile.Entry(matcher: .anyExternal,
                              displayName: "Any", pointWidth: 1920, pointHeight: 1080,
                              refreshHz: 60, isHiDPI: false)
            ],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let newer = Profile(
            id: UUID(),
            name: "Newer",
            entries: [
                Profile.Entry(matcher: .anyExternal,
                              displayName: "Any", pointWidth: 2560, pointHeight: 1440,
                              refreshHz: 60, isHiDPI: false)
            ],
            createdAt: Date(timeIntervalSince1970: 2_000_000)
        )
        store.add(older)
        store.add(newer)
        let result = store.profileMatchingExactly(
            [info(id: 1, name: "External")],
            entryMatchesDisplay: { _, _ in true }
        )
        #expect(result?.id == newer.id)
    }

    @Test("Auto-apply ignores profiles that leave a live display uncovered")
    func exactMatchRejectsExtraLiveDisplays() {
        let store = makeStore()
        let profile = Profile(name: "Built-in only", entries: [
            Profile.Entry(
                matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                displayName: "Built-in",
                pointWidth: 1800,
                pointHeight: 1169,
                refreshHz: 120,
                isHiDPI: true
            )
        ])
        store.add(profile)

        let result = store.profileMatchingExactly(
            [
                info(id: 1, name: "Built-in"),
                info(id: 2, name: "Projector"),
            ],
            entryMatchesDisplay: { entry, display in entry.displayName == display.name }
        )

        #expect(result == nil)
    }

    // MARK: - Flexible profiles and known monitors
    //
    // Reported on 2026-10-23: with the built-in and only the LG UltraFine of a
    // three-display desk connected, auto-apply picked 'Presentation', a
    // flexible profile saved with an Acer GN246HL, and gave the LG the Acer's
    // 1920x1080. The LG is a known monitor: 'Home Office' names it. A flexible
    // entry is for a monitor no profile knows (a projector, a TV), so it must
    // not stand in for one that a profile names.

    private static let builtIn = DisplayMatcher.builtIn(vendor: 1, model: 2, serial: 3)
    private static let lg = DisplayMatcher.edid(vendor: 10, model: 11, serial: 12)
    private static let acer = DisplayMatcher.edid(vendor: 20, model: 21, serial: 22)

    /// Display 1 is the built-in, 2 the LG, 3 a projector nobody saved.
    private static func identity(_ matcher: DisplayMatcher, _ id: CGDirectDisplayID) -> Bool {
        switch (matcher, id) {
        case (.builtIn, 1): return true
        case (.anyExternal, 2), (.anyExternal, 3): return true
        case (.edid(10, 11, 12), 2): return true
        default: return false
        }
    }

    private func entry(_ matcher: DisplayMatcher, _ name: String) -> Profile.Entry {
        Profile.Entry(matcher: matcher, displayName: name, pointWidth: 1920, pointHeight: 1080,
                      refreshHz: 60, isHiDPI: false)
    }

    private func reportedSetup() -> ProfileStore {
        let store = makeStore()
        _ = store.add(Profile(name: "Home Office", entries: [
            entry(Self.builtIn, "Built-in"), entry(Self.acer, "GN246HL"), entry(Self.lg, "LG UltraFine"),
        ]))
        _ = store.add(Profile(name: "Presentation", entries: [
            entry(Self.builtIn, "Built-in"), entry(.anyExternal, "GN246HL"),
        ]))
        return store
    }

    @Test("A flexible profile does not take over a monitor another profile names")
    func flexibleSkipsKnownMonitor() {
        let store = reportedSetup()

        let result = store.profileForAutoApply(
            [info(id: 1, name: "Built-in"), info(id: 2, name: "LG UltraFine")],
            matches: Self.identity
        )

        #expect(result == nil, "auto-apply gave the LG the flexible profile's mode")
    }

    @Test("A flexible profile still applies to a monitor no profile knows")
    func flexibleTakesUnknownMonitor() {
        let store = reportedSetup()

        let result = store.profileForAutoApply(
            [info(id: 1, name: "Built-in"), info(id: 3, name: "Projector")],
            matches: Self.identity
        )

        #expect(result?.name == "Presentation")
    }

    @Test("A specific profile for exactly what is connected still applies")
    func specificProfileApplies() {
        let store = reportedSetup()
        _ = store.add(Profile(name: "LG desk", entries: [
            entry(Self.builtIn, "Built-in"), entry(Self.lg, "LG UltraFine"),
        ]))

        let result = store.profileForAutoApply(
            [info(id: 1, name: "Built-in"), info(id: 2, name: "LG UltraFine")],
            matches: Self.identity
        )

        #expect(result?.name == "LG desk")
    }

    // MARK: - Where auto-apply runs

    @Test("A display change asks for auto-apply from the store, not from a view")
    func tokenBumpAsksForAutoApply() {
        let displays = DisplayStore()
        var asked = 0
        displays.onAutoApplyNeeded = { asked += 1 }

        displays.bumpAutoApplyToken()

        #expect(asked == 1)
    }

    @Test("An auto-apply that finds no profile records nothing for the popover")
    func noMatchRecordsNothing() {
        let store = reportedSetup()

        let result = store.autoApply(to: [info(id: 1, name: "Built-in"), info(id: 2, name: "LG UltraFine")])

        #expect(result == nil)
        #expect(store.lastAutoApply == nil)
    }
}

