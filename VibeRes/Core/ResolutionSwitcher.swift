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

    /// One display's share of a reconfiguration.
    struct BatchChange {
        let display: CGDirectDisplayID
        let mode: CGDisplayMode
    }

    /// What a committed transaction did.
    ///
    /// Staging is per-display but committing is not, so failure comes in two
    /// shapes: a display CoreGraphics refused to stage (the rest still go
    /// through), and a commit that fails outright — which is thrown, because
    /// then nothing happened to anyone.
    struct BatchOutcome {
        let applied: Set<CGDirectDisplayID>
        let rejected: [CGDirectDisplayID: Failure]
    }

    /// Reconfigures any number of displays in a single Begin/Configure/Complete
    /// transaction.
    ///
    /// This is why the three-step API exists. Doing it per display means one
    /// full reconfiguration each — every screen blanks, comes back, and windows
    /// are relaid out against the new geometry — so a three-monitor profile
    /// blanked the desktop three times and passed through two intermediate
    /// layouts nobody asked for. Staged together, macOS blanks once and the
    /// desktop only ever has the arrangement the profile describes.
    ///
    /// `.permanently` persists the choice across reboots — pass `.forSession`
    /// for a temporary toggle that a countdown can take back.
    @discardableResult
    static func applyBatch(
        _ changes: [BatchChange],
        scope: CGConfigureOption = .permanently
    ) throws -> BatchOutcome {
        // An empty transaction is not free: Begin/Complete still asks
        // WindowServer to reconfigure. Nothing to do means nothing to open.
        guard !changes.isEmpty else { return BatchOutcome(applied: [], rejected: [:]) }

        var config: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&config)
        guard beginErr == .success else { throw Failure.beginConfig(beginErr) }

        var staged: Set<CGDirectDisplayID> = []
        var rejected: [CGDirectDisplayID: Failure] = [:]
        for change in changes {
            let err = CGConfigureDisplayWithDisplayMode(config, change.display, change.mode, nil)
            if err == .success {
                staged.insert(change.display)
            } else {
                // One unsupported mode must not cost the user the displays that
                // would have worked, so the transaction carries on without it.
                rejected[change.display] = .applyMode(err)
            }
        }

        // Everything was refused: committing would blank the screens to achieve
        // nothing. Cancel and let the caller report the per-display reasons.
        guard !staged.isEmpty else {
            CGCancelDisplayConfiguration(config)
            return BatchOutcome(applied: [], rejected: rejected)
        }

        let completeErr = CGCompleteDisplayConfiguration(config, scope)
        guard completeErr == .success else { throw Failure.completeConfig(completeErr) }
        return BatchOutcome(applied: staged, rejected: rejected)
    }

    /// Applies a display mode to a single display.
    ///
    /// A one-element batch, so there is exactly one implementation of the
    /// transaction to reason about.
    static func apply(
        _ mode: CGDisplayMode,
        to display: CGDirectDisplayID,
        scope: CGConfigureOption = .permanently
    ) throws {
        let outcome = try applyBatch([BatchChange(display: display, mode: mode)], scope: scope)
        if let failure = outcome.rejected[display] { throw failure }
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
