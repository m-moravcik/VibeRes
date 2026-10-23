#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Development harness: renders the README hero loop, a profile clicked in the
/// popover. Debug builds only; `scripts/profile-demo.sh` drives it and encodes
/// the GIF and the MP4.
///
/// The story: the pointer clicks a second profile, the displays blank, the
/// outcome note drops in, the size on the display that changed rolls to its
/// new numbers and the card glows, the MAIN badge travels to the display that
/// became main, the pill's checkmark bounces while the menu bar icon's window
/// springs out. Then the first profile again, so the loop is seamless.
///
/// Unlike `MotionDemo`, which swaps between still captures, this runs the real
/// popover live and samples it while its SwiftUI animations play: `RootView`
/// in an off-screen window the harness owns, drawn through
/// `NSHostingView.cacheDisplay` 30 times a second. The clicks are mouse events
/// sent to that window, so the pill's own action runs (classification,
/// `ProfileStore.applyDetailed`, the outcome note, `onModeSwitch`). Nothing
/// reaches WindowServer: the transaction seams update a demo display list
/// instead, which the store's real debounced refresh then reads, as it would
/// read macOS after a change. The desktop, the menu bar strip, the window and
/// the pointer are scenery; the menu bar icon is `MenuBarIcon` drawn at the
/// real animator's phase.
///
/// The profiles live in a scratch directory and are invented. The display
/// list is this Mac's, and the demo needs two displays: it never invents one.
@MainActor
enum ProfileDemo {
    static let environmentKey = "VIBERES_PROFILE_DEMO"
    /// `1` leaves the main display where it is: the second profile then only
    /// changes a size. See `run`.
    static let keepMainKey = "VIBERES_PROFILE_DEMO_KEEP_MAIN"

    static var requestedOutput: URL? {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static let fps = 30.0
    /// Render scale; the script downsamples to the GIF and MP4 widths.
    static let renderScale: CGFloat = 3
    /// The stage's width in points: the top-right corner of the built-in
    /// display. The height follows the popover.
    static let stageWidth: CGFloat = 600
    static let popoverTop: CGFloat = 30
    static let popoverTrailing: CGFloat = 10
    static let menuBarHeight: CGFloat = 24

    // MARK: Run

    static func run(into output: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        VibeResApp.installDisplayNamer()

        let preferences = Preferences()
        guard !preferences.livePreviewEnabled else {
            fail("pass -VibeRes.LivePreviewEnabled NO: live preview would capture the real desktop")
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            fail("Reduce Motion is on, so the popover would play its reduced variant; turn it off for the take")
        }

        let real = DisplayManager.snapshot()
        guard real.count >= 2 else {
            fail("only \(real.count) display is active; this loop needs two (the built-in and an external). Connect one: the demo never invents a display")
        }
        guard let builtIn = real.first(where: { CGDisplayIsBuiltin($0.id) != 0 }),
              let external = real.first(where: { CGDisplayIsBuiltin($0.id) == 0 })
        else { fail("the loop needs the built-in display and an external one, both active") }
        guard let target = group(on: external, stepsFromCurrent: 1) ?? group(on: external, stepsFromCurrent: -1),
              let targetMode = target.modesByRefresh.last?.mode,
              targetMode.ioDisplayModeID != external.currentMode?.ioDisplayModeID
        else { fail("\(external.name) has no second size to switch to") }

        let movesMain = ProcessInfo.processInfo.environment[keepMainKey] != "1"
        let world = DemoDisplays(real)

        // Profiles live in a scratch directory, never the user's catalog.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResProfileDemo-\(UUID().uuidString)", isDirectory: true)
        let samples = scratch.appendingPathComponent("samples", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        } catch {
            fail("\(error)")
        }
        let names = seed(ProfileStore(directory: scratch), displays: real, builtIn: builtIn,
                         external: external, target: target, movesMain: movesMain, main: world.main)

        // Every take's `DisplayStore` registered a reconfiguration callback
        // that does not retain it, so none is released before the process
        // exits.
        var takes: [Take] = []
        for scheme in [ColorScheme.light, .dark] {
            // A take whose samples came late is played again: the popover
            // runs in real time, and a hiccup would show as a stutter.
            var recorded: Recording?
            for attempt in 1...3 where recorded == nil {
                world.reset()
                let take = Take(scheme: scheme, world: world, scratch: scratch,
                                samples: samples.appendingPathComponent("\(scheme == .dark ? "dark" : "light")-\(attempt)"),
                                preferences: preferences, names: names)
                takes.append(take)
                recorded = take.record()
            }
            guard let recorded else { fail("three takes in a row had samples more than half a frame late") }
            let dir = output.appendingPathComponent(scheme == .dark ? "frames-dark" : "frames-light", isDirectory: true)
            compose(recorded, scheme: scheme, into: dir)
            print("wrote \(dir.path)")
        }
        try? FileManager.default.removeItem(at: scratch)
        withExtendedLifetime(takes) { exit(0) }
    }

    /// The invented profiles, on this Mac's displays: A, every display as it
    /// is now (where the loop starts, so its pill is active); B, a second size
    /// on the external and, unless `keepMainKey`, the other display as main;
    /// and a third that is never clicked, so the strip reads like a real one.
    private static func seed(
        _ store: ProfileStore, displays: [DisplayInfo], builtIn: DisplayInfo, external: DisplayInfo,
        target: ResolutionGroup, movesMain: Bool, main: CGDirectDisplayID
    ) -> [String] {
        let names = localizedNames
        guard let builtInMode = builtIn.currentMode else { fail("\(builtIn.name) reports no current mode") }
        let other = displays.first(where: { $0.id != main }) ?? external
        let a = Profile(
            name: names[0],
            entries: displays.compactMap { info in info.currentMode.map { entry(for: info, size: ($0.width, $0.height, $0.refreshHz, $0.isHiDPI)) } },
            mainDisplay: movesMain ? matcher(for: main) : nil
        )
        let b = Profile(
            name: names[1],
            entries: [
                entry(for: builtIn, size: (builtInMode.width, builtInMode.height, builtInMode.refreshHz, builtInMode.isHiDPI)),
                entry(for: external, size: (target.pointWidth, target.pointHeight, target.modesByRefresh.last?.hz, target.isHiDPI)),
            ],
            mainDisplay: movesMain ? matcher(for: other.id) : nil
        )
        var profiles = [a, b]
        if let denser = group(on: builtIn, stepsFromCurrent: -1) ?? group(on: builtIn, stepsFromCurrent: 1) {
            profiles.append(Profile(name: names[2], entries: [
                entry(for: builtIn, size: (denser.pointWidth, denser.pointHeight, denser.modesByRefresh.last?.hz, denser.isHiDPI)),
            ]))
        }
        for profile in profiles {
            guard case .saved = store.add(profile) else { fail("could not save the demo profile \(profile.name)") }
        }
        return names
    }

    private static func entry(for display: DisplayInfo, size: (Int, Int, Int?, Bool)) -> Profile.Entry {
        Profile.Entry(matcher: matcher(for: display.id), displayName: display.name,
                      pointWidth: size.0, pointHeight: size.1, refreshHz: size.2, isHiDPI: size.3)
    }

    private static func matcher(for id: CGDirectDisplayID) -> DisplayMatcher {
        let identity = DisplayIdentity.capture(id)
        return CGDisplayIsBuiltin(id) != 0
            ? .builtIn(vendor: identity.vendor, model: identity.model, serial: identity.serial)
            : .edid(vendor: identity.vendor, model: identity.model, serial: identity.serial)
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

    /// Profile names are user data, not UI copy, so they are not in the String
    /// Catalog; the demo still names them in the language being rendered.
    private static var localizedNames: [String] {
        switch Bundle.main.preferredLocalizations.first {
        case "sk": return ["Práca", "Prezentácia", "Kód"]
        case "de": return ["Arbeit", "Präsentation", "Code"]
        default: return ["Desk", "Presentation", "Code"]
        }
    }

    fileprivate static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("profile-demo: \(message)\n".utf8))
        exit(1)
    }

    // MARK: Script

    /// The loop's timeline, in seconds: two halves, each a glide to a pill, a
    /// press and a release on it, and the displays blanking while the
    /// transaction runs. The first half clicks B, the second A. Pure, so the
    /// beats can be tested.
    nonisolated struct Script: Sendable {
        static let half = 4.6
        static var loop: Double { 2 * half }

        enum Beat {
            /// The pointer moves from the pill it last clicked to the next.
            static let glide = 0.30...1.00
            /// Mouse down; the pill gives under it (`Design.Motion.press`).
            static let press = 1.30
            /// Mouse up: the click. The pill's action runs here.
            static let release = 1.46
            /// Relative to the release: the displays go dark while the
            /// transaction runs, which returns at `blank`; then they come back.
            static let darkIn = 0.04...0.16
            static let blank = 0.34
            static let darkOut = 0.34...0.56
        }

        /// The pill each half clicks: 1 is B, 0 is A.
        static func target(ofHalf index: Int) -> Int { index % 2 == 0 ? 1 : 0 }

        enum EventKind: Equatable, Sendable { case mouseDown, mouseUp }

        struct Event: Equatable, Sendable {
            let time: Double
            let kind: EventKind
            /// The pill: 0 is A, 1 is B.
            let pill: Int
        }

        /// Every mouse event of `loops` loops, in time order.
        static func events(loops: Int) -> [Event] {
            (0..<(2 * loops)).flatMap { index -> [Event] in
                let start = Double(index) * half
                let pill = target(ofHalf: index)
                return [Event(time: start + Beat.press, kind: .mouseDown, pill: pill),
                        Event(time: start + Beat.release, kind: .mouseUp, pill: pill)]
            }
        }

        /// Where the pointer is, between pill A's point (`a`) and B's.
        static func pointer(at t: Double, a: CGPoint, b: CGPoint) -> CGPoint {
            let (index, local) = split(t)
            let to = target(ofHalf: index)
            let points = [a, b]
            let from = points[1 - to], end = points[to]
            let u = CGFloat(ease(progress(local, Beat.glide)))
            return CGPoint(x: from.x + (end.x - from.x) * u, y: from.y + (end.y - from.y) * u)
        }

        /// The pointer shrinks a touch while the button is down.
        static func pointerScale(at t: Double) -> Double {
            let (_, local) = split(t)
            guard local >= Beat.press, local < Beat.release else { return 1 }
            return 1 - 0.1 * sin(.pi * (local - Beat.press) / (Beat.release - Beat.press))
        }

        /// How dark the displays are, 0 to 1.
        static func darkness(at t: Double) -> Double {
            let (_, local) = split(t)
            let since = local - Beat.release
            guard since >= 0 else { return 0 }
            return ease(progress(since, Beat.darkIn) * (1 - progress(since, Beat.darkOut)))
        }

        /// The half `t` falls in, and the time since it started.
        static func split(_ t: Double) -> (Int, Double) {
            let index = max(0, Int((t / half).rounded(.down)))
            return (index, t - Double(index) * half)
        }

        private static func progress(_ t: Double, _ r: ClosedRange<Double>) -> Double {
            min(1, max(0, (t - r.lowerBound) / (r.upperBound - r.lowerBound)))
        }

        private static func ease(_ u: Double) -> Double {
            u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
        }
    }

    // MARK: Take

    /// One captured frame of the popover, at a loop time.
    struct Sample {
        let time: Double
        let url: URL
        let iconPhase: Double?
    }

    struct Recording {
        let samples: [Sample]
        /// Pill A's and B's point, in popover points from the top left.
        let a: CGPoint
        let b: CGPoint
    }

    /// One appearance: fresh stores on the shared demo display list, the
    /// popover in its own off-screen window, two loops played live, the second
    /// one sampled.
    @MainActor
    private final class Take {
        let scheme: ColorScheme
        let world: DemoDisplays
        let displays = DisplayStore()
        let profiles: ProfileStore
        let animator: MenuBarIconAnimator
        let window: DemoCaptureWindow
        let hosting: NSHostingView<AnyView>
        let samplesDir: URL
        let names: [String]
        let encoder = DispatchQueue(label: "profile-demo.encode", qos: .utility, attributes: .concurrent)
        let encoding = DispatchGroup()
        /// The loop's clock: seconds since the take started.
        var start: TimeInterval = 0
        var now: Double { ProcessInfo.processInfo.systemUptime - start }

        init(scheme: ColorScheme, world: DemoDisplays, scratch: URL, samples: URL,
             preferences: Preferences, names: [String]) {
            self.scheme = scheme
            self.world = world
            self.samplesDir = samples
            self.names = names
            profiles = ProfileStore(directory: scratch)
            // The harness ticks the animator once per sample, so the icon is
            // drawn at the phase the animator holds at that moment.
            animator = MenuBarIconAnimator(startTicker: { _, _ in {} })
            let updater = makeUpdaterController()
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let canvas = CGSize(width: Design.Layout.popoverWidth, height: Design.Layout.popoverMaxHeight)
            hosting = NSHostingView(rootView: AnyView(
                RootView(path: .constant(NavigationPath()))
                    .environment(displays)
                    .environment(profiles)
                    .environment(preferences)
                    .environment(\.updater, updater)
                    .environment(updater.updateStatus)
                    .frame(width: Design.Layout.popoverWidth)
                    .frame(maxHeight: Design.Layout.popoverMaxHeight)
                    .fixedSize(horizontal: false, vertical: true)
                    // The popover's material has nothing to blur off screen; a
                    // solid fill in its resting colour, as the screenshots use.
                    .background(scheme == .dark
                                ? Color(red: 0.16, green: 0.16, blue: 0.17)
                                : Color(red: 0.95, green: 0.95, blue: 0.96))
                    .environment(\.colorScheme, scheme)
                    // Hangs from the top of a fixed canvas, so a row that
                    // arrives grows the popover downwards, and the empty rest
                    // stays transparent for `contentHeight`.
                    .frame(width: canvas.width, height: canvas.height, alignment: .top)
            ))
            hosting.appearance = appearance
            // The canvas is fixed; the window must not follow the content.
            hosting.sizingOptions = []
            window = DemoCaptureWindow(
                contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: canvas),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.appearance = appearance
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentView = hosting
            rig()
        }

        /// Every path that could reach the displays goes to the demo list or
        /// ends the process, and the one refresh decision the loop must not
        /// meet in the real app, closing the popover, ends it too.
        private func rig() {
            let world = world, displays = displays
            displays.demoSnapshot = { world.snapshot() }
            displays.applyMode = { _, _, _ in ProfileDemo.fail("the demo tried to apply a display mode") }
            displays.applyOrigins = { _, _ in ProfileDemo.fail("the demo tried to rearrange the displays") }
            displays.dismissStalePopoverOverride = {
                ProfileDemo.fail("the app would close the popover here: a refresh after the profile saw the main display move (DisplayStore.RefreshTransition.mainSwapped), so the badge's travel is not a state the popover reaches. Rerun with \(ProfileDemo.keepMainKey)=1, or keep the popover open on a profile's main change first")
            }
            displays.refresh()

            profiles.applyBatch = { [weak self] changes, _ in
                // The transaction blanks the displays and holds the main
                // thread until they are back; the run loop turns meanwhile so
                // the samples keep coming (the frames are dark).
                self?.holdUntilDisplaysReturn()
                world.apply(changes)
                // What the reconfiguration callback does after a change.
                Task { @MainActor in displays.scheduleRefresh() }
                return ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
            }
            profiles.applyOrigins = { plan, _ in
                world.setOrigins(plan)
                Task { @MainActor in displays.scheduleRefresh() }
            }
            profiles.liveArrangement = { world.arrangement }
            profiles.isInMirrorSet = { _ in false }
            let animator = animator
            profiles.onModeSwitch = { animator.play() }
            displays.onModeSwitch = { animator.play() }
        }

        private var releaseTime: Double = 0

        private func holdUntilDisplaysReturn() {
            let until = releaseTime + Script.Beat.blank
            while now < until {
                RunLoop.main.run(until: Date().addingTimeInterval(min(0.005, max(0, until - now))))
            }
        }

        /// Plays the take and returns its samples, or nil when one came so
        /// late that the loop would stutter.
        func record() -> Recording? {
            try? FileManager.default.createDirectory(at: samplesDir, withIntermediateDirectories: true)
            window.orderFrontRegardless()
            for _ in 0..<4 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                hosting.layoutSubtreeIfNeeded()
            }
            for profile in profiles.profiles.prefix(2) {
                guard DisplaySetClassifier.isCleanApply(DisplaySetClassifier.classify(profile, against: displays.displays)) else {
                    ProfileDemo.fail("\(profile.name) would open the confirmation panel, not apply")
                }
            }
            guard profiles.profiles.first.map({ profiles.isCurrentState($0, displays: displays.displays) }) == true else {
                ProfileDemo.fail("\(names[0]) should be active where the loop starts")
            }
            let pills = pillPoints()
            let a = pills[0], b = pills[1]

            // Two loops: the first brings the popover to the state the loop
            // ends in (the note and the Revert row from the last click), the
            // second is the take, with one frame past its end for the seam.
            let loop = Script.loop
            let frameCount = Int((loop * ProfileDemo.fps).rounded())
            var samples: [Sample] = []
            var nextFrame = 0
            var lateness: [Double] = []
            var done = false

            start = ProcessInfo.processInfo.systemUptime
            for event in Script.events(loops: 2) {
                let timer = Timer(fire: Date().addingTimeInterval(event.time), interval: 0, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.send(event, a: a, b: b) }
                }
                RunLoop.main.add(timer, forMode: .common)
            }
            let ticker = Timer(timeInterval: 1.0 / 480, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !done else { return }
                    let due = loop + Double(nextFrame) / ProfileDemo.fps
                    let t = self.now
                    guard t >= due else { return }
                    lateness.append(t - due)
                    samples.append(self.sample(index: nextFrame, time: due))
                    nextFrame += 1
                    if nextFrame > frameCount { done = true }
                }
            }
            RunLoop.main.add(ticker, forMode: .common)
            while !done {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            ticker.invalidate()
            encoding.wait()
            window.orderOut(nil)

            if let problem = displays.lastError ?? profiles.lastError {
                ProfileDemo.fail("the popover showed a problem during the take: \(problem.englishDescription)")
            }
            let sorted = lateness.sorted()
            print(String(format: "%@: %d samples, sampled late by %.1f ms median, %.1f ms worst",
                         scheme == .dark ? "dark" : "light", samples.count,
                         1000 * sorted[sorted.count / 2], 1000 * (sorted.last ?? 0)))
            if (sorted.last ?? 0) > 0.5 / ProfileDemo.fps {
                print("a sample came more than half a frame late; playing the take again")
                return nil
            }
            return Recording(samples: samples, a: a, b: b)
        }

        /// Draws the popover as it is right now and queues the PNG.
        private func sample(index: Int, time: Double) -> Sample {
            animator.tick()
            let size = hosting.bounds.size
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * ProfileDemo.renderScale), pixelsHigh: Int(size.height * ProfileDemo.renderScale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { ProfileDemo.fail("could not allocate a bitmap") }
            rep.size = size
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let url = samplesDir.appendingPathComponent(String(format: "sample_%04d.png", index))
            guard let image = rep.cgImage else { ProfileDemo.fail("could not read a sample") }
            encoder.async(group: encoding) { writePNG(image, to: url) }
            return Sample(time: time - Script.loop, url: url, iconPhase: animator.phase)
        }

        private func send(_ event: Script.Event, a: CGPoint, b: CGPoint) {
            let point = event.pill == 0 ? a : b
            // Popover points from the top left to window points.
            let inView = CGPoint(x: point.x, y: hosting.isFlipped ? point.y : hosting.bounds.height - point.y)
            let location = hosting.convert(inView, to: nil)
            if event.kind == .mouseUp { releaseTime = now }
            guard let ns = NSEvent.mouseEvent(
                with: event.kind == .mouseDown ? .leftMouseDown : .leftMouseUp,
                location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: event.kind == .mouseDown ? 1 : 0
            ) else { ProfileDemo.fail("could not make a mouse event") }
            window.sendEvent(ns)
        }

        /// Where the pointer rests on each pill, and where it clicks, in
        /// popover points from the top left.
        ///
        /// SwiftUI builds no accessibility tree without a client attached, so
        /// the pills are found in a capture instead: the first band of the
        /// popover where wide runs differ from its solid background is the
        /// pill strip, and its runs are the pills in the catalog's order.
        private func pillPoints() -> [CGPoint] {
            let size = hosting.bounds.size
            let scale = ProfileDemo.renderScale
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { ProfileDemo.fail("could not allocate a bitmap") }
            rep.size = size
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let data = rep.bitmapData else { ProfileDemo.fail("could not read the popover") }
            let width = rep.pixelsWide, stride = rep.bytesPerRow
            func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let i = y * stride + x * 4
                return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
            }
            let background = pixel(2, 2)
            func differs(_ x: Int, _ y: Int) -> Bool {
                let p = pixel(x, y)
                return abs(p.0 - background.0) + abs(p.1 - background.1) + abs(p.2 - background.2) > 6
            }
            /// Runs at least `minimum` pixels wide of a row that differ.
            func runs(_ y: Int, minimum: Int) -> [ClosedRange<Int>] {
                var out: [ClosedRange<Int>] = []
                var x = 0
                while x < width {
                    guard differs(x, y) else { x += 1; continue }
                    let begin = x
                    while x < width, differs(x, y) { x += 1 }
                    if x - begin >= minimum { out.append(begin...(x - 1)) }
                }
                return out
            }
            // A pill is wider than 30 pt; a letter of the header is not.
            let minimum = Int(30 * scale)
            var y = 0
            while y < rep.pixelsHigh, runs(y, minimum: minimum).count < 2 { y += 1 }
            let top = y
            while y < rep.pixelsHigh, runs(y, minimum: minimum).count >= 2 { y += 1 }
            let bottom = y - 1
            // Near the top edge of the fill, above the names.
            let pills = runs(min(top + Int(2 * scale), bottom), minimum: minimum)
            guard top < rep.pixelsHigh, pills.count >= 2 else { ProfileDemo.fail("could not find the profile pills") }
            return pills.map { run in
                let maxX = CGFloat(run.upperBound + 1) / scale
                let minY = CGFloat(top) / scale, maxY = CGFloat(bottom + 1) / scale
                // In the pill's trailing padding (8 pt), past the end of the
                // name, so the arrow covers no text of its own pill.
                return CGPoint(x: maxX - 6, y: (minY + maxY) / 2 + 1)
            }
        }
    }

    // MARK: Compose

    /// Puts each sample on the stage and writes the frames.
    private static func compose(_ recording: Recording, scheme: ColorScheme, into dir: URL) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fail("\(error)")
        }
        // The stage is as tall as the popover gets, plus room for its shadow.
        let popovers = recording.samples.map { sample -> NSImage in
            guard let source = CGImageSourceCreateWithURL(sample.url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { fail("could not read \(sample.url.lastPathComponent)") }
            let height = contentHeight(image)
            guard let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)) else {
                fail("could not crop \(sample.url.lastPathComponent)")
            }
            return NSImage(cgImage: cropped, size: NSSize(width: CGFloat(cropped.width) / renderScale,
                                                          height: CGFloat(cropped.height) / renderScale))
        }
        let tallest = popovers.map(\.size.height).max() ?? 400
        let stage = CGSize(width: stageWidth, height: (popoverTop + tallest + 36).rounded(.up))
        for (index, sample) in recording.samples.enumerated() {
            let t = sample.time
            let view = ProfileStage(
                popover: popovers[index],
                pointer: Script.pointer(at: t, a: recording.a, b: recording.b),
                pointerScale: Script.pointerScale(at: t),
                darkness: Script.darkness(at: t),
                iconPhase: sample.iconPhase,
                scheme: scheme,
                size: stage
            )
            let renderer = ImageRenderer(content: view)
            renderer.scale = renderScale
            guard let image = renderer.cgImage else { fail("render failed") }
            writePNG(image, to: dir.appendingPathComponent(String(format: "frame_%04d.png", index)))
        }
    }

    /// The popover's height in pixels: the opaque rows from the top, down a
    /// column inside the panel's rounded corners.
    private static func contentHeight(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { fail("could not read a sample's pixels") }
        // Row 0 of the buffer is the image's top.
        let x = width / 2
        var rows = 0
        while rows < height, pixels[(rows * width + x) * 4 + 3] > 0 { rows += 1 }
        return max(rows, 1)
    }
}

/// A borderless window for the popover, off screen. Plain `NSWindow` would do
/// for the clicks too; this one only exists so the harness can say what it is.
final class DemoCaptureWindow: NSWindow {}

/// The demo's display list: this Mac's displays, with the modes and the main
/// display the demo has "applied". What `DisplayStore` reads on a refresh and
/// `ProfileStore` reads as the live arrangement.
@MainActor
final class DemoDisplays {
    private let base: [DisplayInfo]
    private let initialMain: CGDirectDisplayID
    private let initialOrigins: [CGDirectDisplayID: CGPoint]
    private var modes: [CGDirectDisplayID: CGDisplayMode] = [:]
    private var origins: [CGDirectDisplayID: CGPoint] = [:]
    private(set) var main: CGDirectDisplayID

    init(_ displays: [DisplayInfo]) {
        base = displays
        initialMain = displays.first(where: \.isMain)?.id ?? displays[0].id
        main = initialMain
        // Read only: where macOS has the displays now.
        initialOrigins = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, CGDisplayBounds($0.id).origin) })
        reset()
    }

    func reset() {
        main = initialMain
        origins = initialOrigins
        modes = Dictionary(uniqueKeysWithValues: base.compactMap { info in info.currentMode.map { (info.id, $0) } })
    }

    /// As `DisplayManager.snapshot` reports it: the main display first, as
    /// `CGGetActiveDisplayList` lists it, then the rest in their order.
    func snapshot() -> [DisplayInfo] {
        let ordered = base.filter { $0.id == main } + base.filter { $0.id != main }
        return ordered.map { info in
            DisplayInfo(id: info.id, name: info.name, isMain: info.id == main, modes: info.modes,
                        currentMode: modes[info.id] ?? info.currentMode, groups: info.groups,
                        variableModeIDs: info.variableModeIDs)
        }
    }

    var arrangement: (main: CGDirectDisplayID, bounds: [CGDirectDisplayID: CGRect]) {
        var bounds: [CGDirectDisplayID: CGRect] = [:]
        for info in base {
            let mode = modes[info.id] ?? info.currentMode
            bounds[info.id] = CGRect(origin: origins[info.id] ?? .zero,
                                     size: CGSize(width: mode?.width ?? 0, height: mode?.height ?? 0))
        }
        return (main, bounds)
    }

    func apply(_ changes: [ResolutionSwitcher.BatchChange]) {
        for change in changes { modes[change.display] = change.mode }
    }

    /// The display at (0, 0) is main, as in CoreGraphics.
    func setOrigins(_ plan: [CGDirectDisplayID: CGPoint]) {
        for (id, origin) in plan { origins[id] = origin }
        if let newMain = plan.first(where: { $0.value == .zero })?.key { main = newMain }
    }
}

private func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("profile-demo: could not write \(url.lastPathComponent)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("profile-demo: could not write \(url.lastPathComponent)\n".utf8))
        exit(1)
    }
}

// MARK: - Stage

/// The top-right corner of the built-in display with the popover open under
/// the menu bar, and the loupe on the icon. The screen keeps its size: the
/// profile changes the external display, not this one.
private struct ProfileStage: View {
    let popover: NSImage
    let pointer: CGPoint
    let pointerScale: Double
    let darkness: Double
    let iconPhase: Double?
    let scheme: ColorScheme
    let size: CGSize

    var body: some View {
        let origin = CGPoint(x: size.width - ProfileDemo.popoverTrailing - popover.size.width, y: ProfileDemo.popoverTop)
        ZStack(alignment: .topLeading) {
            DemoWallpaper(scheme: scheme)

            DemoWindow(scheme: scheme)
                .offset(x: origin.x - 206, y: 172)

            DemoMenuBarStrip(phase: iconPhase, scheme: scheme)
                .frame(width: size.width, height: ProfileDemo.menuBarHeight)

            Image(nsImage: popover)
                .interpolation(.high)
                .frame(width: popover.size.width, height: popover.size.height)
                .demoPopoverChrome(scheme)
                .offset(x: origin.x, y: origin.y)

            DemoPointer(scale: pointerScale)
                .offset(x: origin.x + pointer.x, y: origin.y + pointer.y)

            Color.black.opacity(darkness)

            DemoLoupe(phase: iconPhase, scheme: scheme)
                .padding(.leading, 22)
                .padding(.top, 40)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .environment(\.colorScheme, scheme)
    }
}
#endif
