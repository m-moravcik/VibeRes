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
        store.displayMatches = { _, _ in true }
        let result = store.profileMatchingExactly([info(id: 1, name: "External")])
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
        store.displayMatches = Self.identity

        let result = store.profileMatchingExactly([
            info(id: 1, name: "Built-in"),
            info(id: 2, name: "Projector"),
        ])

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
        store.displayMatches = Self.identity
        return store
    }

    @Test("A flexible profile does not take over a monitor another profile names")
    func flexibleSkipsKnownMonitor() {
        let store = reportedSetup()

        let result = store.profileForAutoApply([info(id: 1, name: "Built-in"), info(id: 2, name: "LG UltraFine")])

        #expect(result == nil, "auto-apply gave the LG the flexible profile's mode")
    }

    @Test("A flexible profile still applies to a monitor no profile knows")
    func flexibleTakesUnknownMonitor() {
        let store = reportedSetup()

        let result = store.profileForAutoApply([info(id: 1, name: "Built-in"), info(id: 3, name: "Projector")])

        #expect(result?.name == "Presentation")
    }

    @Test("A specific profile for exactly what is connected still applies")
    func specificProfileApplies() {
        let store = reportedSetup()
        _ = store.add(Profile(name: "LG desk", entries: [
            entry(Self.builtIn, "Built-in"), entry(Self.lg, "LG UltraFine"),
        ]))

        let result = store.profileForAutoApply([info(id: 1, name: "Built-in"), info(id: 2, name: "LG UltraFine")])

        #expect(result?.name == "LG desk")
    }

    // MARK: - One display, one entry
    //
    // A profile may hold an "any external" row next to specific ones. The
    // flexible row is for the externals the specific rows do not name; it
    // must never also reach the LG, or the LG gets two modes in one
    // transaction and the last one wins.

    /// `CGDisplayMode` has no public initialiser, so the modes come from the
    /// real main display. Nothing is applied to it; the apply is injected.
    private func twoSizes() throws -> (lg: CGDisplayMode, flexible: CGDisplayMode, all: [CGDisplayMode]) {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        let all = try #require(modes, "no display modes available on this machine")
        let lg = try #require(all.first)
        let flexible = try #require(all.first { $0.width != lg.width || $0.height != lg.height },
                                    "need two differently-sized modes")
        return (lg, flexible, all)
    }

    private func sized(_ matcher: DisplayMatcher, _ name: String, _ mode: CGDisplayMode) -> Profile.Entry {
        Profile.Entry(matcher: matcher, displayName: name, pointWidth: mode.width, pointHeight: mode.height,
                      refreshHz: nil, isHiDPI: mode.isHiDPI)
    }

    /// Built-in + LG + a projector nobody saved, all with no current mode so
    /// every bound display is staged.
    private func mixedDesk() throws -> (store: ProfileStore, desk: Profile, displays: [DisplayInfo],
                                        staged: () -> [ResolutionSwitcher.BatchChange],
                                        lg: CGDisplayMode, flexible: CGDisplayMode) {
        let sizes = try twoSizes()
        let store = makeStore()
        store.displayMatches = Self.identity
        var staged: [ResolutionSwitcher.BatchChange] = []
        store.applyBatch = { changes, _ in
            staged.append(contentsOf: changes)
            return ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
        }
        let desk = Profile(name: "Desk", entries: [
            sized(Self.builtIn, "Built-in", sizes.lg),
            sized(Self.lg, "LG UltraFine", sizes.lg),
            sized(.anyExternal, "Any external", sizes.flexible),
        ])
        _ = store.add(desk)
        let displays = [(1, "Built-in"), (2, "LG UltraFine"), (3, "Projector")].map {
            DisplayInfo(id: CGDirectDisplayID($0.0), name: $0.1, isMain: false,
                        modes: sizes.all, currentMode: nil, groups: [])
        }
        return (store, desk, displays, { staged }, sizes.lg, sizes.flexible)
    }

    private func expectOwnModes(_ staged: [ResolutionSwitcher.BatchChange],
                                lg: CGDisplayMode, flexible: CGDisplayMode) {
        let toLG = staged.filter { $0.display == 2 }
        let toProjector = staged.filter { $0.display == 3 }
        #expect(toLG.count == 1, "the LG was given more than one entry's mode")
        #expect(toLG.allSatisfy { $0.mode.width == lg.width && $0.mode.height == lg.height })
        #expect(toProjector.count == 1)
        #expect(toProjector.allSatisfy { $0.mode.width == flexible.width && $0.mode.height == flexible.height })
    }

    @Test("Auto-apply gives the LG its own mode and the flexible mode only to the unsaved monitor")
    func autoApplyMixedProfile() throws {
        let desk = try mixedDesk()

        let result = desk.store.autoApply(to: desk.displays)

        #expect(result != nil, "the mixed profile covers every connected display")
        expectOwnModes(desk.staged(), lg: desk.lg, flexible: desk.flexible)
    }

    @Test("A manual apply gives the LG its own mode and the flexible mode only to the unsaved monitor")
    func manualApplyMixedProfile() throws {
        let desk = try mixedDesk()

        let result = desk.store.applyDetailed(desk.desk, displays: desk.displays)
        let preview = desk.store.previewApply(desk.desk, against: desk.displays)

        expectOwnModes(desk.staged(), lg: desk.lg, flexible: desk.flexible)
        #expect(result.outcomes.filter { $0.displayName == "LG UltraFine" }.count == 1)
        #expect(preview.rows.filter { $0.displayName == "LG UltraFine" }.count == 1)
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

