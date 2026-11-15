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

            Text(verbatim: Self.headline(for: classification))
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
                        Text(verbatim: Self.untouched(preview.untouched))
                            .font(Design.Typography.note)
                            .foregroundStyle(.secondary)
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

    /// The sentence under the panel's title. Names rather than counts, so
    /// it needs no plural forms and says which displays it means.
    static func headline(for c: DisplaySetClassifier.Classification, locale: Locale = .appLanguage) -> String {
        switch c {
        case .exactMatch:
            return String(localized: LocalizedStringResource(
                "panel.headline.exact",
                defaultValue: "Display setup matches the profile.",
                locale: locale,
                comment: "Apply confirmation: every display the profile names is connected"
            ))
        case .partialMatch(let missing):
            let names = missingNames(missing, locale: locale)
            return String(localized: LocalizedStringResource(
                "panel.headline.partial",
                defaultValue: "Not connected: \(names). The other displays will apply as saved.",
                locale: locale,
                comment: "Apply confirmation. 1: the profile's displays that are not connected, as a list"
            ))
        case .supersetMatch(let extra):
            let names = ProfileCopy.list(extra.map(\.name), locale: locale)
            return String(localized: LocalizedStringResource(
                "panel.headline.superset",
                defaultValue: "Also connected: \(names). They will be left untouched.",
                locale: locale,
                comment: "Apply confirmation. 1: connected displays the profile does not name, as a list"
            ))
        case .partialWithExtras(let missing, let extra):
            let missingList = missingNames(missing, locale: locale)
            let extraList = ProfileCopy.list(extra.map(\.name), locale: locale)
            return String(localized: LocalizedStringResource(
                "panel.headline.partialWithExtras",
                defaultValue: "Not connected: \(missingList). Also connected, left untouched: \(extraList).",
                locale: locale,
                comment: "Apply confirmation. 1: the profile's displays that are missing, 2: connected displays it does not name"
            ))
        case .disjoint:
            return disjointHeadline(locale: locale)
        }
    }

    /// Also the second line of the tooltip on a pill that is waiting for its
    /// displays, so the two say the same.
    static func disjointHeadline(locale: Locale = .appLanguage) -> String {
        String(localized: LocalizedStringResource(
            "panel.headline.disjoint",
            defaultValue: "None of this profile's displays is connected, so there is nothing to apply.",
            locale: locale,
            comment: "Apply confirmation and pill tooltip: no display the profile names is connected"
        ))
    }

    private static func missingNames(_ entries: [Profile.Entry], locale: Locale) -> String {
        ProfileCopy.list(ProfileCopy.displayNames(of: entries, locale: locale), locale: locale)
    }

    static func untouched(_ names: [String], locale: Locale = .appLanguage) -> String {
        let list = ProfileCopy.list(names, locale: locale)
        return String(localized: LocalizedStringResource(
            "panel.untouched",
            defaultValue: "Untouched: \(list)",
            locale: locale,
            comment: "Apply confirmation: connected displays the profile leaves alone. 1: their names, as a list"
        ))
    }

    static func applyButtonLabel(for c: DisplaySetClassifier.Classification, locale: Locale = .appLanguage) -> String {
        switch c {
        case .exactMatch, .disjoint:
            return String(localized: LocalizedStringResource(
                "panel.apply",
                defaultValue: "Apply",
                locale: locale,
                comment: "Apply confirmation button"
            ))
        case .partialMatch, .supersetMatch, .partialWithExtras:
            return String(localized: LocalizedStringResource(
                "panel.applyAnyway",
                defaultValue: "Apply anyway",
                locale: locale,
                comment: "Apply confirmation button when some displays are missing or extra"
            ))
        }
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
/// Revert undoes display changes only. Inline for the same reason as the apply
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
