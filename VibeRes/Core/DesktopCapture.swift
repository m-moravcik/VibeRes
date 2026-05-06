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
    /// Returns a still of the given display, or nil if capture isn't available
    /// (permission denied, ScreenCaptureKit unavailable, no shareable content).
    static func snapshot(of displayID: CGDirectDisplayID, maxWidth: Int = 480) async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
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
            return nil
        }
    }
}
