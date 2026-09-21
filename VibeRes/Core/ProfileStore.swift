import CoreGraphics
import Foundation
import Observation
import os.log

private let viberesLog = Logger(subsystem: "sk.moravcik.VibeRes", category: "apply")

/// User-facing intent at save time: should this entry match a specific
/// physical display (EDID-locked) or any monitor of that role.
enum ProfileMatchKind {
    case specific
    case anyExternal
}

extension DisplayMatcher {
    /// Friendly message when no live display satisfies this matcher.
    func notConnectedDescription(for entry: Profile.Entry) -> String {
        switch self {
        case .edid: return "\(entry.displayName) not connected"
        case .anyExternal: return "no external monitor connected"
        case .builtIn: return "built-in display not found"
        }
    }
}

/// Persistent profile catalog. Stored as JSON in
/// `~/Library/Application Support/VibeRes/profiles.json`.
@Observable
@MainActor
final class ProfileStore {
    private(set) var profiles: [Profile] = []
    private(set) var lastError: UserFacingProblem?

    /// Clears the error row — the same acknowledgement `DisplayStore` offers.
    func dismissLastError() {
        lastError = nil
    }

    private let storeURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.storeURL = dir.appendingPathComponent("profiles.json")
        load()
    }

    /// Environment override for the catalog location.
    ///
    /// Exists so the CLI can be driven by a test — and by anyone scripting it —
    /// without writing to the real profile store. The GUI passes its directory
    /// explicitly and never consults this.
    nonisolated static let directoryEnvironmentKey = "VIBERES_PROFILE_DIR"

    private static func defaultDirectory() -> URL {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment[directoryEnvironmentKey],
           !override.isEmpty {
            let dir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath,
                          isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        // `.first!` was the one crash-by-construction left in a shipped path.
        // It cannot realistically return empty on macOS, which is exactly why
        // the day it does, a force unwrap is the worst possible way to find out.
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        let dir = base.appendingPathComponent("VibeRes", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Bounds on the on-disk catalog. It is the user's own file, so this is
    // resilience rather than a trust boundary — but a corrupted or hand-edited
    // file should not be able to stall launch or exhaust memory on a read that
    // happens on the main actor during init.
    nonisolated static let maximumStoreBytes = 4 * 1024 * 1024
    nonisolated static let maximumProfiles = 200
    /// Display enumeration already caps active displays at 32; a profile has no
    /// reason to describe more.
    nonisolated static let maximumEntriesPerProfile = 32

    nonisolated static func isWithinSizeLimit(bytes: Int) -> Bool {
        bytes <= maximumStoreBytes
    }

    /// Trims a decoded catalog to the limits, keeping the first entries so the
    /// result is predictable rather than arbitrary.
    nonisolated static func capped(_ profiles: [Profile]) -> [Profile] {
        profiles.prefix(maximumProfiles).map { profile in
            guard profile.entries.count > maximumEntriesPerProfile else { return profile }
            return Profile(
                id: profile.id,
                name: profile.name,
                entries: Array(profile.entries.prefix(maximumEntriesPerProfile)),
                createdAt: profile.createdAt
            )
        }
    }

    func load() {
        // Check the size before reading rather than after: the point is to not
        // pull an implausible file into memory on the main actor at launch.
        let size = (try? storeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard Self.isWithinSizeLimit(bytes: size) else {
            lastError = .profilesUnreadable
            profiles = []
            return
        }

        guard let data = try? Data(contentsOf: storeURL) else {
            profiles = []
            return
        }
        do {
            profiles = Self.capped(try JSONDecoder().decode([Profile].self, from: data))
        } catch {
            // Sanitised — don't surface JSONDecoder internals or file paths.
            lastError = .profilesUnreadable
            profiles = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: storeURL, options: [.atomic])
            // Restrict to owner read/write only — profiles contain EDID identifiers
            // and resolution preferences which other users on the machine
            // shouldn't read.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storeURL.path
            )
            lastError = nil
        } catch {
            lastError = .profilesNotSaved
        }
    }

    /// Adds a profile, or says why it would not.
    ///
    /// Returns a result rather than nothing: these guards used to drop the
    /// profile silently, and `captureCurrent` reported `.saved` regardless — so
    /// `viberes profile save "   "` printed success and stored nothing.
    @discardableResult
    func add(_ profile: Profile) -> SaveResult {
        var p = profile
        p.name = Self.sanitised(p.name)
        guard !p.name.isEmpty else { return .rejectedEmptyName }
        guard !nameIsTaken(p.name, excluding: p.id) else { return .rejectedDuplicateName(p.name) }
        profiles.append(p)
        save()
        return .saved
    }

    @discardableResult
    func update(_ profile: Profile) -> SaveResult {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return .rejectedNotFound }
        var p = profile
        p.name = Self.sanitised(p.name)
        guard !p.name.isEmpty else { return .rejectedEmptyName }
        guard !nameIsTaken(p.name, excluding: p.id) else { return .rejectedDuplicateName(p.name) }
        profiles[i] = p
        save()
        return .saved
    }

    /// True when a *different* profile already answers to this name.
    ///
    /// Case-insensitive, because a name is a handle a person types: "work" and
    /// "Work" are the same handle to everyone except a byte comparison, and the
    /// CLI resolves them the same way.
    func nameIsTaken(_ name: String, excluding id: UUID?) -> Bool {
        let candidate = Self.sanitised(name)
        return profiles.contains {
            $0.id != id && $0.name.caseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    /// How a handle typed on the command line — a name or an id — maps onto a
    /// saved profile.
    enum Lookup: Equatable {
        case found(Profile)
        case notFound
        /// More than one profile answers to this name. `add` and `update`
        /// refuse to create that state, but a catalog written by 0.9.0 or
        /// edited by hand can already be in it, and picking the first match
        /// would make `viberes profile apply Work` a coin flip.
        case ambiguous(count: Int)
    }

    /// Resolves a name or an id to exactly one profile, or refuses to guess.
    ///
    /// The id is tried first and is the documented way out of an ambiguous
    /// name — `viberes profile list` prints it for exactly this reason.
    func resolve(_ needle: String) -> Lookup {
        if let id = UUID(uuidString: needle) {
            return profiles.first(where: { $0.id == id }).map(Lookup.found) ?? .notFound
        }
        let matches = profiles.filter { $0.name.caseInsensitiveCompare(needle) == .orderedSame }
        switch matches.count {
        case 0: return .notFound
        case 1: return .found(matches[0])
        default: return .ambiguous(count: matches.count)
        }
    }

    /// Strip control characters / null bytes and cap length, so that hand-edited
    /// JSON or CLI argument abuse can't push junk into the profile name field.
    static func sanitised(_ name: String) -> String {
        let stripped = name.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && scalar != "\0"
        }.map(Character.init)
        let trimmed = String(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(128))
    }

    func delete(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    /// Refreshes a profile's recorded resolution+refresh+HiDPI for each entry from
    /// the displays currently connected. Keeps the profile's id, name, createdAt,
    /// and matcher policy (specific/anyExternal/builtIn) — so toggling between
    /// flexible and specific isn't lost. Entries whose matcher doesn't bind to
    /// anything live are left as-is so a Q3279 entry doesn't disappear just
    /// because the user is on the road.
    @discardableResult
    func updateFromCurrent(_ profile: Profile, displays: [DisplayInfo]) -> Profile? {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return nil }
        var updated = profiles[i]
        updated.entries = updated.entries.map { entry -> Profile.Entry in
            guard let info = displays.first(where: { entry.matcher.matches($0.id) }),
                  let mode = info.currentMode
            else { return entry } // no live match — keep prior snapshot
            return Profile.Entry(
                matcher: entry.matcher,
                displayName: info.name,
                pointWidth: mode.width,
                pointHeight: mode.height,
                refreshHz: mode.refreshHz,
                isHiDPI: mode.isHiDPI
            )
        }
        profiles[i] = updated
        save()
        return updated
    }

    /// Outcome of a flexible/specific toggle. `.blockedNoExternal` is returned
    /// when the user asks to lock an .anyExternal profile to current monitors
    /// but no external display is currently connected — without one we have
    /// no EDID to capture, so silently leaving the profile flexible would be
    /// misleading. The UI surfaces this as a problem-tone announcement.
    enum LockResult {
        case madeFlexible
        case madeSpecific
        case blockedNoExternal
    }

    /// Toggles each external entry between .edid (specific) and .anyExternal
    /// (flexible). Built-in entries stay as-is — built-in is always exactly one
    /// physical display, so the distinction is meaningless there.
    @discardableResult
    func toggleFlexible(_ profile: Profile, displays: [DisplayInfo]) -> LockResult {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return .madeFlexible }
        var updated = profiles[i]
        let isCurrentlyFlexible = updated.entries.contains {
            if case .anyExternal = $0.matcher { return true }
            return false
        }

        // Locking a flexible profile requires a connected external to capture
        // its EDID. Without one, refuse the action so the profile doesn't end
        // up silently still flexible after a "lock to current monitors" click.
        if isCurrentlyFlexible {
            let hasExternal = displays.contains { CGDisplayIsBuiltin($0.id) == 0 }
            if !hasExternal { return .blockedNoExternal }
        }

        updated.entries = updated.entries.map { entry -> Profile.Entry in
            switch entry.matcher {
            case .builtIn:
                return entry
            case .edid:
                if !isCurrentlyFlexible {
                    var e = entry
                    e.matcher = .anyExternal
                    return e
                }
                return entry
            case .anyExternal:
                if isCurrentlyFlexible {
                    if let info = displays.first(where: { CGDisplayIsBuiltin($0.id) == 0 }) {
                        let id = DisplayIdentity.capture(info.id)
                        var e = entry
                        e.matcher = .edid(vendor: id.vendor, model: id.model, serial: id.serial)
                        e.displayName = info.name
                        return e
                    }
                    return entry
                }
                return entry
            }
        }
        profiles[i] = updated
        save()
        return isCurrentlyFlexible ? .madeSpecific : .madeFlexible
    }

    /// Validation outcomes for profile-mutating calls. Distinct from
    /// ApplyOutcome — those describe what happened at apply time, these
    /// describe whether the save itself was accepted.
    enum SaveResult: Equatable {
        case saved
        /// Saved, but displays the user had selected were gone by the time Save
        /// was pressed. A distinct case rather than a payload on `.saved`
        /// because Swift lets `case .saved:` match a case *with* a payload, so
        /// every call site would stay free to ignore it — which is the silence
        /// this exists to end.
        case savedWithMissingDisplays(count: Int)
        case rejectedEmpty                      // no entries to save
        case rejectedEmptyName                  // nothing left after sanitising
        case rejectedDuplicateName(String)      // another profile holds the name
        case rejectedNotFound                   // the profile is no longer in the store
        case rejectedMultipleAnyExternal        // more than one `.anyExternal` entry
    }

    /// How many of the user's selected displays are no longer attached.
    ///
    /// `nonisolated` because it is set arithmetic; ProfileStore is @MainActor
    /// and tests would otherwise have to cross an actor boundary to count.
    nonisolated static func missingSelections(
        selection: [CGDirectDisplayID: ProfileMatchKind],
        liveDisplayIDs: Set<CGDirectDisplayID>
    ) -> Int {
        // Only selected-but-gone counts. A live display the user deliberately
        // left out is a choice, not a loss.
        selection.keys.filter { !liveDisplayIDs.contains($0) }.count
    }

    /// True if a list of entries contains more than one `.anyExternal` matcher.
    /// Multiple flexible externals cause conflicting applies (each entry
    /// matches every external, so the last entry "wins" after blinking
    /// through the earlier ones). The UI surfaces this as a hard error
    /// rather than letting users save a profile that visibly misbehaves.
    static func hasMultipleAnyExternal(_ entries: [Profile.Entry]) -> Bool {
        var seen = 0
        for e in entries {
            if case .anyExternal = e.matcher {
                seen += 1
                if seen > 1 { return true }
            }
        }
        return false
    }

    /// Replaces a profile's entries wholesale while preserving id/name/createdAt.
    /// Used by the inline Edit form so per-entry tweaks (resolution, Hz, HiDPI,
    /// matcher kind, removal) save in one shot rather than as a sequence of
    /// targeted mutations. Rejected when the list is empty or contains more
    /// than one `.anyExternal` matcher (the latter would cause conflicting
    /// applies at runtime).
    @discardableResult
    func replaceEntries(_ profile: Profile, with newEntries: [Profile.Entry]) -> SaveResult {
        guard !newEntries.isEmpty else { return .rejectedEmpty }
        guard !Self.hasMultipleAnyExternal(newEntries) else { return .rejectedMultipleAnyExternal }
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return .rejectedNotFound }
        var updated = profiles[i]
        updated.entries = newEntries
        profiles[i] = updated
        save()
        return .saved
    }

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

    /// Captures the current state of selected displays as a new profile.
    /// `selection` decides which physical displays to include and how to bind
    /// each entry — by EDID (specific) or by role (any external).
    @discardableResult
    func captureCurrent(
        name: String,
        displays: [DisplayInfo],
        selection: [CGDirectDisplayID: ProfileMatchKind],
        mainSelection: CGDirectDisplayID? = nil
    ) -> SaveResult {
        let entries: [Profile.Entry] = displays.compactMap { info in
            guard let mode = info.currentMode else { return nil }
            guard let kind = selection[info.id] else { return nil }
            let matcher = Self.matcher(for: info.id, kind: kind)
            return Profile.Entry(
                matcher: matcher,
                displayName: info.name,
                pointWidth: mode.width,
                pointHeight: mode.height,
                refreshHz: mode.refreshHz,
                isHiDPI: mode.isHiDPI
            )
        }
        guard !entries.isEmpty else { return .rejectedEmpty }
        guard !Self.hasMultipleAnyExternal(entries) else { return .rejectedMultipleAnyExternal }

        // The main pick must be one of the *saved* displays: a selection that
        // was unchecked (or unplugged) before Save has no entry to anchor to.
        // A display with no current mode produces no entry either (see the
        // loop above) — its matcher would have nothing to anchor a "main" to.
        var mainDisplay: DisplayMatcher?
        if let mainSelection,
           let kind = selection[mainSelection],
           let mainInfo = displays.first(where: { $0.id == mainSelection }),
           mainInfo.currentMode != nil {
            mainDisplay = Self.matcher(for: mainSelection, kind: kind)
        }
        // Report what the store actually did. `add` refuses a blank or
        // already-taken name, and swallowing that here is what let the CLI
        // print `saved profile` over an empty catalog.
        let outcome = add(Profile(name: name, entries: entries, mainDisplay: mainDisplay))
        guard outcome == .saved else { return outcome }

        // A monitor unplugged between opening the form and pressing Save is no
        // longer in `displays`, so its entry never gets built. Saying nothing
        // leaves the user a display short with no reason to suspect it.
        let missing = Self.missingSelections(
            selection: selection,
            liveDisplayIDs: Set(displays.map(\.id))
        )
        return missing > 0 ? .savedWithMissingDisplays(count: missing) : .saved
    }

    /// Outcome of applying a single profile entry. Lets the UI explain *what*
    /// actually happened — exact match, fallback to a different refresh rate
    /// or close size, or skipped because no display matched.
    struct ApplyOutcome {
        enum Status: Equatable {
            case applied                  // exact request honoured
            case appliedWithFallback      // got close, see fallback fields
            case alreadyApplied           // mode === current; nothing changed
            case skippedNoMatch           // nothing matched the matcher
            case skippedNoMode            // matched but no usable mode found
            /// The transaction refused this display. Carries the problem as
            /// a value so the UI can localise it; the CLI renders
            /// `englishDescription`.
            case failed(UserFacingProblem)
        }
        let displayName: String
        let matcherKind: MatcherKind
        let requestedSize: PointSize
        let requestedHz: Int?
        // Filled in once the transaction commits: an outcome is planned before
        // it is known whether the display took the mode.
        var appliedSize: PointSize?
        var appliedHz: Int?
        var status: Status

        /// Slim mirror of DisplayMatcher kept on outcomes so summary copy can
        /// adapt to the matcher style without holding EDID identifiers in UI
        /// payloads. Crucially distinguishes `.anyExternal` from `.specific`,
        /// so a flexible profile with no external connected reads as "no
        /// external monitor connected" rather than the misleading
        /// "<savedName> not connected".
        enum MatcherKind {
            case specific      // .edid or .builtIn — bound to one identity
            case anyExternal
        }

        /// Human-readable summary used in tooltips and CLI output.
        var summary: String {
            switch status {
            case .applied:
                let hz = appliedHz.map { " @ \($0)Hz" } ?? ""
                return "\(displayName) → \(appliedSize?.formatted ?? "?")\(hz)"
            case .alreadyApplied:
                return "\(displayName) already at requested mode"
            case .appliedWithFallback:
                let req = requestedSize.formatted + (requestedHz.map { " @\($0)Hz" } ?? "")
                let got = (appliedSize?.formatted ?? "?") + (appliedHz.map { " @\($0)Hz" } ?? "")
                return "\(displayName): wanted \(req), used \(got) (closest available)"
            case .skippedNoMatch:
                switch matcherKind {
                case .anyExternal: return "no external monitor connected"
                case .specific: return "\(displayName) not connected"
                }
            case .skippedNoMode:
                return "\(displayName): no usable mode for \(requestedSize.formatted)"
            case .failed(let problem):
                return "\(displayName): \(problem.englishDescription)"
            }
        }

        var isProblem: Bool {
            switch status {
            case .applied, .alreadyApplied: return false
            case .appliedWithFallback, .skippedNoMatch, .skippedNoMode, .failed: return true
            }
        }

        /// True when this entry actually mutated display state. Used by
        /// auto-apply to suppress the "Applied 'Work'…" toast when nothing
        /// in fact changed (every display was already at its target mode).
        var didChange: Bool {
            switch status {
            case .applied, .appliedWithFallback: return true
            case .alreadyApplied, .skippedNoMatch, .skippedNoMode, .failed: return false
            }
        }
    }

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
        case failed(UserFacingProblem)               // the origin transaction threw

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
            case .failed(let problem):
                return "main display not changed: \(problem.englishDescription)"
            }
        }
    }

    /// A display change decided but not yet committed, with the slot in the
    /// result it will fill once the transaction returns.
    private struct PlannedChange {
        let outcomeIndex: Int
        let display: CGDirectDisplayID
        let name: String
        let mode: CGDisplayMode
        let previous: CGDisplayMode?
        let isExact: Bool
    }

    /// Test seam. Reconfiguring displays is the one thing a unit test must not
    /// really do; injecting the transaction lets a test assert that a
    /// three-monitor profile is one commit rather than three, and that partial
    /// failure is reported per display.
    @ObservationIgnored
    var applyBatch: ([ResolutionSwitcher.BatchChange], CGConfigureOption) throws
        -> ResolutionSwitcher.BatchOutcome = { try ResolutionSwitcher.applyBatch($0, scope: $1) }

    /// Test seams for the main-display phase — same rationale as `applyBatch`:
    /// the origin transaction and the live arrangement reads must be
    /// injectable, because a unit test must not rearrange the machine.
    @ObservationIgnored
    var applyOrigins: ([CGDirectDisplayID: CGPoint], CGConfigureOption) throws -> Void =
        { try ResolutionSwitcher.applyOrigins($0, scope: $1) }

    @ObservationIgnored
    var liveArrangement: () -> (main: CGDirectDisplayID, bounds: [CGDirectDisplayID: CGRect]) = {
        ResolutionSwitcher.currentArrangement()
    }

    @ObservationIgnored
    var isInMirrorSet: (CGDirectDisplayID) -> Bool = { CGDisplayIsInMirrorSet($0) != 0 }

    /// Apply every entry of the profile to its matching live display, picking the
    /// best mode via the same scoring used by SetResolutionIntent. Returns a
    /// per-entry outcome so the UI can distinguish between success, fallback,
    /// and skip.
    ///
    /// All matched displays are committed in a single transaction, so the
    /// desktop goes straight from the old arrangement to the profile's, with no
    /// intermediate layout and one blank instead of one per monitor.
    @discardableResult
    func applyDetailed(
        _ profile: Profile,
        displays: [DisplayInfo],
        revert: RevertHistory? = nil
    ) -> ProfileApplyResult {
        var outcomes: [ApplyOutcome] = []
        // Collect pre-change snapshots so a single multi-display profile
        // apply can be undone with one Revert click.
        var batchSnapshot: [(id: CGDirectDisplayID, name: String, before: CGDisplayMode)] = []
        var seenForRevert: Set<CGDirectDisplayID> = []
        // Planned first, committed once. Nothing reaches WindowServer until
        // every entry of the profile has been scored.
        var planned: [PlannedChange] = []

        for entry in profile.entries {
            let mk: ApplyOutcome.MatcherKind = {
                if case .anyExternal = entry.matcher { return .anyExternal }
                return .specific
            }()
            let matches = displays.filter { entry.matcher.matches($0.id) }
            if matches.isEmpty {
                outcomes.append(ApplyOutcome(
                    displayName: entry.displayName,
                    matcherKind: mk,
                    requestedSize: PointSize(width: entry.pointWidth, height: entry.pointHeight),
                    requestedHz: entry.refreshHz,
                    appliedSize: nil,
                    appliedHz: nil,
                    status: .skippedNoMatch
                ))
                continue
            }
            for info in matches {
                guard let mode = bestMatch(in: info.modes, entry: entry) else {
                    outcomes.append(ApplyOutcome(
                        displayName: info.name,
                        matcherKind: mk,
                        requestedSize: PointSize(width: entry.pointWidth, height: entry.pointHeight),
                        requestedHz: entry.refreshHz,
                        appliedSize: nil,
                        appliedHz: nil,
                        status: .skippedNoMode
                    ))
                    continue
                }
                // If the picked mode is the display's current mode, switching
                // is a no-op at the system level — but still surface a status
                // so callers can distinguish "we did something" from "nothing
                // to do". Auto-apply uses this to suppress redundant toasts.
                let isAlready = mode.ioDisplayModeID == info.currentMode?.ioDisplayModeID
                let isExact = mode.width == entry.pointWidth
                    && mode.height == entry.pointHeight
                    && (entry.refreshHz == nil || entry.refreshHz == mode.refreshHz)
                    && mode.isHiDPI == entry.isHiDPI

                if isAlready {
                    outcomes.append(ApplyOutcome(
                        displayName: info.name,
                        matcherKind: mk,
                        requestedSize: PointSize(width: entry.pointWidth, height: entry.pointHeight),
                        requestedHz: entry.refreshHz,
                        appliedSize: PointSize(width: mode.width, height: mode.height),
                        appliedHz: mode.refreshHz,
                        status: .alreadyApplied
                    ))
                    continue
                }

                // Everything else is a real change: reserve its place in the
                // result and stage it. The status here is provisional — the
                // merge below rewrites every planned index without exception,
                // so no `.failed` placeholder can reach a caller.
                planned.append(PlannedChange(
                    outcomeIndex: outcomes.count,
                    display: info.id,
                    name: info.name,
                    mode: mode,
                    previous: info.currentMode,
                    isExact: isExact
                ))
                outcomes.append(ApplyOutcome(
                    displayName: info.name,
                    matcherKind: mk,
                    requestedSize: PointSize(width: entry.pointWidth, height: entry.pointHeight),
                    requestedHz: entry.refreshHz,
                    appliedSize: PointSize(width: mode.width, height: mode.height),
                    appliedHz: mode.refreshHz,
                    status: .failed(.other("not attempted"))
                ))
            }
        }

        // One transaction for the whole profile. Applying display by display
        // meant one full reconfiguration each: three monitors blanked three
        // times, and in between the desktop passed through layouts that match
        // no profile — which is also what made auto-apply retrigger on its own
        // intermediate states.
        if !planned.isEmpty {
            for change in planned {
                // Diagnostic logging — when apply silently fails the user has
                // zero visibility into why. Goes to Console.app under
                // sk.moravcik.VibeRes.
                viberesLog.notice("apply \(change.name, privacy: .public): \(change.previous?.width ?? 0)×\(change.previous?.height ?? 0) → \(change.mode.width)×\(change.mode.height) @ \(change.mode.refreshHz ?? 0)Hz hidpi=\(change.mode.isHiDPI) modeID=\(change.mode.ioDisplayModeID)")
            }

            do {
                let result = try applyBatch(
                    planned.map { ResolutionSwitcher.BatchChange(display: $0.display, mode: $0.mode) },
                    .permanently
                )
                for change in planned {
                    // `applied` is checked first on purpose: two entries can
                    // match the same display, and if either staged, that
                    // display really did change.
                    if result.applied.contains(change.display) {
                        outcomes[change.outcomeIndex].status = change.isExact ? .applied : .appliedWithFallback
                        if let previous = change.previous, seenForRevert.insert(change.display).inserted {
                            batchSnapshot.append((change.display, change.name, previous))
                        }
                        viberesLog.notice("apply \(change.name, privacy: .public): SUCCESS")
                    } else {
                        let failure = result.rejected[change.display] ?? .applyMode(.failure)
                        outcomes[change.outcomeIndex].status = .failed(.switchFailed(failure))
                        let reason = failure.userFacingDescription
                        outcomes[change.outcomeIndex].appliedSize = nil
                        outcomes[change.outcomeIndex].appliedHz = nil
                        viberesLog.error("apply \(change.name, privacy: .public): REJECTED — \(reason, privacy: .public)")
                    }
                }
            } catch {
                // The commit itself failed, so not one of the staged displays
                // changed. Reporting anything as applied here would leave the
                // user with a success message and an unchanged desktop.
                viberesLog.error("apply: transaction failed with \(String(describing: error), privacy: .public)")
                for change in planned {
                    outcomes[change.outcomeIndex].status = .failed(error.asUserFacingProblem)
                    outcomes[change.outcomeIndex].appliedSize = nil
                    outcomes[change.outcomeIndex].appliedHz = nil
                }
            }
        }

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

        // Revert undoes "the last profile apply" rather than the last
        // individual switch within it — and only records displays that
        // actually moved, so it never offers to restore one that never changed.
        // A main-only change (all modes already at target) must still arm it.
        if !batchSnapshot.isEmpty || previousMainID != nil, let revert = revert {
            revert.recordBatch(batchSnapshot, beforeMain: previousMainID)
        }
        return ProfileApplyResult(outcomes: outcomes, mainChange: mainChange)
    }

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
            guard target != live.main else { return .alreadyMain }
            // Arrangement combined with mirroring is a spike unknown; leave
            // it alone rather than find out on a user's machine.
            guard !activeIDs.contains(where: isInMirrorSet) else { return .skippedMirrored }
            guard let plan = MainDisplayPlanner.plan(bounds: live.bounds, target: target) else {
                return .skippedNoMatch
            }

            let name = displays.first(where: { $0.id == target })?.name ?? "display \(target)"
            viberesLog.notice("main display: \(live.main) → \(target) (\(name, privacy: .public)), \(plan.count) origins")
            do {
                try applyOrigins(plan, .permanently)
            } catch {
                viberesLog.error("main display: transaction failed — \(String(describing: error), privacy: .public)")
                return .failed(error.asUserFacingProblem)
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

    /// Returns the saved profile that best fits the current display set, or
    /// nil if none of the saved profiles can fully match.
    ///
    /// Hierarchy (CSS-style specificity — *more specific wins*):
    ///   3 points per `.edid` external entry  (locked to one physical monitor)
    ///   2 points per `.builtIn` entry        (the laptop's own panel)
    ///   1 point  per `.anyExternal` entry    (role-based, any external)
    ///
    /// Tie-breaker: more recently saved profile wins (`createdAt desc`).
    ///
    /// Why specificity beats coverage: when both "Work" (Built-in + Q3279
    /// EDID-locked) and "Presentation" (Built-in + any external) match the
    /// same setup, the user's intent is "Work — that's *my* desk". Picking
    /// the flexible variant would override their precise saved layout with
    /// a generic fallback.
    func profileMatchingExactly(_ liveDisplays: [DisplayInfo]) -> Profile? {
        profileMatchingExactly(liveDisplays) { entry, display in
            entry.matcher.matches(display.id)
        }
    }

    func profileMatchingExactly(
        _ liveDisplays: [DisplayInfo],
        entryMatchesDisplay: (Profile.Entry, DisplayInfo) -> Bool
    ) -> Profile? {
        let liveIDs = Set(liveDisplays.map(\.id))
        let scored: [(Profile, Int)] = profiles.compactMap { profile in
            guard !profile.entries.isEmpty else { return nil }

            var matchedIDs: Set<CGDirectDisplayID> = []

            // Every entry must bind to at least one live display, and every
            // live display must be covered. Auto-apply must not run a profile
            // that would leave extra monitors untouched.
            for entry in profile.entries {
                let matches = liveDisplays.filter { entryMatchesDisplay(entry, $0) }
                guard !matches.isEmpty else { return nil }
                matchedIDs.formUnion(matches.map(\.id))
            }
            guard matchedIDs == liveIDs else { return nil }

            // Specificity score — higher = more "this exact setup".
            let score = profile.entries.reduce(0) { acc, entry in
                acc + Self.specificity(of: entry.matcher)
            }
            return (profile, score)
        }

        return scored.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.createdAt > rhs.0.createdAt
        }.first?.0
    }

    /// Per-entry specificity weight. Exposed for tests.
    static func specificity(of matcher: DisplayMatcher) -> Int {
        switch matcher {
        case .edid:        return 3   // locked to one physical external
        case .builtIn:     return 2   // locked to the (single) built-in panel
        case .anyExternal: return 1   // any external, role-based fallback
        }
    }

    /// True when applying the profile right now would change nothing:
    /// every entry binds to at least one connected display, every display it
    /// binds to is already at the entry's saved mode, and — when the profile
    /// pins a main display — that display is currently main. This is what
    /// the pill bar highlights as "active": the profile the desktop is
    /// actually in, as opposed to one that merely *could* be applied.
    func isCurrentState(_ profile: Profile, displays: [DisplayInfo]) -> Bool {
        guard !profile.entries.isEmpty else { return false }

        for entry in profile.entries {
            let matches = displays.filter { entry.matcher.matches($0.id) }
            guard !matches.isEmpty else { return false }
            for info in matches {
                guard let current = info.currentMode,
                      current.width == entry.pointWidth,
                      current.height == entry.pointHeight,
                      entry.refreshHz == nil || entry.refreshHz == current.refreshHz,
                      current.isHiDPI == entry.isHiDPI
                else { return false }
            }
        }

        if let main = profile.mainDisplay {
            let matches = displays.filter { main.matches($0.id) }
            guard matches.count == 1, matches[0].isMain else { return false }
        }
        return true
    }

    /// Compute a "what would happen" preview without mutating any display.
    /// Used by the hover tooltip and the partial-match confirmation panel so
    /// the user sees the exact set of changes before committing.
    func previewApply(_ profile: Profile, against displays: [DisplayInfo]) -> ProfileApplyPreview {
        var rows: [ProfileApplyPreview.Row] = []
        var touchedIDs: Set<CGDirectDisplayID> = []

        for entry in profile.entries {
            let matches = displays.filter { entry.matcher.matches($0.id) }
            if matches.isEmpty {
                rows.append(ProfileApplyPreview.Row(
                    id: UUID(),
                    displayName: entry.displayName,
                    action: .skippedNotConnected,
                    savedWidth: entry.pointWidth,
                    savedHeight: entry.pointHeight,
                    savedHz: entry.refreshHz,
                    savedIsHiDPI: entry.isHiDPI
                ))
                continue
            }
            for info in matches {
                touchedIDs.insert(info.id)
                guard let mode = bestMatch(in: info.modes, entry: entry) else {
                    rows.append(ProfileApplyPreview.Row(
                        id: UUID(),
                        displayName: info.name,
                        action: .skippedNoMode,
                        savedWidth: entry.pointWidth,
                        savedHeight: entry.pointHeight,
                        savedHz: entry.refreshHz,
                        savedIsHiDPI: entry.isHiDPI
                    ))
                    continue
                }
                let isAlready = mode.ioDisplayModeID == info.currentMode?.ioDisplayModeID
                let isExact = mode.width == entry.pointWidth
                    && mode.height == entry.pointHeight
                    && (entry.refreshHz == nil || entry.refreshHz == mode.refreshHz)
                    && mode.isHiDPI == entry.isHiDPI
                let action: ProfileApplyPreview.Row.Action = {
                    if isAlready {
                        // Report what the display is actually at right now,
                        // not what the entry asked for. For .anyExternal
                        // entries targeting a high resolution (e.g. saved
                        // from a 4K monitor) on a 1080p external, the picked
                        // mode is the closest available — saying "already at
                        // 2880×1620" when the display is at 1920×1080 is a
                        // user-facing lie.
                        return .alreadyApplied(
                            currentWidth: mode.width,
                            currentHeight: mode.height,
                            currentHz: mode.refreshHz,
                            currentIsHiDPI: mode.isHiDPI
                        )
                    }
                    if isExact { return .willApplyExact }
                    return .willApplyFallback(
                        targetWidth: mode.width,
                        targetHeight: mode.height,
                        targetHz: mode.refreshHz
                    )
                }()
                rows.append(ProfileApplyPreview.Row(
                    id: UUID(),
                    displayName: info.name,
                    action: action,
                    savedWidth: entry.pointWidth,
                    savedHeight: entry.pointHeight,
                    savedHz: entry.refreshHz,
                    savedIsHiDPI: entry.isHiDPI
                ))
            }
        }

        let untouched = displays.filter { !touchedIDs.contains($0.id) }.map(\.name)
        return ProfileApplyPreview(rows: rows, untouched: untouched)
    }

    private func bestMatch(in modes: [CGDisplayMode], entry: Profile.Entry) -> CGDisplayMode? {
        ModeScoring.bestMatch(
            in: modes,
            request: ModeScoring.Request(
                width: entry.pointWidth,
                height: entry.pointHeight,
                refreshHz: entry.refreshHz,
                preferHiDPI: entry.isHiDPI
            )
        )
    }
}
