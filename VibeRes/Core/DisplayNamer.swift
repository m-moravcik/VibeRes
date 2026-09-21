import CoreGraphics
import Foundation

/// Resolves a human-readable name for a CGDirectDisplayID. Pure-Foundation
/// callers (CLI, tests) get a fallback; the GUI app injects a closure that
/// uses NSScreen.localizedName to produce the same name shown in System
/// Settings → Displays. Lets the Core layer stay free of AppKit.
enum DisplayNamer {
    /// The active resolver. `VibeResApp` installs the AppKit-backed
    /// implementation at startup; everything else gets the safe fallback.
    ///
    /// Readable everywhere, writable only through `install(_:)`, and only
    /// once. It was a plain `nonisolated(unsafe) static var`, which is a
    /// process-wide mutable function pointer that any code in the process
    /// could swap at any time — the one hole in an otherwise complete strict
    /// concurrency story, and an escape hatch with no reason to stay open
    /// after launch.
    private(set) nonisolated(unsafe) static var resolve: @Sendable (CGDirectDisplayID) -> String = fallback

    private nonisolated(unsafe) static var installed = false

    /// Installs the platform resolver. The first call wins; later ones are
    /// ignored, so nothing can redirect display naming mid-session.
    static func install(_ resolver: @escaping @Sendable (CGDirectDisplayID) -> String) {
        guard !installed else { return }
        installed = true
        resolve = resolver
    }

    /// Conservative naming used by the CLI and any caller that hasn't
    /// installed an AppKit-backed resolver. Keeps the Core layer
    /// platform-agnostic at the Foundation level (no AppKit symbols).
    @Sendable
    static func fallback(for id: CGDirectDisplayID) -> String {
        CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "External Display \(id)"
    }
}
