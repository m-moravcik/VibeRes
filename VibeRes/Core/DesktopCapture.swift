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
    /// Why Live Preview is fragile on ad-hoc signed builds:
    /// macOS TCC keys Screen Recording grants by *code signature hash*, not
    /// bundle ID. Ad-hoc signatures can drift between bundle replacements
    /// (or even within a session), so even after the user clicks Allow in
    /// System Settings, `CGPreflightScreenCaptureAccess` may keep returning
    /// false. Calling `CGRequestScreenCaptureAccess` after a fresh grant is
    /// supposed to return true — when it returns false twice in a row we
    /// detect the loop and disable the feature for the rest of the session
    /// instead of nagging the user with prompt after prompt.

    enum Status: Equatable {
        case unknown
        case granted
        case denied
        /// User clicked Allow but the system keeps reporting "no access".
        /// Symptom of TCC + ad-hoc signature drift; only a notarized build
        /// will fix it permanently.
        case stuckLoop
    }

    private(set) static var status: Status = .unknown
    private static var deniedAttempts = 0

    /// Returns a still of the given display, or nil when capture isn't
    /// available. After a stuck-loop or hard denial we stop calling
    /// ScreenCaptureKit altogether — caller falls back to the geometric
    /// preview without any further prompts.
    static func snapshot(of displayID: CGDirectDisplayID, maxWidth: Int = 480) async -> NSImage? {
        guard await ensurePermission() else { return nil }

        do {
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
            // Capture failed despite the cache saying we had permission —
            // treat that as a TCC stuck-loop signal so the next attempt
            // doesn't re-prompt.
            status = .stuckLoop
            return nil
        }
    }

    /// Reset hook for the "I just turned Live Preview back on" flow. Puts the
    /// cache back to `.unknown` so the next capture may prompt once more; a
    /// second denial after that is what makes `.stuckLoop` reachable, which it
    /// was not while `.denied` short-circuited every subsequent attempt.
    static func resetPermissionCache() {
        status = .unknown
        deniedAttempts = 0
    }

    /// Returns true once we know the user has granted Screen Recording.
    /// Tracks repeated denials so a TCC drift loop disables the feature
    /// after the second failed grant rather than prompting forever.
    private static func ensurePermission() async -> Bool {
        switch status {
        case .granted:
            return true
        case .denied:
            // Preflight does not prompt, so it is safe to re-ask here. Without
            // this, granting the permission in System Settings after one denial
            // left the feature dead until the app was relaunched.
            if CGPreflightScreenCaptureAccess() {
                status = .granted
                deniedAttempts = 0
                return true
            }
            return false
        case .stuckLoop:
            return false
        case .unknown:
            break
        }

        if CGPreflightScreenCaptureAccess() {
            status = .granted
            return true
        }
        // Preflight false. Ask the system; if the user already clicked Allow
        // earlier, this returns true immediately. If it keeps returning
        // false despite clear user intent, we're in TCC drift territory.
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            status = .granted
            return true
        }
        deniedAttempts += 1
        status = deniedAttempts >= 2 ? .stuckLoop : .denied
        return false
    }
}
