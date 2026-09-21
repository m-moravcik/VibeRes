import AppKit
import SwiftUI

@main
struct VibeResApp: App {
    @State private var displayStore: DisplayStore
    @State private var profileStore: ProfileStore
    @State private var updater: UpdaterProviding
    @State private var preferences: Preferences

    init() {
        // Wire up the AppKit-backed display name resolver before any DisplayStore
        // snapshot runs. Keeps the Core layer free of AppKit while still giving
        // the GUI the same names System Settings → Displays shows.
        DisplayNamer.install { id in
            if let screen = NSScreen.screens.first(where: { s in
                let key = NSDeviceDescriptionKey("NSScreenNumber")
                return (s.deviceDescription[key] as? NSNumber)?.uint32Value == id
            }) {
                return screen.localizedName
            }
            return DisplayNamer.fallback(for: id)
        }
        _displayStore = State(initialValue: DisplayStore())
        _profileStore = State(initialValue: ProfileStore())
        // Sparkle schedules its own checks; there is nothing to kick off here.
        _updater = State(initialValue: makeUpdaterController())
        let prefs = Preferences()
        // Re-register if a stored "launch at login" intent no longer matches
        // what SMAppService reports. Without this the setting can quietly stop
        // working — a replaced or moved bundle invalidates the registration and
        // the toggle just reads off, with nothing to notice the regression.
        prefs.launchAtLoginIntent = LoginItem.reconcile(storedIntent: prefs.launchAtLoginIntent)
        _preferences = State(initialValue: prefs)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(displayStore)
                .environment(profileStore)
                .environment(\.updater, updater)
                .environment(updater.updateStatus)
                .environment(preferences)
                .frame(minWidth: 280)
        } label: {
            Image(systemName: "rectangle.on.rectangle.angled")
                .accessibilityLabel("VibeRes")
        }
        .menuBarExtraStyle(.window)

        // Standard macOS Settings scene — opens via ⌘, from anywhere in
        // the app, including the footer's Settings… row. Categorised tabs
        // give the preferences surface room to grow without bloating the
        // menu-bar popover.
        Settings {
            SettingsView()
                .environment(displayStore)
                .environment(profileStore)
                .environment(\.updater, updater)
                .environment(updater.updateStatus)
                .environment(preferences)
        }
    }
}
