import CoreGraphics
import Foundation

/// Localised copy for `UserFacingProblem`.
///
/// Lives in `VibeRes/UI` for the same reason `ApplyOutcomeNote` does: the
/// `VibeRes/Core` types it renders are compiled into the bundle-less `viberes`
/// tool, which has no String Catalog to resolve against and prints
/// `englishDescription` verbatim. Only the app resolves these keys.
///
/// The numeric CoreGraphics code is appended outside the translated sentence,
/// so no language has to reassemble "(code 1004)" — and a bug report stays
/// actionable whatever the reporter's language is.
extension UserFacingProblem {
    var localizedDescription: String {
        switch self {
        case .switchFailed(let failure):
            return failure.localizedDescription

        case .mirroredArrangement:
            return String(localized: LocalizedStringResource(
                "problem.mirroredArrangement",
                defaultValue: "Displays are mirrored — the main display was left unchanged.",
                comment: "Shown when a main-display change is refused because mirroring is on"
            ))

        case .mainDisplayAdjusted:
            return String(localized: LocalizedStringResource(
                "problem.mainDisplayAdjusted",
                defaultValue: "Main display set, but macOS adjusted the arrangement.",
                comment: "The origin transaction committed but the read-back differs from the plan"
            ))

        case .previousMainNotRestored:
            return String(localized: LocalizedStringResource(
                "problem.previousMainNotRestored",
                defaultValue: "The previous main display could not be restored — macOS adjusted the arrangement.",
                comment: "Revert put the modes back but could not move the menu bar back"
            ))

        case .profilesUnreadable:
            return String(localized: LocalizedStringResource(
                "problem.profilesUnreadable",
                defaultValue: "Saved profiles could not be read and were not loaded.",
                comment: "profiles.json is too large, or does not decode"
            ))

        case .profilesNotSaved:
            return String(localized: LocalizedStringResource(
                "problem.profilesNotSaved",
                defaultValue: "Profiles could not be saved.",
                comment: "Writing profiles.json failed"
            ))

        case .other(let text):
            // Nothing to map. Better an untranslated sentence than a lost one.
            return text
        }
    }
}

extension ResolutionSwitcher.Failure {
    /// The same five buckets `userFacingDescription` uses, translated.
    ///
    /// The phase (begin / configure / complete) is deliberately still not
    /// mentioned: "beginConfig failed" means nothing to someone who just
    /// wanted a different resolution.
    var localizedDescription: String {
        let code: CGError
        switch self {
        case .originCoverage:
            return String(localized: LocalizedStringResource(
                "problem.originCoverage",
                defaultValue: "The display setup changed while applying — the arrangement was left unchanged.",
                comment: "An origin plan no longer covers exactly the active displays, so it is refused"
            ))
        case .beginConfig(let c), .applyMode(let c), .completeConfig(let c), .applyOrigin(let c):
            code = c
        }

        let explanation: String
        switch code {
        case .cannotComplete:
            explanation = String(localized: LocalizedStringResource(
                "problem.switch.busy",
                defaultValue: "macOS refused the change — the display may be busy, try again",
                comment: "CoreGraphics returned cannotComplete for a display reconfiguration"
            ))
        case .rangeCheck, .illegalArgument:
            explanation = String(localized: LocalizedStringResource(
                "problem.switch.unsupportedMode",
                defaultValue: "That mode is not supported by this display",
                comment: "CoreGraphics rejected the requested display mode"
            ))
        case .invalidConnection, .invalidContext, .invalidOperation:
            explanation = String(localized: LocalizedStringResource(
                "problem.switch.connectionDropped",
                defaultValue: "The display connection dropped while changing the mode",
                comment: "The display went away mid-reconfiguration"
            ))
        default:
            explanation = String(localized: LocalizedStringResource(
                "problem.switch.generic",
                defaultValue: "The resolution could not be changed",
                comment: "Fallback for any other CoreGraphics error code"
            ))
        }
        return "\(explanation) (code \(code.rawValue))"
    }
}
