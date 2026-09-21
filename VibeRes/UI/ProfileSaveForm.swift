import SwiftUI

/// The inline "Save profile" form: a per-display checklist plus a name and a
/// main-display pick.
///
/// Owns one `Binding` to its whole state rather than the five hand-rolled
/// bindings that used to pattern-match on the section's `Mode` enum — each of
/// which had to re-find the display it was editing on every keystroke.
struct ProfileSaveForm: View {
    @Binding var state: ProfilesSection.SaveFormState
    let save: () -> Void
    let cancel: () -> Void

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Profile name", text: $state.name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($nameFieldFocused)
                    .onSubmit(save)
            }

            Text("INCLUDE")
                .font(Design.Typography.sectionHeader)
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            ForEach($state.perDisplay) { $choice in
                row(for: $choice)
            }

            Text("MAIN DISPLAY")
                .font(Design.Typography.sectionHeader)
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            Picker(selection: $state.mainDisplayID) {
                Text("Don't change").tag(CGDirectDisplayID?.none)
                ForEach(state.perDisplay.filter(\.isIncluded)) { choice in
                    Text(choice.displayName).tag(CGDirectDisplayID?.some(choice.displayID))
                }
            } label: { EmptyView() }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Main display")
            .help("Which display hosts the menu bar after this profile is applied. 'Don't change' leaves the arrangement alone.")

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!state.isSavable)
            }
        }
        .padding(.horizontal, Design.Spacing.l)
        .onAppear { nameFieldFocused = true }
    }

    @ViewBuilder
    private func row(for choice: Binding<ProfilesSection.DisplayChoice>) -> some View {
        let value = choice.wrappedValue
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: includeBinding(choice)) {
                Image(systemName: value.isBuiltIn ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Include \(value.displayName)")

            VStack(alignment: .leading, spacing: 2) {
                Text(value.displayName)
                    .font(Design.Typography.control)
                    .lineLimit(1)
                Text(value.currentModeDescription)
                    .font(Design.Typography.note)
                    .foregroundStyle(.secondary)

                // Only externals can be flexible. Built-in is always specific:
                // there is exactly one of it, so the distinction is meaningless.
                if !value.isBuiltIn, value.isIncluded {
                    let blocked = ProfilesSection.SaveFormState.anyExternalTakenByAnother(
                        than: value.displayID,
                        in: state.perDisplay
                    )
                    Toggle(isOn: choice.matchAnyExternal) {
                        Text("Match any external monitor")
                            .font(Design.Typography.note)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                    .disabled(blocked)
                    .help(blocked
                          ? "Only one display per profile can match 'any external monitor'. Uncheck the other first."
                          : "")
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    /// Un-including the display that was picked as main leaves the picker
    /// pointing at nothing, so the pick is reset with it.
    private func includeBinding(_ choice: Binding<ProfilesSection.DisplayChoice>) -> Binding<Bool> {
        Binding(
            get: { choice.wrappedValue.isIncluded },
            set: { newValue in
                choice.wrappedValue.isIncluded = newValue
                if !newValue, state.mainDisplayID == choice.wrappedValue.displayID {
                    state.mainDisplayID = nil
                }
            }
        )
    }
}

extension ProfilesSection.SaveFormState {
    /// Whether Save should be available. Pure, so it is covered by tests
    /// rather than by looking at the button.
    var isSavable: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && perDisplay.contains(where: \.isIncluded)
    }

    /// True when an included display *other than* this one is already set to
    /// match any external. Disabling the second checkbox keeps the user out of
    /// a state the store would reject at save time.
    static func anyExternalTakenByAnother(
        than displayID: CGDirectDisplayID,
        in choices: [ProfilesSection.DisplayChoice]
    ) -> Bool {
        choices.contains { $0.displayID != displayID && $0.isIncluded && $0.matchAnyExternal }
    }
}
