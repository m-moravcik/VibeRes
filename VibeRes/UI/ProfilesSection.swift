import SwiftUI

/// Compact profiles strip shown above the displays list. Each saved profile is one
/// pill button; tap to apply, long-press for actions. "+" pill captures the current
/// state as a new profile.
struct ProfilesSection: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(DisplayStore.self) private var displays
    @State private var isNaming = false
    @State private var newName = ""
    @State private var renamingProfile: Profile?
    @State private var lastFailure: String?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("PROFILES")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                infoTooltip
                Spacer()
            }
            .padding(.horizontal, Design.Spacing.l)

            if isNaming {
                inlineNamePrompt
            } else if profiles.profiles.isEmpty {
                HStack {
                    Text("Save a multi-display preset")
                        .font(Design.Typography.footer)
                        .foregroundStyle(.secondary)
                    Spacer()
                    saveButton
                }
                .padding(.horizontal, Design.Spacing.l)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(profiles.profiles) { profile in
                            ProfilePill(profile: profile) {
                                let failures = profiles.apply(profile, displays: displays.displays)
                                lastFailure = failures.isEmpty ? nil : failures.joined(separator: ", ")
                            } onRename: {
                                renamingProfile = profile
                                newName = profile.name
                                isNaming = true
                            } onDelete: {
                                profiles.delete(profile)
                            }
                        }
                        saveButton
                    }
                    .padding(.horizontal, Design.Spacing.l)
                }
            }

            if let lastFailure {
                Text(lastFailure)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, Design.Spacing.l)
                    .lineLimit(2)
            }
        }
        .padding(.bottom, Design.Spacing.s)
    }

    /// Inline prompt — replaces .alert which is unreliable inside MenuBarExtra
    /// because clicking outside the popover dismisses both the menu bar window
    /// and any anchored alert. Used for both Save (new profile) and Rename.
    private var inlineNamePrompt: some View {
        VStack(alignment: .leading, spacing: 4) {
            if renamingProfile != nil {
                Text("Rename profile")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField("Profile name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($nameFieldFocused)
                    .onSubmit(commit)

                Button(renamingProfile == nil ? "Save" : "Rename") { commit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Cancel") { cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, Design.Spacing.l)
        .onAppear { nameFieldFocused = true }
    }

    private func commit() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if var profile = renamingProfile {
            profile.name = trimmed
            profiles.update(profile)
        } else {
            profiles.captureCurrent(name: trimmed, displays: displays.displays)
        }
        cancel()
    }

    private func cancel() {
        newName = ""
        isNaming = false
        renamingProfile = nil
    }

    private var saveButton: some View {
        Button {
            newName = suggestedName
            isNaming = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Save")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
        }
        .buttonStyle(.plain)
        .help("Save the current state of every connected display as a named profile")
    }

    /// Suggests a name based on the connected display count so the user has something
    /// to start typing over instead of staring at an empty field.
    private var suggestedName: String {
        let n = displays.displays.count
        return n == 1 ? "Single Display" : "Setup \(profiles.profiles.count + 1)"
    }

    private var infoTooltip: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .help("A profile remembers the resolution & refresh rate of every connected display. Tap a profile to apply it across all of them at once. Profiles match displays by EDID, so they survive reboots and USB-C reconnects.")
    }
}

private struct ProfilePill: View {
    let profile: Profile
    let onApply: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 9))
                Text(profile.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Apply \(profile.name) (\(profile.entries.count) display\(profile.entries.count == 1 ? "" : "s")). Right-click for more.")
        .contextMenu {
            Button("Apply", action: onApply)
            Button("Rename…", action: onRename)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
