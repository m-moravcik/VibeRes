import Foundation
import Testing
@testable import VibeRes

/// Pure-logic tests for the version-comparison helper that drives the
/// "update available" banner. The network-fetch path is intentionally not
/// unit-tested — it would either hit api.github.com (flaky in CI) or need a
/// URLSession mock, both of which are higher-effort than the value warrants
/// for a single GET that's invisible when it fails.
@Suite("UpdateChecker version comparison")
struct UpdateCheckerVersionTests {
    @Test("Higher patch version is detected as newer")
    func patchBump() {
        #expect(VibeResVersion.isVersion("0.2.1", newerThan: "0.2.0"))
        #expect(VibeResVersion.isVersion("v0.2.1", newerThan: "0.2.0"))
        #expect(VibeResVersion.isVersion("0.2.1", newerThan: "v0.2.0"))
    }

    @Test("Higher minor version is newer")
    func minorBump() {
        #expect(VibeResVersion.isVersion("0.3.0", newerThan: "0.2.5"))
        #expect(VibeResVersion.isVersion("v0.3.0", newerThan: "v0.2.99"))
    }

    @Test("Higher major version is newer")
    func majorBump() {
        #expect(VibeResVersion.isVersion("1.0.0", newerThan: "0.99.99"))
    }

    @Test("Equal versions are not 'newer'")
    func equalVersions() {
        #expect(VibeResVersion.isVersion("0.2.0", newerThan: "0.2.0") == false)
        #expect(VibeResVersion.isVersion("v0.2.0", newerThan: "0.2.0") == false)
    }

    @Test("Older versions are not 'newer'")
    func olderNotNewer() {
        #expect(VibeResVersion.isVersion("0.1.99", newerThan: "0.2.0") == false)
        #expect(VibeResVersion.isVersion("0.2.0", newerThan: "0.2.1") == false)
    }

    @Test("Pre-release suffix is ignored on comparison")
    func preReleaseSuffix() {
        // 0.3.0-beta vs 0.3.0 should compare equal (suffix dropped → both "0.3.0")
        #expect(VibeResVersion.isVersion("0.3.0-beta", newerThan: "0.3.0") == false)
        #expect(VibeResVersion.isVersion("0.3.0", newerThan: "0.3.0-beta") == false)
        // 0.3.1-beta is still newer than 0.3.0
        #expect(VibeResVersion.isVersion("0.3.1-beta", newerThan: "0.3.0"))
    }

    @Test("Mismatched component counts compared with implicit zeros")
    func differentComponentCounts() {
        // "0.3" should equal "0.3.0", neither is newer
        #expect(VibeResVersion.isVersion("0.3", newerThan: "0.3.0") == false)
        #expect(VibeResVersion.isVersion("0.3.0", newerThan: "0.3") == false)
        // "0.3.0.1" is newer than "0.3.0"
        #expect(VibeResVersion.isVersion("0.3.0.1", newerThan: "0.3.0"))
    }

    @Test("Garbage strings compare as not-newer (no false positives)")
    func garbageDoesntFalsePositive() {
        // We deliberately don't crash or claim "newer" on bizarre inputs —
        // the banner stays hidden if either side is unparseable enough that
        // both reduce to [].
        #expect(VibeResVersion.isVersion("abc", newerThan: "def") == false)
        #expect(VibeResVersion.isVersion("", newerThan: "0.2.0") == false)
        #expect(VibeResVersion.isVersion("v", newerThan: "v") == false)
    }
}
