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

    /// Apply every entry of the profile to its matching live display, picking the
    /// best mode via the same scoring used by SetResolutionIntent. Skipping rules:
    /// - .edid / .builtIn matchers that find no display → "X not connected" warning
    /// - .anyExternal that finds no external display → "no external connected"
    /// - .anyExternal with multiple externals → applies to all of them
    @discardableResult
    func apply(_ profile: Profile, displays: [DisplayInfo]) -> [String] {
        var failures: [String] = []
        var anyApplied = false

        for entry in profile.entries {
            let matches = displays.filter { entry.matcher.matches($0.id) }
            if matches.isEmpty {
                failures.append(entry.matcher.notConnectedDescription(for: entry))
                continue
            }
            for info in matches {
                guard let mode = bestMatch(in: info.modes, entry: entry) else {
                    failures.append("No matching mode on \(info.name)")
                    continue
                }
                do {
                    try ResolutionSwitcher.apply(mode, to: info.id)
                    anyApplied = true
                } catch {
                    failures.append("\(info.name): \(error)")
                }
            }
        }
        if !anyApplied && failures.isEmpty {
            failures.append("Nothing to apply.")
        }
        return failures
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
