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
            lastError = "Failed to read profiles: \(error.localizedDescription)"
            profiles = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: storeURL, options: [.atomic])
            lastError = nil
        } catch {
            lastError = "Failed to save profiles: \(error.localizedDescription)"
        }
    }

    func add(_ profile: Profile) {
        profiles.append(profile)
        save()
    }

    func update(_ profile: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
            save()
        }
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

    /// Toggles each external entry between .edid (specific) and .anyExternal
    /// (flexible). Built-in entries stay as-is — built-in is always exactly one
    /// physical display, so the distinction is meaningless there. Returns true
    /// if the resulting profile contains any flexible entry.
    @discardableResult
    func toggleFlexible(_ profile: Profile, displays: [DisplayInfo]) -> Bool {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return false }
        var updated = profiles[i]
        let isCurrentlyFlexible = updated.entries.contains {
            if case .anyExternal = $0.matcher { return true }
            return false
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
                    // Try to bind back to a connected external display by capturing its EDID.
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
        return !isCurrentlyFlexible
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
            case skippedNoMatch           // nothing matched the matcher
            case skippedNoMode            // matched but no usable mode found
            case failed(String)           // ResolutionSwitcher threw
        }
        let displayName: String
        let requestedSize: (Int, Int)
        let requestedHz: Int?
        let appliedSize: (Int, Int)?
        let appliedHz: Int?
        let status: Status

        /// Human-readable summary used in tooltips and CLI output.
        var summary: String {
            switch status {
            case .applied:
                let hz = appliedHz.map { " @ \($0)Hz" } ?? ""
                return "\(displayName) → \(appliedSize.map { "\($0.0)×\($0.1)" } ?? "?")\(hz)"
            case .appliedWithFallback:
                let req = "\(requestedSize.0)×\(requestedSize.1)" + (requestedHz.map { " @\($0)Hz" } ?? "")
                let got = (appliedSize.map { "\($0.0)×\($0.1)" } ?? "?") + (appliedHz.map { " @\($0)Hz" } ?? "")
                return "\(displayName): wanted \(req), used \(got) (closest available)"
            case .skippedNoMatch:
                return "\(displayName) not connected"
            case .skippedNoMode:
                return "\(displayName): no usable mode for \(requestedSize.0)×\(requestedSize.1)"
            case .failed(let err):
                return "\(displayName): \(err)"
            }
        }

        var isProblem: Bool {
            switch status {
            case .applied: return false
            case .appliedWithFallback, .skippedNoMatch, .skippedNoMode, .failed: return true
            }
        }
    }

    /// Apply every entry of the profile to its matching live display, picking the
    /// best mode via the same scoring used by SetResolutionIntent. Returns a
    /// per-entry outcome so the UI can distinguish between success, fallback,
    /// and skip.
    @discardableResult
    func applyDetailed(_ profile: Profile, displays: [DisplayInfo]) -> [ApplyOutcome] {
        var outcomes: [ApplyOutcome] = []

        for entry in profile.entries {
            let matches = displays.filter { entry.matcher.matches($0.id) }
            if matches.isEmpty {
                outcomes.append(ApplyOutcome(
                    displayName: entry.displayName,
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
                        requestedSize: (entry.pointWidth, entry.pointHeight),
                        requestedHz: entry.refreshHz,
                        appliedSize: nil,
                        appliedHz: nil,
                        status: .skippedNoMode
                    ))
                    continue
                }
                let isExact = mode.width == entry.pointWidth
                    && mode.height == entry.pointHeight
                    && (entry.refreshHz == nil || entry.refreshHz == mode.refreshHz)
                    && mode.isHiDPI == entry.isHiDPI
                do {
                    try ResolutionSwitcher.apply(mode, to: info.id)
                    outcomes.append(ApplyOutcome(
                        displayName: info.name,
                        requestedSize: (entry.pointWidth, entry.pointHeight),
                        requestedHz: entry.refreshHz,
                        appliedSize: (mode.width, mode.height),
                        appliedHz: mode.refreshHz,
                        status: isExact ? .applied : .appliedWithFallback
                    ))
                } catch {
                    outcomes.append(ApplyOutcome(
                        displayName: info.name,
                        requestedSize: (entry.pointWidth, entry.pointHeight),
                        requestedHz: entry.refreshHz,
                        appliedSize: nil,
                        appliedHz: nil,
                        status: .failed("\(error)")
                    ))
                }
            }
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
