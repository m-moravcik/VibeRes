# Main Display in a Profile (Stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A profile can optionally pin which display becomes main (hosts the menu bar) when applied, with a working Revert, without storing any geometry.

**Architecture:** Two-phase apply. Phase 1 is the existing mode transaction in `ResolutionSwitcher.applyBatch` — untouched, still per-display tolerant. Phase 2 (only when `Profile.mainDisplay` is set) reads the **live post-mode arrangement**, translates every active display's origin so the target lands at (0,0), and commits all origins in a new, separate, **all-or-nothing** transaction (`ResolutionSwitcher.applyOrigins`). Pure planning/guards live in a new `MainDisplayPlanner`; `ProfileStore.applyDetailed` orchestrates and reports a `MainChangeOutcome` alongside the per-display outcomes.

**Why two-phase instead of extending `applyBatch` with origins (what the spike doc sketched):**
1. Mode changes alter sizes in points. A translation of *pre-mode* bounds combined with new sizes can describe gaps/overlaps — a plan shape the spike never measured (F3 only measured a correctly reflowed plan). Translating the *post-mode* live arrangement is exactly the measured-safe shape (F2: complete, consistent, applies exactly).
2. Modes must stay per-display tolerant; origins must be all-or-nothing (F1, F6). One transaction carrying both would need cancel-and-retry gymnastics when an origin is refused at staging or the commit dies on a vanished display. Two transactions keep both semantics with zero change to the proven mode path.
3. Cost: one extra reconfiguration, only when the profile actually changes main. Task 0 observes how visible an origin-only reconfigure is.

**Tech Stack:** Swift 6, CoreGraphics display-configuration API, SwiftUI (MenuBarExtra), Swift Testing (`import Testing`, `@Test`, `#expect`), xcodegen (`make test` regenerates the project, so new files are picked up automatically).

## Global Constraints

- Spike findings are law: F1 partial origin change mangles silently; F2 complete translation applies exactly; F5 return code is not evidence — re-read `CGDisplayBounds`; F6 a vanished display kills the whole origin transaction at commit; F7 gate on `CGGetActiveDisplayList` immediately before `CGBeginDisplayConfiguration`. See `docs/display-arrangement-spike-2026-08-01.md`.
- Origins: all-or-nothing, must cover **every active display**. Modes: keep existing per-display graceful degradation. Never regress the mode path.
- `VibeRes/Core/` is compiled into the bundle-less `viberes` CLI: no SwiftUI, no String Catalog lookups there; user-facing Core strings stay English. Localised copy belongs in `VibeRes/UI/` (see `ApplyOutcomeNote.swift` header).
- `Profile.mainDisplay` never participates in profile matching, auto-apply specificity, or `hasMatchingDisplay`.
- Default is always "Don't change": existing profiles decode with `mainDisplay == nil` and behave exactly as today.
- Arrangement combined with mirroring or with inactive (asleep/clamshell) displays is untested territory — skip the origin phase in those states, never guess.
- Unit tests must not reconfigure real displays: inject transactions via closures (pattern: `ProfileStore.applyBatch` seam, `VibeResTests/BatchApplyTests.swift`). Fake display IDs 101–103 with an all-ones `.edid` matcher bind on any machine; `.anyExternal` never matches fake IDs; `CGDisplayIsBuiltin(fakeID)` returns -1 (truthy).
- Test suite: `make test` (xcodebuild, scheme VibeRes). Single suite: `xcodebuild -project VibeRes.xcodeproj -scheme VibeRes test -only-testing:VibeResTests/<SuiteName>` after `xcodegen generate`.
- Commit messages: English, imperative, concise. No new dependencies.
- Ships as 0.9.0 (dedicated release per BACKLOG.md decision rule), not a 0.8.x patch.

---

### Task 0: Close the `.forSession` unknown with the existing spike

**Files:**
- No source changes. Uses `scripts/display-arrangement-spike.swift` as-is (its `mainfull` mode already accepts a `session` scope argument).
- Modify: `docs/display-arrangement-spike-2026-08-01.md` (record results)

**Interfaces:**
- Produces: a recorded F8 finding on `.forSession` origin behaviour. Stage 1 itself does not use `.forSession` (profile applies are `.permanently`, revert is an explicit re-apply), so **this task gates nothing in Tasks 1–9** — it closes the spike unknown that would gate a future "Keep this arrangement? 15 s" countdown, and it measures how visible an origin-only reconfigure is (phase-2 UX cost).

⚠️ Manual task: mutates the live desktop. Requires ≥2 awake displays and the user present.

- [ ] **Step 1: Build the spike**

```bash
cd /Users/moravcikmi/Projects/VibeRes
swiftc -O -o /tmp/spike scripts/display-arrangement-spike.swift -framework AppKit -framework CoreGraphics
/tmp/spike state
```
Expected: exit 0, ≥2 active displays listed. If fewer, stop the task — rerun when docked.

- [ ] **Step 2: `.forSession` full renormalisation with explicit restore**

```bash
/tmp/spike mainfull session
```
Record: were all origins EXACT? did main + menu bar move? did the explicit restore verify OK? Also note the *visual* character of the origin-only transactions (hard blank vs. brief fade) — this is the phase-2 UX cost.

- [ ] **Step 3: `.forSession` survival across process exit**

```bash
/tmp/spike mainfull session norestore
/tmp/spike state   # after the first command exits
```
Expected if `.forSession` behaves as documented: the arrangement change **survives** process exit (unlike `.forAppOnly`, F4) and would revert only at logout. Record what actually happened, then restore:

```bash
/tmp/spike setall <id>:<x>:<y> ...   # values printed by the norestore run
/tmp/spike state                     # verify original arrangement is back
```

- [ ] **Step 4: Record results in the spike doc**

Append an `### F8 — .forSession behaviour with origins` section to `docs/display-arrangement-spike-2026-08-01.md` with the actual output, and delete the `.forSession` bullet from "What is still unknown". Note the observed visual cost of an origin-only transaction.

- [ ] **Step 5: Commit**

```bash
git add docs/display-arrangement-spike-2026-08-01.md
git commit -m "Record .forSession origin behaviour measured with the spike"
```

---

### Task 1: `Profile.mainDisplay` field

**Files:**
- Modify: `VibeRes/Core/Profile.swift:94-98` (property) and `:221-226` (init)
- Test: `VibeResTests/ProfileMainDisplayTests.swift` (create)

**Interfaces:**
- Produces: `Profile.mainDisplay: DisplayMatcher?` and `Profile.init(id:name:entries:createdAt:mainDisplay:)` with `mainDisplay` defaulting to `nil`. All later tasks read/write this property.
- `Profile` uses **synthesised** Codable (only `Profile.Entry` has a custom decoder), so an optional stored property decodes via `decodeIfPresent` semantics automatically — legacy JSON yields `nil`, and `nil` is omitted on encode.

- [ ] **Step 1: Write the failing tests**

Create `VibeResTests/ProfileMainDisplayTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// `mainDisplay` is the 0.9.0 arrangement field. Pre-0.9 profile JSON has no
/// such key, and hand-written JSON may add one — both must round-trip.
@Suite("Profile.mainDisplay coding")
struct ProfileMainDisplayTests {
    @Test("Legacy JSON without mainDisplay decodes to nil")
    func legacyDecodesNil() throws {
        let json = Data("""
        {"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"Desk","createdAt":0,
         "entries":[{"matcher":{"kind":"anyExternal"},"displayName":"LG",
                     "pointWidth":2560,"pointHeight":1440,"isHiDPI":false}]}
        """.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.mainDisplay == nil)
    }

    @Test("mainDisplay survives an encode/decode round trip")
    func roundTrip() throws {
        let profile = Profile(
            name: "Desk",
            entries: [Profile.Entry(
                matcher: .anyExternal, displayName: "LG",
                pointWidth: 2560, pointHeight: 1440, refreshHz: 60, isHiDPI: false
            )],
            mainDisplay: .edid(vendor: 1, model: 2, serial: 3)
        )
        let data = try JSONEncoder().encode(profile)
        let back = try JSONDecoder().decode(Profile.self, from: data)
        #expect(back.mainDisplay == .edid(vendor: 1, model: 2, serial: 3))
    }

    @Test("Default init leaves mainDisplay nil")
    func defaultNil() {
        let profile = Profile(name: "Desk", entries: [])
        #expect(profile.mainDisplay == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `make test`
Expected: compile error — `Profile` has no member `mainDisplay`.

- [ ] **Step 3: Implement**

In `VibeRes/Core/Profile.swift`, after `var createdAt: Date` (line 98):

```swift
    /// Which display should become main (host the menu bar) when this profile
    /// is applied. `nil` — the default and the value every pre-0.9 profile
    /// decodes to — means the arrangement is never touched. Resolved against
    /// live displays at apply time and honoured only when it binds to exactly
    /// one of them; no geometry is stored.
    var mainDisplay: DisplayMatcher?
```

Replace the init (lines 221–226):

```swift
    init(
        id: UUID = UUID(),
        name: String,
        entries: [Entry],
        createdAt: Date = Date(),
        mainDisplay: DisplayMatcher? = nil
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
        self.mainDisplay = mainDisplay
    }
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: PASS (all suites — the field must not disturb existing Profile tests).

- [ ] **Step 5: Commit**

```bash
git add VibeRes/Core/Profile.swift VibeResTests/ProfileMainDisplayTests.swift
git commit -m "Add optional mainDisplay matcher to Profile"
```

---

### Task 2: `MainDisplayPlanner` — pure resolution, translation, verification

**Files:**
- Create: `VibeRes/Core/MainDisplayPlanner.swift`
- Test: `VibeResTests/MainDisplayPlannerTests.swift` (create)

**Interfaces:**
- Produces:
  - `MainDisplayPlanner.resolveTarget(_ matcher: DisplayMatcher, activeIDs: [CGDirectDisplayID]) -> Resolution` where `Resolution` is `case target(CGDirectDisplayID)`, `case noMatch`, `case ambiguous(count: Int)`
  - `MainDisplayPlanner.plan(bounds: [CGDirectDisplayID: CGRect], target: CGDirectDisplayID) -> [CGDirectDisplayID: CGPoint]?`
  - `MainDisplayPlanner.verified(plan: [CGDirectDisplayID: CGPoint], actualBounds: [CGDirectDisplayID: CGRect]) -> Bool`
- Consumes: `DisplayMatcher.matches(_:)` from `VibeRes/Core/Profile.swift`.

- [ ] **Step 1: Write the failing tests**

Create `VibeResTests/MainDisplayPlannerTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import VibeRes

/// The planner is the pure half of the main-display feature: which display the
/// matcher means, how every origin must move so it lands at (0,0), and whether
/// the window server actually did what was asked (spike F5: the return code is
/// not evidence). The expected origins below are the spike's F2 measurement.
@Suite("Main display planning")
struct MainDisplayPlannerTests {
    // Fake IDs, per BatchApplyTests: EDID fields of an unknown ID read all-ones,
    // so the all-ones matcher binds to every fake ID; a non-all-ones one to none.
    private let allOnes = DisplayMatcher.edid(vendor: .max, model: .max, serial: .max)

    @Test("Matcher binding exactly one active display resolves to it")
    func exactlyOne() {
        #expect(MainDisplayPlanner.resolveTarget(allOnes, activeIDs: [101]) == .target(101))
    }

    @Test("Matcher binding several displays is ambiguous, not a coin flip")
    func ambiguous() {
        #expect(MainDisplayPlanner.resolveTarget(allOnes, activeIDs: [101, 102, 103])
            == .ambiguous(count: 3))
    }

    @Test("Matcher binding nothing reports noMatch")
    func noMatch() {
        let unmatched = DisplayMatcher.edid(vendor: 1, model: 2, serial: 3)
        #expect(MainDisplayPlanner.resolveTarget(unmatched, activeIDs: [101, 102]) == .noMatch)
    }

    @Test("Plan is a pure translation putting the target at (0,0) — spike F2 layout")
    func translationMatchesSpikeF2() {
        let bounds: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            2: CGRect(x: 1074, y: -1080, width: 1920, height: 1080),
            3: CGRect(x: -1486, y: -1440, width: 2560, height: 1440),
        ]
        let plan = MainDisplayPlanner.plan(bounds: bounds, target: 2)
        #expect(plan?[1] == CGPoint(x: -1074, y: 1080))
        #expect(plan?[2] == .zero)
        #expect(plan?[3] == CGPoint(x: -2560, y: -360))
        #expect(plan?.count == 3, "every active display gets an origin (F1)")
    }

    @Test("Plan for a target with no bounds entry is refused")
    func planNeedsTargetBounds() {
        #expect(MainDisplayPlanner.plan(bounds: [1: .zero], target: 2) == nil)
    }

    @Test("Verification accepts the exact arrangement and nothing else")
    func verification() {
        let plan: [CGDirectDisplayID: CGPoint] = [1: .zero, 2: CGPoint(x: -1280, y: 0)]
        let exact: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            2: CGRect(x: -1280, y: 0, width: 1280, height: 720),
        ]
        #expect(MainDisplayPlanner.verified(plan: plan, actualBounds: exact))

        var snapped = exact
        snapped[2] = CGRect(x: -1920, y: 0, width: 1280, height: 720)
        #expect(!MainDisplayPlanner.verified(plan: plan, actualBounds: snapped))

        #expect(!MainDisplayPlanner.verified(plan: plan, actualBounds: [1: exact[1]!]),
                "a display missing from the read-back is a failed verification")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `make test`
Expected: compile error — `MainDisplayPlanner` not found.

- [ ] **Step 3: Implement**

Create `VibeRes/Core/MainDisplayPlanner.swift`:

```swift
import CoreGraphics
import Foundation

/// Pure planning for "main display in a profile".
///
/// Setting the main display on macOS is not an API call — it is a statement
/// about the whole arrangement: whichever display sits at (0,0) is main. The
/// spike (docs/display-arrangement-spike-2026-08-01.md) measured that a
/// partial origin change is silently mangled (F1) while a complete translated
/// arrangement applies exactly (F2). Everything here is therefore a
/// full-coverage translation of the live arrangement, derived at apply time —
/// no geometry is ever stored.
enum MainDisplayPlanner {
    enum Resolution: Equatable {
        case target(CGDirectDisplayID)
        case noMatch
        case ambiguous(count: Int)
    }

    /// The single active display the profile's main matcher binds to.
    ///
    /// Exactly-one is a hard rule: zero means the monitor is not there; two or
    /// more (an `.anyExternal` matcher with two externals attached, or twin
    /// monitors with identical EDID) means the user's intent is unknowable,
    /// and guessing would move their menu bar on a coin flip.
    static func resolveTarget(
        _ matcher: DisplayMatcher,
        activeIDs: [CGDirectDisplayID]
    ) -> Resolution {
        let matches = activeIDs.filter { matcher.matches($0) }
        switch matches.count {
        case 0: return .noMatch
        case 1: return .target(matches[0])
        default: return .ambiguous(count: matches.count)
        }
    }

    /// Translates every display's origin so `target` lands at (0,0).
    ///
    /// A pure translation preserves relative topology by construction — no
    /// stored geometry, no reflow, no gaps. Nil when the target has no bounds
    /// entry, because a plan that does not include its own target is exactly
    /// the partial statement F1 warns about.
    static func plan(
        bounds: [CGDirectDisplayID: CGRect],
        target: CGDirectDisplayID
    ) -> [CGDirectDisplayID: CGPoint]? {
        guard let t = bounds[target] else { return nil }
        var out: [CGDirectDisplayID: CGPoint] = [:]
        for (id, r) in bounds {
            out[id] = CGPoint(x: r.origin.x - t.origin.x, y: r.origin.y - t.origin.y)
        }
        return out
    }

    /// F5: a successful commit is not evidence that the request was honoured.
    /// Compare what was asked for with what the window server actually did.
    static func verified(
        plan: [CGDirectDisplayID: CGPoint],
        actualBounds: [CGDirectDisplayID: CGRect]
    ) -> Bool {
        plan.allSatisfy { id, origin in
            guard let r = actualBounds[id] else { return false }
            return r.origin.x == origin.x && r.origin.y == origin.y
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add VibeRes/Core/MainDisplayPlanner.swift VibeResTests/MainDisplayPlannerTests.swift
git commit -m "Add pure planner for main-display resolution and origin translation"
```

---

### Task 3: `ResolutionSwitcher.applyOrigins` — the all-or-nothing origin transaction

**Files:**
- Modify: `VibeRes/Core/ResolutionSwitcher.swift` (Failure enum lines 5–39; new functions after `applyBatch`)
- Test: `VibeResTests/ApplyOriginsTests.swift` (create)

**Interfaces:**
- Produces:
  - `ResolutionSwitcher.applyOrigins(_ plan: [CGDirectDisplayID: CGPoint], scope: CGConfigureOption = .permanently, activeIDs: [CGDirectDisplayID]? = nil) throws`
  - `ResolutionSwitcher.activeDisplayIDs() -> [CGDirectDisplayID]`
  - New `Failure` cases: `.applyOrigin(CGError)`, `.originCoverage`
- The `activeIDs` parameter exists solely so tests can drive the coverage guard without touching WindowServer; production callers omit it.

- [ ] **Step 1: Write the failing tests**

Create `VibeResTests/ApplyOriginsTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import VibeRes

/// Only the guard is unit-testable — everything past it is a live WindowServer
/// transaction (covered by the manual checklist in the plan's final task).
/// The guard is also the safety property: an origin plan that does not cover
/// every active display must never reach CGBeginDisplayConfiguration, because
/// a partial arrangement statement is silently mangled (spike F1) and a
/// vanished display kills the commit outright (F6).
@Suite("Origin transaction coverage guard")
struct ApplyOriginsTests {
    @Test("A plan missing an active display is refused before any CG call")
    func partialPlanRefused() {
        #expect(throws: ResolutionSwitcher.Failure.originCoverage) {
            try ResolutionSwitcher.applyOrigins(
                [101: .zero],
                activeIDs: [101, 102]
            )
        }
    }

    @Test("A plan naming a display that is not active is refused")
    func stalePlanRefused() {
        #expect(throws: ResolutionSwitcher.Failure.originCoverage) {
            try ResolutionSwitcher.applyOrigins(
                [101: .zero, 102: CGPoint(x: 1800, y: 0)],
                activeIDs: [101]
            )
        }
    }

    @Test("An empty plan is refused")
    func emptyPlanRefused() {
        #expect(throws: ResolutionSwitcher.Failure.originCoverage) {
            try ResolutionSwitcher.applyOrigins([:], activeIDs: [])
        }
    }

    @Test("Coverage failure explains itself without a numeric code")
    func coverageCopy() {
        let text = ResolutionSwitcher.Failure.originCoverage.userFacingDescription
        #expect(text.contains("arrangement"))
    }
}
```

Note: `Failure` needs `Equatable` for `#expect(throws:)` — add conformance in Step 3.

- [ ] **Step 2: Run to verify failure**

Run: `make test`
Expected: compile error — no member `applyOrigins` / `originCoverage`.

- [ ] **Step 3: Implement**

In `VibeRes/Core/ResolutionSwitcher.swift`, extend the enum declaration (line 5) and cases:

```swift
    enum Failure: Error, Equatable {
        case beginConfig(CGError)
        case applyMode(CGError)
        case completeConfig(CGError)
        case applyOrigin(CGError)
        /// The origin plan does not cover exactly the active display set. A
        /// partial arrangement statement is completed for you — badly (spike
        /// F1) — so it is refused before any CG call is made.
        case originCoverage
```

Update `userFacingDescription` (lines 16–38) — the coverage case has no CGError:

```swift
        var userFacingDescription: String {
            let code: CGError
            switch self {
            case .originCoverage:
                return "the display set changed while applying — arrangement left unchanged"
            case .beginConfig(let c), .applyMode(let c), .completeConfig(let c), .applyOrigin(let c):
                code = c
            }
```

(The remainder of the method is unchanged.)

After `applyBatch` (line 106), add:

```swift
    /// Moves the whole arrangement in one transaction so that one display ends
    /// up at (0,0) — i.e. becomes main and hosts the menu bar.
    ///
    /// All-or-nothing by design, unlike the mode path above: spike F1 showed a
    /// partial origin change is silently "completed" by the window server into
    /// a mangled layout, so a plan is refused outright unless it covers every
    /// active display. The active-list gate sits here, immediately before
    /// Begin, because a display asleep or unplugged since the plan was built
    /// is online-but-not-active (F7) and would take the whole transaction down
    /// at commit (F6).
    static func applyOrigins(
        _ plan: [CGDirectDisplayID: CGPoint],
        scope: CGConfigureOption = .permanently,
        activeIDs: [CGDirectDisplayID]? = nil
    ) throws {
        let active = activeIDs ?? activeDisplayIDs()
        guard !plan.isEmpty, Set(plan.keys) == Set(active) else {
            throw Failure.originCoverage
        }

        var config: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&config)
        guard beginErr == .success else { throw Failure.beginConfig(beginErr) }

        for (id, origin) in plan {
            let err = CGConfigureDisplayOrigin(config, id, Int32(origin.x), Int32(origin.y))
            guard err == .success else {
                // One refused origin poisons the whole statement (F1); there
                // is no per-display fallback like the mode path has.
                CGCancelDisplayConfiguration(config)
                throw Failure.applyOrigin(err)
            }
        }

        let completeErr = CGCompleteDisplayConfiguration(config, scope)
        guard completeErr == .success else { throw Failure.completeConfig(completeErr) }
    }

    /// Live *active* display list — not `online`: asleep or clamshell displays
    /// are online but not active, and configuring one fails with undocumented
    /// errors (F7).
    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: PASS (including all existing suites — `Equatable` on `Failure` is additive).

- [ ] **Step 5: Commit**

```bash
git add VibeRes/Core/ResolutionSwitcher.swift VibeResTests/ApplyOriginsTests.swift
git commit -m "Add all-or-nothing origin transaction with active-set coverage guard"
```

---

### Task 4: Main-display phase in `ProfileStore.applyDetailed`

**Files:**
- Modify: `VibeRes/Core/ProfileStore.swift` (seams near line 440, `applyDetailed` lines 451–601, `apply` wrapper lines 604–609, new types near `ApplyOutcome`)
- Modify: `VibeRes/UI/ProfilesSection.swift:359` and `:1247` (return-type change)
- Modify: `VibeResCLI/main.swift:302-315` (return-type change; full CLI copy lands in Task 8)
- Modify: `VibeResTests/BatchApplyTests.swift` (mechanical `.outcomes` updates)
- Test: `VibeResTests/MainDisplayApplyTests.swift` (create)

**Interfaces:**
- Consumes: `MainDisplayPlanner` (Task 2), `ResolutionSwitcher.applyOrigins` / `activeDisplayIDs` (Task 3), `Profile.mainDisplay` (Task 1).
- Produces (used by Tasks 5, 8):
  - `struct ProfileStore.ProfileApplyResult { var outcomes: [ApplyOutcome]; var mainChange: MainChangeOutcome?; var didChangeAnything: Bool }`
  - `enum ProfileStore.MainChangeOutcome: Equatable` with cases `.changed(displayName: String)`, `.changedButAdjusted(displayName: String)`, `.alreadyMain`, `.skippedNoMatch`, `.skippedAmbiguous(count: Int)`, `.skippedMirrored`, `.failed(String)`; plus `var didChange: Bool` and `var problemSummary: String?` (English, Core-safe).
  - `applyDetailed(_:displays:revert:) -> ProfileApplyResult` (was `[ApplyOutcome]`)
  - Seams: `var applyOrigins: ([CGDirectDisplayID: CGPoint], CGConfigureOption) throws -> Void`, `var liveArrangement: () -> (main: CGDirectDisplayID, bounds: [CGDirectDisplayID: CGRect])`, `var isInMirrorSet: (CGDirectDisplayID) -> Bool`
  - This task keeps calling `revert.recordBatch(batchSnapshot)` unchanged (it only widens the *condition* to also fire on a main-only change); Task 5 adds the `beforeMain:` parameter and threads `previousMainID` through. Tasks 4 and 5 each leave the build green on their own.

- [ ] **Step 1: Write the failing tests**

Create `VibeResTests/MainDisplayApplyTests.swift`. Fake-ID trap to know before reading: the all-ones matcher binds to **every** fake ID, so a two-fake-display arrangement can never resolve to exactly one. "Exactly one match" is therefore staged with the machine's one real display (`CGMainDisplayID()`, whose EDID is not all-ones) as the other arrangement member:

```swift
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

        let result = store.applyDetailed(profile(main: allOnes), displays: [])

        #expect(probes.originCalls().count == 1)
        let plan = probes.originCalls().first
        #expect(plan?[fake] == .zero)
        #expect(plan?[realID] == CGPoint(x: -1074, y: 1080))
        #expect(plan?.count == 2, "the plan covers every active display (F1)")
        #expect(result.mainChange == .changed(displayName: "display \(101)"))
        #expect(result.didChangeAnything)
        #expect(probes.currentMain() == fake)
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
```

- [ ] **Step 2: Run to verify failure**

Run: `make test`
Expected: compile errors — `ProfileApplyResult`, seams, and `mainChange` do not exist.

- [ ] **Step 3: Implement the types and seams**

In `VibeRes/Core/ProfileStore.swift`, after the `ApplyOutcome` struct (ends near line 422):

```swift
    /// What applying a profile did: per-display mode outcomes plus, when the
    /// profile pins a main display, what happened to the arrangement.
    struct ProfileApplyResult {
        var outcomes: [ApplyOutcome]
        var mainChange: MainChangeOutcome?

        /// True when anything on screen actually changed. Auto-apply uses
        /// this to suppress "Applied…" toasts for no-op applies.
        var didChangeAnything: Bool {
            outcomes.contains(where: \.didChange) || mainChange?.didChange == true
        }
    }

    /// Outcome of the main-display phase. `nil` on ProfileApplyResult means
    /// the profile does not pin a main display at all.
    enum MainChangeOutcome: Equatable {
        case changed(displayName: String)            // committed and verified (F5)
        case changedButAdjusted(displayName: String) // committed, but read-back differs from the plan
        case alreadyMain
        case skippedNoMatch                          // matcher bound no active display
        case skippedAmbiguous(count: Int)            // matcher bound 2+ — intent unknowable
        case skippedMirrored                         // arrangement + mirroring is unmeasured
        case failed(String)                          // the origin transaction threw

        var didChange: Bool {
            switch self {
            case .changed, .changedButAdjusted: return true
            case .alreadyMain, .skippedNoMatch, .skippedAmbiguous, .skippedMirrored, .failed:
                return false
            }
        }

        /// English, Core-safe (the CLI prints it verbatim); localised copy
        /// lives in ApplyOutcomeNote.
        var problemSummary: String? {
            switch self {
            case .changed, .alreadyMain:
                return nil
            case .changedButAdjusted:
                return "main display set, but macOS adjusted the arrangement"
            case .skippedNoMatch:
                return "main display not changed: the saved display is not connected"
            case .skippedAmbiguous(let count):
                return "main display not changed: \(count) connected displays match"
            case .skippedMirrored:
                return "main display not changed: displays are mirrored"
            case .failed(let message):
                return "main display not changed: \(message)"
            }
        }
    }
```

Next to the existing `applyBatch` seam (line 439–441):

```swift
    /// Test seams for the main-display phase — same rationale as `applyBatch`:
    /// the origin transaction and the live arrangement reads must be
    /// injectable, because a unit test must not rearrange the machine.
    @ObservationIgnored
    var applyOrigins: ([CGDirectDisplayID: CGPoint], CGConfigureOption) throws -> Void =
        { try ResolutionSwitcher.applyOrigins($0, scope: $1) }

    @ObservationIgnored
    var liveArrangement: () -> (main: CGDirectDisplayID, bounds: [CGDirectDisplayID: CGRect]) = {
        var bounds: [CGDirectDisplayID: CGRect] = [:]
        for id in ResolutionSwitcher.activeDisplayIDs() { bounds[id] = CGDisplayBounds(id) }
        return (CGMainDisplayID(), bounds)
    }

    @ObservationIgnored
    var isInMirrorSet: (CGDirectDisplayID) -> Bool = { CGDisplayIsInMirrorSet($0) != 0 }
```

- [ ] **Step 4: Implement the phase in `applyDetailed`**

Change the signature (line 451–456):

```swift
    @discardableResult
    func applyDetailed(
        _ profile: Profile,
        displays: [DisplayInfo],
        revert: RevertHistory? = nil
    ) -> ProfileApplyResult {
```

Immediately **before** the revert-recording block (line 594–599), insert the phase — note it runs *after* the mode transaction on purpose, so the translation is derived from post-mode geometry (a complete, consistent statement, the F2 shape — never a stale one, the F1 shape):

```swift
        // Phase 2 — main display. Ordered after the mode transaction: modes
        // change sizes in points, and only the *post-mode* live arrangement is
        // guaranteed to be a consistent layout to translate (F2). Stale
        // geometry could describe gaps the window server has never been
        // measured on.
        var mainChange: MainChangeOutcome?
        var previousMainID: CGDirectDisplayID?
        if let matcher = profile.mainDisplay {
            mainChange = applyMainDisplay(matcher, displays: displays,
                                          previousMain: &previousMainID)
        }
```

Adjust the revert-recording condition and the return (was lines 594–600):

```swift
        // Revert undoes "the last profile apply" rather than the last
        // individual switch within it — and only records displays that
        // actually moved, so it never offers to restore one that never changed.
        // A main-only change (all modes already at target) must still arm it.
        if !batchSnapshot.isEmpty || previousMainID != nil, let revert = revert {
            revert.recordBatch(batchSnapshot)
            // Task 5 wires previousMainID into RevertHistory.
        }
        return ProfileApplyResult(outcomes: outcomes, mainChange: mainChange)
```

Add the private method after `applyDetailed`:

```swift
    /// Resolves the profile's main matcher against the live arrangement and,
    /// when it binds to exactly one active display that is not already main,
    /// commits a full-coverage origin translation and verifies it (F5).
    private func applyMainDisplay(
        _ matcher: DisplayMatcher,
        displays: [DisplayInfo],
        previousMain: inout CGDirectDisplayID?
    ) -> MainChangeOutcome {
        let live = liveArrangement()
        let activeIDs = Array(live.bounds.keys)

        switch MainDisplayPlanner.resolveTarget(matcher, activeIDs: activeIDs) {
        case .noMatch:
            return .skippedNoMatch
        case .ambiguous(let count):
            return .skippedAmbiguous(count: count)
        case .target(let target):
            // Arrangement combined with mirroring is a spike unknown; leave
            // it alone rather than find out on a user's machine.
            guard !activeIDs.contains(where: isInMirrorSet) else { return .skippedMirrored }
            guard target != live.main else { return .alreadyMain }
            guard let plan = MainDisplayPlanner.plan(bounds: live.bounds, target: target) else {
                return .skippedNoMatch
            }

            let name = displays.first(where: { $0.id == target })?.name ?? "display \(target)"
            viberesLog.notice("main display: \(live.main) → \(target) (\(name, privacy: .public)), \(plan.count) origins")
            do {
                try applyOrigins(plan, .permanently)
            } catch {
                viberesLog.error("main display: transaction failed — \(String(describing: error), privacy: .public)")
                return .failed(error.userFacingText)
            }
            previousMain = live.main

            // F5: the return code is not evidence — read the arrangement back.
            let after = liveArrangement()
            if after.main == target, MainDisplayPlanner.verified(plan: plan, actualBounds: after.bounds) {
                return .changed(displayName: name)
            }
            viberesLog.error("main display: committed but read-back differs from the plan (F5)")
            return .changedButAdjusted(displayName: name)
        }
    }
```

- [ ] **Step 5: Mechanically update the call sites**

All of them only need the outcome list where they needed it before:

- `VibeRes/Core/ProfileStore.swift:604-609` — the wrapper:

```swift
    /// Backward-compat wrapper that converts the result into a flat problem list.
    @discardableResult
    func apply(_ profile: Profile, displays: [DisplayInfo]) -> [String] {
        let result = applyDetailed(profile, displays: displays)
        var problems = result.outcomes.filter(\.isProblem).map(\.summary)
        if let main = result.mainChange, let summary = main.problemSummary {
            problems.append(summary)
        }
        return problems
    }
```

- `VibeRes/UI/ProfilesSection.swift:359` (inside the confirm-apply flow):

```swift
                profiles.applyDetailed(profile, displays: snapshotDisplays, revert: revert)
```
The call is used for its result — find the surrounding lines; the variable that received `[ApplyOutcome]` now receives `ProfileApplyResult`, and whatever fed `announceOutcome(...)` passes `result.outcomes` for now (Task 8 upgrades the note to carry `mainChange`).

- `VibeRes/UI/ProfilesSection.swift:1246-1252` (auto-apply):

```swift
        let result = profiles.applyDetailed(match, displays: displays.displays)
        autoApplyLog.notice("autoApply: outcomes=\(result.outcomes.count) didChange=\(result.didChangeAnything)")
        if result.didChangeAnything {
            announce("Applied '\(match.name)' for the new display setup.", tone: .info)
        }
```

- `VibeResCLI/main.swift:302-315` — minimal for now (Task 8 adds the main line):

```swift
    let result = store.applyDetailed(profile, displays: displays)
    var hadProblem = false
    print("# applied profile \"\(profile.name)\"")
    for o in result.outcomes {
```

- `VibeResTests/BatchApplyTests.swift` — every `let outcomes = store.applyDetailed(...)` becomes `let outcomes = store.applyDetailed(...).outcomes`; the two bare `store.applyDetailed(...)` statement calls are `@discardableResult` and stay as they are.

- [ ] **Step 6: Run tests**

Run: `make test`
Expected: PASS — new suite green, BatchApplyTests still green (they never set `mainDisplay`, so `liveArrangement` is never called there).

- [ ] **Step 7: Commit**

```bash
git add VibeRes/Core/ProfileStore.swift VibeRes/UI/ProfilesSection.swift VibeResCLI/main.swift VibeResTests/BatchApplyTests.swift VibeResTests/MainDisplayApplyTests.swift
git commit -m "Apply a profile's main display as a verified origin translation"
```

---

### Task 5: Revert knows the previous main display

**Files:**
- Modify: `VibeRes/Core/RevertHistory.swift`
- Modify: `VibeRes/Core/DisplayStore.swift` (seams near line 322; `performRevert` lines 457–480)
- Modify: `VibeRes/Core/ProfileStore.swift` (the `recordBatch` call from Task 4 Step 4)
- Test: `VibeResTests/RevertHistoryTests.swift` (extend), `VibeResTests/RevertMainDisplayTests.swift` (create)

**Interfaces:**
- Consumes: `MainDisplayPlanner.plan` (Task 2), `ResolutionSwitcher.applyOrigins` (Task 3).
- Produces:
  - `RevertHistory.beforeMainID: CGDirectDisplayID?` (read-only), `recordBatch(_:beforeMain:)` (`beforeMain` defaults to `nil`), `consume() -> (entries: [Entry], beforeMain: CGDirectDisplayID?)`, `canRevert` true when either is non-empty.
  - `DisplayStore.applyOrigins` and `DisplayStore.liveArrangement` seams with the same shapes as ProfileStore's (Task 4).
- Design note: revert does **not** store per-display origins. Stored origins would cover only the displays that changed mode — replaying them is the partial statement F1 mangles. Restoring main is the same operation as setting it: a fresh full-coverage translation of the *live* arrangement, targeting the old main. (This deliberately deviates from the spike doc's "Entry gains beforeOrigin" sketch.)

- [ ] **Step 1: Write the failing tests**

Extend `VibeResTests/RevertHistoryTests.swift` — add to the existing suite (adapt the suite name if it differs; consume-call sites in the existing tests change from `history.consume()` to `history.consume().entries`):

```swift
    @Test("A main-only apply arms Revert with no mode entries")
    func mainOnlyArmsRevert() {
        let history = RevertHistory()
        history.recordBatch([], beforeMain: 42)
        #expect(history.canRevert)
        let consumed = history.consume()
        #expect(consumed.entries.isEmpty)
        #expect(consumed.beforeMain == 42)
        #expect(!history.canRevert, "consume clears the main id too")
    }

    @Test("clear drops the previous main id")
    func clearDropsMain() {
        let history = RevertHistory()
        history.recordBatch([], beforeMain: 42)
        history.clear()
        #expect(!history.canRevert)
        #expect(history.consume().beforeMain == nil)
    }
```

Create `VibeResTests/RevertMainDisplayTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// Reverting a main-display change is not "replay stored origins" — stored
/// origins would cover only the displays that changed mode, which is the
/// partial arrangement statement spike F1 mangles. It is the same operation
/// as setting main: a fresh full-coverage translation of the live
/// arrangement, targeting the old main.
@Suite("Revert restores the previous main display")
@MainActor
struct RevertMainDisplayTests {
    @Test("performRevert translates the live arrangement back to the old main")
    func revertsMain() {
        let store = DisplayStore()
        var plans: [[CGDirectDisplayID: CGPoint]] = []
        store.applyMode = { _, _, _ in }
        store.liveArrangement = {
            (main: 7, bounds: [
                5: CGRect(x: -1800, y: 0, width: 1800, height: 1169),
                7: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            ])
        }
        store.applyOrigins = { plan, _ in plans.append(plan) }
        store.revert.recordBatch([], beforeMain: 5)

        let restored = store.performRevert()

        #expect(plans.count == 1)
        #expect(plans.first?[5] == .zero)
        #expect(plans.first?[7] == CGPoint(x: 1800, y: 0))
        #expect(restored == 1)
        #expect(!store.revert.canRevert)
    }

    @Test("An old main that is no longer active is skipped, not guessed at")
    func staleMainSkipped() {
        let store = DisplayStore()
        var originCalled = false
        store.applyMode = { _, _, _ in }
        store.liveArrangement = { (main: 7, bounds: [7: .zero]) }
        store.applyOrigins = { _, _ in originCalled = true }
        store.revert.recordBatch([], beforeMain: 5)

        _ = store.performRevert()

        #expect(!originCalled)
        #expect(!store.revert.canRevert, "nothing left to restore onto — history clears")
    }

    @Test("A failed origin restore keeps the way back armed")
    func failedRestoreStaysArmed() {
        let store = DisplayStore()
        store.applyMode = { _, _, _ in }
        store.liveArrangement = {
            (main: 7, bounds: [5: CGRect(x: -1800, y: 0, width: 1800, height: 1169), 7: .zero])
        }
        store.applyOrigins = { _, _ in throw ResolutionSwitcher.Failure.originCoverage }
        store.revert.recordBatch([], beforeMain: 5)

        let restored = store.performRevert()

        #expect(restored == 0)
        #expect(store.revert.canRevert, "the display is still not where the user wanted it")
        #expect(store.revert.consume().beforeMain == 5)
    }
}
```

(If `DisplayStore()` requires arguments, mirror how `VibeResTests/DisplayStoreRefreshTests.swift` constructs one and note the difference here.)

- [ ] **Step 2: Run to verify failure**

Run: `make test`
Expected: compile errors — `recordBatch(_:beforeMain:)`, `liveArrangement`, `applyOrigins` missing on the respective types.

- [ ] **Step 3: Implement `RevertHistory`**

In `VibeRes/Core/RevertHistory.swift`:

```swift
    private(set) var entries: [Entry] = []

    /// The display that was main before the last recorded batch, when that
    /// batch also moved the menu bar. Restoring it is a fresh translation of
    /// the live arrangement at revert time — no origins are stored here,
    /// because a stored partial plan is exactly what spike F1 mangles.
    private(set) var beforeMainID: CGDirectDisplayID?

    /// True when there's at least one captured change to undo.
    var canRevert: Bool { !entries.isEmpty || beforeMainID != nil }
```

`summary` gains a main-only case (first line of the method):

```swift
    var summary: String {
        if entries.isEmpty, beforeMainID != nil { return "main display" }
        switch entries.count {
        ...
```

`recordBatch`, `consume`, `clear`:

```swift
    func recordBatch(
        _ batch: [(id: CGDirectDisplayID, name: String, before: CGDisplayMode)],
        beforeMain: CGDirectDisplayID? = nil
    ) {
        entries = batch.map { Entry(displayID: $0.id, displayName: $0.name, before: $0.before) }
        beforeMainID = beforeMain
    }

    func consume() -> (entries: [Entry], beforeMain: CGDirectDisplayID?) {
        let snapshot = (entries, beforeMainID)
        entries.removeAll()
        beforeMainID = nil
        return snapshot
    }

    func clear() {
        entries.removeAll()
        beforeMainID = nil
    }
```

- [ ] **Step 4: Implement `DisplayStore`**

Seams, next to `applyMode` (line 322):

```swift
    /// Injected for the same reason as `applyMode`: reverting a main-display
    /// change must be assertable without rearranging the machine.
    @ObservationIgnored
    var applyOrigins: ([CGDirectDisplayID: CGPoint], CGConfigureOption) throws -> Void =
        { try ResolutionSwitcher.applyOrigins($0, scope: $1) }

    @ObservationIgnored
    var liveArrangement: () -> (main: CGDirectDisplayID, bounds: [CGDirectDisplayID: CGRect]) = {
        var bounds: [CGDirectDisplayID: CGRect] = [:]
        for id in ResolutionSwitcher.activeDisplayIDs() { bounds[id] = CGDisplayBounds(id) }
        return (CGMainDisplayID(), bounds)
    }
```

(If `@ObservationIgnored` is not used on `applyMode` in this file, match whatever `applyMode` does.)

`performRevert` (replace lines 457–480):

```swift
    /// Re-apply each display's `before` mode, then — if the recorded batch
    /// also moved the menu bar — translate the live arrangement back so the
    /// previous main hosts it again. Returns the count of restorations so the
    /// caller can surface a toast.
    @discardableResult
    func performRevert() -> Int {
        let snapshot = revert.consume()
        var failed: [(id: CGDirectDisplayID, name: String, before: CGDisplayMode)] = []
        var restored = 0

        for entry in snapshot.entries {
            do {
                try applyMode(entry.before, entry.displayID, .permanently)
                restored += 1
            } catch {
                // Keep the entry: this display is still in the mode the user
                // wanted undone, so the way back must survive the attempt.
                failed.append((entry.displayID, entry.displayName, entry.before))
                lastError = error.userFacingText
            }
        }

        // Origins go after modes for the same reason profile apply orders
        // them this way: only the post-mode live arrangement is guaranteed to
        // be a consistent layout to translate (F2), never a stale one (F1).
        var failedMain: CGDirectDisplayID?
        if let beforeMain = snapshot.beforeMain {
            let live = liveArrangement()
            if live.main != beforeMain {
                if let plan = MainDisplayPlanner.plan(bounds: live.bounds, target: beforeMain) {
                    do {
                        try applyOrigins(plan, .permanently)
                        restored += 1
                    } catch {
                        failedMain = beforeMain
                        lastError = error.userFacingText
                    }
                }
                // No plan means the old main is no longer active — there is
                // nothing to restore onto, and keeping it armed would promise
                // a revert that can never run.
            }
        }

        if !failed.isEmpty || failedMain != nil {
            revert.recordBatch(failed, beforeMain: failedMain)
        }
        if restored > 0 { refresh() }
        // Only what actually came back, so a caller cannot report a success
        // that did not happen.
        return restored
    }
```

- [ ] **Step 5: Wire `previousMainID` in ProfileStore**

In `VibeRes/Core/ProfileStore.swift`, the recording block from Task 4 Step 4 becomes:

```swift
        if !batchSnapshot.isEmpty || previousMainID != nil, let revert = revert {
            revert.recordBatch(batchSnapshot, beforeMain: previousMainID)
        }
```

Add an assertion to `VibeResTests/MainDisplayApplyTests.swift` (end of `happyPath`, passing a `RevertHistory` in):

```swift
        // In happyPath, change the apply call to:
        //   let history = RevertHistory()
        //   let result = store.applyDetailed(profile(main: allOnes), displays: [], revert: history)
        // and add:
        #expect(history.beforeMainID == realID, "revert must know who was main before")
```

- [ ] **Step 6: Fix remaining `consume()` call sites**

`grep -n "consume()" VibeRes VibeResTests -r` — besides `performRevert`, existing `RevertHistoryTests` uses change to `.entries`. There are no other production callers (verified at plan time: `DisplayStore.performRevert` is the only one).

- [ ] **Step 7: Run tests**

Run: `make test`
Expected: PASS, including the pre-existing RevertCountdown/RevertFailure suites.

- [ ] **Step 8: Commit**

```bash
git add VibeRes/Core/RevertHistory.swift VibeRes/Core/DisplayStore.swift VibeRes/Core/ProfileStore.swift VibeResTests/RevertHistoryTests.swift VibeResTests/RevertMainDisplayTests.swift VibeResTests/MainDisplayApplyTests.swift
git commit -m "Restore the previous main display on Revert via a live translation"
```

---

### Task 6: Save form — main display picker

**Files:**
- Modify: `VibeRes/Core/ProfileStore.swift` (`captureCurrent`, lines 302–347)
- Modify: `VibeRes/UI/ProfilesSection.swift` (`SaveFormState` line 61–65, save form lines 545–583, `commitSave` lines 1200–1226, bindings section)
- Test: `VibeResTests/ProfileMainDisplayTests.swift` (extend)

**Interfaces:**
- Consumes: `Profile.mainDisplay` (Task 1).
- Produces: `captureCurrent(name:displays:selection:mainSelection:)` with `mainSelection: CGDirectDisplayID? = nil`; a static helper `ProfileStore.matcher(for:kind:) -> DisplayMatcher` reused by the entry loop.

- [ ] **Step 1: Write the failing test**

Add to `VibeResTests/ProfileMainDisplayTests.swift` (needs `@MainActor` on these tests since ProfileStore is main-actor; keep them in a nested suite):

```swift
@Suite("captureCurrent with a main selection")
@MainActor
struct CaptureMainSelectionTests {
    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-capture-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    private func info(_ id: CGDirectDisplayID) -> DisplayInfo {
        let mode = (CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode])?.first
        return DisplayInfo(id: id, name: "Mon \(id)", isMain: false,
                           modes: mode.map { [$0] } ?? [], currentMode: mode, groups: [])
    }

    @Test("The chosen display's matcher is stored as mainDisplay")
    func mainSelectionStored() {
        let store = makeStore()
        let displays = [info(101), info(102)]
        let result = store.captureCurrent(
            name: "Desk", displays: displays,
            selection: [101: .specific, 102: .specific],
            mainSelection: 102
        )
        #expect(result == .saved)
        let profile = store.profiles.first
        #expect(profile?.mainDisplay != nil)
        // Consistency beats hardcoding EDID reads for fake IDs: main must be
        // built the same way as that display's entry matcher.
        #expect(profile?.mainDisplay == profile?.entries.first(where: { $0.displayName == "Mon 102" })?.matcher)
    }

    @Test("No selection leaves mainDisplay nil — the pre-0.9 shape")
    func noSelectionNil() {
        let store = makeStore()
        _ = store.captureCurrent(
            name: "Desk", displays: [info(101)],
            selection: [101: .specific]
        )
        #expect(store.profiles.first?.mainDisplay == nil)
    }

    @Test("A main selection pointing at an unselected display is ignored")
    func unselectedMainIgnored() {
        let store = makeStore()
        _ = store.captureCurrent(
            name: "Desk", displays: [info(101), info(102)],
            selection: [101: .specific],
            mainSelection: 102
        )
        #expect(store.profiles.first?.mainDisplay == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `make test`
Expected: compile error — `captureCurrent` has no `mainSelection` parameter.

- [ ] **Step 3: Implement `captureCurrent`**

In `VibeRes/Core/ProfileStore.swift`, first extract the matcher construction (it is currently inlined in the entry loop, lines 314–325) into a helper next to `captureCurrent`:

```swift
    /// How a live display gets bound: by role (any external) or by identity —
    /// built-in panels get `.builtIn`, everything else `.edid`. Shared by the
    /// entry loop and the main-display selection so the two can never drift.
    private static func matcher(for id: CGDirectDisplayID, kind: ProfileMatchKind) -> DisplayMatcher {
        switch kind {
        case .anyExternal:
            return .anyExternal
        case .specific:
            let identity = DisplayIdentity.capture(id)
            return CGDisplayIsBuiltin(id) != 0
                ? .builtIn(vendor: identity.vendor, model: identity.model, serial: identity.serial)
                : .edid(vendor: identity.vendor, model: identity.model, serial: identity.serial)
        }
    }
```

The entry loop's inline closure (lines 314–325) becomes `let matcher = Self.matcher(for: info.id, kind: kind)`.

Then the signature and profile construction:

```swift
    @discardableResult
    func captureCurrent(
        name: String,
        displays: [DisplayInfo],
        selection: [CGDirectDisplayID: ProfileMatchKind],
        mainSelection: CGDirectDisplayID? = nil
    ) -> SaveResult {
```

and (replacing `add(Profile(name: name, entries: entries))` at line 337):

```swift
        // The main pick must be one of the *saved* displays: a selection that
        // was unchecked (or unplugged) before Save has no entry to anchor to.
        var mainDisplay: DisplayMatcher?
        if let mainSelection,
           let kind = selection[mainSelection],
           displays.contains(where: { $0.id == mainSelection }) {
            mainDisplay = Self.matcher(for: mainSelection, kind: kind)
        }
        add(Profile(name: name, entries: entries, mainDisplay: mainDisplay))
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: PASS.

- [ ] **Step 5: Add the picker to the save form**

In `VibeRes/UI/ProfilesSection.swift`:

`SaveFormState` (line 61–65):

```swift
    struct SaveFormState: Equatable {
        var name: String = ""
        /// Per-display: include? + how to bind (specific vs anyExternal)
        var perDisplay: [DisplayChoice] = []
        /// Which included display becomes main on apply; nil = don't change.
        var mainDisplayID: CGDirectDisplayID?
    }
```

In `saveForm` (after the `ForEach(state.perDisplay)` block, line 566), insert:

```swift
                Text("MAIN DISPLAY")
                    .font(Design.Typography.sectionHeader)
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)

                Picker(selection: bindingForMainDisplay) {
                    Text("Don't change").tag(CGDirectDisplayID?.none)
                    ForEach(state.perDisplay.filter(\.isIncluded)) { choice in
                        Text(choice.displayName).tag(CGDirectDisplayID?.some(choice.displayID))
                    }
                } label: { EmptyView() }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Main display")
                .help("Which display hosts the menu bar after this profile is applied. 'Don't change' leaves the arrangement alone.")
```

In the Bindings section (near `bindingForName`, line 663):

```swift
    private var bindingForMainDisplay: Binding<CGDirectDisplayID?> {
        Binding(
            get: {
                if case .saving(let s) = mode { return s.mainDisplayID }
                return nil
            },
            set: { newValue in
                if case .saving(var s) = mode {
                    s.mainDisplayID = newValue
                    mode = .saving(s)
                }
            }
        )
    }
```

In `bindingForInclude`'s setter (find it in the Bindings section — it flips `isIncluded` for a display ID), add after the flip, inside the same `if case .saving(var s)` block:

```swift
                    // Un-including the display that was picked as main leaves
                    // the picker pointing at nothing — reset to "Don't change".
                    if !newValue, s.mainDisplayID == id { s.mainDisplayID = nil }
```

(`id` here is whatever the existing setter calls the captured display ID — match its actual name.)

In `commitSave` (line 1211), thread the selection through:

```swift
        switch profiles.captureCurrent(
            name: trimmed,
            displays: displays.displays,
            selection: selection,
            mainSelection: s.perDisplay.first(where: { $0.isIncluded && $0.displayID == s.mainDisplayID })?.displayID
        ) {
```

- [ ] **Step 6: Run tests + build the app**

Run: `make test` — expected PASS.
Run: `make app` — expected build succeeds (views are not unit-tested by repo convention; the form is exercised in the manual checklist, Task 9).

- [ ] **Step 7: Commit**

```bash
git add VibeRes/Core/ProfileStore.swift VibeRes/UI/ProfilesSection.swift VibeResTests/ProfileMainDisplayTests.swift
git commit -m "Let the save form pick which display becomes main"
```

---

### Task 7: Edit form — main display picker (and the stale-entries `update` fix)

**Files:**
- Modify: `VibeRes/UI/ProfilesSection.swift` (`EditFormState` line 83–87, `editForm` lines 750–791, `buildInitialEditState` ending line 1028, `commitEdit` lines 1141–1187, edit bindings section)

**Interfaces:**
- Consumes: `Profile.mainDisplay` (Task 1).
- Produces: `EditFormState.mainRowID: UUID?`; private `rowMatcher(_ e: EntryEdit) -> DisplayMatcher` reused by `commitEdit` and preselection.
- ⚠️ **Pre-existing bug fixed here** (verified by reading, not by a failing UI test — the repo does not test views): `commitEdit` calls `profiles.replaceEntries(profile, with: newEntries)` and then `profiles.update(profile)` **with the stale `profile` value captured before `replaceEntries`**, whose `entries` are the *old* ones — `update` replaces the stored profile wholesale (`ProfileStore.swift:126-134`), so entry edits are silently undone by the rename step. The rewrite below re-fetches after `replaceEntries`. Mention this in the commit message; if testing shows the read is wrong, stop and re-verify rather than shipping the "fix".

- [ ] **Step 1: Add `mainRowID` and the shared matcher helper**

`EditFormState` (line 83–87):

```swift
    struct EditFormState: Equatable {
        let profileID: UUID
        var name: String
        var entries: [EntryEdit]
        /// Row whose display becomes main on apply; nil = don't change.
        var mainRowID: UUID?
    }
```

Private helper near `commitEdit`:

```swift
    /// The matcher a row would save as — single source of truth for
    /// commitEdit and for preselecting the main-display picker.
    private func rowMatcher(_ e: EntryEdit) -> DisplayMatcher {
        switch e.matcherKind {
        case .anyExternal:
            return .anyExternal
        case .specific:
            return e.isBuiltIn
                ? .builtIn(vendor: e.vendor, model: e.model, serial: e.serial)
                : .edid(vendor: e.vendor, model: e.model, serial: e.serial)
        }
    }
```

`commitEdit`'s inline matcher closure (lines 1153–1161) becomes `let matcher = rowMatcher(e)`.

- [ ] **Step 2: Preselect in `buildInitialEditState`**

Replace the return (line 1028):

```swift
        var state = EditFormState(profileID: profile.id, name: profile.name, entries: entries)
        // Preselect the row that would save the same matcher the profile
        // already stores. A hand-edited mainDisplay matching no row shows as
        // "Don't change" and is dropped on save — the edit form owns the field.
        state.mainRowID = entries.first(where: { profile.mainDisplay == rowMatcher($0) })?.id
        return state
```

- [ ] **Step 3: Picker UI + binding**

In `editForm`, after the `ForEach(state.entries)` block (line 768):

```swift
                Text("MAIN DISPLAY")
                    .font(Design.Typography.sectionHeader)
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)

                Picker(selection: bindingForEditMainRow) {
                    Text("Don't change").tag(UUID?.none)
                    ForEach(state.entries.filter(\.isIncluded)) { entry in
                        Text(entry.displayName).tag(UUID?.some(entry.id))
                    }
                } label: { EmptyView() }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Main display")
                .help("Which display hosts the menu bar after this profile is applied. 'Don't change' leaves the arrangement alone.")
```

Binding, in the Edit bindings section:

```swift
    private var bindingForEditMainRow: Binding<UUID?> {
        Binding(
            get: {
                if case .editing(let s) = mode { return s.mainRowID }
                return nil
            },
            set: { newValue in
                if case .editing(var s) = mode {
                    s.mainRowID = newValue
                    mode = .editing(s)
                }
            }
        )
    }
```

In `bindingForEditInclude`'s setter (the existing include toggle for edit rows), add inside the mutation block:

```swift
                    if !newValue, s.mainRowID == rowID { s.mainRowID = nil }
```

(`rowID` is whatever the existing setter calls the captured row id — match its actual name.)

- [ ] **Step 4: Rewrite `commitEdit`'s success path (fixes the stale-entries bug)**

Replace lines 1174–1181:

```swift
        switch profiles.replaceEntries(profile, with: newEntries) {
        // Re-fetch after replaceEntries: `profile` was captured before it and
        // still carries the old entries — updating with it would silently undo
        // the entry edits that replaceEntries just saved.
        case .saved, .savedWithMissingDisplays:
            if var fresh = profiles.profiles.first(where: { $0.id == s.profileID }) {
                fresh.name = trimmed
                fresh.mainDisplay = kept.first(where: { $0.id == s.mainRowID }).map(rowMatcher)
                profiles.update(fresh)
            }
            announce("Updated '\(trimmed)'", tone: .info)
            mode = .idle
```

- [ ] **Step 5: Build + run tests**

Run: `make test && make app`
Expected: PASS / build succeeds. Manual verification of both forms is in Task 9's checklist (including a regression check for the stale-entries fix: edit a profile's resolution, save, re-open, confirm the new resolution stuck).

- [ ] **Step 6: Commit**

```bash
git add VibeRes/UI/ProfilesSection.swift
git commit -m "Add main-display picker to the edit form and stop rename undoing entry edits"
```

---

### Task 8: Outcome copy — popover note and CLI

**Files:**
- Modify: `VibeRes/UI/ApplyOutcomeNote.swift`
- Modify: `VibeRes/UI/ProfilesSection.swift` (`announceOutcome` line 1272–1282 and its callers)
- Modify: `VibeResCLI/main.swift` (`cmdProfileApply` lines 295–316, `cmdProfileList` entry loop ending line 293)
- Test: `VibeResTests/ApplyOutcomeNoteTests.swift` (extend)

**Interfaces:**
- Consumes: `ProfileStore.ProfileApplyResult` / `MainChangeOutcome` (Task 4).
- Produces: `ApplyOutcomeNote.make(from:mainChange:)` (`mainChange` defaults to `nil`); `ApplyOutcomeNote.mainDetail: Detail?`; new `Detail` cases `.mainChanged(display:)`, `.mainAdjusted(display:)`, `.mainNotConnected`, `.mainAmbiguous(count:)`, `.mainMirrored`, `.mainFailed(message:)`.

- [ ] **Step 1: Write the failing tests**

Add to `VibeResTests/ApplyOutcomeNoteTests.swift` (match the existing suite's helper style for building outcomes — reuse its factory if one exists):

```swift
    @Test("A verified main change rides along on an info note")
    func mainChangeOnInfoNote() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: (2560, 1440), requestedHz: 60,
            appliedSize: (2560, 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .changed(displayName: "LG"))
        #expect(note?.tone == .info)
        #expect(note?.mainDetail == .mainChanged(display: "LG"))
    }

    @Test("A skipped main change lowers a clean apply to fallback tone")
    func skippedMainIsFallback() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: (2560, 1440), requestedHz: 60,
            appliedSize: (2560, 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .skippedAmbiguous(count: 2))
        #expect(note?.tone == .fallback)
        #expect(note?.mainDetail == .mainAmbiguous(count: 2))
    }

    @Test("A failed main change makes the note a problem")
    func failedMainIsProblem() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: (2560, 1440), requestedHz: 60,
            appliedSize: (2560, 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .failed("boom"))
        #expect(note?.tone == .problem)
        #expect(note?.mainDetail == .mainFailed(message: "boom"))
    }

    @Test("alreadyMain adds nothing to the note")
    func alreadyMainSilent() {
        let outcomes = [ProfileStore.ApplyOutcome(
            displayName: "LG", matcherKind: .specific,
            requestedSize: (2560, 1440), requestedHz: 60,
            appliedSize: (2560, 1440), appliedHz: 60, status: .applied
        )]
        let note = ApplyOutcomeNote.make(from: outcomes, mainChange: .alreadyMain)
        #expect(note?.mainDetail == nil)
        #expect(note?.tone == .info)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `make test`
Expected: compile errors — no `mainChange` parameter, no `mainDetail`.

- [ ] **Step 3: Implement `ApplyOutcomeNote`**

New `Detail` cases (after `.failed`, line 31):

```swift
        case mainChanged(display: String)
        case mainAdjusted(display: String)
        case mainNotConnected
        case mainAmbiguous(count: Int)
        case mainMirrored
        case mainFailed(message: String)
```

Struct fields and tone escalation (replace lines 41–42):

```swift
    let tone: Tone
    let content: Content
    /// The main-display line, rendered after the per-display content. Kept
    /// separate from Content so the aggregation precedence above stays about
    /// modes only.
    let mainDetail: Detail?

    init(tone: Tone, content: Content, mainDetail: Detail? = nil) {
        self.tone = tone
        self.content = content
        self.mainDetail = mainDetail
    }
```

`make` — rename the existing body to a private `modeNote(from:)` (its `ApplyOutcomeNote(tone:content:)` constructions are unchanged thanks to the defaulted init) and compose:

```swift
    static func make(
        from outcomes: [ProfileStore.ApplyOutcome],
        mainChange: ProfileStore.MainChangeOutcome? = nil
    ) -> ApplyOutcomeNote? {
        let base = modeNote(from: outcomes)
        guard let (detail, mainTone) = mainDetail(for: mainChange) else { return base }
        // The main line rides on whatever the modes produced; when the modes
        // produced nothing (rare mixed statuses), it still deserves a note.
        let content = base?.content ?? .alreadyAtSavedSettings
        return ApplyOutcomeNote(
            tone: max(base?.tone ?? .info, mainTone),
            content: content,
            mainDetail: detail
        )
    }

    private static func mainDetail(
        for change: ProfileStore.MainChangeOutcome?
    ) -> (Detail, Tone)? {
        switch change {
        case nil, .alreadyMain:
            return nil
        case .changed(let name):
            return (.mainChanged(display: name), .info)
        case .changedButAdjusted(let name):
            return (.mainAdjusted(display: name), .fallback)
        case .skippedNoMatch:
            return (.mainNotConnected, .fallback)
        case .skippedAmbiguous(let count):
            return (.mainAmbiguous(count: count), .fallback)
        case .skippedMirrored:
            return (.mainMirrored, .fallback)
        case .failed(let message):
            return (.mainFailed(message: message), .problem)
        }
    }
```

Tone ordering (extend the `Tone` enum):

```swift
    enum Tone: Equatable, Comparable {
        case info
        case fallback
        case problem
    }
```

(`Comparable` on a `String`-free enum synthesises case-declaration order: info < fallback < problem — exactly the severity ranking.)

Localised copy — add to `Detail.localizedDescription` (after `.failed`, line 204):

```swift
        case let .mainChanged(display):
            return String(localized: LocalizedStringResource(
                "note.detail.mainChanged",
                defaultValue: "Main display \u{2192} \(display)",
                comment: "The menu bar moved to this display. 1: display name"
            ))

        case let .mainAdjusted(display):
            return String(localized: LocalizedStringResource(
                "note.detail.mainAdjusted",
                defaultValue: "Main display \u{2192} \(display), but macOS adjusted the arrangement",
                comment: "Main display was set but the layout differs from what was requested. 1: display name"
            ))

        case .mainNotConnected:
            return String(localized: LocalizedStringResource(
                "note.detail.mainNotConnected",
                defaultValue: "Main display unchanged — the saved display is not connected",
                comment: "The profile's main display is not attached"
            ))

        case let .mainAmbiguous(count):
            return String(localized: LocalizedStringResource(
                "note.detail.mainAmbiguous",
                defaultValue: "Main display unchanged — \(count) connected displays match",
                comment: "Several displays match the saved main. 1: how many"
            ))

        case .mainMirrored:
            return String(localized: LocalizedStringResource(
                "note.detail.mainMirrored",
                defaultValue: "Main display unchanged — displays are mirrored",
                comment: "Arrangement is not touched while mirroring is on"
            ))

        case let .mainFailed(message):
            return String(localized: LocalizedStringResource(
                "note.detail.mainFailed",
                defaultValue: "Main display unchanged: \(message)",
                comment: "Setting the main display failed. 1: system error text"
            ))
        }
```

And render it — in the note-level `localizedDescription` (line 215), append at the end:

```swift
    var localizedDescription: String {
        let base: String
        switch content {
        // ... existing cases assign to `base` instead of returning ...
        }
        guard let mainDetail else { return base }
        return base + "; " + mainDetail.localizedDescription
    }
```

(Mechanical change: each `return X` in the switch becomes `base = X`.)

- [ ] **Step 4: Wire the callers**

`VibeRes/UI/ProfilesSection.swift` — `announceOutcome` (line 1272):

```swift
    private func announceOutcome(_ result: ProfileStore.ProfileApplyResult) {
        guard let note = ApplyOutcomeNote.make(from: result.outcomes, mainChange: result.mainChange) else {
            lastNote = nil
            return
        }
        lastNoteTone = note.tone
        lastNote = .outcome(note)
        scheduleNoteClear()
    }
```

Its caller(s) pass the whole `ProfileApplyResult` from Task 4's call sites (drop the interim `.outcomes` unwrapping added there).

`VibeResCLI/main.swift` — `cmdProfileApply` after the outcome loop (before the `if hadProblem` line):

```swift
    if let main = result.mainChange {
        switch main {
        case .changed(let name):
            print("  ✓ main display → \(name)")
        case .alreadyMain:
            print("  = main display already \(profile.name)'s choice")
        case .changedButAdjusted:
            print("  ~ \(main.problemSummary ?? "")"); hadProblem = true
        case .skippedNoMatch, .skippedAmbiguous, .skippedMirrored, .failed:
            print("  ✗ \(main.problemSummary ?? "")"); hadProblem = true
        }
    }
```

`cmdProfileList` — after the entry loop (line 292):

```swift
    if let main = p.mainDisplay {
        let kind: String
        switch main {
        case .builtIn: kind = "built-in"
        case .anyExternal: kind = "any external"
        case .edid: kind = "specific"
        }
        print("  main: \(kind)")
    }
```

- [ ] **Step 5: Run tests**

Run: `make test`
Expected: PASS, including existing ApplyOutcomeNoteTests (defaulted `mainChange:` keeps old calls compiling; `Comparable` on Tone is additive).

- [ ] **Step 6: Commit**

```bash
git add VibeRes/UI/ApplyOutcomeNote.swift VibeRes/UI/ProfilesSection.swift VibeResCLI/main.swift VibeResTests/ApplyOutcomeNoteTests.swift
git commit -m "Report the main-display outcome in the popover note and CLI"
```

---

### Task 9: Docs, changelog, and the manual multi-monitor checklist

**Files:**
- Modify: `BACKLOG.md` (lines 47–82, the "Display arrangement preservation" entry)
- Modify: `docs/display-arrangement-spike-2026-08-01.md` (status line 5)
- Modify: `CHANGELOG.md` (new 0.9.0 section, matching the file's existing format)
- Modify: `README.md` (profiles feature bullet — mention the optional main-display pick, matching existing tone)

**Interfaces:** none — documentation and verification only.

- [ ] **Step 1: Update BACKLOG.md**

In the "Display arrangement preservation" entry, after the "Spiked 2026-08-01" paragraph (line 52–58), add:

```markdown
**Stage 1 shipped in 0.9.0** — a profile can pin which display is main
(`Profile.mainDisplay`), applied as a full-coverage origin translation with
post-commit verification and Revert support. Stage 2 (full stored geometry)
remains deferred; see
[the implementation plan](docs/superpowers/plans/2026-08-01-main-display-in-profile.md).
```

In "Known limitations → Display arrangement reset by macOS on extreme resolution change" (line 170), update the "When to revisit" line to note Stage 1 shipped but does not address reshuffles (it stores no geometry) — Stage 2 still owns that.

- [ ] **Step 2: Update the spike doc status**

Line 5: `Status: **spike complete, feature not implemented**` becomes:

```markdown
Status: **spike complete; Stage 1 implemented in 0.9.0** (see docs/superpowers/plans/2026-08-01-main-display-in-profile.md)
```

- [ ] **Step 3: CHANGELOG and README**

Add a 0.9.0 "Added" entry describing the feature from the user's point of view (a profile can make a chosen display the main one; "Don't change" remains the default; Revert restores the previous main). Update README's profile description with one sentence. Match each file's existing structure — read them first.

- [ ] **Step 4: Manual multi-monitor checklist**

⚠️ Requires the user's real desk setup (≥2 displays). Build `make app`, run the app, and walk through — record each result in the PR/commit message:

1. Save a profile with main = external; apply while built-in is main → menu bar moves, note reads "Main display → …", System Settings → Displays agrees.
2. Revert (menubar button) → menu bar returns, modes return, history empty.
3. Apply the same profile again → main line; apply once more → no "Applied…" toast from auto-apply paths (alreadyMain + alreadyApplied are silent no-ops).
4. Profile with main + a *mode change on the target display* in the same apply → both land; arrangement stays sane (this is the two-phase case).
5. Unplug the profile's main display; apply → modes still apply, note says main unchanged / not connected.
6. `.anyExternal` main with two externals connected → note says ambiguous, arrangement untouched.
7. Mirror displays in System Settings; apply → note says mirrored, arrangement untouched.
8. Close the lid (clamshell) and apply a profile via CLI → no origin transaction attempted on a not-active display (check Console.app, subsystem sk.moravcik.VibeRes).
9. CLI: `viberes profile apply "<name>"` prints the main line; `viberes profile list` shows `main:`.
10. Regression for the Task 7 fix: edit a profile's resolution, save, reopen edit → new resolution stuck.
11. Regression: apply a pre-existing profile (no main) → behaves exactly as 0.8.6.

- [ ] **Step 5: Full suite + commit**

```bash
make test
git add BACKLOG.md docs/display-arrangement-spike-2026-08-01.md CHANGELOG.md README.md
git commit -m "Document the main-display profile feature and Stage 2 status"
```

---

## Deviations from the spike doc's Stage 1 sketch (intentional)

1. **`applyBatch` is not extended with origins** — a separate `applyOrigins` transaction runs after the mode transaction. Rationale in the Architecture note: measured-safe plan shape (F2), no tolerant/atomic mixing (F1/F6), zero regression risk to the mode path. Cost: one extra reconfiguration when main actually changes.
2. **`RevertHistory.Entry` does not gain `beforeOrigin`** — per-entry origins cover only displays that changed mode, and replaying that subset is the partial statement F1 mangles. The history stores `beforeMainID` only; revert re-derives a full translation from live state.
3. **`.forSession` stays out of Stage 1** — profile applies are `.permanently` and revert is an explicit re-apply, matching current behaviour. Task 0 measures `.forSession` so a future "Keep this arrangement?" countdown can be a follow-up decision based on data.
