import Foundation
import Testing
@testable import VibeRes

/// The popover row that says an update is ready is driven by Sparkle delegate
/// callbacks. Every failure path has to clear it, or the row keeps advertising
/// an update that is not there — and the user clicks it and nothing happens.
///
/// Mapped onto a pure enum because the real callbacks take Sparkle types, which
/// only compile in Release; tests run in Debug and would never reach them.
@Suite("Update readiness transitions")
struct UpdateReadinessTests {
    @Test("A downloaded update queued for install makes the row appear")
    func downloadedAndQueued() {
        #expect(UpdateReadiness.next(after: .queuedForInstallOnQuit, currentlyReady: false) == true)
    }

    @Test("Every failure path clears the row", arguments: [
        UpdateReadiness.Event.downloadFailed,
        .downloadCancelled,
        .aborted,
        .userChoseInstall,
        .userChoseSkip,
    ])
    func failuresClear(event: UpdateReadiness.Event) {
        #expect(UpdateReadiness.next(after: event, currentlyReady: true) == false)
    }

    @Test("Dismissing a downloaded update keeps the row: the update is still there")
    func dismissKeepsDownloaded() {
        #expect(UpdateReadiness.next(after: .userDismissed(downloaded: true), currentlyReady: true) == true)
    }

    @Test("Dismissing before the download finished clears it")
    func dismissBeforeDownload() {
        #expect(UpdateReadiness.next(after: .userDismissed(downloaded: false), currentlyReady: true) == false)
    }

    @Test("Finishing a cycle with no update available does not invent one")
    func noUpdateFound() {
        #expect(UpdateReadiness.next(after: .cycleFinished, currentlyReady: false) == false)
    }

    @Test("Finishing a cycle does not discard an update already waiting")
    func cycleDoesNotClobberReady() {
        // A scheduled check completing must not wipe a row the user has not
        // acted on yet.
        #expect(UpdateReadiness.next(after: .cycleFinished, currentlyReady: true) == true)
    }
}
