import CoreGraphics
import Foundation

/// Resolves a human-readable name for a CGDirectDisplayID. Pure-Foundation
/// callers (CLI, tests) get a fallback; the GUI app injects a closure that
/// uses NSScreen.localizedName to produce the same name shown in System
/// Settings → Displays. Lets the Core layer stay free of AppKit.
enum DisplayNamer {
    /// The active resolver. Replace from `VibeResApp` at startup with the
    /// AppKit-backed implementation. Default is the safe fallback.
    nonisolated(unsafe) static var resolve: @Sendable (CGDirectDisplayID) -> String = fallback

    /// Conservative naming used by the CLI and any caller that hasn't
    /// installed an AppKit-backed resolver. Keeps the Core layer
    /// platform-agnostic at the Foundation level (no AppKit symbols).
    static func fallback(for id: CGDirectDisplayID) -> String {
        CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "External Display \(id)"
    }
}
