import SwiftUI

struct MenuContent: View {
    @Environment(DisplayStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var path = NavigationPath()
    @State private var menuTracking = false

    var body: some View {
        Group {
            // First-launch onboarding takes over the popover entirely until
            // the user finishes or skips. Drawing it as a peer of the
            // navigation stack (instead of a SwiftUI sheet) keeps it inside
            // the menu-bar window — sheets pop out into a separate panel
            // that breaks the "dropdown" mental model.
            if !preferences.onboardingShown {
                OnboardingView()
            } else {
                NavigationStack(path: $path) {
                    RootView(path: $path)
                        .navigationDestination(for: DisplayInfo.ID.self) { displayID in
                            DisplayDetailView(displayID: displayID)
                        }
                }
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
    @Environment(ProfileStore.self) private var profiles
    @Environment(UpdateStatus.self) private var updateStatus
    @Environment(\.updater) private var updater
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 0) {
            // Display problems first — they are about what is on screen right
            // now. A profile that could not be read or written is also worth
            // saying: `ProfileStore` recorded it and nothing ever showed it.
            if let problem = store.lastError {
                ProblemRow(problem: problem) { store.dismissLastError() }
            }
            if let problem = profiles.lastError {
                ProblemRow(problem: problem) { profiles.dismissLastError() }
            }

            if updateStatus.isUpdateReady {
                UpdateReadyBanner { updater?.installUpdate() }
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
                            // Safety net for the launch-race / wake-race case
                            // where the initial snapshot was empty AND the
                            // retry loop in DisplayStore also missed. Opening
                            // the menu is the user's "try again" signal — run
                            // one extra refresh on appear so they don't have
                            // to find the Refresh button.
                            .onAppear { store.refresh() }
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

            if let seconds = store.confirmationSecondsRemaining {
                // The countdown is the safety net; this row is for people who can
                // see the screen and do not want to wait it out.
                HStack(spacing: Design.Spacing.s) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(Design.Typography.note)
                    Text("Keep this resolution? Reverting in \(seconds)s")
                        .font(Design.Typography.note)
                    Spacer(minLength: Design.Spacing.s)
                    Button("Keep") { store.confirmDisplayChange() }
                        .font(Design.Typography.note)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal, Design.Spacing.l)
                .padding(.vertical, Design.Spacing.xs)
                .background(Color.orange.opacity(0.12))
            }

            FooterBar()
        }
    }
}

/// The error row in the popover, with the acknowledgement it used to lack.
///
/// The copy is resolved through `UserFacingProblem.localizedDescription`, so a
/// Slovak or German interface no longer carries an English sentence about a
/// CoreGraphics failure.
private struct ProblemRow: View {
    let problem: UserFacingProblem
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Design.Typography.footer)
                .accessibilityHidden(true)
            Text(verbatim: problem.localizedDescription)
                .font(Design.Typography.footer)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Design.Spacing.s)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .help("Dismiss")
        }
        .foregroundStyle(.red)
        .padding(.horizontal, Design.Spacing.l)
        .padding(.top, Design.Spacing.xs)
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
    /// Collapsed by default: the tail of the size list is rarely what someone
    /// came for. Resets per detail-view appearance, like the hover state.
    @State private var showSmallerSizes = false
    /// Height of the list's content, measured, so the scroll view can be as
    /// tall as its rows up to `listMaxHeight`. A fixed ideal height left a
    /// blank band under the list once the smaller sizes started collapsed.
    @State private var listContentHeight: CGFloat?
    private static let listMaxHeight: CGFloat = 480
    /// Y-coordinate of the hovered row inside this detail view's coordinate
    /// space, used by the side popover anchor.
    /// Per-row Y midpoints, keyed by ResolutionGroup.id. Updated each
    /// render via PreferenceKey so onHoverChange can read the right Y

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

            // A failed apply used to be completely silent here: the error row
            // lived only on the root view, and applying a mode does not pop
            // the navigation stack — so the user clicked a resolution, nothing
            // changed, and nothing said why.
            if let problem = store.lastError {
                ProblemRow(problem: problem) { store.dismissLastError() }
            }

            if let display {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        currentModeCard(for: display)
                        makeMainRow(for: display)
                        filterToggle(for: display)
                        livePreviewHint
                        sizeList(for: display)
                    }
                    .padding(.vertical, 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        listContentHeight = height
                    }
                }
                .frame(idealHeight: min(listContentHeight ?? Self.listMaxHeight, Self.listMaxHeight))
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
                    .font(Design.Typography.footer)
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

    // MARK: Make main display

    /// One-off sibling of the profile "main display" pin: only worth showing
    /// when there is somewhere else the menu bar could go, and when it isn't
    /// already here.
    @ViewBuilder
    private func makeMainRow(for display: DisplayInfo) -> some View {
        if !display.isMain, store.displays.count > 1 {
            HStack {
                Button {
                    store.makeMain(display.id)
                } label: {
                    Label("Make main display", systemImage: "menubar.rectangle")
                        .font(Design.Typography.control)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Moves the menu bar and Dock to this display. The arrangement only shifts — relative positions are preserved.")
                Spacer()
            }
            .padding(.horizontal, Design.Spacing.l)
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

    // MARK: Live preview hint

    /// Offers live preview once, where it would be used.
    ///
    /// The feature that separates VibeRes from the alternatives shipped off by
    /// default with its only mention in a Settings tab, so most people never
    /// found out it exists. The hint sits directly above the rows it applies
    /// to, turns the feature on in place rather than sending the user to
    /// Settings, and never comes back once it has been answered.
    @ViewBuilder
    private var livePreviewHint: some View {
        if !preferences.livePreviewEnabled, !preferences.livePreviewHintDismissed {
            HStack(alignment: .center, spacing: Design.Spacing.s) {
                Image(systemName: "sparkles")
                    .font(Design.Typography.note)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("See your desktop in the preview?")
                    .font(Design.Typography.note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Design.Spacing.s)

                Button("Turn on") {
                    preferences.livePreviewEnabled = true
                    // Same reset the Settings toggle does: re-enabling is the
                    // user's signal to try the permission again.
                    DesktopCapture.resetPermissionCache()
                    preferences.livePreviewHintDismissed = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("Shows a screenshot of your desktop scaled into the proposed mode. Asks for Screen Recording the first time.")

                Button {
                    preferences.livePreviewHintDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .help("Dismiss")
            }
            .padding(.horizontal, Design.Spacing.l)
            .padding(.bottom, 6)
        }
    }

    // MARK: Resolution list

    @ViewBuilder
    private func sizeList(for display: DisplayInfo) -> some View {
        let groups = visibleGroups(for: display)
        let split = ResolutionListPartition.split(
            sizes: groups.map { (width: $0.pointWidth, height: $0.pointHeight) },
            currentIndex: groups.firstIndex { group in
                group.modesByRefresh.contains {
                    $0.mode.ioDisplayModeID == display.currentMode?.ioDisplayModeID
                }
            }
        )

        VStack(spacing: 0) {
            ForEach(split.primary, id: \.self) { index in
                row(for: groups[index], on: display)
            }

            if !split.collapsed.isEmpty {
                // The small end of the list is available but not in the way.
                // Collapsed rather than dropped: someone occasionally does want
                // 1280×720 for a screen share.
                DisclosureGroup(isExpanded: $showSmallerSizes) {
                    ForEach(split.collapsed, id: \.self) { index in
                        row(for: groups[index], on: display)
                    }
                } label: {
                    Text("\(split.collapsed.count) smaller sizes")
                        .font(Design.Typography.cardSubtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Design.Spacing.l)
                .padding(.top, Design.Spacing.xs)
            }
        }
        // One snapshot per detail-view appearance, taken on the *first hover*
        // rather than on appearance.
        //
        // It used to fire on appearance, which meant someone who turned on
        // "Live preview on hover" was asked for Screen Recording the moment
        // they opened a display — before they had hovered anything, and with
        // nothing on screen connecting the prompt to the feature. Apple's
        // guidance is to ask at the point of use, and this is that point.
        // Failures still fall back silently to the geometric preview.
        .task(id: hoveredGroupID) {
            guard preferences.livePreviewEnabled,
                  hoveredGroupID != nil,
                  desktopSnapshot == nil
            else { return }
            desktopSnapshot = await DesktopCapture.snapshot(of: displayID)
        }
        .onChange(of: displayID) { _, _ in
            // Belt and braces: a detail view is rebuilt per display, but a
            // reused instance must not paint one display's desktop into
            // another's preview.
            desktopSnapshot = nil
        }
    }

    @ViewBuilder
    private func row(for group: ResolutionGroup, on display: DisplayInfo) -> some View {
        let isCurrent = group.modesByRefresh.contains {
            $0.mode.ioDisplayModeID == display.currentMode?.ioDisplayModeID
        }
        CompactResolutionRow(
            group: group,
            currentMode: display.currentMode,
            isHovered: hoveredGroupID == group.id,
            simpleMode: preferences.simpleMode,
            onHoverChange: { hovering in
                guard !isCurrent else { return }
                hoveredGroupID = hovering ? group.id : (hoveredGroupID == group.id ? nil : hoveredGroupID)
            },
            apply: { mode in store.apply(mode, to: display.id, confirmFirst: preferences.confirmDisplayChanges) }
        )
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
    @Environment(UpdateStatus.self) private var updateStatus
    @Environment(\.updater) private var updater
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
                        // The label was previously omitted because applying a
                        // resolution dismissed the popover, so ⌘Z lost key focus
                        // before anyone could press it. That dismissal was a bug
                        // in the debounced refresh path and is fixed, so the
                        // shortcut now works exactly when this row is visible
                        // and can be advertised honestly.
                        shortcut: "⌘Z",
                        action: {
                            store.performRevert()
                            // No toast — displays jump back, the row
                            // disappears, that's the feedback.
                        }
                    )
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
                        updater?.checkForUpdates()
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
    ///
    /// Built from the history's values rather than `RevertHistory.summary`,
    /// which stays English for the CLI and the log.
    private var revertLabel: LocalizedStringKey {
        let revert = store.revert
        let alsoMain = revert.beforeMainID != nil
        switch revert.entries.count {
        case 0:
            // A main-only revert has no entries — name it rather than falling
            // back to the generic label.
            return alsoMain ? "Revert main display" : "Revert last change"
        case 1:
            let entry = revert.entries[0]
            let size = "\(entry.before.width)×\(entry.before.height)"
            return alsoMain
                ? "Revert \(entry.displayName) → \(size) and main display"
                : "Revert \(entry.displayName) → \(size)"
        case let n:
            return "Revert last change (\(n) displays)"
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
    /// A key, not a `String`: `Text(String)` is verbatim, which is how the
    /// footer stayed English in every language while its translations sat
    /// unused in the catalog.
    let label: LocalizedStringKey
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
private struct UpdateReadyBanner: View {
    let install: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: install) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update ready")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Click to restart into the new version")
                        .font(Design.Typography.note)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(Design.Typography.footer)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.card)
                    .fill(Color.green.opacity(isHovering ? 0.18 : 0.10))
            )
            .padding(.horizontal, Design.Spacing.m)
            .padding(.top, Design.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Installs the downloaded update and relaunches VibeRes")
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
                    .font(Design.Typography.control)
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

/// One row per point size.
///
/// The inline real-estate badge is deliberately absent: it competed visually
/// with the refresh chips and crowded the row. The percentage still reaches the
/// user through `tooltipText`. Keep it that way unless the row layout changes.
/// Refresh rates render as a native segmented Picker for accessibility and
/// consistency with other macOS controls.
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

    /// The row is a `Button`, not an `HStack` with an `.onTapGesture`.
    ///
    /// It used to be the latter, which made the app's primary action
    /// mouse-only: a tap gesture is not an accessibility element with an
    /// action, so VoiceOver announced a static group and keyboard focus never
    /// landed on the row. Simple Mode — the default for fresh installs — hides
    /// the per-rate chips, so that gesture was the *only* way to apply a mode.
    ///
    /// The two modes build different button shapes rather than nesting
    /// buttons, because a button inside a button is where SwiftUI's hit
    /// testing on macOS gets unpredictable:
    ///  - Simple Mode: the whole row is one button.
    ///  - Advanced Mode: the size label is a button that applies the highest
    ///    rate, and each chip is its own button beside it — so clicking the
    ///    label or the gap still means "I don't care, give me the best rate"
    ///    instead of being a dead zone.
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if simpleMode {
                rowButton {
                    HStack(alignment: .center, spacing: 10) {
                        sizeLabel
                        Spacer(minLength: 6)
                        simpleHzLabel
                    }
                }
            } else {
                rowButton {
                    HStack(alignment: .center, spacing: 0) {
                        sizeLabel
                        Spacer(minLength: 6)
                    }
                }
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
    }

    /// Wraps a row label in the apply button, with the accessibility and
    /// tooltip surface both modes share.
    @ViewBuilder
    private func rowButton<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button {
            if let mode = preferredMode {
                apply(mode)
            }
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(tooltipText)
        .help(tooltipText)
    }

    /// What VoiceOver reads for the row's action. In Simple Mode it has to
    /// carry the refresh rate too, because the Hz label beside it is decorative.
    private var accessibilityLabelText: String {
        var text = "\(group.pointWidth) by \(group.pointHeight)"
        if simpleMode, let hz = preferredMode?.refreshHz {
            text += ", \(hz) hertz"
        }
        if isCurrentSize { text += ", current" }
        return text
    }

    private var sizeLabel: some View {
        Text("\(formatThousands(group.pointWidth)) × \(formatThousands(group.pointHeight))")
            .font(.system(size: 13, weight: isCurrentSize ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(isCurrentSize ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .frame(minWidth: 100, alignment: .leading)
            .accessibilityHidden(true)
    }

    /// Subtle Hz hint shown in Simple Mode — communicates the preferred
    /// refresh rate without the chip group's chrome. Hidden from VoiceOver
    /// because `accessibilityLabelText` already says it.
    @ViewBuilder
    private var simpleHzLabel: some View {
        if let preferred = preferredMode {
            Text(preferred.refreshHz.map { "\($0) Hz" } ?? "")
                .font(Design.Typography.cardSubtitle)
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
        guard let cur = currentMode,
              let pct = RealEstateBadge.percentChange(
                  currentWidth: cur.width, currentHeight: cur.height,
                  proposedWidth: group.pointWidth, proposedHeight: group.pointHeight
              ),
              pct != 0
        else { return "" }
        let sign = pct > 0 ? "+" : "−"
        return " · \(sign)\(abs(pct))% screen space"
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
