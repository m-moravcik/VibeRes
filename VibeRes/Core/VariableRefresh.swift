import CoreGraphics
import Darwin
import Foundation

/// Variable refresh rate (Adaptive Sync, FreeSync, ProMotion) support.
///
/// Public CoreGraphics cannot tell a VRR mode from a fixed one. With Adaptive
/// Sync on, macOS marks the panel's top-rate modes as VRR and they share
/// width, height, pixel size and `refreshRate` with a fixed twin; `ioFlags`
/// does not differ either. Bucketing by rounded Hz therefore collapsed
/// "Variable (48-160 Hz)" and "160 Hz" into one chip, keeping whichever came
/// last, and Simple Mode's "highest rate" turned a user's variable setting
/// into fixed 160 Hz (issue #7).
///
/// The one reliable source is SkyLight's `SLSIsDisplayModeVRR`, resolved at
/// runtime so a macOS that drops it degrades to exactly the behaviour before
/// VRR support: every mode fixed. Everything else in this file is pure and
/// takes the answer as an `isVariable` closure, so it is tested with stub
/// modes rather than with whatever panel the test machine happens to have.
enum VariableRefresh {
    /// Whether mode `modeID` (`CGDisplayModeGetIODisplayModeID`) of a display
    /// is a variable refresh mode, as SkyLight says; false for every mode when
    /// the symbol is gone. On Intel Macs the call bounds-checks and answers
    /// false for every mode. Called once per mode per snapshot
    /// (`DisplayManager.snapshot`), never from a view.
    static func isVariable(display: CGDirectDisplayID, modeID: Int32) -> Bool {
        guard let isVRR = SkyLight.isDisplayModeVRR else { return false }
        return isVRR(Int32(bitPattern: display), modeID)
    }

    /// True when `modes` also holds a *fixed* mode at the same point size,
    /// scale and rounded rate as `mode`. Only then is "VRR" a choice the user
    /// has to be shown: a ProMotion panel's 120 Hz modes are all variable and
    /// have no fixed twin, so they stay plain "120".
    static func hasFixedTwin<Mode: DisplayModeProtocol>(
        _ mode: Mode,
        in modes: [Mode],
        isVariable: (Mode) -> Bool
    ) -> Bool {
        modes.contains {
            !isVariable($0)
                && $0.width == mode.width
                && $0.height == mode.height
                && $0.isHiDPI == mode.isHiDPI
                && $0.refreshHz == mode.refreshHz
        }
    }

    /// Whether a mode honours the refresh kind a saved entry asked for.
    ///
    /// Asymmetric on purpose. A variable entry is honoured only by a variable
    /// mode. A fixed entry is the shape of every profile saved before VRR
    /// support, so "fixed" also means "unknown": it is honoured by a fixed
    /// mode, and by a variable one that has no fixed twin, because there was
    /// never a fixed mode to prefer. Otherwise every ProMotion profile would
    /// read as a fallback and never as active.
    static func honoursKind(
        wantsVariable: Bool,
        modeIsVariable: Bool,
        modeHasFixedTwin: Bool
    ) -> Bool {
        wantsVariable ? modeIsVariable : (!modeIsVariable || !modeHasFixedTwin)
    }

    /// The rate a one-click apply should pick among a size's options.
    ///
    /// A display running a variable mode stays variable when the size offers
    /// one: "the highest rate" would silently swap Adaptive Sync for a fixed
    /// 160 Hz. Otherwise the highest rate wins, as it always has, and a tie
    /// between a fixed and a variable option at that rate goes to the fixed
    /// one, because the display is on a fixed rate now.
    ///
    /// Returns an index into `rates` so callers keep their own element type.
    static func preferredIndex(
        _ rates: [(hz: Int, isVariable: Bool)],
        stayVariable: Bool
    ) -> Int? {
        if stayVariable,
           let variable = rates.indices.filter({ rates[$0].isVariable })
               .max(by: { rates[$0].hz < rates[$1].hz }) {
            return variable
        }
        return rates.indices.max { lhs, rhs in
            let l = rates[lhs], r = rates[rhs]
            if l.hz != r.hz { return l.hz < r.hz }
            // Ordered so the fixed option of a tie is the maximum.
            return l.isVariable && !r.isVariable
        }
    }
}

/// The dynamically resolved SkyLight entry point.
///
/// `@unchecked Sendable` because a C function pointer resolved once and never
/// written again is safe to share; Swift just has no way to say so for a
/// `@convention(c)` value.
private enum SkyLight {
    typealias IsDisplayModeVRR = @convention(c) (Int32, Int32) -> Bool

    private struct Resolved: @unchecked Sendable {
        let function: IsDisplayModeVRR?
    }

    /// Resolved on first use. SkyLight is already mapped into any process that
    /// talks to the window server, so `dlopen` only hands back a handle; it is
    /// deliberately never closed.
    private static let resolved: Resolved = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "SLSIsDisplayModeVRR")
        else { return Resolved(function: nil) }
        return Resolved(function: unsafeBitCast(symbol, to: IsDisplayModeVRR.self))
    }()

    static var isDisplayModeVRR: IsDisplayModeVRR? { resolved.function }
}
