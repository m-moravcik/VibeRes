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

    init() {
        if UserDefaults.standard.object(forKey: Self.autoApplyKey) == nil {
            self.autoApplyOnDisplayChange = true
        } else {
            self.autoApplyOnDisplayChange = UserDefaults.standard.bool(forKey: Self.autoApplyKey)
        }
        // Live preview is opt-in: never trigger the permission dialog unless
        // the user explicitly enables it.
        self.livePreviewEnabled = UserDefaults.standard.bool(forKey: Self.livePreviewKey)
        // Simple Mode is on by default for fresh installs — non-tech users
        // get the cleanest decision surface. Existing users keep whichever
        // value they previously had (defaults to false the first time we
        // ship this key).
        if UserDefaults.standard.object(forKey: Self.simpleModeKey) == nil {
            self.simpleMode = true
        } else {
            self.simpleMode = UserDefaults.standard.bool(forKey: Self.simpleModeKey)
        }
    }
}
