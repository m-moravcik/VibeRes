import AppKit
import SwiftUI

/// Standalone macOS Settings window. Opens via the menu bar's Settings…
/// row and via the standard ⌘, shortcut. Lives in its own scene rather
/// than as inline footer toggles so the popover stays focused on the
/// primary action (switching resolutions) and the preferences surface
/// has room to grow without bloating the main menu.
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.updater) private var updater
    @Environment(DisplayStore.self) private var displays
    @Environment(ProfileStore.self) private var profiles
    /// True for a moment after "Copy diagnostics", so the button can say it worked
    /// in place instead of raising an alert.
    @State private var diagnosticsCopied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Report a problem had to put the diagnostics on the clipboard, because
    /// they did not fit the link; says so until the next report.
    @State private var reportOnClipboard = false
    @State private var loginStatus: LoginItem.Status = LoginItem.status
    @State private var loginChangeFailed = false
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
        case general, display, shortcuts, updates, debug
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

            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                .tag(SettingsTab.updates)

            debugTab(prefs: $prefs)
                .tabItem { Label("Debug", systemImage: "ladybug") }
                .tag(SettingsTab.debug)
        }
        // Sized so no tab scrolls. A little empty space beats a scroll bar in a
        // settings window with four tabs — the previous 320pt height cut off
        // the General tab once the confirmation setting was added. 490pt fits
        // the Debug tab with both Report a problem captions in French, its
        // longest language.
        .frame(width: 470, height: 490)
        .task {
            // What macOS says now. A registration that went missing shows as
            // off with a note, not as the intent's "on".
            loginStatus = LoginItem.status
            loginChangeFailed = false
            // Reset on every appear — covers re-opens after close.
            selectedTab = .general
        }
        // Back from System Settings, where the user may have switched VibeRes
        // on or off under Login Items.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginStatus = LoginItem.status
        }
    }

    // MARK: General

    @ViewBuilder
    private func loginItemNote(_ note: LoginItem.Note) -> some View {
        switch note {
        case .needsApproval:
            HStack(alignment: .firstTextBaseline) {
                Text("VibeRes is switched off in System Settings, so it does not open at login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Open System Settings…") { LoginItem.openSystemSettings() }
                    .controlSize(.small)
            }
        case .couldNotChange:
            Text("Launch at login could not be changed. Try again.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func generalTab(prefs: Bindable<Preferences>) -> some View {
        Form {
            Section {
                // Shows what macOS reports, not what was asked for: a toggle
                // that stayed on over a failed registration said VibeRes
                // would open at login when it would not.
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.toggleIsOn(loginStatus) },
                    set: { newValue in
                        // Record the intent before touching the service. It is
                        // what the user asked for and has to outlive a failed
                        // registration, so the next launch can retry instead of
                        // quietly leaving the setting off.
                        preferences.launchAtLoginIntent = newValue
                        loginChangeFailed = !LoginItem.setEnabled(newValue)
                        loginStatus = LoginItem.status
                        // Read again a runloop tick later, in case macOS
                        // settles the registration after the call returns.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(150))
                            loginStatus = LoginItem.status
                        }
                    }
                ))
                if let note = LoginItem.note(status: loginStatus,
                                             storedIntent: preferences.launchAtLoginIntent,
                                             lastChangeFailed: loginChangeFailed) {
                    loginItemNote(note)
                }
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

    // MARK: Debug

    @ViewBuilder
    private func debugTab(prefs: Bindable<Preferences>) -> some View {
        Form {
            Section {
                Toggle("Write debug log to file", isOn: prefs.debugLogEnabled)
                Text("Off by default. Logs display changes and their results to ~/Library/Logs/VibeRes, up to about 1 MB. Nothing is sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Detail level", selection: prefs.debugLogLevel) {
                    Text("Errors only").tag(LogLevel.error)
                    Text("Standard").tag(LogLevel.info)
                    Text("Everything").tag(LogLevel.debug)
                }
                .disabled(!preferences.debugLogEnabled)

                HStack {
                    Spacer()
                    Button("Open log file") {
                        NSWorkspace.shared.open(LogSink.shared.existingFileURL())
                    }
                    .disabled(!preferences.debugLogEnabled)
                }
            } header: {
                Text("Debug log")
            }

            Section {
                Text("Copies versions, Mac model, these settings, displays and the latest log lines for a bug report. No serial numbers or file paths.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Report a problem opens a new issue on GitHub with these diagnostics filled in. They reach GitHub in the link, but nothing is posted until you submit the issue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if reportOnClipboard {
                    Text("The diagnostics were too long for the link and are on the clipboard. Paste them into the issue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Report a problem…", action: reportProblem)
                    Button {
                        copyDiagnostics()
                    } label: {
                        // One label whose symbol and words swap in place. Both
                        // labels sit hidden underneath, so the button keeps the
                        // wider one's width and the row stays still.
                        ZStack {
                            Label("Copy diagnostics", systemImage: "doc.on.doc").hidden()
                            Label("Copied", systemImage: "checkmark").hidden()
                            Label(diagnosticsCopied ? LocalizedStringKey("Copied") : "Copy diagnostics",
                                  systemImage: diagnosticsCopied ? "checkmark" : "doc.on.doc")
                                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                                .animation(Design.Motion.quick, value: diagnosticsCopied)
                        }
                    }
                }
            } header: {
                Text("Diagnostics")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func collectDiagnostics() -> Diagnostics.Report {
        Diagnostics.collect(
            preferences: preferences,
            displays: displays.displays,
            profileCount: profiles.profiles.count
        )
    }

    /// Opens the bug report form in the browser with the diagnostics in it.
    /// If they are too long for a link even without log lines, the form opens
    /// empty and the full report goes on the clipboard instead.
    private func reportProblem() {
        let report = collectDiagnostics()
        let link = BugReport.link(for: report)
        if !link.carriesDiagnostics {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report.render(), forType: .string)
        }
        reportOnClipboard = !link.carriesDiagnostics
        NSWorkspace.shared.open(link.url)
    }

    private func copyDiagnostics() {
        let report = collectDiagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.render(), forType: .string)
        diagnosticsCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            diagnosticsCopied = false
        }
    }
}
