import Foundation

/// "1920×1080 · 120 Hz VRR · HiDPI": how the profile forms name a mode. One
/// function for the save form and the edit form, so the two cannot drift;
/// the save form used to write "120Hz" next to the edit form's "120 Hz".
enum ModeSummary {
    static func text(width: Int, height: Int, refreshHz: Int?, isVRR: Bool, isHiDPI: Bool) -> String {
        var parts = ["\(width)×\(height)"]
        if let refreshHz { parts.append(isVRR ? "\(refreshHz) Hz VRR" : "\(refreshHz) Hz") }
        if isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }
}
