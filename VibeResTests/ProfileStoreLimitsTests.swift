import Foundation
import Testing
@testable import VibeRes

/// `profiles.json` is read with `Data(contentsOf:)` on the main actor with no
/// size or count limit. It is the user's own file, so this is resilience rather
/// than a trust boundary — but a hand-edited or corrupted file should not be
/// able to stall launch or exhaust memory, and the app should say so instead of
/// hanging.
@Suite("Profile store limits")
struct ProfileStoreLimitsTests {
    @Test("An ordinary catalog is well inside the limit")
    func ordinaryFileAccepted() {
        #expect(ProfileStore.isWithinSizeLimit(bytes: 0))
        #expect(ProfileStore.isWithinSizeLimit(bytes: 64 * 1024))
    }

    @Test("An implausibly large file is refused before it is read")
    func hugeFileRefused() {
        #expect(!ProfileStore.isWithinSizeLimit(bytes: 64 * 1024 * 1024))
        // Right at the boundary: the limit itself is still acceptable.
        #expect(ProfileStore.isWithinSizeLimit(bytes: ProfileStore.maximumStoreBytes))
        #expect(!ProfileStore.isWithinSizeLimit(bytes: ProfileStore.maximumStoreBytes + 1))
    }

    @Test("Decoded catalogs are capped rather than trusted")
    func profileCountCapped() {
        let many = (0..<(ProfileStore.maximumProfiles + 25)).map {
            Profile(name: "P\($0)", entries: [])
        }
        let capped = ProfileStore.capped(many)
        #expect(capped.count == ProfileStore.maximumProfiles)
        // Keeps the first ones, so the cap is predictable rather than arbitrary.
        #expect(capped.first?.name == "P0")
    }

    @Test("A single profile cannot carry an unbounded number of entries")
    func entryCountCapped() {
        let entry = Profile.Entry(
            matcher: .anyExternal,
            displayName: "X",
            pointWidth: 1920,
            pointHeight: 1080,
            refreshHz: 60,
            isHiDPI: false
        )
        let bloated = Profile(
            name: "Bloated",
            entries: Array(repeating: entry, count: ProfileStore.maximumEntriesPerProfile + 10)
        )
        let capped = ProfileStore.capped([bloated])
        #expect(capped.first?.entries.count == ProfileStore.maximumEntriesPerProfile)
    }

    @Test("A catalog already within limits is returned untouched")
    func withinLimitsUnchanged() {
        let profiles = [Profile(name: "Desk", entries: []), Profile(name: "Travel", entries: [])]
        #expect(ProfileStore.capped(profiles).map(\.name) == ["Desk", "Travel"])
    }
}
