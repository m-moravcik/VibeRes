import CoreGraphics
import Foundation

/// How a profile entry binds to a live display when applied. Three flavours
/// cover the realistic use-cases without exposing "matcher" jargon to the user.
enum DisplayMatcher: Hashable {
    /// Default. Locked to one specific physical monitor by EDID identifiers.
    /// "PosAm Desk" — applies only when the same Q3279WG5B is connected.
    case edid(vendor: UInt32, model: UInt32, serial: UInt32)

    /// Match any non-built-in display. Lets a profile travel — useful for
    /// "Presentation" mode where you want a fixed point-size on whatever
    /// external monitor (projector, TV, hotel screen) happens to be hooked up.
    case anyExternal

    /// Match the built-in display by its EDID. We always know the built-in
    /// is the same physical panel, but storing identity keeps the matcher
    /// uniform and re-bindable across MacBook trades-in.
    case builtIn(vendor: UInt32, model: UInt32, serial: UInt32)

    /// Returns true if this matcher would bind to the given live display.
    func matches(_ id: CGDirectDisplayID) -> Bool {
        switch self {
        case let .edid(vendor, model, serial):
            return CGDisplayVendorNumber(id) == vendor
                && CGDisplayModelNumber(id) == model
                && CGDisplaySerialNumber(id) == serial
        case .anyExternal:
            return CGDisplayIsBuiltin(id) == 0
        case let .builtIn(vendor, model, serial):
            return CGDisplayIsBuiltin(id) != 0
                && CGDisplayVendorNumber(id) == vendor
                && CGDisplayModelNumber(id) == model
                && CGDisplaySerialNumber(id) == serial
        }
    }
}

/// Codable representation of DisplayMatcher. Includes a "kind" discriminator
/// and the EDID fields. Backwards compatible: when reading old Profile.Entry
/// JSON that lacks `matcher`, the decoder synthesises an `.edid` matcher from
/// the legacy displayVendor/Model/Serial fields.
extension DisplayMatcher: Codable {
    private enum Kind: String, Codable {
        case edid, anyExternal, builtIn
    }

    private enum CodingKeys: String, CodingKey {
        case kind, vendor, model, serial
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .edid:
            self = .edid(
                vendor: try c.decode(UInt32.self, forKey: .vendor),
                model: try c.decode(UInt32.self, forKey: .model),
                serial: try c.decode(UInt32.self, forKey: .serial)
            )
        case .anyExternal:
            self = .anyExternal
        case .builtIn:
            self = .builtIn(
                vendor: try c.decode(UInt32.self, forKey: .vendor),
                model: try c.decode(UInt32.self, forKey: .model),
                serial: try c.decode(UInt32.self, forKey: .serial)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .edid(vendor, model, serial):
            try c.encode(Kind.edid, forKey: .kind)
            try c.encode(vendor, forKey: .vendor)
            try c.encode(model, forKey: .model)
            try c.encode(serial, forKey: .serial)
        case .anyExternal:
            try c.encode(Kind.anyExternal, forKey: .kind)
        case let .builtIn(vendor, model, serial):
            try c.encode(Kind.builtIn, forKey: .kind)
            try c.encode(vendor, forKey: .vendor)
            try c.encode(model, forKey: .model)
            try c.encode(serial, forKey: .serial)
        }
    }
}

/// A named, multi-display resolution preset. "PosAm Desk" — both monitors;
/// "Presentation" — built-in + any external; "Code Mode" — just the built-in.
struct Profile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var entries: [Entry]
    var createdAt: Date

    /// Per-display target. The matcher decides which live display this entry
    /// applies to; the resolution fields decide what mode to switch it into.
    struct Entry: Codable, Hashable {
        var matcher: DisplayMatcher
        /// Snapshotted localized name at save time, for UI display only
        /// (e.g. shown in error messages and the save dialog preview).
        var displayName: String
        var pointWidth: Int
        var pointHeight: Int
        var refreshHz: Int?
        var isHiDPI: Bool

        // Backward compatibility: old JSON had displayVendor/Model/Serial as
        // top-level fields and no `matcher`. Detect that shape and rebuild.
        private enum CodingKeys: String, CodingKey {
            case matcher, displayName, pointWidth, pointHeight, refreshHz, isHiDPI
            // Legacy keys:
            case displayVendor, displayModel, displaySerial
        }

        init(
            matcher: DisplayMatcher,
            displayName: String,
            pointWidth: Int,
            pointHeight: Int,
            refreshHz: Int?,
            isHiDPI: Bool
        ) {
            self.matcher = matcher
            self.displayName = displayName
            self.pointWidth = pointWidth
            self.pointHeight = pointHeight
            self.refreshHz = refreshHz
            self.isHiDPI = isHiDPI
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.displayName = try c.decode(String.self, forKey: .displayName)
            self.pointWidth = try c.decode(Int.self, forKey: .pointWidth)
            self.pointHeight = try c.decode(Int.self, forKey: .pointHeight)
            self.refreshHz = try c.decodeIfPresent(Int.self, forKey: .refreshHz)
            self.isHiDPI = try c.decode(Bool.self, forKey: .isHiDPI)

            if let m = try c.decodeIfPresent(DisplayMatcher.self, forKey: .matcher) {
                self.matcher = m
            } else {
                // Legacy format — synthesise an .edid matcher from the loose fields.
                let vendor = try c.decode(UInt32.self, forKey: .displayVendor)
                let model = try c.decode(UInt32.self, forKey: .displayModel)
                let serial = try c.decode(UInt32.self, forKey: .displaySerial)
                self.matcher = .edid(vendor: vendor, model: model, serial: serial)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(matcher, forKey: .matcher)
            try c.encode(displayName, forKey: .displayName)
            try c.encode(pointWidth, forKey: .pointWidth)
            try c.encode(pointHeight, forKey: .pointHeight)
            try c.encodeIfPresent(refreshHz, forKey: .refreshHz)
            try c.encode(isHiDPI, forKey: .isHiDPI)
        }
    }

    /// True when applying this profile would touch any display currently connected.
    func hasMatchingDisplay(in displays: [DisplayInfo]) -> Bool {
        entries.contains { entry in
            displays.contains { entry.matcher.matches($0.id) }
        }
    }

    /// One-line description for tooltips: "Built-in only" / "Built-in + any external" /
    /// "Built-in + Q3279WG5B" so users can hover a pill and see what it'll touch.
    var humanSummary: String {
        let parts = entries.map { entry -> String in
            switch entry.matcher {
            case .builtIn: return "Built-in"
            case .anyExternal: return "any external"
            case .edid: return entry.displayName
            }
        }
        return parts.joined(separator: " + ")
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
