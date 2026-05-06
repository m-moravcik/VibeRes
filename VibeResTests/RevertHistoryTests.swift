import Foundation
import Testing
@testable import VibeRes

/// RevertHistory uses real CGDisplayMode references in entries, but the
/// store itself doesn't introspect them — it only treats them as opaque
/// payloads. Tests can therefore exercise the bookkeeping with empty
/// state transitions; recording requires a real CGDisplayMode and is
/// covered indirectly by the DisplayStore / ProfileStore integration.
@Suite("RevertHistory bookkeeping")
@MainActor
struct RevertHistoryTests {
    @Test("Empty history is not revertable and has empty summary")
    func emptyState() {
        let h = RevertHistory()
        #expect(h.canRevert == false)
        #expect(h.summary.isEmpty)
        #expect(h.entries.isEmpty)
    }

    @Test("Clear on already-empty history is a no-op")
    func clearWhenEmpty() {
        let h = RevertHistory()
        h.clear()
        #expect(h.canRevert == false)
    }

    @Test("Consume on empty history returns empty array")
    func consumeWhenEmpty() {
        let h = RevertHistory()
        let snapshot = h.consume()
        #expect(snapshot.isEmpty)
        #expect(h.canRevert == false)
    }

    // Recording / consume / batch round-trip is covered by the integration
    // path, not here. CGDisplayMode is a CF class we can't allocate from
    // Swift unit tests (same reason DisplayModeProtocol exists), and
    // touching real displays from a unit run is a non-goal.
}
