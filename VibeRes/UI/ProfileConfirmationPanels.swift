import SwiftUI

/// Shown before a profile whose displays do not exactly match what is
/// connected is applied, so the user sees what will be skipped and what will
/// be left alone before anything moves.
///
/// Inline rather than an `NSAlert`: an alert takes key focus, and the popover
/// dismisses itself when it loses key — the question would take its own
/// context off screen.
///
/// Takes values and two closures rather than the section's `Mode`, so it can
/// be read, and moved, without the state machine that drives it.
struct ProfileApplyConfirmation: View {
    let profileName: String
    let preview: ProfileApplyPreview
    let classification: DisplaySetClassifier.Classification
    let apply: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: Self.warningIcon(for: classification))
                    .foregroundStyle(Self.warningTint(for: classification))
                    .accessibilityHidden(true)
                Text("Apply '\(profileName)'?")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(Self.headline(for: classification))
                .font(Design.Typography.footer)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(preview.rows) { row in
                    PreviewRow(row: row)
                }
                if !preview.untouched.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.dotted")
                            .font(Design.Typography.note)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text("Untouched: " + preview.untouched.joined(separator: ", "))
                            .font(Design.Typography.note)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button(Self.applyButtonLabel(for: classification), action: apply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(Self.isDisjoint(classification))
            }
        }
        .padding(Design.Spacing.l)
    }

    // MARK: Copy and styling for a classification

    static func warningIcon(for c: DisplaySetClassifier.Classification) -> String {
        switch c {
        case .exactMatch: return "checkmark.seal.fill"
        case .partialMatch, .partialWithExtras: return "exclamationmark.triangle.fill"
        case .supersetMatch: return "info.circle.fill"
        case .disjoint: return "xmark.octagon.fill"
        }
    }

    static func warningTint(for c: DisplaySetClassifier.Classification) -> Color {
        switch c {
        case .exactMatch: return .green
        case .partialMatch, .partialWithExtras: return .orange
        case .supersetMatch: return .accentColor
        case .disjoint: return .red
        }
    }

    static func headline(for c: DisplaySetClassifier.Classification) -> String {
        switch c {
        case .exactMatch:
            return "Display setup matches the profile."
        case .partialMatch(let missing):
            let names = missing.map(\.displayName).joined(separator: ", ")
            return "\(missing.count) of the profile's displays is not connected (\(names)). Other entries will apply as saved."
        case .supersetMatch(let extra):
            let names = extra.map(\.name).joined(separator: ", ")
            return "You have \(extra.count) extra monitor(s) connected (\(names)). They will be left untouched."
        case .partialWithExtras(let missing, let extra):
            return "\(missing.count) saved display(s) missing, \(extra.count) extra connected. Only matched entries will apply."
        case .disjoint:
            return "None of this profile's monitors are connected. There's nothing to apply."
        }
    }

    static func applyButtonLabel(for c: DisplaySetClassifier.Classification) -> String {
        if case .exactMatch = c { return "Apply" }
        if case .disjoint = c { return "Apply" }
        return "Apply anyway"
    }

    /// Nothing the profile names is connected, so there is nothing to apply.
    static func isDisjoint(_ c: DisplaySetClassifier.Classification) -> Bool {
        if case .disjoint = c { return true }
        return false
    }
}

/// One display's line in the confirmation panel.
private struct PreviewRow: View {
    let row: ProfileApplyPreview.Row

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: Self.icon(row.action))
                .foregroundStyle(Self.tint(row.action))
                .font(Design.Typography.note)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.displayName)
                    .font(.system(size: 11, weight: .medium))
                Text(verbatim: row.detailText)
                    .font(Design.Typography.note)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func icon(_ action: ProfileApplyPreview.Row.Action) -> String {
        switch action {
        // Blue arrow = "this will change". Green check is reserved for
        // displays that are *already* at the target mode — green next to a
        // mode change reads as "OK, done", which misleads.
        case .willApplyExact: return "arrow.right.circle.fill"
        case .willApplyFallback: return "arrow.right.circle"
        case .alreadyApplied: return "checkmark.circle.fill"
        case .skippedNotConnected: return "exclamationmark.triangle.fill"
        case .skippedNoMode: return "questionmark.circle.fill"
        }
    }

    static func tint(_ action: ProfileApplyPreview.Row.Action) -> Color {
        switch action {
        case .willApplyExact: return .accentColor
        case .willApplyFallback: return .orange
        case .alreadyApplied: return .green
        case .skippedNotConnected: return .red
        case .skippedNoMode: return .orange
        }
    }
}

/// Asks before deleting a profile.
///
/// The one irreversible action in the app: there is no undo for a profile, and
/// `⌘Z` is wired to display revert. Inline for the same reason as the apply
/// confirmation.
struct ProfileDeleteConfirmation: View {
    let profileName: String
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "trash.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Delete '\(profileName)'?")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text("The saved resolutions for this profile are gone for good. Your displays are not touched.")
                .font(Design.Typography.footer)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                // Cancel is the prominent, default action: Return must not be
                // the key that destroys a profile.
                Button("Cancel", action: cancel)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Delete", action: delete)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(Design.Spacing.l)
    }
}
