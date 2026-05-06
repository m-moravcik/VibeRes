import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Single-shot desktop snapshots for the resolution-row hover preview.
///
/// Why this is opt-in: macOS Screen Recording permission is sticky and
/// privacy-loaded. Users who never enable Live Preview never see the
/// system prompt. Those who do get one capture per popover open, cached
/// for the lifetime of the popover, and dropped on close.
///
/// We deliberately avoid `SCStream` (continuous capture) — it would keep a
/// CoreMedia pipeline alive for the whole popover session. A single
/// `SCScreenshotManager.captureImage(...)` is enough.
@MainActor
enum DesktopCapture {
    /// Sticky session-level cache for the permission decision so we don't
    /// hammer `CGPreflightScreenCaptureAccess` on every hover (and accidentally
    /// re-trigger the system prompt on ad-hoc signed builds where TCC sometimes
    /// loses the grant between bundle replacements).
    private static var permissionGranted: Bool? = nil

    /// Returns a still of the given display, or nil if capture isn't available
    /// (permission denied, ScreenCaptureKit unavailable, no shareable content).
    /// Will request permission exactly once per process if it hasn't been
    /// asked before; subsequent calls re-use the cached decision.
    static func snapshot(of displayID: CGDirectDisplayID, maxWidth: Int = 480) async -> NSImage? {
        guard await ensurePermission() else { return nil }

        do {
            // `excludingDesktopWindows` keeps the System Settings → Screen
            // Recording grant stable across calls; bare `.current` is
            // documented but in macOS 26 occasionally re-prompts.
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let target = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }
            let cfg = SCStreamConfiguration()
            cfg.width = min(target.width, maxWidth)
            cfg.height = Int(Double(cfg.width) * Double(target.height) / Double(target.width))
            cfg.captureResolution = .nominal
            cfg.showsCursor = false

            let filter = SCContentFilter(display: target, excludingWindows: [])
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: cfg
            )
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            // If a capture fails *after* we believed we had permission, assume
            // the grant flipped (common on ad-hoc signed builds when the
            // bundle is replaced) and clear the cache so the next opt-in
            // request can re-prompt cleanly.
            permissionGranted = nil
            return nil
        }
    }

    /// Manual reset hook for the "I just toggled Live Preview" flow — lets
    /// the next snapshot attempt re-evaluate from scratch instead of trusting
    /// a stale cache.
    static func resetPermissionCache() {
        permissionGranted = nil
    }

    /// Returns true once we know the user has granted Screen Recording.
    /// Triggers exactly one `requestScreenCaptureAccess` call per process.
    /// After a denial, returns false forever (until the user resets in
    /// System Settings AND we receive a fresh `resetPermissionCache()`).
    private static func ensurePermission() async -> Bool {
        if let cached = permissionGranted { return cached }

        // CGPreflightScreenCaptureAccess returns true ONLY if the grant
        // already exists; it never prompts. CGRequestScreenCaptureAccess
        // either returns true immediately (already granted) or shows the
        // system prompt and returns the user's decision.
        if CGPreflightScreenCaptureAccess() {
            permissionGranted = true
            return true
        }
        let granted = CGRequestScreenCaptureAccess()
        permissionGranted = granted
        return granted
    }
}
