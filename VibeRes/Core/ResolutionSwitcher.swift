import CoreGraphics
import Foundation

enum ResolutionSwitcher {
    enum Failure: Error {
        case beginConfig(CGError)
        case applyMode(CGError)
        case completeConfig(CGError)

        /// Plain-English explanation for the popover and for `viberes` output.
        ///
        /// Interpolating the error directly yields
        /// `applyMode(__C.CGError(rawValue: 1004))`, which reads like a crash
        /// report. Stays English: Core is compiled into the bundle-less CLI, so
        /// a String Catalog lookup here would not resolve.
        var userFacingDescription: String {
            let code: CGError
            switch self {
            case .beginConfig(let c), .applyMode(let c), .completeConfig(let c):
                code = c
            }

            // The phase is deliberately not mentioned: "beginConfig failed"
            // means nothing to someone who just wanted a different resolution.
            // The numeric code is kept so a bug report stays actionable.
            let explanation: String
            switch code {
            case .cannotComplete:
                explanation = "macOS refused the change — the display may be busy, try again"
            case .rangeCheck, .illegalArgument:
                explanation = "that mode is not supported by this display"
            case .invalidConnection, .invalidContext, .invalidOperation:
                explanation = "the display connection dropped while changing the mode"
            default:
                explanation = "the resolution could not be changed"
            }
            return "\(explanation) (code \(code.rawValue))"
        }
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

extension Error {
    /// Text safe to show a person. Maps the errors we throw ourselves to plain
    /// language and falls back to the Swift description for anything else, so no
    /// call site has to remember to do the cast.
    var userFacingText: String {
        (self as? ResolutionSwitcher.Failure)?.userFacingDescription ?? "\(self)"
    }
}
