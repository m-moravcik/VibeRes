import AppKit
import SwiftUI

@main
struct VibeResApp: App {
    @State private var displayStore: DisplayStore
    @State private var profileStore: ProfileStore

    init() {
        // Wire up the AppKit-backed display name resolver before any DisplayStore
        // snapshot runs. Keeps the Core layer free of AppKit while still giving
        // the GUI the same names System Settings → Displays shows.
        DisplayNamer.resolve = { id in
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
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(displayStore)
                .environment(profileStore)
                .frame(minWidth: 280)
        } label: {
            Image(systemName: "rectangle.on.rectangle.angled")
                .accessibilityLabel("VibeRes")
        }
        .menuBarExtraStyle(.window)
    }
}
