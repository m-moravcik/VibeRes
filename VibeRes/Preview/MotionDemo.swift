#if DEBUG
import AppKit
import SwiftUI

/// Development harness: renders the README hero animation frame by frame.
/// Debug builds only; `scripts/motion-demo.sh` drives it and encodes the GIF.
///
/// The story is the app's one key moment: a click on a size in the display
/// detail, the screen coming back at the new size with everything on it
/// smaller (more space), and the menu bar icon's switch animation. Then the
/// same back again, so the loop is seamless.
///
/// Nothing is switched. The popover is the real `DisplayDetailView`, captured
/// off screen against this Mac's real display list, with the "current" mode
/// replaced through `DisplayStore.showForDemo`. The mode-applying seams are
/// rigged to abort the process, so a stray call cannot reach the displays.
/// Live preview must be off, so no desktop is ever captured. The desktop, the
/// menu bar strip, the window and the pointer are scenery; the menu bar icon is
/// `MenuBarIcon`'s own drawing at each frame's phase.
@MainActor
enum MotionDemo {
    static let environmentKey = "VIBERES_MOTION_DEMO"

    static var requestedOutput: URL? {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    // MARK: Timing

    static let fps = 30.0
    /// One switch: from one size to the other. The loop is two of them.
    nonisolated static let half = 4.0
    static var loop: Double { 2 * half }

    /// Beats of one half, in seconds from its start.
    enum Beat {
        /// The pointer moves from the current row to the target row.
        static let glide = 0.20...0.72
        /// The click. The app's icon animation starts here (`play()` runs as
        /// soon as `apply` returns) and takes `MenuBarIcon.duration`.
        static let click = 1.30
        static let press = 0.12
        /// The displays go dark while the mode is applied, and come back at
        /// the new size. Relative to the click.
        static let darkIn = 0.06...0.18
        static let swap = 0.30
        static let darkOut = 0.42...0.72
    }

    /// Stage, in points of the screen at the larger text size: the top-right
    /// corner of the built-in display.
    static let stage = CGSize(width: 560, height: 380)
    /// Render scale; the script downsamples to the GIF width with lanczos.
    static let renderScale: CGFloat = 3

    // MARK: Run

    static func run(into output: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        VibeResApp.installDisplayNamer()

        let displays = DisplayStore()
        // Belt and braces: nothing here calls `apply`, and if anything did,
        // the process dies before a display is touched.
        displays.applyMode = { _, _, _ in fail("the demo tried to apply a display mode") }
        displays.applyOrigins = { _, _ in fail("the demo tried to rearrange the displays") }
        displays.dismissStalePopoverOverride = {}

        let preferences = Preferences()
        guard !preferences.livePreviewEnabled else {
            fail("pass -VibeRes.LivePreviewEnabled NO: live preview would capture the real desktop")
        }

        let known = displays.displays
        guard let display = known.first(where: { CGDisplayIsBuiltin($0.id) != 0 }) else {
            fail("no active built-in display: open the lid and wake the screen")
        }
        let scaled = display.groups.filter(\.isHiDPI)
        let list = scaled.isEmpty ? display.groups : scaled
        guard list.count >= 3,
              let roomyMode = list[0].modesByRefresh.last?.mode,
              let largerTextMode = list[2].modesByRefresh.last?.mode
        else { fail("\(display.name) has too few sizes for the demo") }
        // A: larger text (where the loop starts), B: more space.
        let sizes = [list[2], list[0]]
        let modes = [largerTextMode, roomyMode]
        let screenScale = [1.0, Double(list[2].pointWidth) / Double(list[0].pointWidth)]

        func showing(_ mode: CGDisplayMode) -> [DisplayInfo] {
            known.map { info in
                guard info.id == display.id else { return info }
                return DisplayInfo(id: info.id, name: info.name, isMain: info.isMain,
                                   modes: info.modes, currentMode: mode, groups: info.groups,
                                   variableModeIDs: info.variableModeIDs)
            }
        }

        for scheme in [ColorScheme.light, .dark] {
            // The popover in every state the loop passes through: each current
            // size, with nothing or one row under the pointer.
            var states: [PopoverState] = []
            let rowRange = (list.firstIndex(of: sizes[1]) ?? 0)...(list.firstIndex(of: sizes[0]) ?? 2)
            for (index, mode) in modes.enumerated() {
                // Re-applied around every layout pass: the store's own refresh
                // (a retry after an empty launch snapshot, a wake) would put
                // the real list back.
                let snapshot = showing(mode)
                let hold = { displays.showForDemo(snapshot) }
                func capture(_ view: some View, scheme: ColorScheme) -> NSImage {
                    MotionDemo.capture(view, scheme: scheme, hold: hold)
                }
                let base = capture(detail(display.id, hovering: nil, displays, preferences), scheme: scheme)
                var rows: [Row] = []
                for groupIndex in rowRange where list[groupIndex] != sizes[index] {
                    let group = list[groupIndex]
                    let hovered = capture(detail(display.id, hovering: group.id, displays, preferences), scheme: scheme)
                    guard let band = hoverBand(base: base, hovered: hovered) else {
                        fail("could not find the row for \(group.id)")
                    }
                    rows.append(Row(groupID: group.id, band: band, image: hovered))
                }
                states.append(PopoverState(base: base, rows: rows))
            }
            // Where the pointer rests on each size's row: the band the other
            // state found for it. The layout does not move between states.
            guard let rowA = states[1].rows.first(where: { $0.groupID == sizes[0].id })?.band,
                  let rowB = states[0].rows.first(where: { $0.groupID == sizes[1].id })?.band
            else { fail("missing row bands") }
            let script = Script(rowY: [mid(rowA), mid(rowB)], screenScale: screenScale)

            let dir = output.appendingPathComponent(scheme == .dark ? "frames-dark" : "frames-light", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let count = Int((loop * fps).rounded())
                for frame in 0..<count {
                    let t = Double(frame) / fps
                    let f = script.frame(at: t, states: states)
                    let image = render(Stage(frame: f, scheme: scheme))
                    try write(image, to: dir.appendingPathComponent(String(format: "frame_%04d.png", frame)))
                }
            } catch {
                fail("\(error)")
            }
            print("wrote \(dir.path)")
        }
        exit(0)
    }

    private static func mid(_ band: ClosedRange<CGFloat>) -> CGFloat {
        (band.lowerBound + band.upperBound) / 2
    }

    private static func detail(
        _ id: CGDirectDisplayID, hovering: String?, _ displays: DisplayStore, _ preferences: Preferences
    ) -> some View {
        DisplayDetailView(displayID: id, hoveredGroupID: hovering)
            .frame(width: Design.Layout.popoverWidth)
            .frame(maxHeight: Design.Layout.popoverMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .environment(displays)
            .environment(preferences)
    }

    // MARK: Script

    struct Row {
        let groupID: String
        /// The row's extent in popover points.
        let band: ClosedRange<CGFloat>
        let image: NSImage
    }

    struct PopoverState {
        let base: NSImage
        let rows: [Row]

        func image(pointerY: CGFloat?) -> NSImage {
            guard let y = pointerY, let row = rows.first(where: { $0.band.contains(y) }) else { return base }
            return row.image
        }
    }

    /// One frame of the stage.
    struct Frame {
        var popover: NSImage
        var screenScale: Double
        var pointer: CGPoint
        var pointerScale: Double
        var dark: Double
        var iconPhase: Double?
    }

    /// The pointer's x in popover points: right of the size labels, so it
    /// never covers the text it points at.
    nonisolated static let pointerX: CGFloat = 196

    struct Script {
        /// Popover y of the row for each size: A, B.
        let rowY: [CGFloat]
        let screenScale: [Double]

        func frame(at t: Double, states: [PopoverState]) -> Frame {
            let index = t < half ? 0 : 1
            let local = t - Double(index) * half
            let from = index, to = 1 - index
            let sinceClick = local - Beat.click

            let swapped = sinceClick >= Beat.swap
            let current = swapped ? to : from

            let glide = ease(progress(local, Beat.glide))
            let y = rowY[from] + (rowY[to] - rowY[from]) * CGFloat(glide)

            var dark = 0.0
            if sinceClick >= 0 {
                dark = progress(sinceClick, Beat.darkIn) * (1 - progress(sinceClick, Beat.darkOut))
                dark = ease(dark)
            }
            let press = sinceClick >= 0 && sinceClick < Beat.press
                ? sin(.pi * sinceClick / Beat.press) : 0

            let phase: Double? = sinceClick >= 0 && sinceClick < MenuBarIcon.duration ? sinceClick : nil

            return Frame(
                popover: states[current].image(pointerY: y),
                screenScale: screenScale[current],
                pointer: CGPoint(x: MotionDemo.pointerX, y: y),
                pointerScale: 1 - 0.1 * press,
                dark: dark,
                iconPhase: phase
            )
        }

        private func progress(_ t: Double, _ r: ClosedRange<Double>) -> Double {
            min(1, max(0, (t - r.lowerBound) / (r.upperBound - r.lowerBound)))
        }

        private func ease(_ u: Double) -> Double {
            u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
        }
    }

    // MARK: Capture

    /// The rows a hover highlights, found by comparing a capture with the row
    /// under the pointer against one without: the highlight spans the row's
    /// full width, so a column near the left edge differs exactly there.
    private static func hoverBand(base: NSImage, hovered: NSImage) -> ClosedRange<CGFloat>? {
        guard let a = base.representations.first as? NSBitmapImageRep,
              let b = hovered.representations.first as? NSBitmapImageRep,
              a.pixelsHigh == b.pixelsHigh
        else { return nil }
        let x = Int(4 * renderScale)
        var rows: [Int] = []
        for y in 0..<a.pixelsHigh {
            guard let ca = a.colorAt(x: x, y: y), let cb = b.colorAt(x: x, y: y) else { continue }
            let d = abs(ca.redComponent - cb.redComponent) + abs(ca.greenComponent - cb.greenComponent)
                + abs(ca.blueComponent - cb.blueComponent)
            if d > 0.003 { rows.append(y) }
        }
        guard let first = rows.first, let last = rows.last else { return nil }
        return CGFloat(first) / renderScale...CGFloat(last + 1) / renderScale
    }

    /// Lays the view out in an off-screen window and draws it at
    /// `renderScale`, as `ScreenshotHarness` does: the popover's AppKit-backed
    /// controls draw only through `cacheDisplay`.
    private static func capture(_ view: some View, scheme: ColorScheme, hold: () -> Void) -> NSImage {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view
            .background(scheme == .dark
                        ? Color(red: 0.16, green: 0.16, blue: 0.17)
                        : Color(red: 0.95, green: 0.95, blue: 0.96))
            .environment(\.colorScheme, scheme))
        hosting.appearance = appearance
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<3 {
            hold()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
        }
        hold()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hold()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()

        let size = hosting.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * renderScale), pixelsHigh: Int(size.height * renderScale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { fail("could not allocate a bitmap") }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func render(_ view: some View) -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = renderScale
        guard let cgImage = renderer.cgImage else { fail("render failed") }
        return NSBitmapImageRep(cgImage: cgImage)
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) throws {
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fail("could not encode \(url.lastPathComponent)")
        }
        try png.write(to: url)
    }

    fileprivate static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("motion-demo: \(message)\n".utf8))
        exit(1)
    }
}

// MARK: - Stage

/// The top-right corner of the screen, and the loupe on the icon.
///
/// Everything on the screen is laid out in screen points from the top-right
/// corner and scaled about it, which is what a scaled resolution does to that
/// corner: the menu bar, the popover and the window keep their size in points
/// and so draw smaller when there are more points. The wallpaper fills the
/// screen at any size, so it does not scale. The loupe is not part of the
/// screen and stays put, and visible while the displays are dark.
private struct Stage: View {
    let frame: MotionDemo.Frame
    let scheme: ColorScheme

    private var stage: CGSize { MotionDemo.stage }

    var body: some View {
        let s = CGFloat(frame.screenScale)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topTrailing) {
                Screen(frame: frame, scheme: scheme,
                       size: CGSize(width: stage.width / s, height: stage.height / s))
                    .scaleEffect(s, anchor: .topTrailing)
            }
            .frame(width: stage.width, height: stage.height, alignment: .topTrailing)
            .clipped()
            .background(DemoWallpaper(scheme: scheme))

            Color.black.opacity(frame.dark)

            DemoLoupe(phase: frame.iconPhase, scheme: scheme)
                .padding(.leading, 22)
                .padding(.top, 40)
        }
        .frame(width: stage.width, height: stage.height, alignment: .topLeading)
        .environment(\.colorScheme, scheme)
    }
}

/// The screen's content in its own points, `size` wide and tall.
private struct Screen: View {
    let frame: MotionDemo.Frame
    let scheme: ColorScheme
    let size: CGSize

    static let menuBarHeight: CGFloat = 24
    static let popoverTop: CGFloat = 30
    static let popoverTrailing: CGFloat = 10

    private var dark: Bool { scheme == .dark }

    var body: some View {
        let popover = frame.popover
        let popoverOrigin = CGPoint(x: size.width - Self.popoverTrailing - popover.size.width, y: Self.popoverTop)
        ZStack(alignment: .topLeading) {
            DemoWindow(scheme: scheme)
                .offset(x: popoverOrigin.x - 206, y: 172)

            DemoMenuBarStrip(phase: frame.iconPhase, scheme: scheme)
                .frame(width: size.width, height: Self.menuBarHeight)

            Image(nsImage: popover)
                .interpolation(.high)
                .frame(width: popover.size.width, height: popover.size.height)
                .demoPopoverChrome(scheme)
                .offset(x: popoverOrigin.x, y: popoverOrigin.y)

            DemoPointer(scale: frame.pointerScale)
                .offset(x: popoverOrigin.x + frame.pointer.x, y: popoverOrigin.y + frame.pointer.y)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .foregroundStyle(dark ? Color.white : Color.black)
    }
}
#endif
