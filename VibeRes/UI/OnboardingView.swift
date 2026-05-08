import SwiftUI

/// Three-step welcome tour shown the first time the menu-bar popover opens
/// after a fresh install. Lives inside the popover (not a separate window)
/// because the popover is the user's first surface — pulling them out of it
/// for an onboarding window breaks the "menu bar app" mental model. After
/// the user dismisses (Done or Skip) we set Preferences.onboardingShown so
/// the tour does not re-appear; it can be replayed from Settings → General.
struct OnboardingView: View {
    @Environment(Preferences.self) private var preferences
    @State private var step: Int = 0

    private static let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with skip and step counter — keep it tiny so the body
            // copy gets the visual weight.
            HStack {
                Button(String(localized: "Skip")) {
                    finish()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Spacer()

                Text(String(format: String(localized: "onboarding.step"),
                            step + 1, Self.totalSteps))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
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
        StepCard(
            symbol: "sparkles.tv",
            title: String(localized: "onboarding.welcome.title"),
            bodyText: String(localized: "onboarding.welcome.body")
        )
    }

    @ViewBuilder
    private var stepProfiles: some View {
        StepCard(
            symbol: "rectangle.stack.fill",
            title: String(localized: "onboarding.profiles.title"),
            bodyText: String(localized: "onboarding.profiles.body")
        )
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

private struct StepCard: View {
    let symbol: String
    let title: String
    let bodyText: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.tint)
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
