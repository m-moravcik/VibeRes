import CoreGraphics
import Foundation

/// A named, multi-display resolution preset. "Presentation Mode" → MacBook to 1280×800,
/// external to 1920×1080. Saved to disk so they survive restarts and reboots.
struct Profile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var entries: [Entry]
    var createdAt: Date

    /// Per-display target. Identifies the display by EDID-derived numbers
    /// (vendor + model + serial) so the profile re-matches the same physical
    /// monitor across reconnects, even when CGDirectDisplayID rotates.
    struct Entry: Codable, Hashable {
        var displayVendor: UInt32
        var displayModel: UInt32
        var displaySerial: UInt32
        /// Snapshotted localized name at save time, for UI display only.
        var displayName: String
        var pointWidth: Int
        var pointHeight: Int
        var refreshHz: Int?
        var isHiDPI: Bool
    }

    init(id: UUID = UUID(), name: String, entries: [Entry], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
    }
}

/// Captures EDID identifiers we use to re-bind a Profile.Entry to a live CGDirectDisplayID
/// on apply. CGDisplaySerialNumber + Vendor + Model uniquely identify a physical display
/// on the user's setup, and survive USB-C reconnects.
struct DisplayIdentity: Hashable, Codable {
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32

    static func capture(_ id: CGDirectDisplayID) -> DisplayIdentity {
        DisplayIdentity(
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id)
        )
    }
}
