import AppIntents

/// Pre-built Shortcut phrases users can invoke without setting up a workflow:
/// type them in Spotlight or say to Siri and they run directly.
struct VibeResAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetResolutionIntent(),
            phrases: [
                "Set resolution in \(.applicationName)",
                "Change resolution with \(.applicationName)",
                "Switch \(.applicationName) display",
            ],
            shortTitle: "Set Resolution",
            systemImageName: "rectangle.on.rectangle.angled"
        )

        AppShortcut(
            intent: GetCurrentResolutionIntent(),
            phrases: [
                "Get current resolution from \(.applicationName)",
                "What is my resolution in \(.applicationName)",
            ],
            shortTitle: "Get Current Resolution",
            systemImageName: "info.circle"
        )
    }
}
