import AppKit
import CoreGraphics
import Foundation

// Throwaway spike for the deferred "display arrangement" feature. NOT shipped
// code and not part of any build target — `project.yml` scopes sources to
// VibeRes/, VibeRes/Core/, VibeResCLI/ and VibeResTests/, so this file is inert
// where it sits. Kept only so the measurements can be re-run.
//
// Results and what they mean for the design:
//   docs/display-arrangement-spike-2026-08-01.md
//
//   swiftc -O -o spike display-arrangement-spike.swift \
//       -framework AppKit -framework CoreGraphics
//
// Questions under test:
//   Q1  Does CGConfigureDisplayOrigin(cfg, target, 0, 0) make `target` the main
//       display (i.e. move the menu bar)?          -> mode `main`     (answer: no)
//   Q2  Is the relative topology of the others preserved automatically?
//                                                  -> mode `main`     (answer: no)
//   Q1' Q2' Same, but specifying every active display's origin in one
//       transaction.                               -> mode `mainfull` (answer: yes)
//   Q3  Does WindowServer honour requested origins exactly, or snap them?
//                                                  -> modes `origin`, `mainfull`
//   Q4  Does scope .forAppOnly auto-revert when the process exits?
//                                                  -> any mode + `norestore`
//   Q5  Do a mode change and an origin change commit together, resolved against
//       the post-change geometry?                  -> mode `combo`    (answer: yes)
//   F6  Does a bad display id fail at staging or at commit?
//                                                  -> mode `errors`
//
// Safety: every mutation uses .forAppOnly (auto-reverts on exit) AND an explicit
// restore transaction which is verified against a before-snapshot. `setall` is
// the manual recovery hatch if a run is interrupted.
//
// Requires at least two awake displays. A closed lid is enough to make this
// abort: a sleeping display is ONLINE but not ACTIVE.

// MARK: - CGError naming

func errName(_ e: CGError) -> String {
    switch e.rawValue {
    case 0: return "success"
    case 1000: return "kCGErrorFailure"
    case 1001: return "kCGErrorIllegalArgument"
    case 1002: return "kCGErrorInvalidConnection"
    case 1003: return "kCGErrorInvalidContext"
    case 1004: return "kCGErrorCannotComplete"
    case 1006: return "kCGErrorNotImplemented"
    case 1007: return "kCGErrorRangeCheck"
    case 1008: return "kCGErrorTypeCheck"
    case 1010: return "kCGErrorInvalidOperation"
    case 1011: return "kCGErrorNoneAvailable"
    default: return "undocumented(\(e.rawValue))"
    }
}

// MARK: - Display state

func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count))).sorted()
}

func onlineCount() -> UInt32 {
    var n: UInt32 = 0
    _ = CGGetOnlineDisplayList(0, nil, &n)
    return n
}

struct Snap {
    let main: CGDirectDisplayID
    let bounds: [CGDirectDisplayID: CGRect]
    let menuBarHost: CGDirectDisplayID

    static func take() -> Snap {
        var b: [CGDirectDisplayID: CGRect] = [:]
        for id in activeDisplays() { b[id] = CGDisplayBounds(id) }
        let mb = (NSScreen.screens.first?
            .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return Snap(main: CGMainDisplayID(), bounds: b, menuBarHost: mb)
    }

    func print_(_ label: String) {
        print("[\(label)] CGMainDisplayID=\(main)  NSScreen[0](menu bar)=\(menuBarHost)")
        for id in bounds.keys.sorted() {
            let r = bounds[id]!
            print(String(format: "    id=%-4u origin=(%7.0f,%7.0f) size=%5.0fx%-5.0f %@%@",
                         id, r.origin.x, r.origin.y, r.width, r.height,
                         CGDisplayIsBuiltin(id) != 0 ? "[builtin] " : "[external]",
                         id == main ? " <MAIN>" : ""))
        }
    }

    /// Origin of each display expressed relative to the main display, which
    /// removes the coordinate-space renormalisation that happens on main swap.
    /// If this map is stable across a main swap, topology was preserved.
    var relativeToMain: [CGDirectDisplayID: CGPoint] {
        guard let m = bounds[main] else { return [:] }
        var out: [CGDirectDisplayID: CGPoint] = [:]
        for (id, r) in bounds {
            out[id] = CGPoint(x: r.origin.x - m.origin.x, y: r.origin.y - m.origin.y)
        }
        return out
    }

    /// Topology independent of which display is main: sorted pairwise offsets
    /// keyed by display id, anchored on the lowest id so it survives renumbering
    /// of the coordinate space.
    var anchoredLayout: [CGDirectDisplayID: CGPoint] {
        guard let anchor = bounds.keys.sorted().first, let a = bounds[anchor] else { return [:] }
        var out: [CGDirectDisplayID: CGPoint] = [:]
        for (id, r) in bounds {
            out[id] = CGPoint(x: r.origin.x - a.origin.x, y: r.origin.y - a.origin.y)
        }
        return out
    }
}

// MARK: - Configuration helpers

@discardableResult
func transaction(_ label: String, scope: CGConfigureOption, _ body: (CGDisplayConfigRef?) -> CGError) -> Bool {
    var cfg: CGDisplayConfigRef?
    let b = CGBeginDisplayConfiguration(&cfg)
    guard b == .success else { print("  !! [\(label)] begin: \(errName(b))"); return false }
    let inner = body(cfg)
    guard inner == .success else {
        print("  !! [\(label)] configure: \(errName(inner))")
        CGCancelDisplayConfiguration(cfg)
        return false
    }
    let c = CGCompleteDisplayConfiguration(cfg, scope)
    guard c == .success else { print("  !! [\(label)] complete: \(errName(c))"); return false }
    print("  ✓ [\(label)] committed (scope=\(scope.rawValue))")
    return true
}

func restore(to original: Snap) -> Bool {
    print("\n>>> explicit restore")
    let ok = transaction("restore", scope: .permanently) { cfg in
        // Put the original main back at (0,0) first, then the rest at their
        // captured origins relative to it.
        guard let mainRect = original.bounds[original.main] else { return .failure }
        var err = CGConfigureDisplayOrigin(cfg, original.main, 0, 0)
        if err != .success { return err }
        for (id, r) in original.bounds where id != original.main {
            let dx = Int32(r.origin.x - mainRect.origin.x)
            let dy = Int32(r.origin.y - mainRect.origin.y)
            err = CGConfigureDisplayOrigin(cfg, id, dx, dy)
            if err != .success { return err }
        }
        return .success
    }
    Thread.sleep(forTimeInterval: 1.5)
    let now = Snap.take()
    let mainOK = now.main == original.main
    let boundsOK = now.bounds.keys.sorted() == original.bounds.keys.sorted()
        && now.bounds.allSatisfy { original.bounds[$0.key] == $0.value }
    print("  restore verify: main=\(mainOK ? "OK" : "MISMATCH") bounds=\(boundsOK ? "OK" : "MISMATCH")")
    if !boundsOK { now.print_("RESTORED-STATE") }
    return ok && mainOK && boundsOK
}

// MARK: - Modes that run regardless of how many displays are active

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "state"
/// Skip the explicit restore so .forAppOnly auto-revert can be observed from
/// outside the process. Recovery path is `spike setall id:x:y ...`.
let noRestore = CommandLine.arguments.contains("norestore")
_ = NSScreen.screens  // establish WindowServer connection before configuring

// Unconditional recovery hatch: set every origin explicitly and permanently.
if mode == "setall" {
    var plan: [(CGDirectDisplayID, Int32, Int32)] = []
    for a in CommandLine.arguments.dropFirst(2) {
        let p = a.split(separator: ":")
        guard p.count == 3, let i = CGDirectDisplayID(p[0]),
              let x = Int32(p[1]), let y = Int32(p[2]) else {
            print("bad triple '\(a)', want id:x:y"); exit(2)
        }
        plan.append((i, x, y))
    }
    guard !plan.isEmpty else { print("usage: spike setall id:x:y [id:x:y ...]"); exit(2) }
    for p in plan { print("  set id=\(p.0) -> (\(p.1),\(p.2))") }
    let ok = transaction("setall", scope: .permanently) { cfg in
        for (id, x, y) in plan {
            let e = CGConfigureDisplayOrigin(cfg, id, x, y)
            if e != .success { return e }
        }
        return .success
    }
    Thread.sleep(forTimeInterval: 1.5)
    Snap.take().print_("RESULT")
    exit(ok ? 0 : 1)
}

// F6: where does CoreGraphics report a bad display — staging or commit?
// Neither probe can disturb a real display: both target ids that do not exist.
//
// Both ids here are never-known, so both are rejected at staging, which is the
// harmless case. The dangerous case — staging succeeds and the whole commit
// fails — needs an id that WAS active earlier in the same session. To see it,
// unplug a monitor and re-run against the id it used to have.
if mode == "errors" {
    func probe(_ label: String, _ id: CGDirectDisplayID) {
        var cfg: CGDisplayConfigRef?
        let b = CGBeginDisplayConfiguration(&cfg)
        let o = CGConfigureDisplayOrigin(cfg, id, 0, 0)
        let c = (o == .success) ? CGCompleteDisplayConfiguration(cfg, .forAppOnly) : CGError.success
        if o != .success { CGCancelDisplayConfiguration(cfg) }
        print("\(label) id=\(id): begin=\(errName(b)) configure=\(errName(o)) complete=\(errName(c))")
    }
    probe("bogus-id        ", 999)
    probe("plausible-absent", (activeDisplays().max() ?? 1) + 1)
    exit(0)
}

let active = activeDisplays()
print("active=\(active.count) online=\(onlineCount()) ids=\(active)")

if mode == "state" {
    Snap.take().print_("STATE")
    exit(active.count >= 2 ? 0 : 1)
}

guard active.count >= (mode == "origin" ? 1 : 2) else {
    print("""

    ABORT: need >= 2 active displays, have \(active.count) (online=\(onlineCount())).
    Cause: a display that is asleep or in clamshell is ONLINE but not ACTIVE.
    Open the lid / wake the external monitor and re-run.
    """)
    exit(1)
}

let original = Snap.take()
original.print_("BEFORE")

// MARK: - Tests

switch mode {
case "main":
    // Q1/Q2: make the non-main display main by moving it to (0,0).
    guard let target = active.first(where: { $0 != original.main }) else { exit(1) }
    print("\n>>> Q1: CGConfigureDisplayOrigin(display \(target) -> (0,0)), scope=.forAppOnly")
    let ok = transaction("main-swap", scope: .forAppOnly) { cfg in
        CGConfigureDisplayOrigin(cfg, target, 0, 0)
    }
    guard ok else { exit(1) }
    Thread.sleep(forTimeInterval: 2.0)
    let after = Snap.take()
    after.print_("AFTER")

    print("\n--- results ---")
    print("Q1 main moved:      \(original.main) -> \(after.main)  => \(after.main == target ? "YES" : "NO")")
    print("Q1 menu bar moved:  \(original.menuBarHost) -> \(after.menuBarHost)  => \(after.menuBarHost == target ? "YES" : "NO")")
    let bl = original.anchoredLayout, al = after.anchoredLayout
    let same = bl.keys.sorted() == al.keys.sorted() && bl.allSatisfy { al[$0.key] == $0.value }
    print("Q2 topology:        before \(bl.map { "\($0.key):(\(Int($0.value.x)),\(Int($0.value.y)))" }.sorted())")
    print("                    after  \(al.map { "\($0.key):(\(Int($0.value.x)),\(Int($0.value.y)))" }.sorted())")
    print("Q2 preserved:       \(same ? "YES" : "NO")")

case "mainfull":
    // Q1'/Q2': same goal as "main", but specify the COMPLETE arrangement in one
    // transaction — every display renormalised so the target sits at (0,0) and
    // relative topology is preserved by construction. This is what displayplacer
    // does, and the "main" test suggests partial specification is what breaks.
    let scopeArg = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "app"
    let scope: CGConfigureOption = (scopeArg == "perm") ? .permanently
        : (scopeArg == "session") ? .forSession : .forAppOnly
    guard let target = active.first(where: { $0 != original.main }),
          let t = original.bounds[target] else { exit(1) }

    print("\n>>> Q1': renormalise ALL origins so display \(target) is at (0,0), scope=\(scopeArg)")
    var plan: [(CGDirectDisplayID, Int32, Int32)] = []
    for id in original.bounds.keys.sorted() {
        let r = original.bounds[id]!
        plan.append((id, Int32(r.origin.x - t.origin.x), Int32(r.origin.y - t.origin.y)))
    }
    for p in plan { print("    plan: id=\(p.0) -> (\(p.1),\(p.2))") }

    let ok = transaction("main-full", scope: scope) { cfg in
        for (id, x, y) in plan {
            let e = CGConfigureDisplayOrigin(cfg, id, x, y)
            if e != .success { return e }
        }
        return .success
    }
    guard ok else { exit(1) }
    Thread.sleep(forTimeInterval: 2.0)
    let after = Snap.take()
    after.print_("AFTER")

    print("\n--- results ---")
    print("Q1' main moved:     \(original.main) -> \(after.main)  => \(after.main == target ? "YES" : "NO")")
    print("Q1' menu bar moved: \(original.menuBarHost) -> \(after.menuBarHost)  => \(after.menuBarHost == target ? "YES" : "NO")")
    var exactAll = true
    for (id, x, y) in plan {
        guard let got = after.bounds[id] else { exactAll = false; continue }
        let exact = Int32(got.origin.x) == x && Int32(got.origin.y) == y
        if !exact { exactAll = false }
        print("    id=\(id) requested (\(x),\(y)) actual (\(Int(got.origin.x)),\(Int(got.origin.y))) \(exact ? "EXACT" : "SNAPPED")")
    }
    print("Q3' all origins exact: \(exactAll ? "YES" : "NO")")
    let bl = original.anchoredLayout, al = after.anchoredLayout
    let same = bl.keys.sorted() == al.keys.sorted() && bl.allSatisfy { al[$0.key] == $0.value }
    print("Q2' topology preserved: \(same ? "YES" : "NO")")

case "combo":
    // Q5: mode change + origin change in ONE transaction. Changing a display's
    // mode changes its size in points, so the arrangement maths depends on the
    // NEW size. Does WindowServer resolve origins against the post-change
    // geometry, or against the geometry as it was when the transaction opened?
    guard let target = active.first(where: { $0 != original.main }),
          let cur = CGDisplayCopyDisplayMode(target),
          let all = CGDisplayCopyAllDisplayModes(target, nil) as? [CGDisplayMode] else { exit(1) }
    // Pick a mode with a clearly different point width so the geometry shift is
    // unambiguous.
    guard let newMode = all.first(where: { $0.width != cur.width && $0.width >= 1280 && $0.pixelWidth == $0.width }) else {
        print("no suitable alternate mode found on display \(target)"); exit(1)
    }
    print("\n>>> Q5: display \(target) mode \(cur.width)x\(cur.height) -> \(newMode.width)x\(newMode.height) + all origins, one transaction")

    // Place the target immediately LEFT of the main display, which is only
    // correct if its NEW width is what counts.
    let mainRect = original.bounds[original.main]!
    var plan: [(CGDirectDisplayID, Int32, Int32)] = []
    for id in original.bounds.keys.sorted() {
        if id == original.main {
            plan.append((id, 0, 0))
        } else if id == target {
            plan.append((id, Int32(-newMode.width), 0))
        } else {
            let r = original.bounds[id]!
            plan.append((id, Int32(r.origin.x - mainRect.origin.x), Int32(r.origin.y - mainRect.origin.y)))
        }
    }
    for p in plan { print("    plan: id=\(p.0) -> (\(p.1),\(p.2))") }

    let ok = transaction("combo", scope: .forAppOnly) { cfg in
        let e = CGConfigureDisplayWithDisplayMode(cfg, target, newMode, nil)
        if e != .success { return e }
        for (id, x, y) in plan {
            let e2 = CGConfigureDisplayOrigin(cfg, id, x, y)
            if e2 != .success { return e2 }
        }
        return .success
    }
    guard ok else { exit(1) }
    Thread.sleep(forTimeInterval: 2.5)
    let after = Snap.take()
    after.print_("AFTER")

    print("\n--- results ---")
    let gotMode = CGDisplayCopyDisplayMode(target)
    print("Q5 mode applied:    \(gotMode?.width ?? 0)x\(gotMode?.height ?? 0) => \(gotMode?.width == newMode.width ? "YES" : "NO")")
    var exactAll = true
    for (id, x, y) in plan {
        guard let got = after.bounds[id] else { exactAll = false; continue }
        let exact = Int32(got.origin.x) == x && Int32(got.origin.y) == y
        if !exact { exactAll = false }
        print("    id=\(id) requested (\(x),\(y)) actual (\(Int(got.origin.x)),\(Int(got.origin.y))) \(exact ? "EXACT" : "SNAPPED")")
    }
    print("Q5 origins exact against NEW geometry: \(exactAll ? "YES" : "NO")")

case "origin":
    // Q3: request a deliberately overlapping origin and see what lands.
    guard CommandLine.arguments.count >= 5,
          let target = CGDirectDisplayID(CommandLine.arguments[2]),
          let x = Int32(CommandLine.arguments[3]),
          let y = Int32(CommandLine.arguments[4]) else {
        print("usage: spike origin <displayID> <x> <y>"); exit(2)
    }
    guard active.contains(target) else {
        print("ABORT: display \(target) is not active. active=\(active)"); exit(1)
    }
    print("\n>>> Q3: request origin (\(x),\(y)) for display \(target)")
    let ok = transaction("origin", scope: .forAppOnly) { cfg in
        CGConfigureDisplayOrigin(cfg, target, x, y)
    }
    guard ok else { exit(1) }
    Thread.sleep(forTimeInterval: 2.0)
    let after = Snap.take()
    after.print_("AFTER")
    if let got = after.bounds[target] {
        let exact = Int32(got.origin.x) == x && Int32(got.origin.y) == y
        print("\nQ3 requested (\(x),\(y)) -> actual (\(Int(got.origin.x)),\(Int(got.origin.y))): \(exact ? "EXACT" : "SNAPPED")")
    }

default:
    print("usage: spike [state|main|origin <id> <x> <y>]"); exit(2)
}

// MARK: - Restore + Q4

if noRestore {
    print("""

    >>> exiting WITHOUT explicit restore (Q4). Probe from the shell now.
        Recovery if .forAppOnly does not auto-revert:
        ./spike setall \(original.bounds.keys.sorted().map { "\($0):\(Int(original.bounds[$0]!.origin.x)):\(Int(original.bounds[$0]!.origin.y))" }.joined(separator: " "))
    """)
    exit(0)
}

print("\n>>> holding 3s so the change is observable, then testing .forAppOnly auto-revert")
Thread.sleep(forTimeInterval: 3.0)

let preExit = Snap.take()
let stillChanged = preExit.main != original.main
    || !preExit.bounds.allSatisfy { original.bounds[$0.key] == $0.value }
print("state still changed right before restore: \(stillChanged)")

// Explicit restore regardless — do not rely on .forAppOnly alone.
let restored = restore(to: original)
print("\n=== RESTORE \(restored ? "OK" : "FAILED — check System Settings > Displays > Arrange") ===")
