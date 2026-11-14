import AppKit
import SwiftUI
import Testing
@testable import VibeRes

/// The bar that drains under "Keep this resolution? Reverting in Ns", measured
/// in the pixels of the real row rendered offscreen. The expected widths come
/// from the countdown's contract (a linear drain over the 12 s window, empty
/// at the deadline, and seconds / window under Reduce Motion), not from the
/// view's own arithmetic. Nothing here arms a countdown that can expire or
/// applies a mode: the store's apply seam is stubbed.
@Suite("Confirmation row's draining bar", .serialized)
@MainActor
struct ConfirmationRowRenderTests {
    private static let rowWidth: CGFloat = 320
    private static let window = Double(DisplayStore.confirmationWindowSeconds)

    /// A window of the confirmation's length that reverts `left` seconds from
    /// now.
    private func window(left: TimeInterval) -> RevertCountdown.Window {
        .init(deadline: Date().addingTimeInterval(left), length: Self.window)
    }

    /// The bar keeps sliding while the row renders, however long the host
    /// takes, so it must sit between the time left on a clock reverting at
    /// `deadline` when the row was built and when its pixels were captured.
    /// The slack covers pixel rounding at the bar's end.
    private func expectDrained(_ shot: Shot, deadline: Date, builtAt: Date,
                               sourceLocation: SourceLocation = #_sourceLocation) {
        let atBuild = deadline.timeIntervalSince(builtAt) / Self.window
        let atCapture = deadline.timeIntervalSince(shot.capturedAt) / Self.window
        #expect(shot.barShare <= atBuild + 0.02 && shot.barShare >= atCapture - 0.02,
                "bar share \(shot.barShare), expected \(atCapture)...\(atBuild)",
                sourceLocation: sourceLocation)
    }

    @Test("The bar follows the continuous time left, not the whole seconds",
          arguments: [ColorScheme.light, .dark])
    func slidesWithContinuousFraction(scheme: ColorScheme) throws {
        // 7 s on the label but half the window on the clock: a bar that
        // stepped with the digits would read 7/12, not at most 1/2.
        let builtAt = Date()
        let deadline = builtAt.addingTimeInterval(6)
        let row = ConfirmationRow(seconds: 7, window: .init(deadline: deadline, length: Self.window), keep: {})
        let shot = try render(row, scheme: scheme, name: "continuous-half")
        expectDrained(shot, deadline: deadline, builtAt: builtAt)
    }

    @Test("Past the deadline the fading row reads empty, not the last rounded-up second")
    func expiryReadsEmpty() throws {
        // The 500 ms tick reverts up to half a second late, while the label
        // still says 1s. The row fading out then must not grow a 1/12 bar.
        let shot = try render(ConfirmationRow(seconds: 1, window: window(left: -0.3), keep: {}),
                              scheme: .light, name: "after-expiry")
        #expect(shot.barShare < 0.01, "bar share \(shot.barShare)")
    }

    @Test("Under Reduce Motion the bar steps with the digits")
    func reduceMotionSteps() throws {
        // The clock says 0.9 of the window; Reduce Motion must ignore it and
        // show 6 of 12 seconds.
        let row = ConfirmationRow(seconds: 6, window: window(left: 0.9 * Self.window), keep: {})
        let shot = try render(row, scheme: .light, reduceMotion: true, name: "reduce-motion-6s")
        #expect(abs(shot.barShare - 0.5) < 0.03, "bar share \(shot.barShare)")
    }

    @Test("A real countdown drains the bar linearly over the window",
          arguments: [3.0, 6.0, 9.0])
    func drainsOverWindow(elapsed: Double) throws {
        var countdown = RevertCountdown()
        let builtAt = Date()
        let armedAt = builtAt.addingTimeInterval(-elapsed)
        countdown.arm(at: armedAt, seconds: DisplayStore.confirmationWindowSeconds)
        let seconds = Int((Self.window - elapsed).rounded(.up))
        let shot = try render(
            ConfirmationRow(seconds: seconds, window: try #require(countdown.window), keep: {}),
            scheme: .light, name: "drain-\(Int(elapsed))s-elapsed"
        )
        expectDrained(shot, deadline: armedAt.addingTimeInterval(Self.window), builtAt: builtAt)
    }

    @Test("The clock symbol takes the warning tint", arguments: [ColorScheme.light, .dark])
    func clockIsTinted(scheme: ColorScheme) throws {
        let shot = try render(ConfirmationRow(seconds: 7, window: window(left: 7), keep: {}),
                              scheme: scheme, name: "clock")
        #expect(shot.tintedPixelsLeftOfText > 10, "orange pixels in the clock area: \(shot.tintedPixelsLeftOfText)")
    }

    @Test("Through the store: armed reads full, Keep commits once and the fading row keeps draining")
    func storeWiring() throws {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        let mode = try #require(modes?.first, "no display mode on this machine")
        let store = DisplayStore.forTesting()
        var commits: [CGConfigureOption] = []
        store.applyMode = { _, _, option in commits.append(option) }
        // Display 101 is no real display; the apply seam is stubbed anyway.
        let armedAt = Date()
        store.armConfirmationForTesting(mode: mode, display: 101)
        defer { store.endPendingConfirmation() }

        let now = Date()
        let window = try #require(store.confirmationWindow)
        #expect(window.length == Self.window)
        #expect(window.fractionRemaining(at: now) > 0.98)
        #expect(abs(window.fractionRemaining(at: now.addingTimeInterval(Self.window / 2)) - 0.5) < 0.02)

        // The clock armed for the 12 s window when the store was asked to.
        let deadline = armedAt.addingTimeInterval(Self.window)
        let seconds = try #require(store.confirmationSecondsRemaining)
        let armedBuiltAt = Date()
        let armed = try render(
            ConfirmationRow(seconds: seconds, window: window, keep: store.confirmDisplayChange),
            scheme: .light, name: "store-armed"
        )
        expectDrained(armed, deadline: deadline, builtAt: armedBuiltAt)

        store.confirmDisplayChange()
        #expect(commits.count == 1)
        #expect(store.confirmationSecondsRemaining == nil)
        #expect(store.confirmationWindow == nil)

        // The row as it fades out keeps the window it was built with, so its
        // bar still shows the time left on the armed clock rather than snapping.
        let fadingBuiltAt = Date()
        let fading = try render(
            ConfirmationRow(seconds: seconds, window: window, keep: {}),
            scheme: .light, name: "store-after-keep"
        )
        expectDrained(fading, deadline: deadline, builtAt: fadingBuiltAt)
    }

    // MARK: - Rendering

    private struct Shot {
        /// The width of the tinted run along the row's bottom edge, as a share
        /// of the row's width.
        var barShare: Double
        /// Tinted pixels in the leading 32 pt above the bar, where the clock sits.
        var tintedPixelsLeftOfText: Int
        /// When the pixels were taken; the frame they show is no later.
        var capturedAt: Date
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
        let capturedAt = Date()
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
        return Shot(barShare: Double(run) / Double(width), tintedPixelsLeftOfText: clock,
                    capturedAt: capturedAt)
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
