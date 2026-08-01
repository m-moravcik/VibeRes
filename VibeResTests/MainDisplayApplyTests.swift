import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// The main-display phase of a profile apply. Transactions and live-state
/// reads are injected (same rationale as BatchApplyTests): asserted here is
/// *when* the origin transaction is attempted, with which plan, and how each
/// guard failure is reported.
///
/// Fake-ID constraint: EDID fields of any unknown ID read all-ones, so the
/// all-ones matcher binds to every fake ID in the arrangement. "Exactly one
/// match" is therefore staged as an arrangement whose *other* member is the
/// one real display on the machine — `CGMainDisplayID()` — whose EDID is not
/// all-ones, leaving fake 101 as the single match.
@Suite("Profile apply — main display phase")
@MainActor
struct MainDisplayApplyTests {
    private let allOnes = DisplayMatcher.edid(vendor: .max, model: .max, serial: .max)
    private let fake: CGDirectDisplayID = 101
    private let realID = CGMainDisplayID()

    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-main-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    /// No entry matches anything live, so the mode phase is a no-op and only
    /// the main phase can act.
    private func profile(main: DisplayMatcher?) -> Profile {
        Profile(
            name: "Desk",
            entries: [Profile.Entry(
                matcher: .edid(vendor: 1, model: 2, serial: 3),
                displayName: "Ghost", pointWidth: 1920, pointHeight: 1080,
                refreshHz: nil, isHiDPI: false
            )],
            mainDisplay: main
        )
    }

    /// Wires the three seams over a mutable fake arrangement and returns
    /// probes into it. `applyOrigins` plays an honest window server: it
    /// honours the plan exactly, so post-commit verification succeeds.
    private struct Probes {
        var originCalls: () -> [[CGDirectDisplayID: CGPoint]]
        var currentMain: () -> CGDirectDisplayID
    }

    private func arrange(
        _ store: ProfileStore,
        main: CGDirectDisplayID,
        bounds: [CGDirectDisplayID: CGRect],
        mirrored: Bool = false,
        failWith: Error? = nil
    ) -> Probes {
        var liveMain = main
        var liveBounds = bounds
        var calls: [[CGDirectDisplayID: CGPoint]] = []
        store.isInMirrorSet = { _ in mirrored }
        store.liveArrangement = { (main: liveMain, bounds: liveBounds) }
        store.applyOrigins = { plan, _ in
            if let failWith { throw failWith }
            calls.append(plan)
            for (id, origin) in plan {
                if var r = liveBounds[id] { r.origin = origin; liveBounds[id] = r }
            }
            if let newMain = plan.first(where: { $0.value == .zero })?.key {
                liveMain = newMain
            }
        }
        return Probes(originCalls: { calls }, currentMain: { liveMain })
    }

    @Test("Exactly-one match commits a full translation and verifies it")
    func happyPath() {
        let store = makeStore()
        let probes = arrange(store, main: realID, bounds: [
            realID: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            fake: CGRect(x: 1074, y: -1080, width: 1920, height: 1080),
        ])

        let history = RevertHistory()
        let result = store.applyDetailed(profile(main: allOnes), displays: [], revert: history)

        #expect(probes.originCalls().count == 1)
        let plan = probes.originCalls().first
        #expect(plan?[fake] == .zero)
        #expect(plan?[realID] == CGPoint(x: -1074, y: 1080))
        #expect(plan?.count == 2, "the plan covers every active display (F1)")
        #expect(result.mainChange == .changed(displayName: "display \(101)"))
        #expect(result.didChangeAnything)
        #expect(probes.currentMain() == fake)
        #expect(history.beforeMainID == realID, "revert must know who was main before")
    }

    @Test("nil mainDisplay never touches arrangement state")
    func nilMainIsInert() {
        let store = makeStore()
        let probes = arrange(store, main: realID, bounds: [realID: .zero])
        var arrangementRead = false
        let inner = store.liveArrangement
        store.liveArrangement = { arrangementRead = true; return inner() }

        let result = store.applyDetailed(profile(main: nil), displays: [])

        #expect(result.mainChange == nil)
        #expect(probes.originCalls().isEmpty)
        #expect(!arrangementRead, "pre-0.9 profiles must not even look at arrangement")
    }

    @Test("Two matching displays are ambiguous — skipped, not guessed")
    func ambiguous() {
        let store = makeStore()
        let probes = arrange(store, main: 103, bounds: [
            101: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            102: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
        ])

        let result = store.applyDetailed(profile(main: allOnes), displays: [])

        #expect(result.mainChange == .skippedAmbiguous(count: 2))
        #expect(probes.originCalls().isEmpty)
        #expect(!result.didChangeAnything)
    }

    @Test("No matching display is reported, not silently ignored")
    func noMatch() {
        let store = makeStore()
        let probes = arrange(store, main: realID, bounds: [realID: .zero])

        let result = store.applyDetailed(
            profile(main: .edid(vendor: 9, model: 9, serial: 9)), displays: [])

        #expect(result.mainChange == .skippedNoMatch)
        #expect(probes.originCalls().isEmpty)
    }

    @Test("Target already main is a no-op, not a transaction")
    func alreadyMain() {
        let store = makeStore()
        let probes = arrange(store, main: fake, bounds: [
            realID: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
            fake: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ])

        let result = store.applyDetailed(profile(main: allOnes), displays: [])

        #expect(result.mainChange == .alreadyMain)
        #expect(probes.originCalls().isEmpty)
        #expect(!result.didChangeAnything)
    }

    @Test("Mirrored displays skip the origin phase — untested territory")
    func mirrored() {
        let store = makeStore()
        let probes = arrange(store, main: realID, bounds: [
            realID: .zero,
            fake: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
        ], mirrored: true)

        let result = store.applyDetailed(profile(main: allOnes), displays: [])

        #expect(result.mainChange == .skippedMirrored)
        #expect(probes.originCalls().isEmpty)
    }

    @Test("A throwing transaction is reported with its user-facing text")
    func transactionFails() {
        let store = makeStore()
        _ = arrange(store, main: realID, bounds: [
            realID: .zero,
            fake: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
        ], failWith: ResolutionSwitcher.Failure.originCoverage)

        let result = store.applyDetailed(profile(main: allOnes), displays: [])

        guard case .failed(let message)? = result.mainChange else {
            Issue.record("expected .failed, got \(String(describing: result.mainChange))")
            return
        }
        #expect(message.contains("arrangement"))
        #expect(!result.didChangeAnything)
    }

    @Test("The display name comes from the snapshot when the target is in it")
    func namedFromSnapshot() {
        let store = makeStore()
        _ = arrange(store, main: realID, bounds: [
            realID: .zero,
            fake: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
        ])
        let info = DisplayInfo(id: fake, name: "LG UltraFine", isMain: false,
                               modes: [], currentMode: nil, groups: [])

        let result = store.applyDetailed(profile(main: allOnes), displays: [info])

        #expect(result.mainChange == .changed(displayName: "LG UltraFine"))
    }
}
