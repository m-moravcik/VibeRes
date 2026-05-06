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

    init() {
        if UserDefaults.standard.object(forKey: Self.autoApplyKey) == nil {
            self.autoApplyOnDisplayChange = true
        } else {
            self.autoApplyOnDisplayChange = UserDefaults.standard.bool(forKey: Self.autoApplyKey)
        }
        // Live preview is opt-in: never trigger the permission dialog unless
        // the user explicitly enables it.
        self.livePreviewEnabled = UserDefaults.standard.bool(forKey: Self.livePreviewKey)
    }
}
