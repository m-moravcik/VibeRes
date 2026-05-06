import SwiftUI

struct MenuContent: View {
    @Environment(DisplayStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if store.displays.isEmpty {
                Text("No displays detected.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(Array(store.displays.enumerated()), id: \.element.id) { index, display in
                    if index > 0 {
                        Divider().padding(.vertical, 4)
                    }
                    DisplaySection(display: display)
                }
            }

            Divider().padding(.top, 4)

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
        .padding(.top, 6)
        .frame(width: 320)
    }
}

// MARK: - Display section

private struct DisplaySection: View {
    let display: DisplayInfo
    @State private var filter: ModeFilter = .hiDPIIfAvailable
    @Environment(DisplayStore.self) private var store

    enum ModeFilter: Hashable {
        case hiDPIIfAvailable
        case allNative
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: display.isMain ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
                Text(display.name).font(.headline)
                if display.isMain {
                    Text("MAIN")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
                Spacer()
                if hasBothKinds {
                    Picker("", selection: $filter) {
                        Text("HiDPI").tag(ModeFilter.hiDPIIfAvailable)
                        Text("Native").tag(ModeFilter.allNative)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
            .padding(.horizontal, 12)

            ForEach(visibleGroups) { group in
                ResolutionRow(
                    group: group,
                    currentModeID: display.currentMode?.ioDisplayModeID,
                    apply: { mode in store.apply(mode, to: display.id) }
                )
            }
        }
    }

    private var allGroups: [ResolutionGroup] {
        ResolutionGroup.build(from: display.modes)
    }

    private var hasBothKinds: Bool {
        let kinds = Set(allGroups.map(\.isHiDPI))
        return kinds.count > 1
    }

    private var visibleGroups: [ResolutionGroup] {
        switch filter {
        case .hiDPIIfAvailable:
            let hidpi = allGroups.filter(\.isHiDPI)
            return hidpi.isEmpty ? allGroups : hidpi
        case .allNative:
            let native = allGroups.filter { !$0.isHiDPI }
            return native.isEmpty ? allGroups : native
        }
    }
}

// MARK: - Resolution row

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

            Text("\(group.pointWidth) × \(group.pointHeight)")
                .font(.system(.body, design: .default).monospacedDigit())

            Spacer(minLength: 6)

            if group.modesByRefresh.count == 1, let only = group.modesByRefresh.first {
                // Single refresh rate — render as plain label, click whole row to apply.
                if only.hz > 0 {
                    Text("\(only.hz) Hz")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
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
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            // Clicking outside chips applies the highest refresh rate of this size.
            if let best = group.modesByRefresh.last?.mode {
                apply(best)
            }
        }
    }

    private var isCurrentSize: Bool {
        guard let id = currentModeID else { return false }
        return group.modesByRefresh.contains { $0.mode.ioDisplayModeID == id }
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
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(hz > 0 ? "\(hz) Hz" : "Unknown refresh rate")
    }
}
