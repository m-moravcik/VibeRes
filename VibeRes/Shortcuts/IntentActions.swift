import CoreGraphics
import Foundation

/// The stores the running app owns, reachable from App Intents. An intent is a
/// value Shortcuts creates on its own, so it cannot be handed the stores the
/// way a view is; the app registers them once at launch. They are the same
/// instances the popover and the global shortcuts use, which is what lets
/// Revert in the popover take back what a Shortcut applied.
@MainActor
enum IntentRuntime {
    static var displays: DisplayStore?
    static var profiles: ProfileStore?

    static func requireDisplays() throws -> DisplayStore {
        guard let displays else { throw IntentProblem.appNotReady }
        return displays
    }

    static func requireProfiles() throws -> ProfileStore {
        guard let profiles else { throw IntentProblem.appNotReady }
        return profiles
    }
}

/// Why an intent did not do what it was asked. Values, so a test can check the
/// cause on any Mac; the words are resolved in the app's language only when a
/// Shortcut shows them.
enum IntentProblem: Error, Equatable {
    case appNotReady
    case displayNotConnected
    case profileMissing
    case noDisplayConnected(profile: String)
    case noCloseMode(width: Int, height: Int, display: String)
    case widthOutOfRange
    case heightOutOfRange
    case refreshOutOfRange
    /// macOS refused the switch. The text is the store's own explanation.
    case switchFailed(String)
    /// The profile ran and nothing it names could be applied.
    case notApplied(ShortcutAnnouncement)

    func localizedDescription(locale: Locale = .appLanguage) -> String {
        switch self {
        case .appNotReady:
            return String(localized: LocalizedStringResource(
                "intent.problem.appNotReady",
                defaultValue: "VibeRes is still starting. Try again in a moment.",
                locale: locale,
                comment: "Shown by a Shortcuts action that ran before the app finished launching"
            ))
        case .displayNotConnected:
            return String(localized: LocalizedStringResource(
                "That display is no longer connected.", locale: locale
            ))
        case .profileMissing:
            return ShortcutAnnouncement.profileMissing.localizedDescription(locale: locale)
        case let .noDisplayConnected(profile):
            return ShortcutAnnouncement.noDisplayConnected(profile: profile).localizedDescription(locale: locale)
        case let .noCloseMode(width, height, display):
            return String(localized: LocalizedStringResource(
                "No mode close to \(width)×\(height) is available on \(display).", locale: locale
            ))
        case .widthOutOfRange:
            return String(localized: LocalizedStringResource(
                "Width must be between 1 and 16384 points.", locale: locale
            ))
        case .heightOutOfRange:
            return String(localized: LocalizedStringResource(
                "Height must be between 1 and 16384 points.", locale: locale
            ))
        case .refreshOutOfRange:
            return String(localized: LocalizedStringResource(
                "Refresh rate must be between 1 and 1000 Hz.", locale: locale
            ))
        case let .switchFailed(reason):
            return reason
        case let .notApplied(announcement):
            return announcement.localizedDescription(locale: locale)
        }
    }
}

extension IntentProblem: LocalizedError {
    var errorDescription: String? { localizedDescription() }
}

/// What the Shortcuts actions do, apart from Shortcuts. Each takes the stores
/// it acts through, so a test can hand it stores whose display transaction is
/// injected; the intents pass the app's own.
@MainActor
enum IntentActions {
    /// Switches `displayID` to the closest mode to the request, through
    /// `DisplayStore.apply`: the same path as a click in the popover, so the
    /// mode it replaced is armed for Revert. Returns the new resolution as
    /// text, like Get Current Resolution does.
    static func setResolution(
        displayID: Int,
        width: Int,
        height: Int,
        refreshHz: Int?,
        preferHiDPI: Bool,
        variableRefresh: Bool,
        displays: DisplayStore
    ) throws -> String {
        // Shortcuts hands over whatever the automation supplies, including
        // values no display could have. Reject them at the parameter that is
        // wrong rather than silently pick some "closest" mode.
        guard ModeScoring.isRequestInRange(width: width, height: height, refreshHz: refreshHz) else {
            if !(1...16384).contains(width) { throw IntentProblem.widthOutOfRange }
            if !(1...16384).contains(height) { throw IntentProblem.heightOutOfRange }
            throw IntentProblem.refreshOutOfRange
        }

        displays.refresh()
        guard let info = displays.displays.first(where: { Int($0.id) == displayID }) else {
            throw IntentProblem.displayNotConnected
        }
        guard let mode = ModeScoring.bestMatch(
            in: info.modes,
            request: ModeScoring.Request(
                width: width, height: height, refreshHz: refreshHz,
                preferHiDPI: preferHiDPI, preferVariable: variableRefresh
            ),
            isVariable: info.isVariable
        ) else {
            throw IntentProblem.noCloseMode(width: width, height: height, display: info.name)
        }

        // `apply` reports a failure through `lastError` and leaves the Revert
        // already armed alone. A leftover error from an earlier click would
        // read as this call's, so it is cleared first.
        displays.dismissLastError()
        displays.apply(mode, to: info.id)
        if let problem = displays.lastError {
            throw IntentProblem.switchFailed(problem.localizedDescription)
        }
        return "\(mode.width) × \(mode.height)\(SetResolutionIntent.hzPart(mode, on: info))"
    }

    /// Applies a saved profile the way the global shortcut does, and says what
    /// happened in the words of the popover's note. A profile that landed
    /// nothing is an error, so a Shortcut can branch on it; one that landed
    /// some of its displays is a success whose text names what was left out.
    static func applyProfile(id: UUID, displays: DisplayStore, profiles: ProfileStore) throws -> String {
        switch ShortcutActions.runProfile(id, displays: displays, profiles: profiles) {
        case .missing:
            throw IntentProblem.profileMissing
        case .noDisplayConnected(let name):
            throw IntentProblem.noDisplayConnected(profile: name)
        case let .applied(profile, result):
            let note = ApplyOutcomeNote.make(from: result.outcomes, mainChange: result.mainChange)
                ?? ApplyOutcomeNote(tone: .info, content: .alreadyAtSavedSettings)
            let said = ShortcutAnnouncement.applied(profile: profile.name, note: note)
            if ShortcutActions.landedNothing(result) {
                throw IntentProblem.notApplied(said)
            }
            return said.localizedDescription()
        }
    }
}
