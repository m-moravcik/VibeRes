import AppIntents
import CoreGraphics
import Foundation

/// User-facing Shortcuts.app action: pick a display, type a width / height (and
/// optionally a refresh rate or HiDPI flag), VibeRes finds the closest matching
/// CGDisplayMode and applies it.
///
/// Examples it enables:
/// - Spotlight: "Set Display Resolution to 1800x1169"
/// - Shortcuts.app: "Presentation Mode" workflow that switches to 1280x800
/// - Siri: "Run Presentation Mode"
/// - Stream Deck / Loupedeck: trigger a Shortcut that calls this intent
struct SetResolutionIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Resolution"
    static let description = IntentDescription(
        "Switches the chosen display to the requested resolution. Picks the closest matching mode if the exact size isn't available.",
        categoryName: "Display"
    )

    /// Most users have one display — let Shortcuts auto-select it when only one exists.
    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$display) to \(\.$width) by \(\.$height)") {
            \.$refreshHz
            \.$preferHiDPI
        }
    }

    @Parameter(title: "Display")
    var display: DisplayEntity

    @Parameter(title: "Width", description: "Width in points (logical pixels), e.g. 1800")
    var width: Int

    @Parameter(title: "Height", description: "Height in points, e.g. 1169")
    var height: Int

    @Parameter(
        title: "Refresh Rate",
        description: "Optional. If omitted, picks the highest available for that size.",
        default: nil
    )
    var refreshHz: Int?

    @Parameter(
        title: "Prefer HiDPI",
        description: "When both HiDPI and native modes exist for the size, prefer the HiDPI variant.",
        default: true
    )
    var preferHiDPI: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let snapshot = await MainActor.run { DisplayManager.snapshot() }
        guard let info = snapshot.first(where: { Int($0.id) == display.id }) else {
            throw $display.needsValueError("That display is no longer connected.")
        }

        guard let mode = bestMatch(in: info.modes) else {
            throw $width.needsValueError(
                "No mode close to \(width)×\(height) is available on \(display.name)."
            )
        }

        // CGConfigure* APIs are thread-safe; no need to hop to the main actor.
        try ResolutionSwitcher.apply(mode, to: info.id)

        let hzPart = mode.refreshHz.map { " @ \($0) Hz" } ?? ""
        return .result(value: "\(mode.width) × \(mode.height)\(hzPart)")
    }

    /// Scoring: lower is better. Penalises distance from requested size, mismatched
    /// HiDPI preference, and (when refreshHz is set) distance from requested refresh.
    private func bestMatch(in modes: [CGDisplayMode]) -> CGDisplayMode? {
        modes.min { lhs, rhs in score(lhs) < score(rhs) }
    }

    private func score(_ m: CGDisplayMode) -> Double {
        let sizeDelta = abs(m.width - width) + abs(m.height - height)
        let hidpiPenalty = (m.isHiDPI == preferHiDPI) ? 0 : 50
        var hzPenalty = 0
        if let want = refreshHz, let got = m.refreshHz {
            hzPenalty = abs(want - got) * 2
        } else if let want = refreshHz, m.refreshHz == nil {
            hzPenalty = want
        }
        return Double(sizeDelta + hidpiPenalty + hzPenalty)
    }
}

/// Returns the current resolution of a display — useful in conditional Shortcuts
/// ("if my MacBook is at 1280x800, switch to 1800x1169").
struct GetCurrentResolutionIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Resolution"
    static let description = IntentDescription(
        "Returns the current resolution of the chosen display as a string like \"1800 × 1169 @ 120 Hz\".",
        categoryName: "Display"
    )

    @Parameter(title: "Display")
    var display: DisplayEntity

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let snapshot = await MainActor.run { DisplayManager.snapshot() }
        guard let info = snapshot.first(where: { Int($0.id) == display.id }),
              let mode = info.currentMode
        else {
            throw $display.needsValueError("That display is no longer connected.")
        }

        let hzPart = mode.refreshHz.map { " @ \($0) Hz" } ?? ""
        let hidpi = mode.isHiDPI ? " (HiDPI)" : ""
        return .result(value: "\(mode.width) × \(mode.height)\(hzPart)\(hidpi)")
    }
}
