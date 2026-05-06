import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable, Hashable, @unchecked Sendable {
    let id: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let modes: [CGDisplayMode]
    let currentMode: CGDisplayMode?
    /// Pre-computed bucketed groups so the UI doesn't re-bucket on every render.
    /// Built once during snapshot, stable across body recomputations.
    let groups: [ResolutionGroup]

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
    /// Cap on simultaneously-active displays we'll honour. macOS supports more in theory,
    /// but a sane upper bound prevents pathological allocations if `CGGetActiveDisplayList`
    /// returns a corrupt count.
    private static let maxDisplays: UInt32 = 32

    /// Returns every active display with its full list of modes (including HiDPI scaled variants)
    /// plus pre-bucketed `ResolutionGroup`s so the UI doesn't re-bucket on every render.
    static func snapshot() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        guard count <= maxDisplays else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        let mainID = CGMainDisplayID()
        return ids.map { id in
            let modes = usableModes(for: id)
            return DisplayInfo(
                id: id,
                name: name(for: id),
                isMain: id == mainID,
                modes: modes,
                currentMode: CGDisplayCopyDisplayMode(id),
                groups: ResolutionGroup.build(from: modes)
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

    /// Resolves the human-readable display name. Delegates to `DisplayNamer.resolve`,
    /// which the GUI app overrides at startup with an AppKit-backed implementation.
    /// CLI and tests use the Foundation-only fallback.
    private static func name(for id: CGDirectDisplayID) -> String {
        DisplayNamer.resolve(id)
    }
}
