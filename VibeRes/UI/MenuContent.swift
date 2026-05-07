import SwiftUI

struct MenuContent: View {
    @Environment(DisplayStore.self) private var store
    @State private var path = NavigationPath()
    @State private var menuTracking = false

    var body: some View {
        NavigationStack(path: $path) {
            RootView(path: $path)
                .navigationDestination(for: DisplayInfo.ID.self) { displayID in
                    DisplayDetailView(displayID: displayID)
                }
        }
        .frame(width: Design.Layout.popoverWidth)
        .frame(maxHeight: Design.Layout.popoverMaxHeight)
        // Lock vertical size to intrinsic content. Without this, NavigationStack
        // remembers the largest height any pushed view ever requested and the
        // popover keeps that height even after popping back to the smaller root.
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial)
        // Reset to root whenever the popover closes. Matches Apple's own menubar
        // patterns (Control Center, Bluetooth, Wi-Fi): each open is a fresh task,
        // not a continuation of an abandoned one. Avoids the "where am I?" moment
        // when reopening hours later mid-detail.
        //
        // Caveat: opening any NSMenu (e.g. a SwiftUI `.contextMenu` from a profile
        // pill) makes the popover briefly resign key — without filtering, that
        // would reset path AND dismiss the popover. We skip resign events that
        // fire while a menu is being tracked.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            menuTracking = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            // Defer slightly — resign-key may fire just after end-tracking.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                menuTracking = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            guard !menuTracking else { return }
            guard let window = note.object as? NSWindow else { return }
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("StatusBar") || className.contains("Popover") {
                path = NavigationPath()
            }
        }
    }
}

// MARK: - Root: list of displays

private struct RootView: View {
    @Environment(DisplayStore.self) private var store
    @Environment(UpdateChecker.self) private var updateChecker
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 0) {
            if let err = store.lastError {
                Text(err)
                    .font(Design.Typography.footer)
                    .foregroundStyle(.red)
                    .padding(.horizontal, Design.Spacing.l)
                    .padding(.top, Design.Spacing.xs)
            }

            if updateChecker.isUpdateAvailable, let url = updateChecker.releaseURL,
               let latest = updateChecker.latestVersion {
                UpdateBanner(latestVersion: latest, releaseURL: url)
            }

            // Tight against the popover top — MenuBarExtra(.window) wraps us
            // in an NSPanel that already has ~8pt internal inset. Adding any
            // .padding(.top) on top of that yields the visible whitespace
            // gap users have called out.
            VStack(spacing: 0) {
                ProfilesSection()

                Divider()
                    .padding(.horizontal, Design.Spacing.m)
                    .padding(.vertical, Design.Spacing.xs)

                VStack(spacing: Design.Spacing.xs) {
                    if store.displays.isEmpty {
                        Text("No displays detected.")
                            .foregroundStyle(.secondary)
                            .padding(Design.Spacing.l)
                    } else {
                        ForEach(store.displays) { display in
                            DisplayCard(display: display) {
                                path.append(display.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, Design.Spacing.m)
            }

            FooterBar()
        }
    }
}

private struct DisplayCard: View {
    let display: DisplayInfo
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.m) {
                Image(systemName: display.isMain ? "laptopcomputer" : "display")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Design.Spacing.s) {
                        Text(display.name)
                            .font(Design.Typography.cardTitle)
                            .lineLimit(1)
                        if display.isMain {
                            Text("MAIN")
                                .font(Design.Typography.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.22), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let cur = display.currentMode {
                        Text(currentModeSubtitle(cur))
                            .font(Design.Typography.cardSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Design.Spacing.s)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Design.Spacing.l)
            .padding(.vertical, Design.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.card)
                    .fill(isHovering ? Design.Palette.cardFillHover : Design.Palette.cardFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func currentModeSubtitle(_ m: CGDisplayMode) -> String {
        var parts = ["\(formatThousands(m.width)) × \(formatThousands(m.height))"]
        if let hz = m.refreshHz { parts.append("\(hz) Hz") }
        if m.isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Detail: one display's modes

/// Carries per-row Y-midpoints from individual `CompactResolutionRow`
/// backgrounds up to `DisplayDetailView`, where the side popover anchor
/// reads the hovered row's Y synchronously.
private struct RowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct DisplayDetailView: View {
    let displayID: CGDirectDisplayID
    @Environment(DisplayStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ModeFilter = .hiDPIIfAvailable
    /// Single desktop snapshot, fetched once per detail-view appearance
    /// when the user has Live Preview enabled. Reused by every hover row.
    @State private var desktopSnapshot: NSImage?
    /// Which row the cursor is currently over. Drives the side popover
    /// preview anchored vertically to that row.
    @State private var hoveredGroupID: String?
    /// Y-coordinate of the hovered row inside this detail view's coordinate
    /// space, used by the side popover anchor.
    @State private var hoveredRowY: CGFloat = 40
    /// Per-row Y midpoints, keyed by ResolutionGroup.id. Updated each
    /// render via PreferenceKey so onHoverChange can read the right Y
    /// for the row being entered without an async onChange round trip.
    @State private var rowFrames: [String: CGFloat] = [:]

    enum ModeFilter: Hashable {
        case hiDPIIfAvailable
        case allNative
    }

    private var display: DisplayInfo? {
        store.displays.first(where: { $0.id == displayID })
    }

    var body: some View {
        VStack(spacing: 0) {
            navHeader

            if let display {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        currentModeCard(for: display)
                        filterToggle(for: display)
                        sizeList(for: display)
                    }
                    .padding(.vertical, 8)
                }
                .frame(idealHeight: 480)
                // Floating preview pinned to the top-right of the list.
                // After several attempts at "popover next to the hovered
                // row" (each tripped on SwiftUI popover dismiss/recreate
                // behaviour or coordinate-space lag), this fixed overlay
                // wins on stability: no flicker, no lag, no first-click-
                // eaten bug. The trade-off — preview is in the corner
                // rather than next to the row — is small in a popover this
                // narrow, and it's at least always in the same place so
                // users find it predictably.
                .overlay(alignment: .topTrailing) {
                    if let resolved = previewTarget(for: display) {
                        PreviewBox(
                            currentWidth: resolved.cur.width,
                            currentHeight: resolved.cur.height,
                            proposedWidth: resolved.group.pointWidth,
                            proposedHeight: resolved.group.pointHeight,
                            maxSize: 90,
                            desktopImage: preferences.livePreviewEnabled ? desktopSnapshot : nil
                        )
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                        .allowsHitTesting(false)
                    }
                }
            } else {
                Text("Display unavailable.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: Header

    private var navHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(display?.name ?? "Display")
                    .font(Design.Typography.navTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                HStack {
                    BackButton { dismiss() }
                    Spacer()
                }
            }
            .padding(.horizontal, Design.Spacing.m)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Design.Palette.separator)
                .frame(height: 1)
        }
    }

    // MARK: Current mode card

    @ViewBuilder
    private func currentModeCard(for display: DisplayInfo) -> some View {
        if let cur = display.currentMode {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "rectangle.inset.filled")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(formatThousands(cur.width)) × \(formatThousands(cur.height))")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    HStack(spacing: 4) {
                        if let hz = cur.refreshHz {
                            Text("\(hz) Hz")
                        }
                        if cur.isHiDPI {
                            Text("·").foregroundStyle(.tertiary)
                            Text("HiDPI")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("CURRENT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.15))
                    )
            }
            .padding(.horizontal, Design.Spacing.l)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.08))
                    .padding(.horizontal, Design.Spacing.m)
            )
            .padding(.bottom, 6)
        }
    }

    // MARK: HiDPI / Native toggle

    @ViewBuilder
    private func filterToggle(for display: DisplayInfo) -> some View {
        if hasBothKinds(for: display) {
            HStack(spacing: 6) {
                Picker("", selection: $filter) {
                    Text("Scaled").tag(ModeFilter.hiDPIIfAvailable)
                    Text("Native").tag(ModeFilter.allNative)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .help("'Scaled' uses HiDPI rendering so text stays sharp on Retina (the default for built-in displays). 'Native' is 1:1 pixel mapping — typical for non-Retina external monitors.")
            }
            .padding(.horizontal, Design.Spacing.l)
            .padding(.bottom, 6)
        }
    }

    // MARK: Resolution list

    @ViewBuilder
    private func sizeList(for display: DisplayInfo) -> some View {
        VStack(spacing: 0) {
            ForEach(visibleGroups(for: display)) { group in
                let isCurrent = group.modesByRefresh.contains {
                    $0.mode.ioDisplayModeID == display.currentMode?.ioDisplayModeID
                }
                // GeometryReader background reports each row's Y to the
                // shared `rowFrames` map every render. The popover anchor
                // then reads the hovered row's Y synchronously, avoiding
                // the "preview opens at the top, then jumps" lag from the
                // previous onChange-based implementation.
                CompactResolutionRow(
                    group: group,
                    currentMode: display.currentMode,
                    isHovered: hoveredGroupID == group.id,
                    simpleMode: preferences.simpleMode,
                    onHoverChange: { hovering in
                        guard !isCurrent else { return }
                        hoveredGroupID = hovering ? group.id : (hoveredGroupID == group.id ? nil : hoveredGroupID)
                    },
                    apply: { mode in store.apply(mode, to: display.id) }
                )
            }
        }
        .task(id: displayID) {
            // Lazily fetch one snapshot per detail-view appearance. Permission
            // prompt fires here on the first run for users who enabled Live
            // Preview. Failures fall back silently to the geometric variant.
            guard preferences.livePreviewEnabled else { return }
            desktopSnapshot = await DesktopCapture.snapshot(of: displayID)
        }
    }

    /// Content of the side popover. Wrapped in a Group so we can attach
    /// `.interactiveDismissDisabled()` (macOS 13+ modifier that stops the
    /// popover from auto-dismissing when the user clicks anywhere "outside"
    /// the visible content — including, importantly, on a refresh chip
    /// underneath this popover's window). Without it the first click on
    /// any chip triggered popover-dismiss instead of the chip action.
    @ViewBuilder
    private func previewPopoverContent(for display: DisplayInfo) -> some View {
        if let resolved = previewTarget(for: display) {
            PreviewBox(
                currentWidth: resolved.cur.width,
                currentHeight: resolved.cur.height,
                proposedWidth: resolved.group.pointWidth,
                proposedHeight: resolved.group.pointHeight,
                maxSize: 110,
                desktopImage: preferences.livePreviewEnabled ? desktopSnapshot : nil
            )
            .padding(8)
            .interactiveDismissDisabled()
            .allowsHitTesting(false)
        } else {
            // Empty placeholder — popover is briefly opened with no target
            // during hover transitions; rendering an empty 1pt view keeps
            // the system from logging a SwiftUI warning.
            Color.clear.frame(width: 1, height: 1)
        }
    }

    /// Returns the (current mode, hovered group) pair we should preview,
    /// or nil if there's nothing to show. Encapsulates the "is the cursor
    /// over a real previewable row?" check so the preview slot and its
    /// height stay in lockstep — no slot reserved when nothing is hovered.
    private func previewTarget(for display: DisplayInfo) -> (cur: CGDisplayMode, group: ResolutionGroup)? {
        guard let cur = display.currentMode,
              let id = hoveredGroupID,
              let group = visibleGroups(for: display).first(where: { $0.id == id }),
              !group.modesByRefresh.contains(where: { $0.mode.ioDisplayModeID == cur.ioDisplayModeID })
        else { return nil }
        return (cur, group)
    }

    // MARK: Filtering helpers

    private func allGroups(for display: DisplayInfo) -> [ResolutionGroup] {
        // DisplayInfo.groups is pre-computed during snapshot — no rebuild on render.
        display.groups
    }

    private func hasBothKinds(for display: DisplayInfo) -> Bool {
        let kinds = Set(allGroups(for: display).map(\.isHiDPI))
        return kinds.count > 1
    }

    private func visibleGroups(for display: DisplayInfo) -> [ResolutionGroup] {
        let all = allGroups(for: display)
        switch filter {
        case .hiDPIIfAvailable:
            let hidpi = all.filter(\.isHiDPI)
            return hidpi.isEmpty ? all : hidpi
        case .allNative:
            let native = all.filter { !$0.isHiDPI }
            return native.isEmpty ? all : native
        }
    }
}

// MARK: - Footer

/// Footer rendered as a native-looking vertical menu list directly in the popover.
/// Each row mimics NSMenuItem chrome: SF symbol on the left, label in the middle,
/// keyboard shortcut on the right, accent-color highlight on hover. Real ⌘-shortcuts
/// are wired via `.keyboardShortcut` modifiers on the underlying buttons.
private struct FooterBar: View {
    @Environment(DisplayStore.self) private var store
    @Environment(UpdateChecker.self) private var updateChecker
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Design.Palette.separator)
                .frame(height: 1)

            VStack(spacing: 0) {
                if store.revert.canRevert {
                    MenuRow(
                        icon: "arrow.uturn.backward.circle",
                        label: revertLabel,
                        // No shortcut label: ⌘Z would only work while the
                        // popover holds key focus, and the act of applying
                        // a resolution typically dismisses it. Showing the
                        // shortcut text would advertise a behaviour that
                        // fails most of the time. Click the row instead.
                        shortcut: nil,
                        action: {
                            store.performRevert()
                            // No toast — displays jump back, the row
                            // disappears, that's the feedback.
                        }
                    )
                    // Keep the binding so power users who reopen the
                    // popover and hit ⌘Z still get the revert; we just
                    // don't promise it in the label.
                    .keyboardShortcut("z")
                }

                MenuRow(
                    icon: "arrow.clockwise",
                    label: "Refresh",
                    shortcut: "⌘R",
                    action: {
                        // Refresh both data sources the popover surfaces:
                        // the display list (sync, fast) and the update
                        // banner (async — fires off but doesn't block the UI).
                        store.refresh()
                        Task { await updateChecker.checkNow() }
                    }
                )
                .keyboardShortcut("r")

                MenuRow(
                    icon: "gearshape",
                    label: "Settings…",
                    shortcut: "⌘,",
                    action: {
                        // Open the standard Settings scene. Activate the app
                        // first because MenuBarExtra(.window) doesn't bring
                        // the new window forward by itself.
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
                )
                .keyboardShortcut(",")

                MenuRow(
                    icon: "info.circle",
                    label: "About VibeRes",
                    shortcut: nil,
                    action: { showAbout() }
                )

                MenuRow(
                    icon: "power",
                    label: "Quit",
                    shortcut: "⌘Q",
                    action: { NSApp.terminate(nil) }
                )
                .keyboardShortcut("q")
            }
            .padding(.top, 4)
            .padding(.bottom, 2)
        }
    }

    /// Compact label for the revert row — fits the menu's natural width
    /// without truncating, regardless of whether one or several displays
    /// were touched by the last apply.
    private var revertLabel: String {
        let n = store.revert.entries.count
        switch n {
        case 0: return "Revert last change"
        case 1: return "Revert \(store.revert.summary)"
        default: return "Revert last change (\(n) displays)"
        }
    }

    private func showAbout() {
        let credits = NSAttributedString(
            string: "Modern menubar resolution switcher for macOS.\nMIT licensed · github.com/m-moravcik/VibeRes",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "VibeRes",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuRow: View {
    let icon: String
    let label: String
    let shortcut: String?
    let action: () -> Void
    var isEnabled: Bool = true

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16, alignment: .center)
                    .accessibilityHidden(true)

                Text(label)
                    .font(.system(size: 13))

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(isHovering && isEnabled ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true) // VoiceOver already announces the keyboardShortcut
                }
            }
            .foregroundStyle(isHovering && isEnabled ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Design.Spacing.l)
            .padding(.vertical, Design.Layout.footerRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovering && isEnabled ? Color.accentColor : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
    }
}

// MARK: - Resolution row

// MARK: - Update banner

/// Subtle banner shown at the top of the root popover when GitHub has a newer
/// release than the running app. Click → opens the release page in Safari.
private struct UpdateBanner: View {
    let latestVersion: String
    let releaseURL: URL
    @State private var isHovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(releaseURL)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(versionLabel(latestVersion)) on GitHub — click to view")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.green.opacity(0.16) : Color.green.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .padding(.horizontal, Design.Spacing.m)
        .padding(.top, Design.Spacing.s)
        .accessibilityLabel("Update available — \(latestVersion) on GitHub")
    }

    /// Strip a leading "v" so the banner reads "0.3.0" rather than "v0.3.0",
    /// matching the way the user thinks about app version numbers.
    private func versionLabel(_ raw: String) -> String {
        raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
    }
}

// MARK: - Back button

private struct BackButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text("Back")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovering ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isHovering ? Color.accentColor : Color.secondary.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Back")
        .accessibilityHint("Return to display list")
        .help("Return to display list")
    }
}

// MARK: - Compact resolution row (new design)

/// Cleaner replacement for ResolutionRow:
/// - drops the inline real-estate badge (it was visually competing with the
///   refresh chips and crowded the row)
/// - bigger row padding, clearer typography
/// - refresh rates as a native segmented Picker — readable, accessible,
///   and consistent with other macOS controls
private struct CompactResolutionRow: View {
    let group: ResolutionGroup
    let currentMode: CGDisplayMode?
    /// Whether the cursor is currently over this row. Hover state lives in
    /// the parent view so it can render a single shared preview banner
    /// rather than a per-row popover (which would steal the first click).
    let isHovered: Bool
    /// When true, the per-rate chip group is hidden and a click on the row
    /// applies the highest available refresh rate for the size. Driven by
    /// `Preferences.simpleMode`.
    let simpleMode: Bool
    let onHoverChange: (Bool) -> Void
    let apply: (CGDisplayMode) -> Void

    private var currentModeID: Int32? { currentMode?.ioDisplayModeID }

    /// Highest available refresh rate for this size — what Simple Mode
    /// applies on a row click.
    private var preferredMode: CGDisplayMode? {
        group.modesByRefresh.last?.mode
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(formatThousands(group.pointWidth)) × \(formatThousands(group.pointHeight))")
                .font(.system(size: 13, weight: isCurrentSize ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isCurrentSize ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .frame(minWidth: 100, alignment: .leading)
                .accessibilityLabel("\(group.pointWidth) by \(group.pointHeight)\(isCurrentSize ? ", current" : "")")

            Spacer(minLength: 6)

            if simpleMode {
                simpleHzLabel
            } else {
                refreshSegment
                    .fixedSize()
            }
        }
        .padding(.horizontal, Design.Spacing.l)
        .padding(.vertical, 6)
        .background(
            isHovered && !isCurrentSize
                ? Color.secondary.opacity(0.08)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { onHoverChange($0) }
        .help(tooltipText)
        .accessibilityValue(tooltipText)
        .onTapGesture {
            // Tap anywhere on the row applies the highest available rate
            // for this size. This works in both modes:
            //  - Simple Mode hides chips entirely → row tap is the only
            //    interaction.
            //  - Advanced Mode shows chips for explicit refresh-rate picks,
            //    but a click on the row body (e.g. on the "1800 × 1169"
            //    text or the gap between text and chip group) shouldn't be
            //    a dead zone — it just means "I don't care, give me the
            //    best rate". Particularly important on displays with one
            //    refresh rate (M2 Air, plain 60 Hz externals) where the
            //    chip group is a tiny target.
            if let mode = preferredMode {
                apply(mode)
            }
        }
    }

    /// Subtle Hz hint shown in Simple Mode — communicates the preferred
    /// refresh rate without the chip group's chrome.
    @ViewBuilder
    private var simpleHzLabel: some View {
        if let preferred = preferredMode {
            Text(preferred.refreshHz.map { "\($0) Hz" } ?? "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var refreshSegment: some View {
        let entries = group.modesByRefresh
        if entries.count == 1, let only = entries.first {
            Button {
                apply(only.mode)
            } label: {
                Text(only.hz > 0 ? "\(only.hz) Hz" : "—")
                    .font(.system(size: 11, weight: only.mode.ioDisplayModeID == currentModeID ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(only.mode.ioDisplayModeID == currentModeID ? Color.white : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(only.mode.ioDisplayModeID == currentModeID
                                  ? Color.accentColor
                                  : Color.secondary.opacity(0.16))
                    )
            }
            .buttonStyle(.plain)
        } else {
            // Multi-rate: render as horizontally laid-out chips, but bigger and
            // grouped in a single capsule "track" so they read as one control.
            HStack(spacing: 0) {
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    let isActive = entry.mode.ioDisplayModeID == currentModeID

                    Button {
                        apply(entry.mode)
                    } label: {
                        Text("\(entry.hz)")
                            .font(.system(size: 11, weight: isActive ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(isActive ? Color.white : .primary)
                            .frame(minWidth: 22)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(chipBackground(active: isActive))
                    }
                    .buttonStyle(.plain)
                    .help("\(entry.hz) Hz")
                    .accessibilityLabel("\(entry.hz) Hertz")

                    if index < entries.count - 1 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1, height: 12)
                    }
                }
            }
            .background(
                Capsule().fill(Color.secondary.opacity(0.12))
            )
        }
    }

    /// Avoids `AnyView` type-erasure (which defeats SwiftUI's diffing) by using
    /// `@ViewBuilder` with both branches typed as concrete shapes.
    @ViewBuilder
    private func chipBackground(active: Bool) -> some View {
        if active {
            Capsule().fill(Color.accentColor)
        } else {
            Color.clear
        }
    }

    private var isCurrentSize: Bool {
        guard let id = currentModeID else { return false }
        return group.modesByRefresh.contains { $0.mode.ioDisplayModeID == id }
    }

    private var tooltipText: String {
        let kind = group.isHiDPI ? "Scaled (HiDPI)" : "Native (1:1)"
        let pixels = "\(group.pixelWidth)×\(group.pixelHeight) pixels"
        let area = areaDelta
        return "\(kind) · \(pixels)\(area)"
    }

    private var areaDelta: String {
        guard let cur = currentMode else { return "" }
        let curArea = Double(cur.width) * Double(cur.height)
        let propArea = Double(group.pointWidth) * Double(group.pointHeight)
        guard curArea > 0 else { return "" }
        let pct = Int(((propArea - curArea) / curArea * 100).rounded())
        if pct == 0 { return "" }
        let sign = pct > 0 ? "+" : "−"
        return " · \(sign)\(abs(pct))% screen space"
    }
}

private struct ResolutionRow: View {
    let group: ResolutionGroup
    let currentMode: CGDisplayMode?
    let apply: (CGDisplayMode) -> Void
    @State private var isHovering = false

    private var currentModeID: Int32? { currentMode?.ioDisplayModeID }

    var body: some View {
        HStack(spacing: Design.Spacing.m) {
            Image(systemName: isCurrentSize ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(isCurrentSize ? AnyShapeStyle(Design.Palette.rowSelectedTint) : AnyShapeStyle(.tertiary))
                .frame(width: 14)

            Text(formatSize(group.pointWidth, group.pointHeight))
                .font(isCurrentSize ? Design.Typography.rowBold : Design.Typography.row)
                .fixedSize()

            if !isCurrentSize, let cur = currentMode {
                RealEstateBadge(
                    currentWidth: cur.width,
                    currentHeight: cur.height,
                    proposedWidth: group.pointWidth,
                    proposedHeight: group.pointHeight
                )
            }

            Spacer(minLength: Design.Spacing.s)

            if group.modesByRefresh.count <= 1 {
                if let only = group.modesByRefresh.first, only.hz > 0 {
                    Text("\(only.hz) Hz")
                        .font(Design.Typography.chip)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            } else {
                HStack(spacing: 3) {
                    ForEach(group.modesByRefresh, id: \.hz) { entry in
                        RefreshChip(
                            hz: entry.hz,
                            isActive: entry.mode.ioDisplayModeID == currentModeID,
                            action: { apply(entry.mode) }
                        )
                    }
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, Design.Spacing.l)
        .padding(.vertical, Design.Layout.rowVerticalPadding)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if let best = group.modesByRefresh.last?.mode {
                apply(best)
            }
        }
        .popover(isPresented: .constant(isHovering && !isCurrentSize), arrowEdge: .trailing) {
            if let cur = currentMode {
                PreviewBox(
                    currentWidth: cur.width,
                    currentHeight: cur.height,
                    proposedWidth: group.pointWidth,
                    proposedHeight: group.pointHeight,
                    maxSize: 120
                )
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isCurrentSize {
            Design.Palette.rowSelectedFill
        } else if isHovering {
            Color.secondary.opacity(0.08)
        } else {
            Color.clear
        }
    }

    private var isCurrentSize: Bool {
        guard let id = currentModeID else { return false }
        return group.modesByRefresh.contains { $0.mode.ioDisplayModeID == id }
    }

    private func formatSize(_ w: Int, _ h: Int) -> String {
        "\(formatThousands(w)) × \(formatThousands(h))"
    }
}

private struct RefreshChip: View {
    let hz: Int
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(hz > 0 ? "\(hz)" : "—")
                .font(isActive ? Design.Typography.chipActive : Design.Typography.chip)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .fixedSize()
                .frame(minWidth: Design.Layout.chipMinWidth)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.chip, style: .continuous)
                        .fill(chipFill)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(hz > 0 ? "\(hz) Hz" : "Unknown refresh rate")
    }

    private var chipFill: Color {
        if isActive { return Color.accentColor }
        if isHovering { return Color.secondary.opacity(0.32) }
        return Design.Palette.chipFill
    }
}

// MARK: - Number formatting (shared)

/// Cached formatter — instantiating NumberFormatter is surprisingly expensive
/// (it pulls locale data) and we'd otherwise allocate one per cell per render
/// for 22+ resolution rows.
private let thousandsFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "\u{202F}" // narrow no-break space
    f.usesGroupingSeparator = true
    return f
}()

private func formatThousands(_ n: Int) -> String {
    thousandsFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
}
