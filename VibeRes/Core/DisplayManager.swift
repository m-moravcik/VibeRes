import AppKit
import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable, Hashable, @unchecked Sendable {
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

    /// Localized display name as macOS shows it in System Settings → Displays
    /// ("Studio Display", "LG UltraFine", "Built-in Retina Display"). The mapping
    /// goes through NSScreen because CoreGraphics has no public name API; NSScreen
    /// pulls the name from EDID + macOS's display database.
    private static func name(for id: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            return (screen.deviceDescription[key] as? NSNumber)?.uint32Value == id
        }) {
            return screen.localizedName
        }
        // Fallback for displays not visible to AppKit (rare; e.g. mid-reconfiguration).
        return CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "External Display"
    }
}
