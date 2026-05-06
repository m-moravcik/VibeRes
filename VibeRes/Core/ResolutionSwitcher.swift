import CoreGraphics
import Foundation

enum ResolutionSwitcher {
    enum Failure: Error {
        case beginConfig(CGError)
        case applyMode(CGError)
        case completeConfig(CGError)
    }

    /// Atomically applies a display mode to a single display.
    ///
    /// Uses the three-step Begin/Configure/Complete transaction so that future multi-display
    /// changes can be batched into one atomic commit. `.permanently` persists the choice
    /// across reboots — pass `.forSession` if you ever need a temporary toggle.
    static func apply(
        _ mode: CGDisplayMode,
        to display: CGDirectDisplayID,
        scope: CGConfigureOption = .permanently
    ) throws {
        var config: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&config)
        guard beginErr == .success else { throw Failure.beginConfig(beginErr) }

        let applyErr = CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        guard applyErr == .success else {
            CGCancelDisplayConfiguration(config)
            throw Failure.applyMode(applyErr)
        }

        let completeErr = CGCompleteDisplayConfiguration(config, scope)
        guard completeErr == .success else { throw Failure.completeConfig(completeErr) }
    }
}
