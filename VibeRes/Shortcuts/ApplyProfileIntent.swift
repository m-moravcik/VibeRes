import AppIntents
import Foundation

/// Applies a saved profile from Shortcuts.app, Spotlight or Siri. It acts
/// through the same stores as the popover's pill and the profile's global
/// shortcut, so Revert in the popover takes it back, and the result says what
/// happened in the words of the popover's note. A profile that could apply
/// nothing fails the action, so a Shortcut can branch on it.
struct ApplyProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Profile"
    static let description = IntentDescription(
        "Applies a saved VibeRes profile. Displays it does not include are left as they are, and Revert in the menu takes it back.",
        categoryName: "Display"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$profile)")
    }

    @Parameter(title: "Profile")
    var profile: ProfileEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let said = try IntentActions.applyProfile(
                id: profile.id,
                displays: try IntentRuntime.requireDisplays(),
                profiles: try IntentRuntime.requireProfiles()
            )
            return .result(value: said)
        } catch let problem as IntentProblem {
            // A profile deleted since the Shortcut was made: have Shortcuts ask
            // for another one instead of failing the whole run.
            if case .profileMissing = problem {
                let said = LocalizedStringResource(
                    "shortcut.announce.profileMissing",
                    defaultValue: "The profile for this shortcut no longer exists"
                )
                throw $profile.needsValueError(IntentDialog(full: said, supporting: said))
            }
            throw problem
        }
    }
}
