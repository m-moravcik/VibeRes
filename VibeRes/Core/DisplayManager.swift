import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let modes: [CGDisplayMode]
    let currentMode: CGDisplayMode?

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id
            && lhs.currentMode?.ioDisplayModeID == rhs.currentMode?.ioDisplayModeID
            && lhs.modes.map(\.ioDisplayModeID) == rhs.modes.map(\.ioDisplayModeID)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(currentMode?.ioDisplayModeID ?? 0)
    }
}

enum DisplayManager {
    /// Returns every active display with its full list of modes (including HiDPI scaled variants).
    static func snapshot() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        let mainID = CGMainDisplayID()
        return ids.map { id in
            DisplayInfo(
                id: id,
                name: name(for: id),
                isMain: id == mainID,
                modes: usableModes(for: id),
                currentMode: CGDisplayCopyDisplayMode(id)
            )
        }
    }

    /// Public API option dictionary that unlocks scaled HiDPI modes hidden from the default call.
    private static func usableModes(for id: CGDirectDisplayID) -> [CGDisplayMode] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let raw = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else {
            return []
        }
        return raw.filter { $0.isUsableForDesktopGUI() }
    }

    /// Best-effort localized display name. macOS 26 exposes `CGDisplayCopyDisplayName`
    /// on Apple Silicon; we fall back to a generic label otherwise.
    private static func name(for id: CGDirectDisplayID) -> String {
        if id == CGMainDisplayID() {
            return "Built-in / Main Display"
        }
        return "Display \(id)"
    }
}
