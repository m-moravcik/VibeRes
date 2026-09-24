#if DEBUG
import AppKit
import SwiftUI

/// Development harness: renders the popover and the app icon to PNG, for the
/// README and the web.pexelo portfolio. Debug builds only; `scripts/screenshots.sh`
/// drives it.
///
/// A MenuBarExtra popover cannot be opened programmatically, and a hand-taken
/// screenshot drifts from the app, comes out at whatever size the window had
/// and carries whatever profiles the author happens to have. This renders the
/// real views against this Mac's real displays and a set of invented profiles
/// kept in a throwaway directory, so the pictures are repeatable and nothing
/// personal ends up in a public repository.
///
/// The panels are captured through `NSHostingView.cacheDisplay`, not
/// `ImageRenderer`: the popover is full of AppKit-backed controls (the Scaled /
/// Native picker, the save form's checkboxes and buttons) that `ImageRenderer`
/// leaves blank. Only the scenery around a finished panel goes through
/// `ImageRenderer`, since it is plain shapes and an image.
@MainActor
enum ScreenshotHarness {
    static let environmentKey = "VIBERES_SCREENSHOTS"

    /// The directory to write into, when the harness was asked for.
    static var requestedOutput: URL? {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static func run(into output: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        VibeResApp.installDisplayNamer()

        // Profiles live in a scratch directory, never the user's catalog.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResScreenshots-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            fail("\(error)")
        }
        let displays = DisplayStore()
        let profiles = ProfileStore(directory: scratch)
        DemoProfiles.seed(profiles, displays: displays.displays)
        // Read only. The script passes the values it needs as launch arguments,
        // which UserDefaults serves from the argument domain without writing
        // anything to the app's real preferences.
        let preferences = Preferences()
        let updater = makeUpdaterController()

        guard let builtIn = displays.displays.first(where: \.isMain) ?? displays.displays.first else {
            fail("no display to render")
        }

        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try write(icon(pixels: 512), to: output.appendingPathComponent("icon.png"))

            for scheme in [ColorScheme.light, .dark] {
                let suffix = scheme == .dark ? "-dark" : "-light"
                func panel(_ content: some View) -> NSBitmapImageRep {
                    capture(
                        PopoverPanel(scheme: scheme) { content }
                            .environment(displays)
                            .environment(profiles)
                            .environment(preferences)
                            .environment(\.updater, updater)
                            .environment(updater.updateStatus),
                        scheme: scheme
                    )
                }

                let root = panel(RootView(path: .constant(NavigationPath())))
                let detail = panel(DisplayDetailView(
                    displayID: builtIn.id,
                    hoveredGroupID: DemoProfiles.previewGroup(on: builtIn)?.id
                ))
                let save = panel(RootView(path: .constant(NavigationPath()), opensSaveForm: true))

                try write(root, to: output.appendingPathComponent("root\(suffix).png"))
                try write(detail, to: output.appendingPathComponent("detail\(suffix).png"))
                try write(save, to: output.appendingPathComponent("save\(suffix).png"))
                try write(
                    render(HeroScene(popover: root, scheme: scheme, banner: false)),
                    to: output.appendingPathComponent("hero\(suffix).png")
                )
                try write(
                    render(HeroScene(popover: root, scheme: scheme, banner: true,
                                     icon: NSImage(data: icon(pixels: 512).representation(using: .png, properties: [:]) ?? Data()))),
                    to: output.appendingPathComponent("banner\(suffix).png")
                )
            }

            // The safety net: the footer's Revert row after a change. Recorded
            // straight into the history, which is memory only; no display is
            // touched. Last, so the other shots do not carry the row.
            if let previous = DemoProfiles.previewGroup(on: builtIn)?.modesByRefresh.last?.mode {
                displays.revert.record(displayID: builtIn.id, displayName: builtIn.name, before: previous)
                for scheme in [ColorScheme.light, .dark] {
                    let rep = capture(
                        PopoverPanel(scheme: scheme) { RootView(path: .constant(NavigationPath())) }
                            .environment(displays)
                            .environment(profiles)
                            .environment(preferences)
                            .environment(\.updater, updater)
                            .environment(updater.updateStatus),
                        scheme: scheme
                    )
                    try write(rep, to: output.appendingPathComponent("revert\(scheme == .dark ? "-dark" : "-light").png"))
                }
            }
        } catch {
            fail("\(error)")
        }

        try? FileManager.default.removeItem(at: scratch)
        exit(0)
    }

    // MARK: Capture

    /// Lays the view out in an off-screen window and draws it at 2x.
    ///
    /// The window is ordered in (off-screen) and the run loop turned for a
    /// moment, so `onAppear` fires and the save form has opened before the
    /// capture, exactly as it would in the popover.
    private static func capture(_ view: some View, scheme: ColorScheme) -> NSBitmapImageRep {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()

        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()

        let size = hosting.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { fail("could not allocate a bitmap") }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }

    /// Renders plain SwiftUI (shapes, text, images) at 2x.
    private static func render(_ view: some View) -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { fail("render failed") }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2)
        return rep
    }

    /// The app icon as the system draws it: the Icon Composer document
    /// compiled into this bundle, glass and all.
    private static func icon(pixels: Int) -> NSBitmapImageRep {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { fail("could not allocate a bitmap") }
        let points = CGFloat(pixels) / 2
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) throws {
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fail("could not encode \(url.lastPathComponent)")
        }
        try png.write(to: url)
        print("wrote \(url.path)  \(rep.pixelsWide)x\(rep.pixelsHigh) px")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("screenshots: \(message)\n".utf8))
        exit(1)
    }
}

/// The popover's frame, as `MenuContent` sets it up.
///
/// The real popover sits on `.ultraThinMaterial` over the desktop, which an
/// off-screen window has nothing to blur. A solid fill in the material's
/// resting colour keeps the contrast what the eye sees.
private struct PopoverPanel<Content: View>: View {
    let scheme: ColorScheme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: Design.Layout.popoverWidth)
            .frame(maxHeight: Design.Layout.popoverMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(scheme == .dark
                        ? Color(red: 0.16, green: 0.16, blue: 0.17)
                        : Color(red: 0.95, green: 0.95, blue: 0.96))
            .environment(\.colorScheme, scheme)
    }
}

/// The popover as it looks open: under its menu bar icon, with the window's
/// rounded corners and shadow, over a plain desktop. Every part that carries
/// information is the captured panel; only the desktop, the menu bar strip and
/// the clock are scenery.
private struct HeroScene: View {
    let popover: NSBitmapImageRep
    let scheme: ColorScheme
    /// The 16:9 portfolio image: the same scene, wider, with the app's icon and
    /// name on the empty half of the desktop.
    let banner: Bool
    var icon: NSImage?

    private var dark: Bool { scheme == .dark }

    var body: some View {
        let panel = NSImage(size: popover.size)
        panel.addRepresentation(popover)

        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()
                // What the app's MenuBarExtra label draws, highlighted the way
                // the menu bar marks the item whose window is open.
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 14))
                    .frame(width: 30, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.14)))
                Image(systemName: "wifi")
                    .font(.system(size: 13, weight: .medium))
                // Fixed, so a re-render does not change the picture.
                Text(verbatim: "9:41")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(height: 24)
            .background(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45))

            HStack(spacing: 0) {
                if banner {
                    VStack(spacing: 20) {
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 176, height: 176)
                        }
                        Text(verbatim: "VibeRes")
                            .font(.system(size: 40, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 30)
                } else {
                    Spacer()
                }
                Image(nsImage: panel)
                    .frame(width: popover.size.width, height: popover.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 0.5))
                    .shadow(color: .black.opacity(dark ? 0.5 : 0.22), radius: 24, y: 12)
            }
            .padding(.top, 6)
            // A popover near the right edge is kept on screen rather than
            // centred under its icon, so it sits flush with a small margin.
            .padding(.trailing, banner ? 120 : 10)
            .padding(.bottom, banner ? 0 : 48)
            .frame(maxHeight: banner ? .infinity : nil, alignment: banner ? .center : .top)
        }
        .frame(width: banner ? 960 : 440, height: banner ? 540 : nil)
        .foregroundStyle(dark ? Color.white : Color.black)
        .background(
            LinearGradient(colors: dark
                           ? [Color(red: 0.11, green: 0.09, blue: 0.26), Color(red: 0.05, green: 0.22, blue: 0.25)]
                           : [Color(red: 0.80, green: 0.78, blue: 0.96), Color(red: 0.74, green: 0.92, blue: 0.90)],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, scheme)
    }
}

/// Invented profiles built on the displays this Mac has, so every pill binds
/// to something real and the "active" checkmark means what it says.
@MainActor
private enum DemoProfiles {
    static func seed(_ store: ProfileStore, displays: [DisplayInfo]) {
        let names = localizedNames
        let builtIn = displays.first(where: { CGDisplayIsBuiltin($0.id) != 0 }) ?? displays.first
        let external = displays.first(where: { CGDisplayIsBuiltin($0.id) == 0 })

        // The desk setup: every display as it is now, so this pill is active.
        store.captureCurrent(
            name: names.desk,
            displays: displays,
            selection: Dictionary(uniqueKeysWithValues: displays.map { ($0.id, .specific) })
        )

        // Presentation: a larger text size on the laptop and a projector-safe
        // 1080p on whatever external is plugged in.
        if let builtIn, let smaller = previewGroup(on: builtIn) {
            var entries = [entry(for: builtIn, group: smaller, matcher: matcher(for: builtIn))]
            if let external {
                entries.append(Profile.Entry(
                    matcher: .anyExternal, displayName: external.name,
                    pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: false
                ))
            }
            _ = store.add(Profile(name: names.presentation, entries: entries))
        }

        // Code: the laptop alone, one size denser than now, so the pill is not
        // active as well.
        if let builtIn, let denser = group(on: builtIn, stepsFromCurrent: -1) ?? group(on: builtIn, stepsFromCurrent: 1) {
            _ = store.add(Profile(
                name: names.code,
                entries: [entry(for: builtIn, group: denser, matcher: matcher(for: builtIn))]
            ))
        }
    }

    /// A scaled size a few steps smaller than the current one: what the detail
    /// shot hovers, and what the presentation profile uses.
    static func previewGroup(on display: DisplayInfo) -> ResolutionGroup? {
        group(on: display, stepsFromCurrent: 2) ?? group(on: display, stepsFromCurrent: 1)
    }

    /// The size `steps` rows below the current one in the detail's list
    /// (largest first), or nil past either end.
    private static func group(on display: DisplayInfo, stepsFromCurrent steps: Int) -> ResolutionGroup? {
        let scaled = display.groups.filter(\.isHiDPI)
        let list = scaled.isEmpty ? display.groups : scaled
        guard let current = list.firstIndex(where: { group in
            group.modesByRefresh.contains { $0.mode.ioDisplayModeID == display.currentMode?.ioDisplayModeID }
        }) else { return nil }
        return list.indices.contains(current + steps) ? list[current + steps] : nil
    }

    private static func entry(for display: DisplayInfo, group: ResolutionGroup, matcher: DisplayMatcher) -> Profile.Entry {
        Profile.Entry(
            matcher: matcher, displayName: display.name,
            pointWidth: group.pointWidth, pointHeight: group.pointHeight,
            refreshHz: group.modesByRefresh.last?.hz, isHiDPI: group.isHiDPI
        )
    }

    private static func matcher(for display: DisplayInfo) -> DisplayMatcher {
        let identity = DisplayIdentity.capture(display.id)
        return CGDisplayIsBuiltin(display.id) != 0
            ? .builtIn(vendor: identity.vendor, model: identity.model, serial: identity.serial)
            : .edid(vendor: identity.vendor, model: identity.model, serial: identity.serial)
    }

    /// Profile names are user data, not UI copy, so they are not in the String
    /// Catalog; the demo still names them in the language being rendered.
    private static var localizedNames: (desk: String, presentation: String, code: String) {
        switch Bundle.main.preferredLocalizations.first {
        case "sk": return ("Práca", "Prezentácia", "Kód")
        case "de": return ("Arbeit", "Präsentation", "Code")
        default: return ("Work", "Presentation", "Code")
        }
    }
}
#endif
