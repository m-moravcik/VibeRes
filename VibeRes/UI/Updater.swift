import Foundation
import Observation
import Security
import SwiftUI

/// In-app updates.
///
/// The approach follows [steipete/CodexBar](https://github.com/steipete/CodexBar)
/// (MIT): a protocol with a real and a no-op implementation chosen by a factory,
/// and Sparkle's install-on-quit hook converted into a user-triggered install so
/// a menu-bar app that runs for weeks still gets updates. Two things are
/// deliberately *not* copied — see `UpdaterGate` for its Homebrew check, and the
/// note on preferences below.
///
/// Lives in `VibeRes/UI` rather than `Core`, which is also compiled into the
/// bundle-less `viberes` tool.
@MainActor
protocol UpdaterProviding: AnyObject, Sendable {
    var automaticallyChecksForUpdates: Bool { get set }
    var isAvailable: Bool { get }
    /// Why updates are off, phrased for the user. Nil when they are on.
    var unavailableReason: String? { get }
    var updateStatus: UpdateStatus { get }
    func checkForUpdates()
    func installUpdate()
}

/// Drives the popover's "update ready" row.
@MainActor
@Observable
final class UpdateStatus {
    var isUpdateReady: Bool

    init(isUpdateReady: Bool = false) {
        self.isUpdateReady = isUpdateReady
    }
}

/// Used when this build must not update itself. Carries the reason so the
/// Settings pane can say what to do instead of showing a dead control.
@MainActor
final class DisabledUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool = false
    let isAvailable = false
    let unavailableReason: String?
    let updateStatus = UpdateStatus()

    init(reason: UpdaterGate.Reason?) {
        self.unavailableReason = reason?.userFacingDescription
    }

    func checkForUpdates() {}
    func installUpdate() {}
}

// MARK: - Signature check

/// True when the bundle carries a Developer ID Application signature from our
/// team. This is what stops a debug or ad-hoc build from downloading and running
/// a binary from the internet.
///
/// Sparkle's EdDSA signature on the downloaded archive is a separate, equally
/// necessary check: this one says *we* are the thing running, that one says the
/// thing we fetched came from us. Neither substitutes for the other.
func isDeveloperIDSigned(bundleURL: URL) -> Bool {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
          let staticCode
    else { return false }

    var requirement: SecRequirement?
    let text = "anchor apple generic and certificate leaf[subject.OU] = \"7TM9VA58W5\"" as CFString
    guard SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess,
          let requirement
    else { return false }

    return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
}

#if canImport(Sparkle) && ENABLE_SPARKLE
import Sparkle

@MainActor
final class SparkleUpdaterController: NSObject, UpdaterProviding,
                                      SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Sparkle hands us a closure to trigger the staged install. Boxed because it
    /// outlives the callback that produced it.
    private final class InstallHandler {
        private let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        func callAsFunction() { run() }
    }

    let updateStatus = UpdateStatus()
    let isAvailable = true
    let unavailableReason: String? = nil

    private var controller: SPUStandardUpdaterController!
    private var installHandler: InstallHandler?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        controller.startUpdater()
    }

    /// Bound straight to Sparkle, which persists it. Sparkle's own header is
    /// explicit that an app should not keep a second copy in its defaults
    /// ("developers shouldn't maintain an additional user default for this
    /// property"), and the reference implementation does exactly that.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            // Downloading ahead of time is what makes the install click instant,
            // and is also what makes willInstallUpdateOnQuit fire at all.
            controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkForUpdates() {
        // VibeRes has no Dock icon, so Sparkle's window would otherwise open
        // behind whatever the user is working in with no way to reach it.
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    func installUpdate() {
        guard let installHandler else { return }
        self.installHandler = nil
        updateStatus.isUpdateReady = false
        installHandler()
    }

    private func apply(_ event: UpdateReadiness.Event) {
        updateStatus.isUpdateReady = UpdateReadiness.next(
            after: event,
            currentlyReady: updateStatus.isUpdateReady
        )
        if !updateStatus.isUpdateReady { installHandler = nil }
    }

    // MARK: SPUUpdaterDelegate
    //
    // Plain main-actor methods: the protocol is NS_SWIFT_UI_ACTOR as of Sparkle
    // 2.9, so hopping through a detached Task would only reintroduce ordering
    // races between these callbacks.

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installHandler = InstallHandler(immediateInstallHandler)
        apply(.queuedForInstallOnQuit)
        // Taking over the *timing* of the install. Sparkle still installs on
        // quit regardless — this is not a way to suppress its UI, which it
        // documents that it reserves the right to show.
        return true
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        apply(.downloadFailed)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        apply(.downloadCancelled)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        apply(.aborted)
    }

    // Swift name is `userDidMake`, not `userDidMakeChoice` — the compiler
    // rejects the latter outright. The spec review asserted the opposite.
    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .install: apply(.userChoseInstall)
        case .skip: apply(.userChoseSkip)
        case .dismiss: apply(.userDismissed(downloaded: state.stage == .downloaded))
        @unknown default: apply(.aborted)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        apply(.cycleFinished)
    }

    // MARK: SPUStandardUserDriverDelegate

    // Unlike SPUUpdaterDelegate, this protocol is not annotated for the main
    // actor, so its members have to be nonisolated and hop explicitly. Marking
    // them plain @MainActor fails to compile with a data-race diagnostic.

    /// Required for background apps. Sparkle's documentation is explicit that a
    /// dockless app must implement this, or scheduled alerts appear behind
    /// everything with no Dock icon to bring them forward.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // A scheduled find is surfaced by our own popover row instead.
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Anything Sparkle does show — a manual check, an impatient reminder —
        // needs the app brought forward first.
        guard state.userInitiated else { return }
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
    }
}

@MainActor
func makeUpdaterController() -> UpdaterProviding {
    let bundleURL = Bundle.main.bundleURL
    let decision = UpdaterGate.decide(
        bundleURL: bundleURL,
        isDeveloperIDSigned: isDeveloperIDSigned(bundleURL: bundleURL),
        caskroomBundleURLs: UpdaterGate.caskroomBundleURLs()
    )
    switch decision {
    case .enabled:
        return SparkleUpdaterController()
    case .disabled(let reason):
        return DisabledUpdaterController(reason: reason)
    }
}
#else
@MainActor
func makeUpdaterController() -> UpdaterProviding {
    // Debug builds carry Sparkle.framework — XcodeGen cannot filter a dependency
    // per configuration — but none of the code above is compiled, so there is
    // nothing to drive it.
    DisabledUpdaterController(reason: .notSigned)
}
#endif

// MARK: - Environment plumbing

/// The updater is a protocol existential, which SwiftUI's `@Observable`
/// environment injection cannot carry. `UpdateStatus` goes through that path
/// because it drives a view; the controller itself goes through a plain key
/// because views only ever call methods on it.
/// Optional because `EnvironmentKey.defaultValue` has to be nonisolated, and
/// every implementation of `UpdaterProviding` is main-actor bound. A `nil`
/// default is honest anyway: a view rendered without the app around it has no
/// updater, rather than a fake one.
private struct UpdaterKey: EnvironmentKey {
    // Sendable via the protocol: every conformer is main-actor isolated, which
    // makes it safe to hand across the environment's nonisolated storage.
    static let defaultValue: (any UpdaterProviding)? = nil
}

extension EnvironmentValues {
    var updater: UpdaterProviding? {
        get { self[UpdaterKey.self] }
        set { self[UpdaterKey.self] = newValue }
    }
}
