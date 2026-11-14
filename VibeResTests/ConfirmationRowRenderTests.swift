import AppKit
import SwiftUI
import Testing
@testable import VibeRes

/// The bar that drains under "Keep this resolution? Reverting in Ns", measured
/// in the pixels of the real row rendered offscreen. The expected widths come
/// from the countdown's contract (a linear drain over the 12 s window, and
/// seconds / window whenever there is no continuous fraction to draw), not from
/// the view's own arithmetic. Nothing here arms a countdown that can expire or
/// applies a mode: the store's apply seam is stubbed.
@Suite("Confirmation row's draining bar", .serialized)
@MainActor
struct ConfirmationRowRenderTests {
    private static let rowWidth: CGFloat = 320
    private static let window = Double(DisplayStore.confirmationWindowSeconds)

    @Test("The bar follows the continuous fraction, not the whole seconds",
          arguments: [ColorScheme.light, .dark])
    func slidesWithContinuousFraction(scheme: ColorScheme) throws {
        // 7 s on the label but half the window on the clock: a bar that
        // stepped with the digits would read 7/12, not 1/2.
        let shot = try render(ConfirmationRow(seconds: 7, fractionRemaining: { _ in 0.5 }, keep: {}),
                              scheme: scheme, name: "continuous-half")
        #expect(abs(shot.barShare - 0.5) < 0.03, "bar share \(shot.barShare)")
    }

    @Test("Once Keep ends the countdown, the fading row holds the last second's share")
    func keepHoldsLastSecond() throws {
        // fractionRemaining is nil after Keep; the bar must read 3/12, not snap
        // to empty while the row fades.
        let shot = try render(ConfirmationRow(seconds: 3, fractionRemaining: { _ in nil }, keep: {}),
                              scheme: .light, name: "after-keep-3s")
        #expect(abs(shot.barShare - 3 / Self.window) < 0.03, "bar share \(shot.barShare)")
    }

    @Test("Under Reduce Motion the bar steps with the digits")
    func reduceMotionSteps() throws {
        // The continuous fraction says 0.9; Reduce Motion must ignore it and
        // show 6 of 12 seconds.
        let row = ConfirmationRow(seconds: 6, fractionRemaining: { _ in 0.9 }, keep: {})
        let shot = try render(row, scheme: .light, reduceMotion: true, name: "reduce-motion-6s")
        #expect(abs(shot.barShare - 0.5) < 0.03, "bar share \(shot.barShare)")
    }

    @Test("A real countdown drains the bar linearly over the window",
          arguments: [3.0, 6.0, 9.0])
    func drainsOverWindow(elapsed: Double) throws {
        var countdown = RevertCountdown()
        countdown.arm(at: Date().addingTimeInterval(-elapsed), seconds: DisplayStore.confirmationWindowSeconds)
        let seconds = Int((Self.window - elapsed).rounded(.up))
        let shot = try render(
            ConfirmationRow(seconds: seconds, fractionRemaining: { countdown.fractionRemaining(at: $0) }, keep: {}),
            scheme: .light, name: "drain-\(Int(elapsed))s-elapsed"
        )
        // Rendering takes a fraction of a second after arming, so allow a
        // little more drain than the nominal share.
        let expected = 1 - elapsed / Self.window
        #expect(shot.barShare <= expected + 0.02 && shot.barShare >= expected - 0.06, "bar share \(shot.barShare)")
    }

    @Test("The clock symbol takes the warning tint", arguments: [ColorScheme.light, .dark])
    func clockIsTinted(scheme: ColorScheme) throws {
        let shot = try render(ConfirmationRow(seconds: 7, fractionRemaining: { _ in 7.0 / 12 }, keep: {}),
                              scheme: scheme, name: "clock")
        #expect(shot.tintedPixelsLeftOfText > 10, "orange pixels in the clock area: \(shot.tintedPixelsLeftOfText)")
    }

    @Test("Through the store: armed reads full, Keep commits once and the row keeps its bar")
    func storeWiring() throws {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        let mode = try #require(modes?.first, "no display mode on this machine")
        let store = DisplayStore.forTesting()
        var commits: [CGConfigureOption] = []
        store.applyMode = { _, _, option in commits.append(option) }
        // Display 101 is no real display; the apply seam is stubbed anyway.
        store.armConfirmationForTesting(mode: mode, display: 101)
        defer { store.endPendingConfirmation() }

        let now = Date()
        let atArm = try #require(store.confirmationFractionRemaining(at: now))
        #expect(atArm > 0.98)
        let halfway = try #require(store.confirmationFractionRemaining(at: now.addingTimeInterval(Self.window / 2)))
        #expect(abs(halfway - 0.5) < 0.02)

        let seconds = try #require(store.confirmationSecondsRemaining)
        let armed = try render(
            ConfirmationRow(seconds: seconds, fractionRemaining: store.confirmationFractionRemaining(at:),
                            keep: store.confirmDisplayChange),
            scheme: .light, name: "store-armed"
        )
        #expect(armed.barShare > 0.9, "bar share \(armed.barShare)")

        store.confirmDisplayChange()
        #expect(commits.count == 1)
        #expect(store.confirmationSecondsRemaining == nil)
        #expect(store.confirmationFractionRemaining(at: Date()) == nil)

        // The row as it fades out: still showing the last seconds it had.
        let fading = try render(
            ConfirmationRow(seconds: seconds, fractionRemaining: store.confirmationFractionRemaining(at:), keep: {}),
            scheme: .light, name: "store-after-keep"
        )
        #expect(abs(fading.barShare - Double(seconds) / Self.window) < 0.03, "bar share \(fading.barShare)")
    }

    // MARK: - Rendering

    private struct Shot {
        /// The width of the tinted run along the row's bottom edge, as a share
        /// of the row's width.
        var barShare: Double
        /// Tinted pixels in the leading 32 pt above the bar, where the clock sits.
        var tintedPixelsLeftOfText: Int
    }

    /// Renders with Reduce Motion pinned to `reduceMotion` whatever the host
    /// says: CI runners have it on, a developer's Mac usually has it off.
    private func render(_ row: some View, scheme: ColorScheme, reduceMotion: Bool = false,
                        name: String) throws -> Shot {
        // The environment value is read-only, so stand in for the system
        // setting inside this process only; the Mac's own setting is never
        // touched.
        let restore = ReduceMotionOverride.install(reduceMotion)
        defer { restore() }
        #expect(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == reduceMotion)
        let view = row
            .frame(width: Self.rowWidth)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en"))
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: Self.rowWidth, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
        }
        hosting.layoutSubtreeIfNeeded()

        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let file = "countdown-\(name)-\(scheme == .dark ? "dark" : "light").png"
        Attachment.record(png, named: file)
        if let dir = ProcessInfo.processInfo.environment["VIBERES_EVIDENCE"], !dir.isEmpty {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let scale = Double(width) / Double(Self.rowWidth)
        // The widest tinted run from the leading edge among the bottom rows
        // the 2 pt bar covers.
        var run = 0
        for y in max(0, height - Int(2 * scale))..<height {
            var x = 0
            while x < width, isTint(bitmap.colorAt(x: x, y: y)) { x += 1 }
            run = max(run, x)
        }
        var clock = 0
        for y in 0..<max(0, height - Int(3 * scale)) {
            for x in 0..<min(width, Int(32 * scale)) where isTint(bitmap.colorAt(x: x, y: y)) {
                clock += 1
            }
        }
        return Shot(barShare: Double(run) / Double(width), tintedPixelsLeftOfText: clock)
    }

    /// System orange in either appearance, and not the 12 % wash behind the row.
    private func isTint(_ color: NSColor?) -> Bool {
        guard let c = color?.usingColorSpace(.sRGB) else { return false }
        return c.redComponent > 0.85 && (0.45...0.75).contains(c.greenComponent) && c.blueComponent < 0.45
    }
}

/// Makes `NSWorkspace.accessibilityDisplayShouldReduceMotion` answer `value`
/// in this test process until the returned closure runs.
@MainActor
private enum ReduceMotionOverride {
    static func install(_ value: Bool) -> () -> Void {
        let cls: AnyClass = NSWorkspace.self
        let selector = #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion)
        guard let method = class_getInstanceMethod(cls, selector) else { return {} }
        let block: @convention(block) (AnyObject) -> Bool = { _ in value }
        let original = method_setImplementation(method, imp_implementationWithBlock(block))
        NotificationCenter.default.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        return {
            method_setImplementation(method, original)
            NotificationCenter.default.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        }
    }
}
