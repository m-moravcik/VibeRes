import CoreGraphics
import Foundation
import Observation

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

    /// Captures the current state of every connected display as a new profile.
    func captureCurrent(name: String, displays: [DisplayInfo]) {
        let entries: [Profile.Entry] = displays.compactMap { info in
            guard let mode = info.currentMode else { return nil }
            let identity = DisplayIdentity.capture(info.id)
            return Profile.Entry(
                displayVendor: identity.vendor,
                displayModel: identity.model,
                displaySerial: identity.serial,
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
    /// best mode via the same scoring used by SetResolutionIntent.
    @discardableResult
    func apply(_ profile: Profile, displays: [DisplayInfo]) -> [String] {
        var failures: [String] = []
        for entry in profile.entries {
            guard let info = displays.first(where: {
                let id = DisplayIdentity.capture($0.id)
                return id.vendor == entry.displayVendor
                    && id.model == entry.displayModel
                    && id.serial == entry.displaySerial
            }) else {
                failures.append("\(entry.displayName) not connected")
                continue
            }
            guard let mode = bestMatch(in: info.modes, entry: entry) else {
                failures.append("No matching mode on \(entry.displayName)")
                continue
            }
            do {
                try ResolutionSwitcher.apply(mode, to: info.id)
            } catch {
                failures.append("\(entry.displayName): \(error)")
            }
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
