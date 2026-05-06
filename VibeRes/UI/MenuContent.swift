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
        .frame(width: 320)
        .frame(minHeight: 200, maxHeight: 560)
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
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            ScrollView {
                VStack(spacing: 6) {
                    if store.displays.isEmpty {
                        Text("No displays detected.")
                            .foregroundStyle(.secondary)
                            .padding(20)
                    } else {
                        ForEach(store.displays) { display in
                            DisplayCard(display: display) {
                                path.append(display.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            Divider()

            HStack {
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh display list")

                Spacer()

                Button("Quit VibeRes") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

private struct DisplayCard: View {
    let display: DisplayInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: display.isMain ? "laptopcomputer" : "display")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(display.name)
                            .font(.headline)
                            .lineLimit(1)
                        if display.isMain {
                            Text("MAIN")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.2), in: Capsule())
                        }
                    }
                    if let cur = display.currentMode {
                        Text(currentModeSubtitle(cur))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func currentModeSubtitle(_ m: CGDisplayMode) -> String {
        var parts = ["\(m.width) × \(m.height)"]
        if let hz = m.refreshHz { parts.append("@ \(hz) Hz") }
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
                                currentModeID: display.currentMode?.ioDisplayModeID,
                                apply: { mode in store.apply(mode, to: display.id) }
                            )
                            Divider().opacity(0.3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("Display unavailable.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(display?.name ?? "Display")
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Symmetric placeholder so the title stays centered.
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if let display, hasBothKinds(for: display) {
                Picker("", selection: $filter) {
                    Text("HiDPI").tag(ModeFilter.hiDPIIfAvailable)
                    Text("Native").tag(ModeFilter.allNative)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()
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

// MARK: - Resolution row + chip

private struct ResolutionRow: View {
    let group: ResolutionGroup
    let currentModeID: Int32?
    let apply: (CGDisplayMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isCurrentSize ? "checkmark" : "circle.dotted")
                .font(.caption)
                .foregroundStyle(isCurrentSize ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .frame(width: 14)

            Text(formatSize(group.pointWidth, group.pointHeight))
                .font(.system(.body).monospacedDigit())
                .fixedSize()

            Spacer(minLength: 6)

            if group.modesByRefresh.count <= 1 {
                if let only = group.modesByRefresh.first, only.hz > 0 {
                    Text("\(only.hz) Hz")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            } else {
                HStack(spacing: 4) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if let best = group.modesByRefresh.last?.mode {
                apply(best)
            }
        }
    }

    private var isCurrentSize: Bool {
        guard let id = currentModeID else { return false }
        return group.modesByRefresh.contains { $0.mode.ioDisplayModeID == id }
    }

    /// Formats numbers with NBSP thousand separator the way the user's locale shows them
    /// in the screenshot (1 800 × 1 169) without taking a hard locale dependency.
    private func formatSize(_ w: Int, _ h: Int) -> String {
        "\(formatThousands(w)) × \(formatThousands(h))"
    }

    private func formatThousands(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}" // narrow no-break space
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private struct RefreshChip: View {
    let hz: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(hz > 0 ? "\(hz)" : "—")
                .font(.caption2.monospacedDigit().weight(isActive ? .bold : .regular))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(isActive ? Color.accentColor : Color.secondary.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
        .help(hz > 0 ? "\(hz) Hz" : "Unknown refresh rate")
    }
}
