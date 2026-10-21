import AppKit
import SwiftUI

@main
struct VibeResApp: App {
    @State private var displayStore: DisplayStore
    @State private var profileStore: ProfileStore
    @State private var updater: UpdaterProviding
    @State private var preferences: Preferences
    @State private var iconAnimator: MenuBarIconAnimator

    init() {
        #if DEBUG
        // Before anything with a side effect: the harness renders and exits,
        // and must not get as far as re-registering this build as a login item.
        if let output = ScreenshotHarness.requestedOutput {
            ScreenshotHarness.run(into: output)
        }
        if let output = MotionDemo.requestedOutput {
            MotionDemo.run(into: output)
        }
        #endif
        Self.installDisplayNamer()
        // The menu bar icon reacts to every resolution switch that went
        // through, from the menu or from a profile, manual or automatic.
        let iconAnimator = MenuBarIconAnimator()
        let displays = DisplayStore()
        let profiles = ProfileStore()
        displays.onModeSwitch = { [weak iconAnimator] in iconAnimator?.play() }
        profiles.onModeSwitch = { [weak iconAnimator] in iconAnimator?.play() }
        _iconAnimator = State(initialValue: iconAnimator)
        _displayStore = State(initialValue: displays)
        _profileStore = State(initialValue: profiles)
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

    /// Wires up the AppKit-backed display name resolver. Must run before any
    /// DisplayStore snapshot. Keeps the Core layer free of AppKit while still
    /// giving the GUI the same names System Settings → Displays shows.
    static func installDisplayNamer() {
        DisplayNamer.install { id in
            if let screen = NSScreen.screens.first(where: { s in
                let key = NSDeviceDescriptionKey("NSScreenNumber")
                return (s.deviceDescription[key] as? NSNumber)?.uint32Value == id
            }) {
                return screen.localizedName
            }
            return DisplayNamer.fallback(for: id)
        }
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
            MenuBarLabel(animator: iconAnimator)
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

/// The menu bar icon, redrawn for the animator's phase while a switch
/// animation plays.
private struct MenuBarLabel: View {
    let animator: MenuBarIconAnimator

    var body: some View {
        Image(nsImage: MenuBarIcon.image(at: animator.phase))
            .accessibilityLabel("VibeRes")
    }
}
