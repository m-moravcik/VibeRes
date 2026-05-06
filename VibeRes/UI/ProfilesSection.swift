import SwiftUI

/// Compact profiles strip shown above the displays list. Each saved profile is one
/// pill button; tap to apply, right-click for actions. "+" pill expands an inline
/// save form letting users include/exclude displays and mark externals as flexible.
struct ProfilesSection: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(DisplayStore.self) private var displays
    @State private var mode: Mode = .idle
    @FocusState private var nameFieldFocused: Bool

    /// What the section is currently showing.
    enum Mode: Equatable {
        case idle
        case saving(SaveFormState)
        case renaming(profileID: UUID, newName: String)
    }

    /// State of the inline "Save profile" form.
    struct SaveFormState: Equatable {
        var name: String = ""
        /// Per-display: include? + how to bind (specific vs anyExternal)
        var perDisplay: [DisplayChoice] = []
    }

    struct DisplayChoice: Equatable, Identifiable {
        let displayID: CGDirectDisplayID
        let displayName: String
        let isBuiltIn: Bool
        let currentModeDescription: String
        var isIncluded: Bool
        var matchAnyExternal: Bool   // only meaningful for non-built-in
        var id: CGDirectDisplayID { displayID }
    }

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

            switch mode {
            case .idle:
                idlePillBar
            case .saving:
                saveForm
            case .renaming:
                renameForm
            }
        }
        .padding(.bottom, Design.Spacing.s)
    }

    // MARK: - Idle pills

    @ViewBuilder
    private var idlePillBar: some View {
        if profiles.profiles.isEmpty {
            HStack {
                Text("Save a multi-display preset")
                    .font(Design.Typography.footer)
                    .foregroundStyle(.secondary)
                Spacer()
                saveButton
            }
            .padding(.horizontal, Design.Spacing.l)
        } else {
            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(profiles.profiles) { profile in
                    ProfilePill(profile: profile) {
                        let failures = profiles.apply(profile, displays: displays.displays)
                        if !failures.isEmpty {
                            // Surface the first failure as a transient note.
                            // (Multiple failures get joined.)
                            print("apply: \(failures.joined(separator: ", "))")
                        }
                    } onRename: {
                        mode = .renaming(profileID: profile.id, newName: profile.name)
                    } onDelete: {
                        profiles.delete(profile)
                    }
                }
                saveButton
            }
            .padding(.horizontal, Design.Spacing.l)
        }
    }

    private var saveButton: some View {
        Button {
            mode = .saving(buildInitialFormState())
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
        .help("Save displays into a profile")
    }

    private var infoTooltip: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .help("A profile snapshots the resolution & refresh rate of each chosen display. Tap a profile to apply it. Externals can be saved as 'specific monitor' (locked to this exact display) or 'any external' (works with any monitor — handy for presentation mode).")
    }

    private func buildInitialFormState() -> SaveFormState {
        var state = SaveFormState()
        state.name = suggestedName
        state.perDisplay = displays.displays.map { d in
            DisplayChoice(
                displayID: d.id,
                displayName: d.name,
                isBuiltIn: d.isMain || CGDisplayIsBuiltin(d.id) != 0,
                currentModeDescription: d.currentMode.map(currentModeDescription) ?? "",
                isIncluded: true,
                matchAnyExternal: false
            )
        }
        return state
    }

    private var suggestedName: String {
        let n = displays.displays.count
        return n == 1 ? "Single Display" : "Setup \(profiles.profiles.count + 1)"
    }

    private func currentModeDescription(_ m: CGDisplayMode) -> String {
        var parts = ["\(m.width)×\(m.height)"]
        if let hz = m.refreshHz { parts.append("\(hz)Hz") }
        if m.isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Save form

    @ViewBuilder
    private var saveForm: some View {
        if case .saving(let state) = mode {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Profile name", text: bindingForName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .focused($nameFieldFocused)
                        .onSubmit(commitSave)
                }

                Text("INCLUDE")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)

                ForEach(state.perDisplay) { choice in
                    displayChoiceRow(choice)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { mode = .idle }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { commitSave() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canSave)
                }
            }
            .padding(.horizontal, Design.Spacing.l)
            .onAppear { nameFieldFocused = true }
        }
    }

    @ViewBuilder
    private func displayChoiceRow(_ choice: DisplayChoice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: bindingForInclude(choice.displayID)) {
                Image(systemName: choice.isBuiltIn ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(choice.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(choice.currentModeDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                // Only externals can be flexible. Built-in is always specific.
                if !choice.isBuiltIn && choice.isIncluded {
                    Toggle(isOn: bindingForAnyExternal(choice.displayID)) {
                        Text("Match any external monitor")
                            .font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Rename form

    @ViewBuilder
    private var renameForm: some View {
        if case .renaming(let id, _) = mode {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rename profile")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("Profile name", text: bindingForRenameText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .focused($nameFieldFocused)
                        .onSubmit { commitRename(id: id) }
                    Button("Rename") { commitRename(id: id) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(currentRenameText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { mode = .idle }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, Design.Spacing.l)
            .onAppear { nameFieldFocused = true }
        }
    }

    private var currentRenameText: String {
        if case .renaming(_, let n) = mode { return n }
        return ""
    }

    // MARK: - Bindings

    private var bindingForName: Binding<String> {
        Binding(
            get: {
                if case .saving(let s) = mode { return s.name }
                return ""
            },
            set: { newValue in
                if case .saving(var s) = mode {
                    s.name = newValue
                    mode = .saving(s)
                }
            }
        )
    }

    private func bindingForInclude(_ id: CGDirectDisplayID) -> Binding<Bool> {
        Binding(
            get: {
                if case .saving(let s) = mode {
                    return s.perDisplay.first(where: { $0.id == id })?.isIncluded ?? false
                }
                return false
            },
            set: { newValue in
                if case .saving(var s) = mode,
                   let i = s.perDisplay.firstIndex(where: { $0.id == id }) {
                    s.perDisplay[i].isIncluded = newValue
                    mode = .saving(s)
                }
            }
        )
    }

    private func bindingForAnyExternal(_ id: CGDirectDisplayID) -> Binding<Bool> {
        Binding(
            get: {
                if case .saving(let s) = mode {
                    return s.perDisplay.first(where: { $0.id == id })?.matchAnyExternal ?? false
                }
                return false
            },
            set: { newValue in
                if case .saving(var s) = mode,
                   let i = s.perDisplay.firstIndex(where: { $0.id == id }) {
                    s.perDisplay[i].matchAnyExternal = newValue
                    mode = .saving(s)
                }
            }
        )
    }

    private var bindingForRenameText: Binding<String> {
        Binding(
            get: { currentRenameText },
            set: { newValue in
                if case .renaming(let id, _) = mode {
                    mode = .renaming(profileID: id, newName: newValue)
                }
            }
        )
    }

    // MARK: - Commit

    private var canSave: Bool {
        if case .saving(let s) = mode {
            let nameOK = !s.name.trimmingCharacters(in: .whitespaces).isEmpty
            let anyIncluded = s.perDisplay.contains(where: \.isIncluded)
            return nameOK && anyIncluded
        }
        return false
    }

    private func commitSave() {
        guard case .saving(let s) = mode else { return }
        let trimmed = s.name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var selection: [CGDirectDisplayID: ProfileMatchKind] = [:]
        for c in s.perDisplay where c.isIncluded {
            selection[c.displayID] = c.matchAnyExternal ? .anyExternal : .specific
        }
        guard !selection.isEmpty else { return }

        profiles.captureCurrent(name: trimmed, displays: displays.displays, selection: selection)
        mode = .idle
    }

    private func commitRename(id: UUID) {
        guard case .renaming(_, let n) = mode else { return }
        let trimmed = n.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              var profile = profiles.profiles.first(where: { $0.id == id }) else {
            mode = .idle
            return
        }
        profile.name = trimmed
        profiles.update(profile)
        mode = .idle
    }
}

// MARK: - ProfilePill

private struct ProfilePill: View {
    let profile: Profile
    let onApply: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9))
                Text(profile.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if isFlexible {
                    // Subtle "✱" mark to hint that this profile travels.
                    Text("✱")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tint)
                }
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
        .help(tooltip)
        .contextMenu {
            Button("Apply", action: onApply)
            Button("Rename…", action: onRename)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    /// True if the profile contains an "any external" matcher — these
    /// profiles travel and deserve a small badge to communicate that.
    private var isFlexible: Bool {
        profile.entries.contains { entry in
            if case .anyExternal = entry.matcher { return true }
            return false
        }
    }

    private var iconName: String {
        // Built-in only: laptop icon. Otherwise: stack of rectangles.
        let allBuiltIn = profile.entries.allSatisfy { entry in
            if case .builtIn = entry.matcher { return true }
            return false
        }
        return allBuiltIn ? "laptopcomputer" : "rectangle.stack.fill"
    }

    private var tooltip: String {
        "Apply '\(profile.name)' (\(profile.humanSummary))"
    }
}
