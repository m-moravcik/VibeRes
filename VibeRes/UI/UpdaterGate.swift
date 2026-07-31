import Foundation

/// Decides whether this particular build of VibeRes is allowed to update itself.
///
/// A pure function on purpose. It is the security boundary of the updater —
/// downloading and executing a binary without checking who signed it is remote
/// code execution — and a factory reading `Bundle.main` directly would put that
/// decision somewhere no test can reach. Tests run in Debug against an ad-hoc
/// signed host, so every gate would answer the same way and cover nothing.
enum UpdaterGate {
    enum Reason: Equatable {
        /// Not signed by us: a debug or ad-hoc build must never self-update.
        case notSigned
        case managedByHomebrew
        /// Running from a build directory rather than an installed bundle.
        case notABundle

        var userFacingDescription: String {
            switch self {
            case .notSigned, .notABundle:
                // Deliberately the same wording: to a user these are both "this
                // copy of the app isn't a real install", and distinguishing them
                // would only invite guessing at the difference.
                return String(localized: LocalizedStringResource(
                    "updates.unavailableInThisBuild",
                    defaultValue: "Updates unavailable in this build.",
                    comment: "Shown in Settings when the running copy cannot self-update"
                ))
            case .managedByHomebrew:
                return String(localized: LocalizedStringResource(
                    "updates.managedByHomebrew",
                    defaultValue: "Updates managed by Homebrew. Run: brew upgrade --cask m-moravcik/viberes/viberes-app",
                    comment: "Shown when VibeRes was installed by a Homebrew cask, which owns updates"
                ))
            }
        }
    }

    enum Decision: Equatable {
        case enabled
        case disabled(reason: Reason)
    }

    /// - Parameters:
    ///   - caskroomBundleURLs: app bundles found under Homebrew's Caskroom.
    ///     The comparison must start here: a cask `app` artifact *moves* the
    ///     bundle to /Applications and leaves the Caskroom entry as a symlink
    ///     pointing at it, so the running bundle's own path never contains
    ///     "/Caskroom/".
    static func decide(
        bundleURL: URL,
        isDeveloperIDSigned: Bool,
        caskroomBundleURLs: [URL]
    ) -> Decision {
        // Signature first. Not for security — every branch here returns the same
        // disabled controller — but for honesty: an unsigned build sitting near a
        // Caskroom path should not be told to run brew for something Homebrew
        // never installed.
        guard isDeveloperIDSigned else { return .disabled(reason: .notSigned) }

        let resolved = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let managedByHomebrew = caskroomBundleURLs.contains {
            $0.resolvingSymlinksInPath().standardizedFileURL == resolved
        }
        if managedByHomebrew { return .disabled(reason: .managedByHomebrew) }

        guard bundleURL.pathExtension == "app" else { return .disabled(reason: .notABundle) }

        return .enabled
    }

    /// App bundles Homebrew has recorded for this cask, across the prefixes it
    /// uses (Apple silicon, Intel, and a custom `HOMEBREW_PREFIX`).
    static func caskroomBundleURLs(
        caskToken: String = "viberes-app",
        bundleName: String = "VibeRes.app",
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        var prefixes = ["/opt/homebrew", "/usr/local"]
        if let custom = environment["HOMEBREW_PREFIX"], !custom.isEmpty {
            prefixes.insert(custom, at: 0)
        }

        return prefixes.flatMap { prefix -> [URL] in
            let caskDir = URL(fileURLWithPath: prefix)
                .appending(path: "Caskroom")
                .appending(path: caskToken)
            guard let versions = try? fileManager.contentsOfDirectory(
                at: caskDir,
                includingPropertiesForKeys: nil
            ) else { return [] }
            return versions.map { $0.appending(path: bundleName) }
        }
    }
}
