import SwiftUI

struct MenuContent: View {
    @Environment(DisplayStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            if store.displays.isEmpty {
                Text("No displays detected.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(store.displays) { display in
                    DisplaySection(display: display)
                }
            }

            Divider()

            HStack {
                Button("Refresh") { store.refresh() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }
}

private struct DisplaySection: View {
    let display: DisplayInfo
    @Environment(DisplayStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(display.name).font(.headline)
                if display.isMain {
                    Text("MAIN")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.25), in: Capsule())
                }
            }
            .padding(.horizontal, 12)

            ForEach(grouped, id: \.id) { group in
                Section {
                    ForEach(group.modes, id: \.ioDisplayModeID) { mode in
                        ModeRow(mode: mode, isCurrent: mode.ioDisplayModeID == display.currentMode?.ioDisplayModeID) {
                            store.apply(mode, to: display.id)
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
            }
        }
    }

    private struct Group: Identifiable {
        let id: String
        let title: String
        let modes: [CGDisplayMode]
    }

    private var grouped: [Group] {
        let hiDPI = display.modes
            .filter(\.isHiDPI)
            .sorted { ($0.width, $0.refreshHz ?? 0) > ($1.width, $1.refreshHz ?? 0) }
        let native = display.modes
            .filter { !$0.isHiDPI }
            .sorted { ($0.width, $0.refreshHz ?? 0) > ($1.width, $1.refreshHz ?? 0) }
        var out: [Group] = []
        if !hiDPI.isEmpty { out.append(Group(id: "hidpi", title: "HiDPI (Looks like)", modes: hiDPI)) }
        if !native.isEmpty { out.append(Group(id: "native", title: "Native", modes: native)) }
        return out
    }
}

private struct ModeRow: View {
    let mode: CGDisplayMode
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isCurrent ? "checkmark" : "circle.dotted")
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                    .frame(width: 14)
                Text(mode.menuDescription)
                Spacer()
                if mode.isHiDPI {
                    Text("\(mode.pixelWidth)×\(mode.pixelHeight)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
