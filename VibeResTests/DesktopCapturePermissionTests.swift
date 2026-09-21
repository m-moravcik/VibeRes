import Foundation
import Testing
@testable import VibeRes

/// The Screen Recording permission state machine.
///
/// Worth its own suite because every defect this feature has had lived here
/// rather than in the capture: a hard denial used to short-circuit every later
/// attempt, which made `.stuckLoop` unreachable through the path it exists
/// for, and left the feature dead until relaunch even after the user granted
/// the permission in System Settings.
///
/// `.serialized` because `DesktopCapture` is an enum of static state. Swift
/// Testing runs tests in parallel by default, and two of these racing on
/// `status` would be a flaky suite testing nothing.
@Suite("Screen recording permission", .serialized)
@MainActor
struct DesktopCapturePermissionTests {
    /// Puts the cache and both seams back, whatever the test did.
    private func withStubbedTCC(
        preflight: @escaping @MainActor () -> Bool,
        requestAccess: @escaping @MainActor () -> Bool = { false },
        _ body: () async -> Void
    ) async {
        let realPreflight = DesktopCapture.preflight
        let realRequest = DesktopCapture.requestAccess
        DesktopCapture.preflight = preflight
        DesktopCapture.requestAccess = requestAccess
        DesktopCapture.resetPermissionCache()

        await body()

        DesktopCapture.preflight = realPreflight
        DesktopCapture.requestAccess = realRequest
        DesktopCapture.resetPermissionCache()
    }

    @Test("An already-granted permission is used without prompting")
    func preflightGrantedNeverPrompts() async {
        var prompted = false
        await withStubbedTCC(preflight: { true }, requestAccess: { prompted = true; return true }) {
            #expect(await DesktopCapture.ensurePermission() == true)
            #expect(DesktopCapture.status == .granted)
            #expect(prompted == false, "preflight said yes — there is nothing to ask about")
        }
    }

    @Test("A grant given in the prompt is remembered")
    func promptGranted() async {
        await withStubbedTCC(preflight: { false }, requestAccess: { true }) {
            #expect(await DesktopCapture.ensurePermission() == true)
            #expect(DesktopCapture.status == .granted)
        }
    }

    @Test("One refusal is a denial, a second is a stuck loop")
    func twoRefusalsBecomeStuckLoop() async {
        var prompts = 0
        await withStubbedTCC(preflight: { false }, requestAccess: { prompts += 1; return false }) {
            #expect(await DesktopCapture.ensurePermission() == false)
            #expect(DesktopCapture.status == .denied)

            #expect(await DesktopCapture.ensurePermission() == false)
            #expect(DesktopCapture.status == .stuckLoop)
            // This is the regression: `.denied` used to return before ever
            // reaching the prompt again, so the counter never hit two.
            #expect(prompts == 2)
        }
    }

    @Test("Granting in System Settings after a denial recovers without a relaunch")
    func denialRecoversWhenSettingsGrantArrives() async {
        var granted = false
        await withStubbedTCC(preflight: { granted }, requestAccess: { false }) {
            #expect(await DesktopCapture.ensurePermission() == false)
            #expect(DesktopCapture.status == .denied)

            // The user opens System Settings and ticks the box.
            granted = true

            #expect(await DesktopCapture.ensurePermission() == true)
            #expect(DesktopCapture.status == .granted)
        }
    }

    @Test("A stuck loop stops calling TCC altogether")
    func stuckLoopStopsAsking() async {
        var calls = 0
        await withStubbedTCC(preflight: { calls += 1; return false }, requestAccess: { calls += 1; return false }) {
            _ = await DesktopCapture.ensurePermission()
            _ = await DesktopCapture.ensurePermission()
            #expect(DesktopCapture.status == .stuckLoop)

            let callsBefore = calls
            #expect(await DesktopCapture.ensurePermission() == false)
            #expect(calls == callsBefore, "a stuck loop must stop nagging, not keep prompting")
        }
    }

    @Test("Re-enabling Live Preview clears the cache so the next attempt may ask again")
    func resetClearsTheCache() async {
        await withStubbedTCC(preflight: { false }, requestAccess: { false }) {
            _ = await DesktopCapture.ensurePermission()
            _ = await DesktopCapture.ensurePermission()
            #expect(DesktopCapture.status == .stuckLoop)

            // What the Settings toggle calls.
            DesktopCapture.resetPermissionCache()
            #expect(DesktopCapture.status == .unknown)
        }
    }
}
