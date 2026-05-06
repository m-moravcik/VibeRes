import Foundation
import Observation

/// Polls GitHub Releases for a newer published version of VibeRes. No
/// background daemon, no auto-download — just a `URLSession` GET against
/// the public API once per day, surfaced as a small banner in the popover.
///
/// Privacy: a single anonymous GET request is sent to api.github.com; no
/// user-identifying data is included beyond the standard User-Agent.
@Observable
@MainActor
final class UpdateChecker {
    /// Latest tag observed on the remote ("v0.3.0"), or nil if not yet fetched
    /// or no newer version exists.
    private(set) var latestVersion: String?
    /// HTML URL of the release page on GitHub for the latest tag.
    private(set) var releaseURL: URL?
    private(set) var lastCheckedAt: Date?
    private(set) var isChecking: Bool = false

    /// True iff we know about a strictly-newer version than the running app.
    var isUpdateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return VibeResVersion.isVersion(latest, newerThan: Self.currentVersion)
    }

    /// "0.2.0" from the Info.plist.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/m-moravcik/VibeRes/releases/latest")!
    private static let lastCheckedKey = "VibeRes.UpdateChecker.lastCheckedAt"
    private static let cachedTagKey = "VibeRes.UpdateChecker.cachedTag"
    private static let cachedURLKey = "VibeRes.UpdateChecker.cachedURL"
    private static let checkInterval: TimeInterval = 60 * 60 * 24 // 24h

    init() {
        // Restore previously-cached state so the badge survives app restarts
        // without immediately re-hitting the GitHub API.
        let defaults = UserDefaults.standard
        if let timestamp = defaults.object(forKey: Self.lastCheckedKey) as? Date {
            self.lastCheckedAt = timestamp
        }
        if let cachedTag = defaults.string(forKey: Self.cachedTagKey),
           VibeResVersion.isVersion(cachedTag, newerThan: Self.currentVersion) {
            self.latestVersion = cachedTag
        }
        if let cachedURLString = defaults.string(forKey: Self.cachedURLKey),
           let cachedURL = URL(string: cachedURLString) {
            self.releaseURL = cachedURL
        }
    }

    /// Schedule a check if more than 24h has elapsed since the last successful poll.
    func checkIfDue() {
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        Task { await checkNow() }
    }

    /// Force a check regardless of cache window. Used for the manual menu item.
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let result = try await fetchLatest()
            // Persist the result so the badge state survives restarts.
            let defaults = UserDefaults.standard
            defaults.set(Date(), forKey: Self.lastCheckedKey)
            defaults.set(result.tag, forKey: Self.cachedTagKey)
            defaults.set(result.htmlURL.absoluteString, forKey: Self.cachedURLKey)

            self.latestVersion = result.tag
            self.releaseURL = result.htmlURL
            self.lastCheckedAt = Date()
        } catch {
            // Quietly accept any error — network down, rate limit, malformed
            // response. The banner just won't appear.
            self.lastCheckedAt = Date()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckedKey)
        }
    }

    // MARK: - Network

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    private func fetchLatest() async throws -> (tag: String, htmlURL: URL) {
        var request = URLRequest(url: Self.releasesAPIURL)
        request.setValue("VibeRes/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let url = URL(string: release.html_url) else { throw URLError(.badURL) }
        return (release.tag_name, url)
    }

    // MARK: - Version comparison (delegated to a non-isolated free function)
    //
    // Lifted out of the actor-isolated class so unit tests can call it
    // directly without crossing actor boundaries.
    static func isVersion(_ candidate: String, newerThan baseline: String) -> Bool {
        VibeResVersion.isVersion(candidate, newerThan: baseline)
    }
}

/// Pure-function version comparison — outside `UpdateChecker` (which is
/// `@MainActor`-isolated) so tests can invoke it from any context.
enum VibeResVersion {
    /// Returns true when `candidate` is strictly newer than `baseline` under
    /// loose semver. Both inputs may have a "v" prefix; pre-release suffixes
    /// (e.g. "-beta") are ignored. Falls back to `false` on parse errors so
    /// we never falsely advertise an update.
    static func isVersion(_ candidate: String, newerThan baseline: String) -> Bool {
        let a = parts(candidate)
        let b = parts(baseline)
        let length = max(a.count, b.count)
        for i in 0..<length {
            let lhs = i < a.count ? a[i] : 0
            let rhs = i < b.count ? b[i] : 0
            if lhs > rhs { return true }
            if lhs < rhs { return false }
        }
        return false
    }

    private static func parts(_ raw: String) -> [Int] {
        var s = raw
        if s.hasPrefix("v") { s.removeFirst() }
        if let cutoff = s.firstIndex(where: { !$0.isNumber && $0 != "." }) {
            s = String(s[..<cutoff])
        }
        return s.split(separator: ".").compactMap { Int($0) }
    }
}
