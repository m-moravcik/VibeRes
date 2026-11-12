import SwiftUI

/// Three-step welcome tour shown the first time the menu-bar popover opens
/// after a fresh install. Lives inside the popover (not a separate window)
/// because the popover is the user's first surface — pulling them out of it
/// for an onboarding window breaks the "menu bar app" mental model. After
/// the user dismisses (Done or Skip) we set Preferences.onboardingShown so
/// the tour does not re-appear; it can be replayed from Settings → General.
struct OnboardingView: View {
    @Environment(Preferences.self) private var preferences
    @State private var step: Int

    private static let totalSteps = 3

    /// `step` lets the screenshot harness open the tour past its first card.
    init(step: Int = 0) {
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with skip and step counter — keep it tiny so the body
            // copy gets the visual weight.
            HStack {
                Button(String(localized: "Skip")) {
                    finish()
                }
                .buttonStyle(.plain)
                .font(Design.Typography.footer)
                .foregroundStyle(.secondary)

                Spacer()

                Text(String(format: String(localized: "onboarding.step"),
                            step + 1, Self.totalSteps))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Step content — animated cross-fade between steps. We swap the
            // identity via .id(step) so SwiftUI runs the transition cleanly.
            Group {
                switch step {
                case 0: stepWelcome
                case 1: stepProfiles
                default: stepSimple
                }
            }
            .id(step)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Step indicator dots — minimal, no buttons, just orientation.
            HStack(spacing: 6) {
                ForEach(0..<Self.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 8)

            // Footer buttons — Back disabled on first step, Next/Done flips
            // on the last. Keep it native macOS rounded buttons.
            HStack {
                Button(String(localized: "Back")) {
                    withAnimation(.easeInOut(duration: 0.18)) { step = max(0, step - 1) }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(step == 0)

                Spacer()

                Button(step == Self.totalSteps - 1
                       ? String(localized: "Done")
                       : String(localized: "Next")) {
                    if step == Self.totalSteps - 1 {
                        finish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { step += 1 }
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: Design.Layout.popoverWidth)
        .background(.ultraThinMaterial)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepWelcome: some View {
        // The welcome step introduces the app, so it shows the app's icon.
        StepCard(
            symbol: nil,
            title: String(localized: "onboarding.welcome.title"),
            bodyText: String(localized: "onboarding.welcome.body")
        )
    }

    /// Explains profiles and offers to save the current displays as the first
    /// one right here, so the tour ends with something the user made rather
    /// than three cards they read.
    @ViewBuilder
    private var stepProfiles: some View {
        VStack(spacing: 12) {
            StepCard(
                symbol: "rectangle.stack.fill",
                title: String(localized: "onboarding.profiles.title"),
                bodyText: String(localized: "onboarding.profiles.body")
            )
            FirstProfileSaver()
        }
    }

    @ViewBuilder
    private var stepSimple: some View {
        StepCard(
            symbol: "slider.horizontal.3",
            title: String(localized: "onboarding.simple.title"),
            bodyText: String(localized: "onboarding.simple.body")
        )
    }

    private func finish() {
        preferences.onboardingShown = true
    }
}

/// Name field and Save button for the tour's profile step. Saves every
/// connected display as it is now, with no form: anything finer (leaving a
/// display out, "any external", which one is main) belongs to the full Save
/// form in the popover, which the user meets next.
///
/// Saving is explicit. Next moves on without saving, because a profile the
/// user did not ask for would be a pill they have to work out how to delete.
private struct FirstProfileSaver: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(DisplayStore.self) private var displays

    @State private var name = ""
    /// The name the profile was saved under, once it was.
    @State private var savedName: String?
    @State private var problem: String?

    var body: some View {
        Group {
            if let savedName {
                Label(
                    String(format: String(localized: "onboarding.save.done"), savedName),
                    systemImage: "checkmark.circle.fill"
                )
                .font(Design.Typography.note)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            } else if !displays.displays.isEmpty {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        TextField(String(localized: "onboarding.save.field"), text: $name)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit(save)
                            .onChange(of: name) { problem = nil }
                        Button(String(localized: "onboarding.save.button"), action: save)
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .disabled(trimmedName.isEmpty)
                    }
                    if let problem {
                        Text(problem)
                            .font(Design.Typography.note)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: savedName)
        .onAppear {
            // Replaying the tour must not offer a name that is already taken.
            if name.isEmpty { name = suggestedName }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var suggestedName: String {
        Profile.suggestedName(
            displayNames: displays.displays.map(\.name),
            existingNames: Set(profiles.profiles.map(\.name))
        )
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        switch profiles.captureWholeSetup(name: trimmedName, displays: displays.displays) {
        case .saved, .savedWithMissingDisplays:
            savedName = trimmedName
            problem = nil
        case .rejectedDuplicateName:
            problem = String(localized: "onboarding.save.duplicate")
        case .rejectedEmpty, .rejectedEmptyName, .rejectedNotFound, .rejectedMultipleAnyExternal:
            problem = String(localized: "onboarding.save.failed")
        }
    }
}

private struct StepCard: View {
    /// Nil shows the app's own icon.
    let symbol: String?
    let title: String
    let bodyText: String

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.tint)
                } else {
                    // As Finder and the Dock draw it, glass included on macOS
                    // 26. The icon art carries its own margin, so it is drawn
                    // larger than the symbols to look the same size. The fixed
                    // frame keeps every step the same height, as in Eject Guard.
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                }
            }
            .frame(height: 56)
            .accessibilityHidden(true)
            .padding(.top, 4)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(bodyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
