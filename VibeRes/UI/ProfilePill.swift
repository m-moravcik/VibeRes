import SwiftUI

struct ProfilePill: View {
    let profile: Profile
    let isCurrentlyFlexible: Bool
    /// True when the profile matches the desktop's current state right now —
    /// applying it would change nothing. Distinct from `isCurrentlyFlexible`
    /// (the `✱` badge), which only says the profile's matcher is role-based;
    /// both can be true at once.
    let isActive: Bool
    /// Lazily computed preview shown on hover so the user knows *before*
    /// clicking what the apply will do. Re-evaluated on each hover so the
    /// preview reflects live display state, not a stale snapshot.
    let previewProvider: () -> ProfileApplyPreview
    let onApply: () -> Void
    let onRename: () -> Void
    let onUpdateCurrent: () -> Void
    let onToggleFlexible: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false
    @State private var cachedPreview: ProfileApplyPreview?
    /// Goes up each time the pill turns active while on screen, for the
    /// checkmark's one bounce.
    @State private var activations = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 4) {
                // One symbol that changes, rather than two in an if/else, so
                // the swap to the checkmark is the system's symbol replace
                // instead of one image cut for another.
                Image(systemName: isActive ? "checkmark.circle.fill" : iconName)
                    .font(.system(size: 9))
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .symbolEffect(.bounce, options: .nonRepeating, value: activations)
                Text(profile.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if isCurrentlyFlexible {
                    Text("✱")
                        .font(Design.Typography.badge)
                        .foregroundStyle(Design.Palette.accentText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovering
                          ? Color.accentColor.opacity(Design.Palette.pillHoverAccentOpacity)
                          : (isActive ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(Design.Palette.pillRestSecondaryOpacity)))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isActive ? 0.8 : 0), lineWidth: 1)
            }
            .animation(Design.Motion.quick, value: isHovering)
            .animation(Design.Motion.quick, value: isActive)
        }
        .buttonStyle(PressableButtonStyle(scale: Design.Motion.pillPressScale))
        // The pill turns active on the refresh after the displays come back
        // from the change, about when the menu bar icon's window springs out,
        // so the bounce lands with it. See `Design.Motion`.
        .onChange(of: isActive) { _, active in
            if active, !reduceMotion { activations += 1 }
        }
        .onHover { hover in
            isHovering = hover
            // Refresh the preview on each hover-in so it reflects the
            // current display set, not a snapshot from the last hover.
            // Cleared on hover-out to keep the cache small.
            cachedPreview = hover ? previewProvider() : nil
        }
        .help(plainPreviewTooltip)
        .contextMenu {
            // Left-click on the pill already applies — no Apply item to duplicate it.
            // Context menu is for actions without a dedicated UI control.
            Button("Edit…", action: onEdit)
            Button("Update with current setup", action: onUpdateCurrent)
            Button(isCurrentlyFlexible ? "Make specific (lock to current monitors)" : "Make flexible (any external)",
                   action: onToggleFlexible)
            Button("Rename…", action: onRename)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    /// Plain-text apply preview for the system tooltip. We deliberately avoid
    /// SwiftUI `.popover` here: it creates an NSPanel that intercepts the first
    /// click on the pill while the preview is visible.
    private var plainPreviewTooltip: String {
        guard let preview = cachedPreview else { return tooltip }
        var lines = activeTooltipPrefix + ["Applying '\(profile.name)' will:"]
        for row in preview.rows {
            lines.append("  \(row.tooltipMarker) \(row.displayName) — \(row.detailText)")
        }
        if !preview.untouched.isEmpty {
            lines.append("Leaves untouched: " + preview.untouched.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
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
        (activeTooltipPrefix + ["Apply '\(profile.name)' (\(profile.humanSummary))"]).joined(separator: "\n")
    }

    /// First line prepended to both tooltip variants when the pill is active —
    /// empty when it isn't, so joining it never leaves a stray blank line.
    private var activeTooltipPrefix: [String] {
        isActive ? ["Active — matches the current setup"] : []
    }
}

extension KeyEquivalent {
    /// `KeyEquivalent` for a single decimal digit, or nil for anything that is
    /// not one. Keeps the digit-to-key conversion out of the view body and out
    /// of force-unwrapped `Character` construction.
    init?(exactly digit: Int) {
        guard (0...9).contains(digit) else { return nil }
        self.init(Character("\(digit)"))
    }
}
