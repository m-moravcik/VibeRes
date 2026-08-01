import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// Applying a three-monitor profile used to open three separate WindowServer
/// transactions — Begin/Configure/Complete, once per display, in a loop. Each
/// Complete is a full display reconfiguration: the screens go black, come back,
/// and windows get shuffled by the relayout. Three of them in a row is the
/// triple flicker people report, and between the first Complete and the last
/// the desktop is in a geometry that matches no profile at all.
///
/// One transaction with N staged changes is what CoreGraphics offers this for,
/// and `ResolutionSwitcher.apply` has carried a comment promising it since the
/// first commit.
///
/// The transaction itself is injected: a unit test must not reconfigure the
/// machine's displays. What is asserted here is the shape of the call — how
/// many transactions, carrying which displays — and how partial failure is
/// reported back.
@Suite("Batched multi-display apply")
@MainActor
struct BatchApplyTests {
    /// `CGDisplayMode` has no public initialiser, so the modes come from the
    /// real main display. Nothing is applied to it; the apply is injected.
    private func realModes() throws -> [CGDisplayMode] {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        let all = try #require(modes, "no display modes available on this machine")
        // Two modes of different sizes, so "target" is never "current".
        let distinct = all.reduce(into: [CGDisplayMode]()) { acc, mode in
            if !acc.contains(where: { $0.width == mode.width && $0.height == mode.height }) {
                acc.append(mode)
            }
        }
        try #require(distinct.count >= 2, "need two differently-sized modes")
        return distinct
    }

    /// Display IDs deliberately above any real one, so nothing here can name a
    /// display that actually exists.
    ///
    /// The matcher below has to suit them. `.anyExternal` is
    /// `CGDisplayIsBuiltin(id) == 0`, and for an ID that is not a live display
    /// CoreGraphics answers -1, not 0 — sensible for the app (a stale ID must
    /// not match) but it means fake IDs never match `.anyExternal`. Every EDID
    /// field of an unknown ID reads 0xFFFFFFFF instead, uniformly, so an
    /// all-ones EDID matcher is the one that binds to exactly these three on
    /// any machine.
    private let ids: [CGDirectDisplayID] = [101, 102, 103]

    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-batch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    private func info(
        id: CGDirectDisplayID,
        name: String,
        modes: [CGDisplayMode],
        current: CGDisplayMode?
    ) -> DisplayInfo {
        DisplayInfo(id: id, name: name, isMain: false, modes: modes, currentMode: current, groups: [])
    }

    /// A profile whose single entry binds to all three fake displays — the
    /// flexible-matcher shape that produces a genuinely multi-display apply.
    private func profile(target: CGDisplayMode) -> Profile {
        Profile(name: "Desk", entries: [
            Profile.Entry(
                matcher: .edid(vendor: .max, model: .max, serial: .max),
                displayName: "Fake monitor",
                pointWidth: target.width,
                pointHeight: target.height,
                refreshHz: nil,
                isHiDPI: target.isHiDPI
            )
        ])
    }

    @Test("Three displays are reconfigured in one transaction, not three")
    func singleTransactionForThreeDisplays() throws {
        let modes = try realModes()
        let target = modes[0], current = modes[1]
        let store = makeStore()

        var calls: [[ResolutionSwitcher.BatchChange]] = []
        store.applyBatch = { changes, _ in
            calls.append(changes)
            return ResolutionSwitcher.BatchOutcome(
                applied: Set(changes.map(\.display)), rejected: [:]
            )
        }

        let displays = ids.map {
            info(id: $0, name: "Mon \($0)", modes: modes, current: current)
        }
        let outcomes = store.applyDetailed(profile(target: target), displays: displays)

        #expect(calls.count == 1, "one profile apply must be one display reconfiguration")
        #expect(calls.first?.count == 3, "all three displays belong to the same transaction")
        #expect(outcomes.filter { $0.status == .applied }.count == 3)
    }

    @Test("Displays already in the requested mode are left out of the transaction")
    func alreadyAppliedNotStaged() throws {
        let modes = try realModes()
        let target = modes[0]
        let store = makeStore()

        var calls = 0
        store.applyBatch = { changes, _ in
            calls += 1
            return ResolutionSwitcher.BatchOutcome(
                applied: Set(changes.map(\.display)), rejected: [:]
            )
        }

        // Every display is already showing the target mode.
        let displays = ids.prefix(2).map {
            info(id: $0, name: "Mon \($0)", modes: modes, current: target)
        }
        let outcomes = store.applyDetailed(profile(target: target), displays: displays)

        #expect(calls == 0, "a no-op profile must not blank the screens")
        #expect(outcomes.allSatisfy { $0.status == .alreadyApplied })
    }

    @Test("One display rejected in staging does not sink the others")
    func partialRejection() throws {
        let modes = try realModes()
        let target = modes[0], current = modes[1]
        let store = makeStore()

        store.applyBatch = { changes, _ in
            let bad: CGDirectDisplayID = 102
            return ResolutionSwitcher.BatchOutcome(
                applied: Set(changes.map(\.display).filter { $0 != bad }),
                rejected: [bad: .applyMode(.rangeCheck)]
            )
        }

        let displays = ids.map {
            info(id: $0, name: "Mon \($0)", modes: modes, current: current)
        }
        let outcomes = store.applyDetailed(profile(target: target), displays: displays)

        let failed = outcomes.filter(\.isProblem)
        #expect(failed.count == 1)
        #expect(failed.first?.displayName == "Mon 102")
        #expect(outcomes.filter { $0.status == .applied }.count == 2)
    }

    @Test("A transaction that cannot be committed fails every display in it")
    func commitFailureFailsAll() throws {
        let modes = try realModes()
        let target = modes[0], current = modes[1]
        let store = makeStore()

        store.applyBatch = { _, _ in throw ResolutionSwitcher.Failure.completeConfig(.cannotComplete) }

        let displays = ids.map {
            info(id: $0, name: "Mon \($0)", modes: modes, current: current)
        }
        let outcomes = store.applyDetailed(profile(target: target), displays: displays)

        #expect(outcomes.count == 3)
        #expect(outcomes.allSatisfy { $0.isProblem }, "nothing was committed, so nothing succeeded")
    }

    /// The old loop appended to the revert snapshot *before* attempting the
    /// switch and never removed it on failure, so Revert offered to restore
    /// displays that had never changed.
    @Test("Only displays that actually changed are recorded for Revert")
    func revertRecordsOnlyRealChanges() throws {
        let modes = try realModes()
        let target = modes[0], current = modes[1]
        let store = makeStore()
        let history = RevertHistory()

        store.applyBatch = { changes, _ in
            let bad: CGDirectDisplayID = 102
            return ResolutionSwitcher.BatchOutcome(
                applied: Set(changes.map(\.display).filter { $0 != bad }),
                rejected: [bad: .applyMode(.rangeCheck)]
            )
        }

        let displays = ids.map {
            info(id: $0, name: "Mon \($0)", modes: modes, current: current)
        }
        store.applyDetailed(profile(target: target), displays: displays, revert: history)

        #expect(history.entries.map(\.displayID).sorted() == [101, 103],
                "display 102 never changed, so there is nothing to undo on it")
    }

    @Test("A failed commit leaves nothing to revert")
    func noRevertAfterFailedCommit() throws {
        let modes = try realModes()
        let target = modes[0], current = modes[1]
        let store = makeStore()
        let history = RevertHistory()

        store.applyBatch = { _, _ in throw ResolutionSwitcher.Failure.completeConfig(.cannotComplete) }

        let displays = [info(id: ids[0], name: "Mon 101", modes: modes, current: current)]
        store.applyDetailed(profile(target: target), displays: displays, revert: history)

        #expect(!history.canRevert, "offering to undo a change that never happened is a trap")
    }

    @Test("An empty change set never opens a transaction")
    func emptyBatchIsFree() throws {
        // Guards the real implementation, not the seam: Begin/Complete with no
        // staged change still costs a reconfiguration on some machines.
        let outcome = try ResolutionSwitcher.applyBatch([])
        #expect(outcome.applied.isEmpty)
        #expect(outcome.rejected.isEmpty)
    }
}
