import Foundation
import Observation

/// Lightweight user-pref store backed by UserDefaults. Currently single-purpose
/// (auto-apply toggle) but lays the structural groundwork for a real Settings
/// scene later without forcing one in v0.x.
@Observable
@MainActor
final class Preferences {
    private static let autoApplyKey = "VibeRes.AutoApplyOnDisplayChange"
    private static let livePreviewKey = "VibeRes.LivePreviewEnabled"
    private static let simpleModeKey = "VibeRes.SimpleMode"
    private static let onboardingShownKey = "VibeRes.OnboardingShown"
    private static let launchAtLoginKey = "VibeRes.LaunchAtLogin"
    private static let confirmChangesKey = "VibeRes.ConfirmDisplayChanges"
    private static let livePreviewHintDismissedKey = "VibeRes.LivePreviewHintDismissed"

    var autoApplyOnDisplayChange: Bool {
        didSet {
            UserDefaults.standard.set(autoApplyOnDisplayChange, forKey: Self.autoApplyKey)
        }
    }

    /// When true, hovering a resolution row will show a live screenshot of
    /// the desktop scaled into the proposed mode. Off by default so the
    /// macOS Screen Recording permission prompt only fires for users who
    /// asked for the feature.
    var livePreviewEnabled: Bool {
        didSet {
            UserDefaults.standard.set(livePreviewEnabled, forKey: Self.livePreviewKey)
        }
    }

    /// When true, the per-display detail hides individual refresh-rate chips
    /// and offers a single click that applies the highest available refresh
    /// for the chosen size. Reflects the way most non-tech users think about
    /// resolution: pick a size, accept the best refresh available. Power
    /// users turn it off in Settings to get back the chip group.
    var simpleMode: Bool {
        didSet {
            UserDefaults.standard.set(simpleMode, forKey: Self.simpleModeKey)
        }
    }

    /// True once the welcome tour has been completed (or skipped). Stays true
    /// across re-launches; toggled back to false by the "Replay welcome tour"
    /// button in Settings, or implicitly false on a fresh install.
    var onboardingShown: Bool {
        didSet {
            UserDefaults.standard.set(onboardingShown, forKey: Self.onboardingShownKey)
        }
    }

    /// What the user last asked for regarding launch at login.
    ///
    /// `SMAppService` is authoritative about the *current* registration but keeps
    /// no record of intent, so a registration that gets invalidated — the bundle
    /// replaced by an update, moved, or restored from a backup — reads as "off"
    /// with nothing to compare against. Storing intent lets the app notice and
    /// re-register instead of silently stopping at login. `nil` means no answer
    /// has been recorded yet; see `LoginItem.reconciliation`.
    var launchAtLoginIntent: Bool? {
        didSet {
            if let launchAtLoginIntent {
                UserDefaults.standard.set(launchAtLoginIntent, forKey: Self.launchAtLoginKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.launchAtLoginKey)
            }
        }
    }

    /// True once the user has either taken up the live-preview hint or waved it
    /// away.
    ///
    /// Live preview is the one thing VibeRes does that the alternatives do not,
    /// and it is off by default with its only mention buried in Settings — so
    /// most people never learn it exists. The hint sits in the display detail,
    /// directly above the rows it applies to, and appears at most until it is
    /// answered once.
    var livePreviewHintDismissed: Bool {
        didSet {
            UserDefaults.standard.set(livePreviewHintDismissed, forKey: Self.livePreviewHintDismissedKey)
        }
    }

    /// When true, a resolution change is applied for the session only and undone
    /// after a short window unless the user confirms it.
    ///
    /// Off by default, deliberately. It is the only protection against a mode
    /// that leaves the screen unreadable — the popover is on that screen, so a
    /// button nobody can see is useless and the timeout is what saves them — but
    /// it also interrupts the app's core action, which is fine for the vast
    /// majority of changes. Opt-in keeps the default flow untouched.
    var confirmDisplayChanges: Bool {
        didSet {
            UserDefaults.standard.set(confirmDisplayChanges, forKey: Self.confirmChangesKey)
        }
    }

    init() {
        self.confirmDisplayChanges = UserDefaults.standard.bool(forKey: Self.confirmChangesKey)
        // Read before the didSet observers can fire.
        self.launchAtLoginIntent = UserDefaults.standard.object(forKey: Self.launchAtLoginKey) as? Bool

        if UserDefaults.standard.object(forKey: Self.autoApplyKey) == nil {
            self.autoApplyOnDisplayChange = true
        } else {
            self.autoApplyOnDisplayChange = UserDefaults.standard.bool(forKey: Self.autoApplyKey)
        }
        // Live preview is opt-in: never trigger the permission dialog unless
        // the user explicitly enables it.
        let livePreview = UserDefaults.standard.bool(forKey: Self.livePreviewKey)
        self.livePreviewEnabled = livePreview
        // A user who already found the feature has answered the question. Read
        // through the local, not `self`: the remaining stored properties are
        // still uninitialised at this point.
        self.livePreviewHintDismissed =
            UserDefaults.standard.bool(forKey: Self.livePreviewHintDismissedKey) || livePreview
        // Simple Mode is on by default for fresh installs — non-tech users
        // get the cleanest decision surface. Existing users keep whichever
        // value they previously had (defaults to false the first time we
        // ship this key).
        if UserDefaults.standard.object(forKey: Self.simpleModeKey) == nil {
            self.simpleMode = true
        } else {
            self.simpleMode = UserDefaults.standard.bool(forKey: Self.simpleModeKey)
        }
        // First-launch detection: bool(forKey:) returns false when missing,
        // which is exactly what we want — fresh installs see the tour.
        self.onboardingShown = UserDefaults.standard.bool(forKey: Self.onboardingShownKey)
    }
}
