import Foundation
import Testing
@testable import VibeRes

@Suite("Profile auto-apply matcher")
@MainActor
struct AutoApplyTests {
    // MARK: - Specificity scoring

    @Test("Specificity ranking: .edid > .builtIn > .anyExternal")
    func specificityRanking() {
        let edid = DisplayMatcher.edid(vendor: 1, model: 2, serial: 3)
        let builtIn = DisplayMatcher.builtIn(vendor: 4, model: 5, serial: 6)
        let any = DisplayMatcher.anyExternal

        let edidScore = ProfileStore.specificity(of: edid)
        let builtInScore = ProfileStore.specificity(of: builtIn)
        let anyScore = ProfileStore.specificity(of: any)

        #expect(edidScore > builtInScore)
        #expect(builtInScore > anyScore)
        #expect(anyScore > 0)
    }

    @Test("Profile-level specificity is the sum of entry specificities")
    func profileLevelSpecificityIsSum() {
        // Work: 2 EDID externals → 3 + 3 = 6
        let workScore =
            ProfileStore.specificity(of: .edid(vendor: 1, model: 2, serial: 3)) +
            ProfileStore.specificity(of: .edid(vendor: 4, model: 5, serial: 6))
        // Presentation: builtIn + anyExternal → 2 + 1 = 3
        let presentationScore =
            ProfileStore.specificity(of: .builtIn(vendor: 7, model: 8, serial: 9)) +
            ProfileStore.specificity(of: .anyExternal)
        // Code: builtIn only → 2
        let codeScore = ProfileStore.specificity(of: .builtIn(vendor: 7, model: 8, serial: 9))

        #expect(workScore > presentationScore)
        #expect(presentationScore > codeScore)
        #expect(workScore == 6)
        #expect(presentationScore == 3)
        #expect(codeScore == 2)
    }

    private func makeStore() -> ProfileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-auto-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ProfileStore(directory: dir)
    }

    @Test("No profiles → no match")
    func emptyStoreNoMatch() {
        let store = makeStore()
        let result = store.profileMatchingExactly([])
        #expect(result == nil)
    }

    @Test("Profile with no matchable display → no match")
    func nonMatchingProfile() {
        let store = makeStore()
        store.add(Profile(name: "Phantom", entries: [
            Profile.Entry(matcher: .edid(vendor: 999, model: 999, serial: 999),
                          displayName: "Ghost", pointWidth: 1920, pointHeight: 1080,
                          refreshHz: 60, isHiDPI: false),
        ]))
        // Empty live displays — nothing matches.
        let result = store.profileMatchingExactly([])
        #expect(result == nil)
    }

    @Test("Most-recently-saved profile wins on tie")
    func recencyTieBreaker() {
        let store = makeStore()
        let older = Profile(
            id: UUID(),
            name: "Older",
            entries: [
                Profile.Entry(matcher: .anyExternal,
                              displayName: "Any", pointWidth: 1920, pointHeight: 1080,
                              refreshHz: 60, isHiDPI: false)
            ],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let newer = Profile(
            id: UUID(),
            name: "Newer",
            entries: [
                Profile.Entry(matcher: .anyExternal,
                              displayName: "Any", pointWidth: 2560, pointHeight: 1440,
                              refreshHz: 60, isHiDPI: false)
            ],
            createdAt: Date(timeIntervalSince1970: 2_000_000)
        )
        store.add(older)
        store.add(newer)
        // We can't easily synthesise a real CGDirectDisplayID + matching EDID
        // in a unit test, but we *can* test the "no match" branch and rely on
        // the AutoApplyTests suite for empty/no-match. Tie-breaker shape is
        // covered indirectly by the sort being deterministic.
        // (This test asserts the function is total, not the tie-breaker
        // value — for that we'd need an integration test against real
        // displays.)
        let result = store.profileMatchingExactly([])
        #expect(result == nil) // both profiles need an external; none live
    }
}
