import Foundation

/// Something that went wrong and that the person in front of the screen needs
/// told, carried as a *value* rather than as a finished sentence.
///
/// The stores used to hold `String?`, filled from
/// `ResolutionSwitcher.Failure.userFacingDescription`, which is deliberately
/// English: `VibeRes/Core` is also compiled into the bundle-less `viberes`
/// tool, where a String Catalog lookup does not resolve. The consequence was a
/// fully translated interface with an English error sentence sitting in the
/// middle of it.
///
/// This is the same split `ApplyOutcomeNote` already uses for profile outcomes:
/// Core produces values and an English rendering for the CLI, and the UI layer
/// renders the localised copy from those values.
enum UserFacingProblem: Equatable {
    /// A display reconfiguration CoreGraphics refused.
    case switchFailed(ResolutionSwitcher.Failure)
    /// Arrangement combined with mirroring is unmeasured territory, so the
    /// main-display change is refused rather than attempted.
    case mirroredArrangement
    /// The origin transaction committed, but reading the arrangement back
    /// shows something other than the plan (spike F5).
    case mainDisplayAdjusted
    /// Revert restored the modes but could not put the menu bar back.
    case previousMainNotRestored
    /// `profiles.json` is too large, does not decode, or cannot be opened.
    /// `keptAs` names the copy of the file kept beside it, when there is one.
    case profilesUnreadable(keptAs: String?)
    /// `profiles.json` decoded, but some profiles, entries or fields in it
    /// could not be read and were left out. `keptAs` as above.
    case profilesPartlyUnreadable(keptAs: String?)
    /// Writing `profiles.json` failed.
    case profilesNotSaved
    /// An error that is not one of ours. There is nothing to map, so the text
    /// travels as-is.
    case other(String)

    /// English rendering. Used by the CLI, which has no bundle, and as the
    /// fallback for anything the UI has not been taught to localise.
    var englishDescription: String {
        switch self {
        case .switchFailed(let failure):
            return failure.userFacingDescription
        case .mirroredArrangement:
            return "displays are mirrored — main display left unchanged"
        case .mainDisplayAdjusted:
            return "main display set, but macOS adjusted the arrangement"
        case .previousMainNotRestored:
            return "the previous main display could not be restored — macOS adjusted the arrangement"
        case .profilesUnreadable(let keptAs?):
            return "Saved profiles could not be read. The original file is kept next to profiles.json as \(keptAs)."
        case .profilesUnreadable(nil):
            return "Saved profiles could not be read and were not loaded."
        case .profilesPartlyUnreadable(let keptAs?):
            return "Some saved profile settings could not be read and were left out. The original file is kept next to profiles.json as \(keptAs)."
        case .profilesPartlyUnreadable(nil):
            return "Some saved profile settings could not be read and were left out."
        case .profilesNotSaved:
            return "Failed to save profiles."
        case .other(let text):
            return text
        }
    }
}

extension UserFacingProblem {
    /// True for a problem reading `profiles.json`. A successful save leaves
    /// it up, where it clears a failed save's.
    var isCatalogReadProblem: Bool {
        switch self {
        case .profilesUnreadable, .profilesPartlyUnreadable: return true
        default: return false
        }
    }
}

extension Error {
    /// This error as a problem the stores can hold. Maps the ones we throw
    /// ourselves onto their own case so the UI can localise them, and keeps
    /// anything else as text.
    var asUserFacingProblem: UserFacingProblem {
        (self as? ResolutionSwitcher.Failure).map(UserFacingProblem.switchFailed)
            ?? .other("\(self)")
    }
}
