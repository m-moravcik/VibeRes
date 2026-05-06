import SwiftUI

/// Compact profiles strip shown above the displays list. Each saved profile is one
/// pill button; tap to apply, long-press for actions. "+" pill captures the current
/// state as a new profile.
struct ProfilesSection: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(DisplayStore.self) private var displays
    @State private var isPromptingName = false
    @State private var newName = ""
    @State private var lastFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PROFILES")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, Design.Spacing.l)

            if profiles.profiles.isEmpty {
                HStack {
                    Text("No profiles yet")
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
                                if !failures.isEmpty {
                                    lastFailure = failures.joined(separator: ", ")
                                }
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
        .alert("New profile", isPresented: $isPromptingName) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {
                newName = ""
            }
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    profiles.captureCurrent(name: trimmed, displays: displays.displays)
                }
                newName = ""
            }
        } message: {
            Text("Saves the current resolution of every connected display as a named preset.")
        }
    }

    private var saveButton: some View {
        Button {
            isPromptingName = true
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
        .help("Save current state as a profile")
    }
}

private struct ProfilePill: View {
    let profile: Profile
    let onApply: () -> Void
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
        .help("Apply \(profile.name) (\(profile.entries.count) display\(profile.entries.count == 1 ? "" : "s"))")
        .contextMenu {
            Button("Apply", action: onApply)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
