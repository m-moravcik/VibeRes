import SwiftUI

/// Standalone macOS Settings window. Opens via the menu bar's Settings…
/// row and via the standard ⌘, shortcut. Lives in its own scene rather
/// than as inline footer toggles so the popover stays focused on the
/// primary action (switching resolutions) and the preferences surface
/// has room to grow without bloating the main menu.
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(UpdateChecker.self) private var updateChecker
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
        .frame(width: 460, height: 320)
        .task {
            launchAtLogin = LoginItem.isEnabled
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
                        if LoginItem.setEnabled(newValue) {
                            // SMAppService applies async — give it a runloop
                            // tick before reading the canonical state back.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(150))
                                launchAtLogin = LoginItem.isEnabled
                            }
                        }
                    }
                ))
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("Auto-apply matching profile", isOn: prefs.autoApplyOnDisplayChange)
                Text("When you plug or unplug a monitor, VibeRes finds the saved profile that best fits the new layout and applies it silently. Mode-only changes don't trigger this.")
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
                Text("Hide the per-row refresh-rate chips. Clicking a resolution applies it at the highest available refresh rate for your display. Turn off if you want to pick refresh rates manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Resolutions")
            }

            Section {
                Toggle("Live preview on hover", isOn: prefs.livePreviewEnabled)
                Text("Hovering a resolution row shows a real screenshot of your desktop scaled into the proposed mode. Requires Screen Recording permission, which is requested the first time you hover with this turned on.")
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
                        Text(UpdateChecker.currentVersion)
                            .foregroundStyle(.secondary)
                            .font(.callout.monospacedDigit())
                    }
                    Spacer()
                }

                if let latest = updateChecker.latestVersion {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(updateChecker.isUpdateAvailable ? "Update available" : "Latest on GitHub")
                                .font(.callout)
                            Text(latest)
                                .foregroundStyle(.secondary)
                                .font(.callout.monospacedDigit())
                        }
                        Spacer()
                        if updateChecker.isUpdateAvailable, let url = updateChecker.releaseURL {
                            Button("Open release") { NSWorkspace.shared.open(url) }
                        }
                    }
                }

                if let last = updateChecker.lastCheckedAt {
                    HStack {
                        Text("Last checked")
                            .font(.callout)
                        Spacer()
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
            } header: {
                Text("Status")
            }

            Section {
                HStack {
                    Button {
                        Task { await updateChecker.checkNow() }
                    } label: {
                        if updateChecker.isChecking {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Check now")
                        }
                    }
                    .disabled(updateChecker.isChecking)
                    Spacer()
                }
                Text("VibeRes also checks once a day in the background. Brew users can run `brew upgrade --cask m-moravcik/viberes/viberes-app` to install the new build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
