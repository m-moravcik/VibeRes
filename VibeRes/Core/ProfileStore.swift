import CoreGraphics
import Foundation
import Observation

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
    private(set) var lastError: String?

    private let storeURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.storeURL = dir.appendingPathComponent("profiles.json")
        load()
    }

    private static func defaultDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("VibeRes", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func load() {
        guard let data = try? Data(contentsOf: storeURL) else {
            profiles = []
            return
        }
        do {
            profiles = try JSONDecoder().decode([Profile].self, from: data)
        } catch {
            // Sanitised — don't surface JSONDecoder internals or file paths.
            lastError = "Failed to read saved profiles."
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
            lastError = "Failed to save profiles."
        }
    }

    func add(_ profile: Profile) {
        var p = profile
        p.name = Self.sanitised(p.name)
        guard !p.name.isEmpty else { return }
        profiles.append(p)
        save()
    }

    func update(_ profile: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            var p = profile
            p.name = Self.sanitised(p.name)
            guard !p.name.isEmpty else { return }
            profiles[i] = p
            save()
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

    /// Replaces a profile's entries wholesale while preserving id/name/createdAt.
    /// Used by the inline Edit form so per-entry tweaks (resolution, Hz, HiDPI,
    /// matcher kind, removal) save in one shot rather than as a sequence of
    /// targeted mutations. Empty input clears nothing — the call is rejected.
    @discardableResult
    func replaceEntries(_ profile: Profile, with newEntries: [Profile.Entry]) -> Profile? {
        guard !newEntries.isEmpty else { return nil }
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return nil }
        var updated = profiles[i]
        updated.entries = newEntries
        profiles[i] = updated
        save()
        return updated
    }

    /// Captures the current state of selected displays as a new profile.
    /// `selection` decides which physical displays to include and how to bind
    /// each entry — by EDID (specific) or by role (any external).
    func captureCurrent(
        name: String,
        displays: [DisplayInfo],
        selection: [CGDirectDisplayID: ProfileMatchKind]
    ) {
        let entries: [Profile.Entry] = displays.compactMap { info in
            guard let mode = info.currentMode else { return nil }
            guard let kind = selection[info.id] else { return nil }
            let matcher: DisplayMatcher = {
                let identity = DisplayIdentity.capture(info.id)
                let isBuiltin = CGDisplayIsBuiltin(info.id) != 0
                switch kind {
                case .specific:
                    return isBuiltin
                        ? .builtIn(vendor: identity.vendor, model: identity.model, serial: identity.serial)
                        : .edid(vendor: identity.vendor, model: identity.model, serial: identity.serial)
                case .anyExternal:
                    return .anyExternal
                }
            }()
            return Profile.Entry(
                matcher: matcher,
                displayName: info.name,
                pointWidth: mode.width,
                pointHeight: mode.height,
                refreshHz: mode.refreshHz,
                isHiDPI: mode.isHiDPI
            )
        }
        guard !entries.isEmpty else { return }
        add(Profile(name: name, entries: entries))
    }

    /// Outcome of applying a single profile entry. Lets the UI explain *what*
    /// actually happened — exact match, fallback to a different refresh rate
    /// or close size, or skipped because no display matched.
    struct ApplyOutcome {
        enum Status {
            case applied                  // exact request honoured
            case appliedWithFallback      // got close, see fallback fields
            case alreadyApplied           // mode === current; nothing changed
            case skippedNoMatch           // nothing matched the matcher
            case skippedNoMode            // matched but no usable mode found
            case failed(String)           // ResolutionSwitcher threw
        }
        let displayName: String
        let matcherKind: MatcherKind
        let requestedSize: (Int, Int)
        let requestedHz: Int?
        let appliedSize: (Int, Int)?
        let appliedHz: Int?
        let status: Status

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
                return "\(displayName) → \(appliedSize.map { "\($0.0)×\($0.1)" } ?? "?")\(hz)"
            case .alreadyApplied:
                return "\(displayName) already at requested mode"
            case .appliedWithFallback:
                let req = "\(requestedSize.0)×\(requestedSize.1)" + (requestedHz.map { " @\($0)Hz" } ?? "")
                let got = (appliedSize.map { "\($0.0)×\($0.1)" } ?? "?") + (appliedHz.map { " @\($0)Hz" } ?? "")
                return "\(displayName): wanted \(req), used \(got) (closest available)"
            case .skippedNoMatch:
                switch matcherKind {
                case .anyExternal: return "no external monitor connected"
                case .specific: return "\(displayName) not connected"
                }
            case .skippedNoMode:
                return "\(displayName): no usable mode for \(requestedSize.0)×\(requestedSize.1)"
            case .failed(let err):
                return "\(displayName): \(err)"
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

    /// Apply every entry of the profile to its matching live display, picking the
    /// best mode via the same scoring used by SetResolutionIntent. Returns a
    /// per-entry outcome so the UI can distinguish between success, fallback,
    /// and skip.
    @discardableResult
    func applyDetailed(
        _ profile: Profile,
        displays: [DisplayInfo],
        revert: RevertHistory? = nil
    ) -> [ApplyOutcome] {
        var outcomes: [ApplyOutcome] = []
        // Collect pre-change snapshots so a single multi-display profile
        // apply can be undone with one Revert click.
        var batchSnapshot: [(id: CGDirectDisplayID, name: String, before: CGDisplayMode)] = []

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
                    requestedSize: (entry.pointWidth, entry.pointHeight),
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
                        requestedSize: (entry.pointWidth, entry.pointHeight),
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
                do {
                    if !isAlready {
                        if let cur = info.currentMode {
                            batchSnapshot.append((info.id, info.name, cur))
                        }
                        try ResolutionSwitcher.apply(mode, to: info.id)
                    }
                    let status: ApplyOutcome.Status = {
                        if isAlready { return .alreadyApplied }
                        return isExact ? .applied : .appliedWithFallback
                    }()
                    outcomes.append(ApplyOutcome(
                        displayName: info.name,
                        matcherKind: mk,
                        requestedSize: (entry.pointWidth, entry.pointHeight),
                        requestedHz: entry.refreshHz,
                        appliedSize: (mode.width, mode.height),
                        appliedHz: mode.refreshHz,
                        status: status
                    ))
                } catch {
                    outcomes.append(ApplyOutcome(
                        displayName: info.name,
                        matcherKind: mk,
                        requestedSize: (entry.pointWidth, entry.pointHeight),
                        requestedHz: entry.refreshHz,
                        appliedSize: nil,
                        appliedHz: nil,
                        status: .failed("\(error)")
                    ))
                }
            }
        }
        // Commit the batch atomically — Revert undoes "the last profile
        // apply" rather than the last individual switch within it.
        if !batchSnapshot.isEmpty, let revert = revert {
            revert.recordBatch(batchSnapshot)
        }
        return outcomes
    }

    /// Backward-compat wrapper that converts ApplyOutcome list into a flat string array.
    @discardableResult
    func apply(_ profile: Profile, displays: [DisplayInfo]) -> [String] {
        applyDetailed(profile, displays: displays)
            .filter(\.isProblem)
            .map(\.summary)
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
        let scored: [(Profile, Int)] = profiles.compactMap { profile in
            guard !profile.entries.isEmpty else { return nil }

            // Every entry must bind to at least one live display, otherwise
            // the profile isn't a clean fit and we skip it entirely.
            for entry in profile.entries {
                if !liveDisplays.contains(where: { entry.matcher.matches($0.id) }) {
                    return nil
                }
            }

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

    private func bestMatch(in modes: [CGDisplayMode], entry: Profile.Entry) -> CGDisplayMode? {
        modes.min { lhs, rhs in score(lhs, entry: entry) < score(rhs, entry: entry) }
    }

    private func score(_ m: CGDisplayMode, entry: Profile.Entry) -> Int {
        let sizeDelta = abs(m.width - entry.pointWidth) + abs(m.height - entry.pointHeight)
        let hidpi = (m.isHiDPI == entry.isHiDPI) ? 0 : 50
        var hz = 0
        if let want = entry.refreshHz, let got = m.refreshHz {
            hz = abs(want - got) * 2
        }
        return sizeDelta + hidpi + hz
    }
}
