import Foundation

/// "1 920 × 1 080 · 120 Hz VRR · HiDPI": how the profile forms name a mode.
/// A thin wrapper over `ModeFormat`, which every other surface uses too.
enum ModeSummary {
    static func text(width: Int, height: Int, refreshHz: Int?, isVRR: Bool, isHiDPI: Bool) -> String {
        ModeFormat.mode(width: width, height: height, hz: refreshHz, vrr: isVRR, hiDPI: isHiDPI)
    }
}
