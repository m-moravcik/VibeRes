import Foundation

/// One place that turns a `ProfileApplyPreview.Row` into the sentence under a
/// display name.
///
/// There were two of these — `ProfilesSection.rowDetail` for the inline
/// confirmation panel and `ProfilePill.previewDetail` for the hover tooltip —
/// character-for-character identical, each with its own private copy of the
/// "does this already match what was saved?" check. Two copies of the same
/// wording drift; the second one only has to be forgotten once.
///
/// Lives in `VibeRes/UI` for the same reason `ApplyOutcomeNote` does: the type
/// it renders is in `VibeRes/Core`, which is compiled into the bundle-less
/// `viberes` tool where a String Catalog lookup does not resolve.
extension ProfileApplyPreview.Row {
    /// The saved mode, as digits and units only.
    private var savedMode: String {
        var text = "\(savedWidth)×\(savedHeight)"
        if let savedHz { text += " @ \(savedHz)Hz" }
        if savedIsHiDPI { text += " HiDPI" }
        return text
    }

    /// True when the mode the display is already in is the one the profile
    /// asked for — as opposed to the closest available, which is a different
    /// thing to tell the user.
    private func alreadyMatchesSaved(width: Int, height: Int, hz: Int?, isHiDPI: Bool) -> Bool {
        width == savedWidth
            && height == savedHeight
            && (savedHz == nil || savedHz == hz)
            && isHiDPI == savedIsHiDPI
    }

    /// What applying the profile would do to this display.
    var detailText: String {
        switch action {
        case .willApplyExact:
            return String(localized: LocalizedStringResource(
                "preview.row.willApply",
                defaultValue: "→ \(savedMode)",
                comment: "The display will be set to exactly the saved mode. 1: the saved mode"
            ))

        case let .willApplyFallback(width, height, hz):
            let used = "\(width)×\(height)" + (hz.map { " @ \($0)Hz" } ?? "")
            return String(localized: LocalizedStringResource(
                "preview.row.willApplyFallback",
                defaultValue: "wanted \(savedMode), will use \(used)",
                comment: "The saved mode is unavailable. 1: saved mode, 2: the closest available"
            ))

        case let .alreadyApplied(width, height, hz, isHiDPI):
            if alreadyMatchesSaved(width: width, height: height, hz: hz, isHiDPI: isHiDPI) {
                return String(localized: LocalizedStringResource(
                    "preview.row.alreadyAtSaved",
                    defaultValue: "already at \(savedMode)",
                    comment: "The display is already in the saved mode. 1: the saved mode"
                ))
            }
            // Report what the display is actually at, not what was asked for:
            // an `.anyExternal` entry saved from a 4K panel lands on 1920×1080
            // on a 1080p one, and "already at 2880×1620" would be a lie.
            var current = "\(width)×\(height)"
            if let hz { current += " @ \(hz)Hz" }
            if isHiDPI { current += " HiDPI" }
            return String(localized: LocalizedStringResource(
                "preview.row.alreadyAtClosest",
                defaultValue: "already at \(current) (closest to \(savedMode))",
                comment: "The display already holds the closest available mode. 1: current mode, 2: saved mode"
            ))

        case .skippedNotConnected:
            return String(localized: LocalizedStringResource(
                "preview.row.notConnected",
                defaultValue: "not connected — skip",
                comment: "The entry's display is not attached, so it will be skipped"
            ))

        case .skippedNoMode:
            let size = "\(savedWidth)×\(savedHeight)"
            return String(localized: LocalizedStringResource(
                "preview.row.noUsableMode",
                defaultValue: "no usable mode for \(size)",
                comment: "The display is attached but offers nothing close. 1: the saved size"
            ))
        }
    }

    /// Single-character marker for the plain-text hover tooltip, where there is
    /// no room for an SF Symbol.
    var tooltipMarker: String {
        switch action {
        case .willApplyExact: return "✓"
        case .willApplyFallback: return "⚠"
        case .alreadyApplied: return "="
        case .skippedNotConnected: return "✗"
        case .skippedNoMode: return "?"
        }
    }
}
