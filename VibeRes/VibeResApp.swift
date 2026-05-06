import SwiftUI

@main
struct VibeResApp: App {
    @State private var displayStore = DisplayStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(displayStore)
                .frame(minWidth: 280)
        } label: {
            Image(systemName: "rectangle.on.rectangle.angled")
        }
        .menuBarExtraStyle(.window)
    }
}
