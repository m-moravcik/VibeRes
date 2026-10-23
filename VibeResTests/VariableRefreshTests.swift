import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// Variable refresh rate support (issue #7).
///
/// With Adaptive Sync on, macOS lists a variable and a fixed mode at the
/// panel's top rate that CoreGraphics describes identically. The machine that
/// runs these tests may have no such panel (a ProMotion MacBook has variable
/// modes but no fixed twins), so the twin case is built from stubs, and from
/// real modes that are merely *declared* variable.
@Suite("Variable refresh: bucketing and one-click choice")
struct VariableRefreshBucketingTests {
    /// The reporter's panel: fixed 60 / 95 / 144 / 160 plus Variable up to 160.
    private func adaptiveSync(vrrID: Int32 = 5) -> (modes: [StubDisplayMode], isVariable: (StubDisplayMode) -> Bool) {
        let modes = [
            StubDisplayMode.native(width: 2560, height: 1440, hz: 160, id: 4),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 60, id: 1),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 160, id: vrrID),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 95, id: 2),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 144, id: 3),
        ]
        return (modes, { $0.ioDisplayModeID == vrrID })
    }

    /// A ProMotion panel: fixed 48 / 50 / 60, and 120 only as a variable mode.
    private func proMotion() -> (modes: [StubDisplayMode], isVariable: (StubDisplayMode) -> Bool) {
        let modes = [
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 48, id: 1),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 50, id: 2),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 60, id: 3),
            StubDisplayMode.hiDPI(width: 1800, height: 1169, hz: 120, id: 4),
        ]
        return (modes, { $0.ioDisplayModeID == 4 })
    }

    @Test("A variable and a fixed mode at one rate stay two options")
    func twinsAreNotMerged() {
        let panel = adaptiveSync()
        let options = ResolutionBucketing.bucket(panel.modes, isVariable: panel.isVariable)[0].entries
        #expect(options.count == 5)
        #expect(options.filter { $0.hz == 160 }.map(\.isVariable).sorted { !$0 && $1 } == [false, true])
    }

    @Test("The VRR twin comes after the highest fixed chip")
    func twinSortsLast() {
        let panel = adaptiveSync()
        let options = ResolutionBucketing.bucket(panel.modes, isVariable: panel.isVariable)[0].entries
        #expect(options.map(\.hz) == [60, 95, 144, 160, 160])
        #expect(options.map(\.isVRRTwin) == [false, false, false, false, true])
        #expect(options.last?.mode.ioDisplayModeID == 5)
    }

    @Test("A twin below the top fixed rate still goes after every numbered chip")
    func lowerTwinStillLast() {
        let modes = [
            StubDisplayMode.native(width: 2560, height: 1440, hz: 60, id: 1),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 144, id: 2),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 144, id: 3),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 165, id: 4),
        ]
        let options = ResolutionBucketing.bucket(modes) { $0.ioDisplayModeID == 3 }[0].entries
        #expect(options.map(\.hz) == [60, 144, 165, 144])
        #expect(options.last?.isVRRTwin == true)
    }

    @Test("Which twin survives no longer depends on list order")
    func twinsIndependentOfOrder() {
        let panel = adaptiveSync()
        let options = ResolutionBucketing.bucket(Array(panel.modes.reversed()), isVariable: panel.isVariable)[0].entries
        #expect(options.map(\.mode.ioDisplayModeID) == [1, 2, 3, 4, 5])
    }

    @Test("ProMotion's variable-only 120 Hz keeps its number and its place")
    func twinlessVariableIsANumber() {
        let panel = proMotion()
        let options = ResolutionBucketing.bucket(panel.modes, isVariable: panel.isVariable)[0].entries
        #expect(options.map(\.hz) == [48, 50, 60, 120])
        #expect(options.last?.isVariable == true)
        #expect(options.allSatisfy { !$0.isVRRTwin })
    }

    @Test("NTSC dedup still runs, within each kind only")
    func ntscDedupPerKind() {
        let modes = [
            StubDisplayMode.native(width: 2560, height: 1440, hz: 60.0, id: 1),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 59.94, id: 2),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 119.88, id: 3),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 120.0, id: 4),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 59.94, id: 5),
        ]
        let variable: Set<Int32> = [3, 4, 5]
        let options = ResolutionBucketing.bucket(modes) { variable.contains($0.ioDisplayModeID) }[0].entries
        // Fixed 60 beats fixed 59.94, variable 120 beats variable 119.88, and
        // the variable 59.94 is not swallowed by the fixed 60.
        #expect(options.map(\.mode.ioDisplayModeID) == [1, 4, 5])
        #expect(options.map(\.isVRRTwin) == [false, false, true])
    }

    @Test("Without a detector every mode is fixed, exactly as before")
    func defaultIsAllFixed() {
        let panel = adaptiveSync()
        let options = ResolutionBucketing.bucket(panel.modes)[0].entries
        #expect(options.map(\.hz) == [60, 95, 144, 160])
        #expect(options.allSatisfy { !$0.isVariable })
    }

    // MARK: One-click choice (Simple Mode, the size label)

    private func preferred(
        _ panel: (modes: [StubDisplayMode], isVariable: (StubDisplayMode) -> Bool),
        currentIsVariable: Bool
    ) -> RefreshOption<StubDisplayMode>? {
        let options = ResolutionBucketing.bucket(panel.modes, isVariable: panel.isVariable)[0].entries
        return ResolutionBucketing.preferredOption(in: options, currentIsVariable: currentIsVariable)
    }

    @Test("A display on VRR stays on VRR")
    func variableStaysVariable() {
        let pick = preferred(adaptiveSync(), currentIsVariable: true)
        #expect(pick?.isVariable == true)
        #expect(pick?.mode.ioDisplayModeID == 5)
    }

    @Test("A display on a fixed rate gets the fixed twin of the highest rate")
    func fixedPrefersFixedTwin() {
        let pick = preferred(adaptiveSync(), currentIsVariable: false)
        #expect(pick?.hz == 160)
        #expect(pick?.isVariable == false)
        // Whichever ID the variable mode has.
        #expect(preferred(adaptiveSync(vrrID: 0), currentIsVariable: false)?.isVariable == false)
    }

    @Test("On VRR, a size without a variable option gets its highest rate")
    func variableWithoutVariableOption() {
        let modes = [
            StubDisplayMode.native(width: 1920, height: 1080, hz: 60, id: 1),
            StubDisplayMode.native(width: 1920, height: 1080, hz: 144, id: 2),
        ]
        let pick = preferred((modes, { _ in false }), currentIsVariable: true)
        #expect(pick?.hz == 144)
    }

    @Test("ProMotion at 60 Hz still gets 120 Hz from one click, as before")
    func proMotionHighestIsVariable() {
        let pick = preferred(proMotion(), currentIsVariable: false)
        #expect(pick?.hz == 120)
        #expect(pick?.isVariable == true)
    }

    @Test("A variable display picks its highest variable option")
    func highestVariable() {
        let modes = [
            StubDisplayMode.native(width: 2560, height: 1440, hz: 144, id: 1),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 144, id: 2),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 165, id: 3),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 165, id: 4),
        ]
        let variable: Set<Int32> = [2, 4]
        let pick = preferred((modes, { variable.contains($0.ioDisplayModeID) }), currentIsVariable: true)
        #expect(pick?.mode.ioDisplayModeID == 4)
    }

    @Test("No options, no choice")
    func emptyOptions() {
        #expect(VariableRefresh.preferredIndex([], stayVariable: true) == nil)
        #expect(VariableRefresh.preferredIndex([], stayVariable: false) == nil)
    }
}

@Suite("Variable refresh: kind rules and scoring")
struct VariableRefreshRuleTests {
    @Test("A variable entry is honoured only by a variable mode")
    func variableEntry() {
        #expect(VariableRefresh.honoursKind(wantsVariable: true, modeIsVariable: true, modeHasFixedTwin: true))
        #expect(VariableRefresh.honoursKind(wantsVariable: true, modeIsVariable: true, modeHasFixedTwin: false))
        #expect(!VariableRefresh.honoursKind(wantsVariable: true, modeIsVariable: false, modeHasFixedTwin: false))
    }

    @Test("A fixed (or legacy) entry accepts a variable mode only when no fixed twin exists")
    func fixedEntry() {
        #expect(VariableRefresh.honoursKind(wantsVariable: false, modeIsVariable: false, modeHasFixedTwin: false))
        #expect(VariableRefresh.honoursKind(wantsVariable: false, modeIsVariable: true, modeHasFixedTwin: false))
        #expect(!VariableRefresh.honoursKind(wantsVariable: false, modeIsVariable: true, modeHasFixedTwin: true))
    }

    @Test("A fixed twin must match size, scale and rounded rate")
    func fixedTwin() {
        let vrr = StubDisplayMode.native(width: 2560, height: 1440, hz: 160, id: 9)
        let isVariable: (StubDisplayMode) -> Bool = { $0.ioDisplayModeID == 9 }
        let twin = StubDisplayMode.native(width: 2560, height: 1440, hz: 159.97, id: 1)
        #expect(VariableRefresh.hasFixedTwin(vrr, in: [vrr, twin], isVariable: isVariable))
        #expect(!VariableRefresh.hasFixedTwin(vrr, in: [vrr], isVariable: isVariable))
        let otherRate = StubDisplayMode.native(width: 2560, height: 1440, hz: 144, id: 2)
        let otherScale = StubDisplayMode.hiDPI(width: 2560, height: 1440, hz: 160, id: 3)
        #expect(!VariableRefresh.hasFixedTwin(vrr, in: [vrr, otherRate, otherScale], isVariable: isVariable))
    }

    private func best(
        _ modes: [StubDisplayMode],
        hz: Int?,
        preferVariable: Bool,
        variable: Set<Int32>
    ) -> Int32? {
        ModeScoring.bestMatch(
            in: modes,
            request: ModeScoring.Request(
                width: 2560, height: 1440, refreshHz: hz,
                preferHiDPI: false, preferVariable: preferVariable
            ),
            isVariable: { variable.contains($0.ioDisplayModeID) }
        )?.ioDisplayModeID
    }

    private let twins = [
        StubDisplayMode.native(width: 2560, height: 1440, hz: 60, id: 1),
        StubDisplayMode.native(width: 2560, height: 1440, hz: 160, id: 2),
        StubDisplayMode.native(width: 2560, height: 1440, hz: 160, id: 3),
    ]

    @Test("Scoring picks the twin of the requested kind, whatever the mode IDs")
    func scoringPicksKind() {
        for variable: Int32 in [2, 3] {
            let fixed: Int32 = variable == 2 ? 3 : 2
            #expect(best(twins, hz: 160, preferVariable: true, variable: [variable]) == variable)
            #expect(best(twins, hz: 160, preferVariable: false, variable: [variable]) == fixed)
            // No rate asked for: highest rate first, then the kind.
            #expect(best(twins, hz: nil, preferVariable: true, variable: [variable]) == variable)
            #expect(best(twins, hz: nil, preferVariable: false, variable: [variable]) == fixed)
        }
    }

    @Test("The kind never outweighs the rate")
    func kindIsOnlyATieBreak() {
        let modes = [
            StubDisplayMode.native(width: 2560, height: 1440, hz: 144, id: 1),
            StubDisplayMode.native(width: 2560, height: 1440, hz: 160, id: 2),
        ]
        #expect(best(modes, hz: 160, preferVariable: true, variable: [1]) == 2)
    }

    @Test("Without a detector scoring is what it was")
    func scoringDefault() {
        let pick = ModeScoring.bestMatch(
            in: twins,
            request: ModeScoring.Request(width: 2560, height: 1440, refreshHz: 160, preferHiDPI: false)
        )
        #expect(pick?.ioDisplayModeID == 2)
    }
}

@Suite("Variable refresh: profile persistence and copy")
struct VariableRefreshProfileCodingTests {
    private func entry(variable: Bool) -> Profile.Entry {
        Profile.Entry(
            matcher: .edid(vendor: 1, model: 2, serial: 3),
            displayName: "Adaptive",
            pointWidth: 2560, pointHeight: 1440,
            refreshHz: 160, isHiDPI: false,
            isVariableRefresh: variable
        )
    }

    @Test("An entry saved before VRR support decodes as fixed")
    func legacyDecodesFixed() throws {
        let json = """
        {"matcher":{"kind":"edid","vendor":1,"model":2,"serial":3},
         "displayName":"Old","pointWidth":2560,"pointHeight":1440,"refreshHz":160,"isHiDPI":false}
        """
        let decoded = try JSONDecoder().decode(Profile.Entry.self, from: Data(json.utf8))
        #expect(decoded.isVariableRefresh == false)
        #expect(decoded.refreshHz == 160)
    }

    @Test("A fixed entry encodes without the new key, byte-compatible with older builds")
    func fixedOmitsKey() throws {
        let data = try JSONEncoder().encode(entry(variable: false))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["variableRefresh"] == nil)
    }

    @Test("A variable entry round-trips")
    func variableRoundTrips() throws {
        let data = try JSONEncoder().encode(entry(variable: true))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["variableRefresh"] as? Bool == true)
        #expect(try JSONDecoder().decode(Profile.Entry.self, from: data) == entry(variable: true))
    }

    @Test("Fixed and variable entries at one rate are different entries")
    func kindIsPartOfEquality() {
        #expect(entry(variable: true) != entry(variable: false))
    }

    @Test("A mode string says VRR only when asked to")
    func modeStringVRR() {
        #expect(ApplyOutcomeNote.modeString(width: 2560, height: 1440, hz: 160) == "2560×1440 @160Hz")
        #expect(ApplyOutcomeNote.modeString(width: 2560, height: 1440, hz: 160, vrr: true) == "2560×1440 @160Hz VRR")
        #expect(ApplyOutcomeNote.modeString(width: 2560, height: 1440, hz: nil, vrr: true) == "2560×1440")
    }

    @Test("A VRR fallback says what was wanted and what was used")
    func fallbackSummarySaysVRR() {
        let outcome = ProfileStore.ApplyOutcome(
            displayName: "Adaptive",
            matcherKind: .specific,
            requestedSize: PointSize(width: 2560, height: 1440),
            requestedHz: 160,
            appliedSize: PointSize(width: 2560, height: 1440),
            appliedHz: 160,
            status: .appliedWithFallback,
            requestedVRR: true,
            appliedVRR: false
        )
        #expect(outcome.summary == "Adaptive: wanted 2560×1440 @160Hz VRR, used 2560×1440 @160Hz (closest available)")
    }
}

/// `ProfileStore` against real `CGDisplayMode`s, which have no public
/// initialiser. Two modes the main display lists at one size, scale and
/// rounded rate (60 and 59.94 Hz, typically) stand in for a VRR twin once one
/// of them is declared variable through `DisplayInfo.variableModeIDs`. Nothing
/// is applied: the transaction is injected, as in `BatchApplyTests`.
@Suite("Variable refresh: profile apply and active state", .enabled(if: RealTwins.available))
@MainActor
struct VariableRefreshProfileApplyTests {
    private let allOnes = DisplayMatcher.edid(vendor: .max, model: .max, serial: .max)

    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-vrr-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    private func info(
        _ set: RealTwins.Modes,
        current: CGDisplayMode?,
        variable: [CGDisplayMode]
    ) -> DisplayInfo {
        DisplayInfo(
            id: 101, name: "Adaptive", isMain: false,
            modes: set.modes, currentMode: current, groups: [],
            variableModeIDs: Set(variable.map(\.ioDisplayModeID))
        )
    }

    private func entry(for mode: CGDisplayMode, variable: Bool) -> Profile.Entry {
        Profile.Entry(
            matcher: allOnes, displayName: "Adaptive",
            pointWidth: mode.width, pointHeight: mode.height,
            refreshHz: mode.refreshHz, isHiDPI: mode.isHiDPI,
            isVariableRefresh: variable
        )
    }

    /// Records which mode the store would have committed.
    private func capturing(_ store: ProfileStore) -> () -> [Int32] {
        var staged: [Int32] = []
        store.applyBatch = { changes, _ in
            staged.append(contentsOf: changes.map(\.mode.ioDisplayModeID))
            return ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
        }
        return { staged }
    }

    @Test("A variable entry applies the VRR twin, a fixed one the fixed twin")
    func applyPicksTwinOfEntryKind() throws {
        let set = try #require(RealTwins.find())
        // Both ways round, so the result cannot be the mode-ID tie-break.
        for (variable, fixed) in [(set.first, set.second), (set.second, set.first)] {
            let display = info(set, current: set.other, variable: [variable])

            let vrrStore = makeStore()
            let vrrStaged = capturing(vrrStore)
            let vrr = vrrStore.applyDetailed(
                Profile(name: "VRR", entries: [entry(for: variable, variable: true)]),
                displays: [display]
            ).outcomes
            #expect(vrrStaged() == [variable.ioDisplayModeID])
            #expect(vrr.first?.status == .applied)
            #expect(vrr.first?.appliedVRR == true)

            let fixedStore = makeStore()
            let fixedStaged = capturing(fixedStore)
            let plain = fixedStore.applyDetailed(
                Profile(name: "Fixed", entries: [entry(for: fixed, variable: false)]),
                displays: [display]
            ).outcomes
            #expect(fixedStaged() == [fixed.ioDisplayModeID])
            #expect(plain.first?.status == .applied)
            #expect(plain.first?.appliedVRR == false)
        }
    }

    @Test("A variable entry with no VRR mode on offer falls back to the fixed one, and says so")
    func variableFallsBackToFixed() throws {
        let set = try #require(RealTwins.find())
        let store = makeStore()
        let staged = capturing(store)
        let outcome = store.applyDetailed(
            Profile(name: "VRR", entries: [entry(for: set.first, variable: true)]),
            displays: [info(set, current: set.other, variable: [])]
        ).outcomes.first
        #expect(staged().count == 1)
        #expect(outcome?.status == .appliedWithFallback)
        #expect(outcome?.requestedVRR == true)
        #expect(outcome?.appliedVRR == false)
        #expect(outcome?.summary.contains("Hz VRR, used") == true)
    }

    @Test("VRR and fixed at one rate are not the same active state")
    func activeStateHonoursKind() throws {
        let set = try #require(RealTwins.find())
        let store = makeStore()
        let onVRR = info(set, current: set.first, variable: [set.first])
        let onFixed = info(set, current: set.second, variable: [set.first])

        let fixedProfile = Profile(name: "Fixed", entries: [entry(for: set.second, variable: false)])
        let vrrProfile = Profile(name: "VRR", entries: [entry(for: set.first, variable: true)])

        #expect(!store.isCurrentState(fixedProfile, displays: [onVRR]))
        #expect(store.isCurrentState(fixedProfile, displays: [onFixed]))
        #expect(store.isCurrentState(vrrProfile, displays: [onVRR]))
        #expect(!store.isCurrentState(vrrProfile, displays: [onFixed]))
    }

    @Test("A legacy entry on a variable-only rate (ProMotion) is active and applies cleanly")
    func legacyEntryOnVariableOnlyRate() throws {
        let set = try #require(RealTwins.find())
        // `other` has no twin: declared variable, it is ProMotion's 120 Hz.
        let display = info(set, current: set.first, variable: [set.other])
        let legacy = Profile(name: "Legacy", entries: [entry(for: set.other, variable: false)])
        let store = makeStore()
        let staged = capturing(store)

        let outcome = store.applyDetailed(legacy, displays: [display]).outcomes.first
        #expect(staged() == [set.other.ioDisplayModeID])
        #expect(outcome?.status == .applied)
        #expect(outcome?.appliedVRR == false, "no fixed twin, so nothing to call VRR")

        let after = info(set, current: set.other, variable: [set.other])
        #expect(store.isCurrentState(legacy, displays: [after]))
    }

    @Test("Saving on a VRR mode remembers it")
    func captureRemembersVariable() throws {
        let set = try #require(RealTwins.find())
        let store = makeStore()
        let display = info(set, current: set.first, variable: [set.first])
        _ = store.captureCurrent(name: "Adaptive", displays: [display], selection: [101: .specific])
        #expect(store.profiles.first?.entries.first?.isVariableRefresh == true)
    }

    @Test("The preview names VRR on the saved side when it will fall back")
    func previewSaysVRR() throws {
        let set = try #require(RealTwins.find())
        let store = makeStore()
        let preview = store.previewApply(
            Profile(name: "VRR", entries: [entry(for: set.first, variable: true)]),
            against: [info(set, current: set.other, variable: [])]
        )
        let row = try #require(preview.rows.first)
        #expect(row.savedVRR)
        #expect(!row.targetVRR)
        if case .willApplyFallback = row.action {} else {
            Issue.record("expected a fallback, got \(row.action)")
        }
    }

    @Test("Group equality sees a change of kind at an unchanged rate")
    func groupEqualityIncludesKind() throws {
        let set = try #require(RealTwins.find())
        let fixed = ResolutionGroup.build(from: [set.first])
        let variable = ResolutionGroup.build(from: [set.first]) { _ in true }
        #expect(fixed.map(\.id) == variable.map(\.id))
        #expect(fixed != variable)
    }
}

/// Finds the stand-in twins on the machine running the tests.
enum RealTwins {
    struct Modes {
        let first: CGDisplayMode
        let second: CGDisplayMode
        /// A mode of a different size, with no other mode at its size, scale
        /// and rate.
        let other: CGDisplayMode
        let modes: [CGDisplayMode]
    }

    static var available: Bool { find() != nil }

    static func find() -> Modes? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), options) as? [CGDisplayMode] else {
            return nil
        }
        func key(_ m: CGDisplayMode) -> String { "\(m.width)x\(m.height)-\(m.isHiDPI)-\(m.refreshHz ?? 0)" }
        let byKey = Dictionary(grouping: modes, by: key)
        guard let pair = byKey.values.first(where: { $0.count >= 2 }),
              let other = modes.first(where: {
                  byKey[key($0)]?.count == 1 && ($0.width != pair[0].width || $0.height != pair[0].height)
              })
        else { return nil }
        // Only the pair and the loner: any further mode at the pair's key
        // would be a second fixed twin and blur what is being asserted.
        return Modes(first: pair[0], second: pair[1], other: other, modes: [pair[0], pair[1], other])
    }
}
