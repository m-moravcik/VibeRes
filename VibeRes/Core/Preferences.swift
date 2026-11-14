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
    static let revertHotkeyKey = "VibeRes.RevertHotkey"
    static let debugLogEnabledKey = "VibeRes.DebugLogEnabled"
    static let debugLogLevelKey = "VibeRes.DebugLogLevel"

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
    /// It is the only protection against a mode that leaves the screen
    /// unreadable: the popover is on that screen, so a button nobody can see is
    /// useless and the timeout is what saves them. VISION.md therefore wants it
    /// on by default. A fresh install starts with it on and the welcome tour
    /// shows the switch, so the "Keep?" row never comes as a surprise. An
    /// install from before this default keeps what it had, which for anyone who
    /// never touched it is off: an update must not start reverting changes
    /// someone did not confirm. See `initialConfirmDisplayChanges`.
    ///
    /// It guards a size or rate picked by hand only. Profiles, shortcuts and
    /// auto-apply apply modes the user saved after seeing them work, and arm no
    /// countdown.
    var confirmDisplayChanges: Bool {
        didSet {
            UserDefaults.standard.set(confirmDisplayChanges, forKey: Self.confirmChangesKey)
        }
    }

    /// Opt-in: also write the app log to `~/Library/Logs/VibeRes/` so a bug report
    /// can carry it. Off by default, and nothing in it ever leaves the Mac unless
    /// the user attaches it. `os.Logger` records regardless; this only adds the file.
    var debugLogEnabled: Bool {
        didSet {
            UserDefaults.standard.set(debugLogEnabled, forKey: Self.debugLogEnabledKey)
            applyDebugLog()
        }
    }

    /// How much the debug log file records. Info by default: state changes and
    /// failures, without the per-refresh chatter of `.debug`.
    var debugLogLevel: LogLevel {
        didSet {
            UserDefaults.standard.set(debugLogLevel.rawValue, forKey: Self.debugLogLevelKey)
            applyDebugLog()
        }
    }

    /// Global shortcut for Revert. `nil` until the user records one or takes
    /// the suggestion in Settings: VibeRes never claims a key combination
    /// nobody asked it to.
    var revertHotkey: KeyCombo? {
        didSet {
            if let revertHotkey, let data = try? JSONEncoder().encode(revertHotkey) {
                UserDefaults.standard.set(data, forKey: Self.revertHotkeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.revertHotkeyKey)
            }
        }
    }

    /// The sink the debug log choice drives; nil writes no file whatever the toggle says.
    private let logSink: LogSink?

    private func applyDebugLog() {
        logSink?.configure(enabled: debugLogEnabled, verbosity: debugLogLevel)
    }

    /// The confirmation setting at launch, settled once and written down.
    ///
    /// A stored answer wins. Without one, a fresh install (no welcome tour
    /// finished yet) gets the new default, on, and an install that has been
    /// through the tour keeps the old one, off. The result is persisted so the
    /// answer does not flip once the tour sets `onboardingShown`.
    ///
    /// Any value counts as an answer, read through `bool(forKey:)`: a launch
    /// argument such as `-VibeRes.ConfirmDisplayChanges NO` (the screenshot and
    /// demo scripts pass one) arrives as the string "NO", which `as? Bool`
    /// would miss, and the fallback would then persist a default over it.
    static func initialConfirmDisplayChanges(_ defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: confirmChangesKey) != nil {
            return defaults.bool(forKey: confirmChangesKey)
        }
        let freshInstall = defaults.object(forKey: onboardingShownKey) == nil
        defaults.set(freshInstall, forKey: confirmChangesKey)
        return freshInstall
    }

    init(logSink: LogSink? = nil) {
        self.logSink = logSink
        self.confirmDisplayChanges = Self.initialConfirmDisplayChanges(UserDefaults.standard)
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
        self.debugLogEnabled = UserDefaults.standard.bool(forKey: Self.debugLogEnabledKey)
        self.debugLogLevel = (UserDefaults.standard.object(forKey: Self.debugLogLevelKey) as? Int)
            .flatMap(LogLevel.init(rawValue:)) ?? .info
        // Unreadable data reads as "no shortcut" rather than taking a guess.
        self.revertHotkey = UserDefaults.standard.data(forKey: Self.revertHotkeyKey)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
        // didSet does not run in init, so hand the stored choice to the sink here.
        applyDebugLog()
    }
}
