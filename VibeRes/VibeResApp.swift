import SwiftUI

@main
struct VibeResApp: App {
    @State private var displayStore = DisplayStore()
    @State private var profileStore = ProfileStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(displayStore)
                .environment(profileStore)
                .frame(minWidth: 280)
        } label: {
            Image(systemName: "rectangle.on.rectangle.angled")
        }
        .menuBarExtraStyle(.window)
    }
}
