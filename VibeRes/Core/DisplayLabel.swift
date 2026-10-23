import CoreGraphics
import Foundation

/// How a display appears in the debug log file and the copied diagnostics.
///
/// Never the display's name: `NSScreen.localizedName` can be one the user gave
/// an AirPlay or Sidecar receiver ("Jane's iPad"). Instead a stable label plus
/// the EDID manufacturer (3-letter PNP ID) and product code, enough to look the
/// model up: "Built-in display (APP A0A1)", "External display 2 (GSM 5B71)".
/// Serial numbers are never read. The name may still go to `os.Logger` through
/// a log call's private `detail`.
enum DisplayLabel {
    static func label(for id: CGDirectDisplayID) -> String {
        label(id: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
              vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id))
    }

    /// Without EDID codes (a virtual or unknown display) the label stands alone.
    static func label(id: CGDirectDisplayID, isBuiltIn: Bool, vendor: UInt32, model: UInt32) -> String {
        let base = isBuiltIn ? "Built-in display" : "External display \(id)"
        guard let pnp = pnpID(vendor) else { return base }
        return "\(base) (\(pnp) \(String(format: "%04X", model)))"
    }

    /// Decodes an EDID manufacturer ID: three 5-bit letters, 1 = "A", packed
    /// into the low 15 bits. Nil for anything that is not such a code.
    static func pnpID(_ vendor: UInt32) -> String? {
        guard vendor <= 0x7FFF else { return nil }
        let letters = [(vendor >> 10) & 0x1F, (vendor >> 5) & 0x1F, vendor & 0x1F]
        guard letters.allSatisfy({ (1...26).contains($0) }) else { return nil }
        return String(letters.map { Character(UnicodeScalar(UInt8(64 + $0))) })
    }
}
