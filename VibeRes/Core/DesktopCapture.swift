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

    /// Test seams for the two TCC calls.
    ///
    /// The permission state machine is where the bugs live: a hard denial once
    /// short-circuited every later attempt, which made `.stuckLoop`
    /// unreachable through the very path it was written for, and granting the
    /// permission in System Settings afterwards did nothing until relaunch.
    /// None of that is assertable against the real TCC, and a unit test has no
    /// business prompting for Screen Recording — so the two calls are
    /// injectable and the machine around them is tested directly.
    static var preflight: @MainActor () -> Bool = { CGPreflightScreenCaptureAccess() }
    static var requestAccess: @MainActor () -> Bool = { CGRequestScreenCaptureAccess() }

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

    /// Reset hook for the "I just turned Live Preview back on" flow, and the
    /// way out of a stuck loop without quitting the app. Puts the cache back
    /// to `.unknown` and clears the attempt counter, so the next capture gets
    /// the full two attempts again.
    static func resetPermissionCache() {
        status = .unknown
        deniedAttempts = 0
    }

    /// Returns true once we know the user has granted Screen Recording.
    /// Tracks repeated denials so a TCC drift loop disables the feature
    /// after the second failed grant rather than prompting forever.
    ///
    /// Internal rather than private so the state machine can be driven by a
    /// test through the `preflight` / `requestAccess` seams above.
    @discardableResult
    static func ensurePermission() async -> Bool {
        switch status {
        case .granted:
            return true
        case .stuckLoop:
            // The end of the line: two clear attempts produced no access, so
            // the feature is off for the session and TCC is left alone.
            return false
        case .denied, .unknown:
            // Both go through the same two steps below. `.denied` used to take
            // a branch of its own that preflighted and then returned — so the
            // attempt counter was never reached a second time and `.stuckLoop`
            // stayed unreachable through the exact path it was written for.
            // The README's "stops nagging after two failed grant attempts" was
            // describing behaviour that did not exist.
            break
        }

        // Preflight never prompts, so it is always worth asking first. It is
        // also how a permission granted in System Settings after a denial gets
        // noticed without a relaunch.
        if preflight() {
            status = .granted
            deniedAttempts = 0
            return true
        }

        // Ask. macOS shows its dialog at most once per session, so reaching
        // this a second time is not a second dialog — it is how we learn that
        // clear user intent still is not producing access, which is TCC
        // signature drift rather than a refusal.
        if requestAccess() {
            status = .granted
            deniedAttempts = 0
            return true
        }

        deniedAttempts += 1
        status = deniedAttempts >= 2 ? .stuckLoop : .denied
        return false
    }
}
