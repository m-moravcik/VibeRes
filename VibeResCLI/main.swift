import AppKit
import CoreGraphics
import Foundation

// MARK: - Output helpers

func print2(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

func fail(_ s: String) -> Never {
    print2("error: \(s)")
    exit(1)
}

// MARK: - Display lookup

extension DisplayInfo {
    /// Match by full name (case-insensitive) or by numeric CGDirectDisplayID.
    static func find(_ needle: String, in displays: [DisplayInfo]) -> DisplayInfo? {
        let n = needle.lowercased()
        if let id = UInt32(needle), let hit = displays.first(where: { $0.id == id }) {
            return hit
        }
        // Exact match first, then prefix.
        if let hit = displays.first(where: { $0.name.lowercased() == n }) {
            return hit
        }
        if let hit = displays.first(where: { $0.name.lowercased().hasPrefix(n) }) {
            return hit
        }
        return displays.first(where: { $0.name.lowercased().contains(n) })
    }
}

// MARK: - Mode formatting

extension CGDisplayMode {
    /// One-line CLI-friendly description: "1800x1169 @ 120Hz HiDPI [id=66]"
    var cliDescription: String {
        var parts = ["\(width)x\(height)"]
        if let hz = refreshHz { parts.append("@\(hz)Hz") }
        if isHiDPI { parts.append("HiDPI") }
        parts.append("[id=\(ioDisplayModeID)]")
        return parts.joined(separator: " ")
    }
}

// MARK: - Argument parsing

struct ResolutionSpec {
    var width: Int
    var height: Int
    var refreshHz: Int?
    var preferHiDPI: Bool

    /// Parse strings like:
    ///   "1800x1169"          → 1800×1169, no refresh, default HiDPI prefer
    ///   "1800x1169@120"      → with refresh
    ///   "1920x1080@60-native" → native (non-HiDPI)
    ///   "1920x1080-hidpi"    → HiDPI
    static func parse(_ s: String) -> ResolutionSpec? {
        var spec = ResolutionSpec(width: 0, height: 0, refreshHz: nil, preferHiDPI: true)
        var rest = s.lowercased()

        if rest.hasSuffix("-native") {
            spec.preferHiDPI = false
            rest.removeLast("-native".count)
        } else if rest.hasSuffix("-hidpi") {
            spec.preferHiDPI = true
            rest.removeLast("-hidpi".count)
        }

        let parts = rest.split(separator: "@", maxSplits: 1).map(String.init)
        guard let dim = parts.first else { return nil }
        let dims = dim.split(separator: "x", maxSplits: 1).map(String.init)
        guard dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]) else { return nil }
        // Clamp to sane physical-display limits to keep scoring math safe even
        // when the user feeds the CLI a number outside the realistic range.
        guard (1...16384).contains(w), (1...16384).contains(h) else { return nil }
        spec.width = w
        spec.height = h

        if parts.count == 2 {
            let hz = parts[1].replacingOccurrences(of: "hz", with: "")
            if let rate = Int(hz), (1...1000).contains(rate) {
                spec.refreshHz = rate
            } else {
                return nil
            }
        }
        return spec
    }
}

// MARK: - Best-match scoring (mirrors SetResolutionIntent)

func bestMatch(in modes: [CGDisplayMode], spec: ResolutionSpec) -> CGDisplayMode? {
    ModeScoring.bestMatch(
        in: modes,
        request: ModeScoring.Request(
            width: spec.width,
            height: spec.height,
            refreshHz: spec.refreshHz,
            preferHiDPI: spec.preferHiDPI
        )
    )
}

// MARK: - Profile lookup

/// Resolves a profile handle — a name or the id `profile list` prints — or
/// exits with a message.
///
/// Every profile subcommand goes through this so none of them can quietly pick
/// the first of two profiles sharing a name. The store refuses to create that
/// state now, but a catalog written by an older build can already be in it.
@MainActor
func requireProfile(_ needle: String, in store: ProfileStore) -> Profile {
    switch store.resolve(needle) {
    case .found(let profile):
        return profile
    case .notFound:
        fail("no profile named \"\(needle)\"")
    case .ambiguous(let count):
        fail("""
        \(count) profiles are named "\(needle)" — rename one, or address it by id:
          viberes profile list
        """)
    }
}

/// Turns a rejected save into an exit. Shared so the wording cannot drift
/// between `profile save` and `profile rename`.
@MainActor
func failOnRejection(_ result: ProfileStore.SaveResult) {
    switch result {
    case .saved, .savedWithMissingDisplays:
        return
    case .rejectedEmptyName:
        fail("a profile name cannot be blank")
    case .rejectedDuplicateName(let name):
        fail("a profile named \"\(name)\" already exists")
    case .rejectedNotFound:
        fail("that profile is no longer in the store")
    case .rejectedEmpty:
        fail("no displays selected for the profile")
    case .rejectedMultipleAnyExternal:
        fail("a profile can have at most one 'any external' entry — remove --any-external from one of the displays")
    }
}

// MARK: - Profile main-display formatting

/// Compact "main:" line label — shared by `profile list` and `profile show`
/// so the two commands cannot drift on the mapping.
func mainKindLabel(_ matcher: DisplayMatcher) -> String {
    switch matcher {
    case .builtIn: return "built-in"
    case .anyExternal: return "any external"
    case .edid: return "specific"
    }
}

// MARK: - Commands

func cmdHelp() {
    let help = """
    viberes — VibeRes command-line companion

    Usage:
      viberes list                              List all connected displays
      viberes modes <display>                   List modes available on a display
      viberes current [<display>]               Show current mode (default: all displays)
      viberes set <display> <WxH[@Hz][-hidpi|-native]>
                                                Switch a display to the closest matching mode
      viberes profile list                      List saved profiles
      viberes profile show <name>               Show details (matchers, sizes, refresh)
      viberes profile save <name> [--any-external] [--only <display>...]
                                                Capture current state as a profile.
                                                  --any-external makes external entries flexible
                                                    (matches any non-built-in display, not just
                                                    the one you saved from).
                                                  --only restricts the profile to listed displays.
      viberes profile apply <name>              Apply a profile (prints per-display outcome)
      viberes profile update <name>             Refresh profile entries from current
                                                  display state (keeps name, id, matchers)
      viberes profile flex <name>               Toggle external entries between
                                                  specific (EDID) and flexible (any external)
      viberes profile delete <name>             Delete a profile
      viberes profile rename <old> <new>        Rename a profile

    Environment:
      VIBERES_PROFILE_DIR   Read and write profiles in this directory instead
                            of ~/Library/Application Support/VibeRes.

    <display> can be a (case-insensitive substring of a) display name or its numeric ID.
    <name> can be a profile name (case-insensitive) or the id `profile list` prints.
      Profile names are unique, so a name always identifies one profile; a
      catalog saved by an older version could hold duplicates, and those are
      reported rather than guessed at.

    Examples:
      viberes list
      viberes set "Built-in" 1800x1169@120
      viberes set Q3279 2560x1440-native
      viberes profile save Work
      viberes profile save Presentation --any-external
      viberes profile save "Code Mode" --only Built-in
      viberes profile apply Presentation
    """
    print(help)
}

func cmdList() {
    let displays = DisplayManager.snapshot()
    if displays.isEmpty {
        print("(no displays connected)")
        return
    }
    for d in displays {
        let main = d.isMain ? " [MAIN]" : ""
        var line = "\(d.id)\t\(d.name)\(main)"
        if let cur = d.currentMode {
            line += "\t\(cur.cliDescription)"
        }
        print(line)
    }
}

func cmdModes(_ needle: String) {
    let displays = DisplayManager.snapshot()
    guard let display = DisplayInfo.find(needle, in: displays) else {
        fail("no display matching \"\(needle)\"")
    }
    print("# \(display.name) (id=\(display.id))")
    let groups = ResolutionGroup.build(from: display.modes)
    for g in groups {
        let kind = g.isHiDPI ? "HiDPI" : "Native"
        let rates = g.modesByRefresh.map { String($0.hz) }.joined(separator: ",")
        let curMark = g.modesByRefresh.contains { $0.mode.ioDisplayModeID == display.currentMode?.ioDisplayModeID } ? " *" : ""
        print("\(g.pointWidth)x\(g.pointHeight)\t\(kind)\t@[\(rates)]Hz\(curMark)")
    }
}

func cmdCurrent(_ needle: String?) {
    let displays = DisplayManager.snapshot()
    let targets: [DisplayInfo] = needle.flatMap { DisplayInfo.find($0, in: displays).map { [$0] } } ?? displays
    if targets.isEmpty {
        if let n = needle { fail("no display matching \"\(n)\"") }
        print("(no displays connected)")
        return
    }
    for d in targets {
        if let cur = d.currentMode {
            print("\(d.name)\t\(cur.cliDescription)")
        } else {
            print("\(d.name)\t(no current mode)")
        }
    }
}

func cmdSet(_ needle: String, _ specStr: String) {
    let displays = DisplayManager.snapshot()
    guard let display = DisplayInfo.find(needle, in: displays) else {
        fail("no display matching \"\(needle)\"")
    }
    guard let spec = ResolutionSpec.parse(specStr) else {
        fail("could not parse mode spec \"\(specStr)\". Try \"1800x1169@120\".")
    }
    guard let mode = bestMatch(in: display.modes, spec: spec) else {
        fail("no mode close to \(spec.width)x\(spec.height) on \(display.name)")
    }
    do {
        try ResolutionSwitcher.apply(mode, to: display.id)
        print("\(display.name) → \(mode.cliDescription)")
    } catch {
        fail(error.userFacingText)
    }
}

@MainActor
func cmdProfileList() {
    let store = ProfileStore()
    if store.profiles.isEmpty {
        print("(no profiles)")
        return
    }
    for p in store.profiles {
        print("\(p.name)\t\(p.entries.count) display\(p.entries.count == 1 ? "" : "s")\t\(p.id)")
        if let main = p.mainDisplay {
            print("  main: \(mainKindLabel(main))")
        }
    }
}

@MainActor
func cmdProfileSave(_ name: String, args: [String]) {
    let store = ProfileStore()
    // The name is checked first on purpose: it is wrong or right regardless of
    // what is plugged in, and answering "no displays connected" to someone who
    // typed a blank name is answering a question they did not ask.
    failOnRejection(store.nameVerdict(for: name))
    let displays = DisplayManager.snapshot()
    guard !displays.isEmpty else { fail("no displays connected") }

    let anyExternal = args.contains("--any-external")
    var onlyFilters: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == "--only", i + 1 < args.count {
            onlyFilters.append(args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }

    var selection: [CGDirectDisplayID: ProfileMatchKind] = [:]
    for d in displays {
        if !onlyFilters.isEmpty {
            let matched = onlyFilters.contains { needle in
                d.name.lowercased().contains(needle.lowercased()) || "\(d.id)" == needle
            }
            if !matched { continue }
        }
        let isBuiltin = CGDisplayIsBuiltin(d.id) != 0
        selection[d.id] = (anyExternal && !isBuiltin) ? .anyExternal : .specific
    }
    guard !selection.isEmpty else { fail("no displays matched the --only filter") }

    let result = store.captureCurrent(name: name, displays: displays, selection: selection)
    failOnRejection(result)
    switch result {
    case .savedWithMissingDisplays(let count):
        // Worth saying in a script too: the profile is smaller than asked for.
        print("saved profile \"\(name)\" — \(count) selected display(s) were not connected and were skipped")
    default:
        print("saved profile \"\(name)\" with \(selection.count) display\(selection.count == 1 ? "" : "s")")
    }
}

@MainActor
func cmdProfileShow(_ name: String) {
    let store = ProfileStore()
    let p = requireProfile(name, in: store)
    print("# \(p.name)\t(\(p.humanSummary))")
    for entry in p.entries {
        let kind: String
        switch entry.matcher {
        case .edid: kind = "specific"
        case .anyExternal: kind = "any-external"
        case .builtIn: kind = "built-in"
        }
        let hz = entry.refreshHz.map { "@\($0)Hz" } ?? "@?Hz"
        let scale = entry.isHiDPI ? "HiDPI" : "Native"
        print("  - \(entry.displayName) [\(kind)]\t\(entry.pointWidth)x\(entry.pointHeight) \(hz) \(scale)")
    }
    if let main = p.mainDisplay {
        print("  main: \(mainKindLabel(main))")
    }
}

@MainActor
func cmdProfileApply(_ name: String) {
    let store = ProfileStore()
    let profile = requireProfile(name, in: store)
    let displays = DisplayManager.snapshot()
    let result = store.applyDetailed(profile, displays: displays)
    var hadProblem = false
    print("# applied profile \"\(profile.name)\"")
    for o in result.outcomes {
        let icon: String
        switch o.status {
        case .applied: icon = "✓"
        case .alreadyApplied: icon = "="
        case .appliedWithFallback: icon = "~"; hadProblem = true
        case .skippedNoMatch, .skippedNoMode, .failed: icon = "✗"; hadProblem = true
        }
        print("  \(icon) \(o.summary)")
    }
    if let main = result.mainChange {
        switch main {
        case .changed(let displayName):
            print("  ✓ main display → \(displayName)")
        case .alreadyMain:
            print("  = main display unchanged (already main)")
        case .changedButAdjusted:
            print("  ~ \(main.problemSummary ?? "")"); hadProblem = true
        case .skippedNoMatch, .skippedAmbiguous, .skippedMirrored, .failed:
            print("  ✗ \(main.problemSummary ?? "")"); hadProblem = true
        }
    }
    if hadProblem { exit(2) }
}

@MainActor
func cmdProfileDelete(_ name: String) {
    let store = ProfileStore()
    let profile = requireProfile(name, in: store)
    store.delete(profile)
    print("deleted profile \"\(profile.name)\"")
}

@MainActor
func cmdProfileUpdate(_ name: String) {
    let store = ProfileStore()
    let profile = requireProfile(name, in: store)
    let displays = DisplayManager.snapshot()
    if let updated = store.updateFromCurrent(profile, displays: displays) {
        print("updated \"\(updated.name)\" with current setup (\(updated.entries.count) entries)")
    } else {
        fail("could not update — profile not found in store")
    }
}

@MainActor
func cmdProfileFlex(_ name: String) {
    let store = ProfileStore()
    let profile = requireProfile(name, in: store)
    let displays = DisplayManager.snapshot()
    switch store.toggleFlexible(profile, displays: displays) {
    case .madeFlexible:
        print("\"\(profile.name)\" is now flexible (any external)")
    case .madeSpecific:
        print("\"\(profile.name)\" is now specific (locked to monitors)")
    case .blockedNoExternal:
        fail("can't lock \"\(profile.name)\" — connect the external monitor first")
    }
}

@MainActor
func cmdProfileRename(_ old: String, _ new: String) {
    let store = ProfileStore()
    var profile = requireProfile(old, in: store)
    let previousName = profile.name
    profile.name = new
    // The store can refuse — a blank name, or one another profile already
    // holds. Printing "renamed" over a refusal is how the old code lied.
    failOnRejection(store.update(profile))
    print("renamed \"\(previousName)\" → \"\(new)\"")
}

// MARK: - Dispatcher

@MainActor
func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else {
        cmdHelp()
        return
    }

    switch cmd {
    case "help", "-h", "--help":
        cmdHelp()

    case "list":
        cmdList()

    case "modes":
        guard args.count == 2 else { fail("usage: viberes modes <display>") }
        cmdModes(args[1])

    case "current":
        cmdCurrent(args.count >= 2 ? args[1] : nil)

    case "set":
        guard args.count == 3 else { fail("usage: viberes set <display> <WxH[@Hz][-hidpi|-native]>") }
        cmdSet(args[1], args[2])

    case "profile":
        guard args.count >= 2 else { fail("usage: viberes profile <list|save|apply|delete|rename> ...") }
        switch args[1] {
        case "list":
            cmdProfileList()
        case "save":
            guard args.count >= 3 else { fail("usage: viberes profile save <name> [--any-external] [--only <display>...]") }
            cmdProfileSave(args[2], args: Array(args.dropFirst(3)))
        case "show":
            guard args.count == 3 else { fail("usage: viberes profile show <name>") }
            cmdProfileShow(args[2])
        case "apply":
            guard args.count == 3 else { fail("usage: viberes profile apply <name>") }
            cmdProfileApply(args[2])
        case "delete":
            guard args.count == 3 else { fail("usage: viberes profile delete <name>") }
            cmdProfileDelete(args[2])
        case "update":
            guard args.count == 3 else { fail("usage: viberes profile update <name>") }
            cmdProfileUpdate(args[2])
        case "flex":
            guard args.count == 3 else { fail("usage: viberes profile flex <name>") }
            cmdProfileFlex(args[2])
        case "rename":
            guard args.count == 4 else { fail("usage: viberes profile rename <old> <new>") }
            cmdProfileRename(args[2], args[3])
        default:
            fail("unknown profile subcommand \"\(args[1])\"")
        }

    default:
        fail("unknown command \"\(cmd)\". Run 'viberes help' for usage.")
    }
}

main()
