import SwiftUI

/// Standalone macOS Settings window. Opens via the menu bar's Settings…
/// row and via the standard ⌘, shortcut. Lives in its own scene rather
/// than as inline footer toggles so the popover stays focused on the
/// primary action (switching resolutions) and the preferences surface
/// has room to grow without bloating the main menu.
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.updater) private var updater
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    /// Forces the TabView to start on General every time the Settings
    /// window is opened. SwiftUI keeps the SettingsView instance alive
    /// across opens, so without this the user would land on whichever
    /// tab they last left selected. Apple's own Mail.app and many
    /// well-designed third-party Mac apps reset to General on each
    /// open — predictable, onboarding-friendly, and the General tab
    /// has the toggles users tweak most often (Launch at login,
    /// auto-apply).
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: Hashable {
        case general, display, updates
    }

    var body: some View {
        @Bindable var prefs = preferences
        TabView(selection: $selectedTab) {
            generalTab(prefs: $prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            displayTab(prefs: $prefs)
                .tabItem { Label("Display", systemImage: "display") }
                .tag(SettingsTab.display)

            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                .tag(SettingsTab.updates)
        }
        // Sized so no tab scrolls. A little empty space beats a scroll bar in a
        // settings window with three tabs — the previous 320pt height cut off
        // the General tab once the confirmation setting was added.
        .frame(width: 470, height: 400)
        .task {
            // Prefer the recorded intent: if the registration was invalidated
            // and re-registration failed, the toggle should still show what the
            // user asked for rather than silently reverting to off.
            launchAtLogin = preferences.launchAtLoginIntent ?? LoginItem.isEnabled
            // Reset on every appear — covers re-opens after close.
            selectedTab = .general
        }
    }

    // MARK: General

    @ViewBuilder
    private func generalTab(prefs: Bindable<Preferences>) -> some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        // Record the intent before touching the service. It is
                        // what the user asked for and has to outlive a failed
                        // registration, so the next launch can retry instead of
                        // quietly leaving the setting off.
                        preferences.launchAtLoginIntent = newValue
                        launchAtLogin = newValue

                        guard LoginItem.setEnabled(newValue) else { return }
                        // SMAppService applies async — give it a runloop
                        // tick before reading the canonical state back.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(150))
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                ))
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("Auto-apply matching profile", isOn: prefs.autoApplyOnDisplayChange)
                Text("Applied silently when a monitor is plugged in or unplugged. Changing only a resolution never triggers it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Profiles")
            }

            // Welcome tour replay — surfaces only after the tour has been
            // dismissed at least once. On a fresh install the user is
            // already inside the tour, so showing the button there would
            // be confusingly redundant.
            if preferences.onboardingShown {
                Section {
                    Button("Replay welcome tour") {
                        preferences.onboardingShown = false
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: Display

    @ViewBuilder
    private func displayTab(prefs: Bindable<Preferences>) -> some View {
        Form {
            Section {
                Toggle("Simple mode", isOn: prefs.simpleMode)
                Text("Hides the refresh-rate chips; a click applies the highest rate available for that size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Confirm resolution changes", isOn: prefs.confirmDisplayChanges)
                Text("Applies for this session only and undoes it after \(DisplayStore.confirmationWindowSeconds) seconds unless you confirm. The undo runs on its own, so it works even when the screen is unreadable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Resolutions")
            }

            Section {
                Toggle("Live preview on hover", isOn: Binding(
                    get: { preferences.livePreviewEnabled },
                    set: { newValue in
                        preferences.livePreviewEnabled = newValue
                        // Turning the feature back on is the user's signal to try
                        // again. Without this, a permission granted in System
                        // Settings after one denial stayed unnoticed until the
                        // app was relaunched.
                        if newValue { DesktopCapture.resetPermissionCache() }
                    }
                ))
                Text("Shows a screenshot of your desktop scaled into the proposed mode. Asks for Screen Recording the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: Updates

    @ViewBuilder
    private var updatesTab: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current version")
                            .font(.callout)
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(.secondary)
                            .font(.callout.monospacedDigit())
                    }
                    Spacer()
                }

                if let reason = updater?.unavailableReason {
                    // Say why rather than showing a dead toggle. Covers debug
                    // builds and Homebrew installs, where brew owns updates.
                    Text(reason)
                        .font(Design.Typography.footer)
                        .foregroundStyle(.secondary)
                } else if let updater {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    Text("Downloads updates in the background and offers to restart when one is ready. VibeRes never restarts on its own.")
                        .font(Design.Typography.footer)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("Check for Updates…") { updater.checkForUpdates() }
                    }
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }
}
