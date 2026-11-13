import SwiftUI

/// Settings → Shortcuts: every global shortcut in one place, Revert and one
/// per profile. The popover's Edit form sets a profile's too; this window is
/// the roomier place to record them, and the only one for Revert.
///
/// Its own view rather than a function of `SettingsView` so the screenshot
/// harness can render it without the window's tab bar.
struct ShortcutsSettingsTab: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ProfileStore.self) private var profiles
    @Environment(HotkeyCenter.self) private var hotkeys
    /// Why the suggested Revert shortcut was refused, after a click on it.
    @State private var suggestionProblem: HotkeyProblem?

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section {
                LabeledContent("Revert last change") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if preferences.revertHotkey == nil {
                            Button("Use \(Text(verbatim: KeyCombo.suggestedRevert.localizedDisplayString()))") {
                                useSuggestedRevertShortcut()
                            }
                            .help("Sets the suggested shortcut. Nothing is set until you choose one.")
                        }
                        ShortcutRecorder(
                            owner: .revert,
                            combo: $prefs.revertHotkey,
                            savedCombo: preferences.revertHotkey
                        )
                    }
                }
                if let suggestionProblem {
                    Text(suggestionProblem.message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Undoes the last resolution change from any app, like Revert in the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Revert")
            }

            Section {
                if let problem = profiles.lastError {
                    Text(problem.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if profiles.profiles.isEmpty {
                    Text("Save a profile in the menu first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles.profiles) { profile in
                        LabeledContent {
                            ShortcutRecorder(
                                owner: .profile(profile.id),
                                combo: Binding(
                                    get: { profile.hotkey },
                                    set: { profiles.setHotkey($0, for: profile.id) }
                                ),
                                savedCombo: profile.hotkey
                            )
                        } label: {
                            Text(verbatim: profile.name)
                                .lineLimit(1)
                        }
                    }
                }
                Text("Applies the profile from any app. Displays it does not include are left as they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Profiles")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: preferences.revertHotkey) { suggestionProblem = nil }
    }

    /// Takes the suggested combination for Revert, unless something already
    /// holds it. Checked on the click rather than up front: the check asks
    /// macOS to register the combination, which a view body must not do.
    private func useSuggestedRevertShortcut() {
        if let problem = hotkeys.problem(with: .suggestedRevert, for: .revert) {
            suggestionProblem = problem
        } else {
            preferences.revertHotkey = .suggestedRevert
        }
    }
}
