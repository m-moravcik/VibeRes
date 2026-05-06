import SwiftUI

struct MenuContent: View {
    @Environment(DisplayStore.self) private var store
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            RootView(path: $path)
                .navigationDestination(for: DisplayInfo.ID.self) { displayID in
                    DisplayDetailView(displayID: displayID)
                }
        }
        .frame(width: Design.Layout.popoverWidth)
        .frame(minHeight: Design.Layout.popoverMinHeight, maxHeight: Design.Layout.popoverMaxHeight)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Root: list of displays

private struct RootView: View {
    @Environment(DisplayStore.self) private var store
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 0) {
            if let err = store.lastError {
                Text(err)
                    .font(Design.Typography.footer)
                    .foregroundStyle(.red)
                    .padding(.horizontal, Design.Spacing.l)
                    .padding(.top, Design.Spacing.m)
            }

            ScrollView {
                VStack(spacing: Design.Spacing.s) {
                    if store.displays.isEmpty {
                        Text("No displays detected.")
                            .foregroundStyle(.secondary)
                            .padding(Design.Spacing.xl)
                    } else {
                        ForEach(store.displays) { display in
                            DisplayCard(display: display) {
                                path.append(display.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, Design.Spacing.m)
                .padding(.top, Design.Spacing.m)
                .padding(.bottom, Design.Spacing.s)
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
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ModeFilter = .hiDPIIfAvailable

    enum ModeFilter: Hashable {
        case hiDPIIfAvailable
        case allNative
    }

    private var display: DisplayInfo? {
        store.displays.first(where: { $0.id == displayID })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let display {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleGroups(for: display)) { group in
                            ResolutionRow(
                                group: group,
                                currentMode: display.currentMode,
                                apply: { mode in store.apply(mode, to: display.id) }
                            )
                        }
                    }
                    .padding(.vertical, Design.Spacing.xs)
                }
            } else {
                Text("Display unavailable.")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            FooterBar()
        }
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        VStack(spacing: Design.Spacing.s) {
            ZStack {
                Text(display?.name ?? "Display")
                    .font(Design.Typography.navTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 1) {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                            Text("Back")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderless)

                    Spacer()
                }
            }
            .padding(.horizontal, Design.Spacing.m)
            .padding(.top, Design.Spacing.m)

            if let display, hasBothKinds(for: display) {
                Picker("", selection: $filter) {
                    Text("HiDPI").tag(ModeFilter.hiDPIIfAvailable)
                    Text("Native").tag(ModeFilter.allNative)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .padding(.horizontal, Design.Spacing.l)
                .padding(.bottom, Design.Spacing.xs)
            }

            Rectangle()
                .fill(Design.Palette.separator)
                .frame(height: 1)
        }
    }

    private func allGroups(for display: DisplayInfo) -> [ResolutionGroup] {
        ResolutionGroup.build(from: display.modes)
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

/// Native-style menu in the popover footer. SwiftUI's `Menu` bridges to NSMenu so we get
/// real macOS chrome: SF symbol icons on the left, labels in the middle, ⌘-shortcuts on
/// the right — same look as standard menubar apps' dropdowns.
private struct FooterBar: View {
    @Environment(DisplayStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Design.Palette.separator)
                .frame(height: 1)

            HStack(spacing: 0) {
                Spacer()

                Menu {
                    Button {
                        store.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")

                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                        // Settings scene placeholder until Phase 4 lands.
                    } label: {
                        Label("Settings…", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",")
                    .disabled(true)

                    Divider()

                    Button {
                        showAbout()
                    } label: {
                        Label("About VibeRes", systemImage: "info.circle")
                    }

                    Divider()

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                    }
                    .keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More options")
            }
            .padding(.horizontal, Design.Spacing.m)
            .padding(.vertical, Design.Spacing.xs + 2)
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

// MARK: - Resolution row

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

private func formatThousands(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "\u{202F}" // narrow no-break space
    f.usesGroupingSeparator = true
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
