import Foundation
import Testing
@testable import VibeRes

/// Sparkle refuses to start on some Info.plist combinations, and the only
/// symptom the user gets is "The updater failed to start" — no log, nothing on
/// stderr, and the app otherwise works fine. 0.8.3 shipped exactly that.
///
/// These assert the invariants Sparkle enforces at `startUpdater()`, against the
/// generated Info.plist rather than a copy of the values, so a change in
/// project.yml is what the test sees.
@Suite("Sparkle configuration")
struct SparkleConfigurationTests {
    // A function, not a stored static: [String: Any] is not Sendable, and a
    // shared static would be a data race under strict concurrency.
    private static func loadPlist() -> [String: Any] {
        var dir = URL(fileURLWithPath: #filePath)
        dir.deleteLastPathComponent()          // VibeResTests
        dir.deleteLastPathComponent()          // repo root
        let url = dir.appending(path: "VibeRes/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    private var plist: [String: Any] { Self.loadPlist() }
    private func bool(_ key: String) -> Bool? { plist[key] as? Bool }

    @Test("The Info.plist is readable at all")
    func plistLoads() {
        #expect(!plist.isEmpty, "run `xcodegen generate` — Info.plist is generated from project.yml")
    }

    @Test("Requiring a signed feed also requires verifying before extraction")
    func signedFeedImpliesVerifyBeforeExtraction() {
        // SPUUpdater.m: "For security reasons, SUVerifyUpdateBeforeExtraction
        // needs to also be enabled if SURequireSignedFeed is enabled." Setting
        // one without the other makes startUpdater() return NO, which surfaces
        // as an alert saying the updater failed to start and nothing else.
        guard bool("SURequireSignedFeed") == true else { return }
        #expect(bool("SUVerifyUpdateBeforeExtraction") == true,
                "SURequireSignedFeed without SUVerifyUpdateBeforeExtraction stops Sparkle from starting")
    }

    @Test("Automatic downloads are on, or the update-ready row never appears")
    func autoDownloadEnabled() {
        // willInstallUpdateOnQuit — which is what raises the popover row — only
        // fires after an *automatic* download. Auto-download is off by default.
        #expect(bool("SUAutomaticallyUpdate") == true)
    }

    @Test("The feed URL is present and https")
    func feedURL() throws {
        let raw = try #require(plist["SUFeedURL"] as? String)
        let url = try #require(URL(string: raw))
        #expect(url.scheme == "https", "an http feed would let anyone serve updates")
    }

    @Test("A real EdDSA public key is configured")
    func publicKey() throws {
        let key = try #require(plist["SUPublicEDKey"] as? String)
        #expect(!key.contains("PLACEHOLDER"), "the generate_keys placeholder is still in place")
        // Ed25519 public keys are 32 bytes, which is 44 base64 characters.
        #expect(Data(base64Encoded: key)?.count == 32, "not a 32-byte Ed25519 public key")
    }
}
