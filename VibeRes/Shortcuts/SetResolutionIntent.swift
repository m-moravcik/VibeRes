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
            \.$variableRefresh
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

    /// Off by default, so every Shortcut built before VRR support keeps
    /// landing on the fixed rate it always meant.
    @Parameter(
        title: "Variable Refresh Rate",
        description: "When the display offers a variable refresh rate (Adaptive Sync) next to a fixed one at the same rate, use the variable one.",
        default: false
    )
    var variableRefresh: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Shortcuts hands over whatever the automation supplies, including
        // values no display could have. Scoring survives them now, but the
        // honest answer is to reject them at the parameter that is wrong rather
        // than silently pick some "closest" mode.
        guard ModeScoring.isRequestInRange(width: width, height: height, refreshHz: refreshHz) else {
            if !(1...16384).contains(width) {
                throw $width.needsValueError("Width must be between 1 and 16384 points.")
            }
            if !(1...16384).contains(height) {
                throw $height.needsValueError("Height must be between 1 and 16384 points.")
            }
            throw $refreshHz.needsValueError("Refresh rate must be between 1 and 1000 Hz.")
        }

        let snapshot = await MainActor.run { DisplayManager.snapshot() }
        guard let info = snapshot.first(where: { Int($0.id) == display.id }) else {
            throw $display.needsValueError("That display is no longer connected.")
        }

        guard let mode = bestMatch(on: info) else {
            throw $width.needsValueError(
                "No mode close to \(width)×\(height) is available on \(display.name)."
            )
        }

        // CGConfigure* APIs are thread-safe; no need to hop to the main actor.
        try ResolutionSwitcher.apply(mode, to: info.id)

        return .result(value: "\(mode.width) × \(mode.height)\(Self.hzPart(mode, on: info))")
    }

    /// Scoring: lower is better. Penalises distance from requested size, mismatched
    /// HiDPI preference, and (when refreshHz is set) distance from requested refresh.
    private func bestMatch(on info: DisplayInfo) -> CGDisplayMode? {
        ModeScoring.bestMatch(
            in: info.modes,
            request: ModeScoring.Request(
                width: width,
                height: height,
                refreshHz: refreshHz,
                preferHiDPI: preferHiDPI,
                preferVariable: variableRefresh
            ),
            isVariable: info.isVariable
        )
    }

    /// " @ 160 Hz", or " @ 160 Hz VRR" for a variable mode that has a fixed
    /// twin. Shared with Get Current Resolution so a Shortcut can compare the
    /// two. ProMotion's 120 Hz never gets the suffix, which keeps conditions
    /// written against "1800 × 1169 @ 120 Hz" working.
    static func hzPart(_ mode: CGDisplayMode, on info: DisplayInfo) -> String {
        guard let hz = mode.refreshHz else { return "" }
        return " @ \(hz) Hz" + (info.isVRRTwin(mode) ? " VRR" : "")
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

        let hzPart = SetResolutionIntent.hzPart(mode, on: info)
        let hidpi = mode.isHiDPI ? " (HiDPI)" : ""
        return .result(value: "\(mode.width) × \(mode.height)\(hzPart)\(hidpi)")
    }
}
