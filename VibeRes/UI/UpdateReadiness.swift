import Foundation

/// Whether the popover should be offering "Update ready, restart now?".
///
/// Sparkle reports progress through a scattering of delegate callbacks, and each
/// one that can end an update has to clear this flag. Miss one and the row keeps
/// advertising an update that is no longer there, which the user clicks and
/// nothing happens.
///
/// Kept as a pure function over an enum rather than living inside the delegate:
/// the real callbacks take Sparkle types, which only compile under
/// `ENABLE_SPARKLE` in Release, and tests run in Debug.
enum UpdateReadiness {
    enum Event: Equatable, Sendable {
        /// An automatically downloaded update is staged for install on quit.
        /// This is the only event that turns the row on.
        case queuedForInstallOnQuit
        case downloadFailed
        case downloadCancelled
        case aborted
        /// The user acted through Sparkle's own UI rather than our row.
        case userChoseInstall
        case userChoseSkip
        /// Dismissed without deciding. Whether an update is still waiting
        /// depends on how far it had got.
        case userDismissed(downloaded: Bool)
        /// End of a check cycle, including "no update available".
        case cycleFinished
    }

    static func next(after event: Event, currentlyReady: Bool) -> Bool {
        switch event {
        case .queuedForInstallOnQuit:
            return true

        case .downloadFailed, .downloadCancelled, .aborted,
             .userChoseInstall, .userChoseSkip:
            return false

        case let .userDismissed(downloaded):
            // Dismissing an alert does not discard a finished download; the
            // update really is sitting there ready to install.
            return downloaded

        case .cycleFinished:
            // A scheduled check completing says nothing about an update the user
            // has already been offered and not yet acted on.
            return currentlyReady
        }
    }
}
