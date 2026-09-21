import SwiftUI

/// The inline "Edit profile" form: one row per saved entry, each of which can
/// be kept or dropped, flipped between a specific monitor and any external,
/// and re-pointed at a different mode.
///
/// Like `ProfileSaveForm`, it owns one binding to its whole state instead of
/// six that each re-found their row by id on every keystroke.
struct ProfileEditForm: View {
    @Binding var state: ProfilesSection.EditFormState
    let save: () -> Void
    let cancel: () -> Void

    @Environment(DisplayStore.self) private var displays
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Profile name", text: $state.name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($nameFieldFocused)
                    .onSubmit(save)
            }

            Text("ENTRIES")
                .font(Design.Typography.sectionHeader)
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            ForEach($state.entries) { $entry in
                row(for: $entry)
            }

            Text("MAIN DISPLAY")
                .font(Design.Typography.sectionHeader)
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            Picker(selection: $state.mainRowID) {
                Text("Don't change").tag(UUID?.none)
                ForEach(state.entries.filter(\.isIncluded)) { entry in
                    Text(entry.displayName).tag(UUID?.some(entry.id))
                }
            } label: { EmptyView() }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Main display")
            .help("Which display hosts the menu bar after this profile is applied. 'Don't change' leaves the arrangement alone.")

            if state.entries.allSatisfy({ !$0.isIncluded }) {
                Text("At least one entry must remain to save.")
                    .font(Design.Typography.note)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!state.isSavable)
            }
        }
        .padding(.horizontal, Design.Spacing.l)
        .onAppear { nameFieldFocused = true }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(for entry: Binding<ProfilesSection.EntryEdit>) -> some View {
        let value = entry.wrappedValue
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: keepBinding(entry)) {
                Image(systemName: value.isBuiltIn ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Keep \(value.displayName)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(value.rowTitle)
                        .font(Design.Typography.control)
                        .lineLimit(1)
                    if !value.isBuiltIn, value.matcherKind == .anyExternal {
                        Text("✱ flex")
                            .font(Design.Typography.badge)
                            .foregroundStyle(.tint)
                    }
                    if !isMatcherConnected(value) {
                        Text("not connected")
                            .font(Design.Typography.badge)
                            .foregroundStyle(.orange)
                    }
                }

                if value.isIncluded {
                    if !value.isBuiltIn {
                        let blocked = ProfilesSection.EditFormState.anyExternalTakenByAnother(
                            than: value.id,
                            in: state.entries
                        )
                        Toggle(isOn: anyExternalBinding(entry)) {
                            Text("Match any external monitor")
                                .font(Design.Typography.note)
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.mini)
                        .disabled(blocked)
                        .help(blocked
                              ? "Only one entry per profile can match 'any external monitor'."
                              : "")
                    }

                    modePicker(for: entry)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func modePicker(for entry: Binding<ProfilesSection.EntryEdit>) -> some View {
        let value = entry.wrappedValue
        if value.availableModes.isEmpty {
            // Nothing connected to enumerate modes from, so the saved values
            // are shown as text: the user still needs to know what will be
            // applied once a matching display comes back.
            Text(value.savedModeDescription)
                .font(Design.Typography.note)
                .foregroundStyle(.secondary)
        } else {
            // Two steps: a (size, HiDPI) bucket, then a refresh rate within it.
            let buckets = ProfilesSection.LiveMode.buckets(in: value.availableModes)
            HStack(spacing: 6) {
                Picker("Size", selection: sizeBinding(entry)) {
                    ForEach(buckets, id: \.self) { bucket in
                        Text(bucket.label).tag(bucket)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.mini)

                let rates = ProfilesSection.LiveMode.refreshOptions(
                    in: value.availableModes,
                    bucket: value.bucket
                )
                if !rates.isEmpty {
                    Picker("Hz", selection: entry.refreshHz) {
                        ForEach(rates, id: \.self) { hz in
                            Text(hz.map { "\($0) Hz" } ?? "—").tag(hz)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.mini)
                }
            }
        }
    }

    // MARK: Bindings with a side effect

    /// Un-including the row picked as main leaves the picker pointing at
    /// nothing, so the pick is cleared with it.
    private func keepBinding(_ entry: Binding<ProfilesSection.EntryEdit>) -> Binding<Bool> {
        Binding(
            get: { entry.wrappedValue.isIncluded },
            set: { newValue in
                entry.wrappedValue.isIncluded = newValue
                if !newValue, state.mainRowID == entry.wrappedValue.id {
                    state.mainRowID = nil
                }
            }
        )
    }

    private func anyExternalBinding(_ entry: Binding<ProfilesSection.EntryEdit>) -> Binding<Bool> {
        Binding(
            get: { entry.wrappedValue.matcherKind == .anyExternal },
            set: { entry.wrappedValue.matcherKind = $0 ? .anyExternal : .specific }
        )
    }

    /// Changing the size has to re-pick the rate: the old one is very often
    /// not offered at the new size, and a stale value would be saved as-is.
    private func sizeBinding(_ entry: Binding<ProfilesSection.EntryEdit>) -> Binding<ProfilesSection.LiveMode.Bucket> {
        Binding(
            get: { entry.wrappedValue.bucket },
            set: { bucket in
                entry.wrappedValue.pointWidth = bucket.pointWidth
                entry.wrappedValue.pointHeight = bucket.pointHeight
                entry.wrappedValue.isHiDPI = bucket.isHiDPI
                let rates = ProfilesSection.LiveMode.refreshOptions(
                    in: entry.wrappedValue.availableModes,
                    bucket: bucket
                )
                entry.wrappedValue.refreshHz = rates.compactMap { $0 }.max() ?? rates.first ?? nil
            }
        )
    }

    // MARK: Live state

    /// Whether anything currently attached satisfies this row's matcher.
    private func isMatcherConnected(_ entry: ProfilesSection.EntryEdit) -> Bool {
        switch entry.matcherKind {
        case .anyExternal:
            return displays.displays.contains { CGDisplayIsBuiltin($0.id) == 0 }
        case .specific:
            if entry.isBuiltIn {
                return displays.displays.contains { CGDisplayIsBuiltin($0.id) != 0 }
            }
            return displays.displays.contains {
                CGDisplayVendorNumber($0.id) == entry.vendor
                    && CGDisplayModelNumber($0.id) == entry.model
                    && CGDisplaySerialNumber($0.id) == entry.serial
            }
        }
    }
}

// MARK: - Pure form logic
//
// Everything below is arithmetic and formatting on the form's own state, which
// means it can be tested without a view. That is the point of moving it here.

extension ProfilesSection.EditFormState {
    /// Whether Save should be available.
    var isSavable: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && entries.contains(where: \.isIncluded)
    }

    /// True when a *different* kept row is already `.anyExternal`. Disabling
    /// the second toggle keeps the user out of a state the store rejects.
    static func anyExternalTakenByAnother(
        than rowID: UUID,
        in entries: [ProfilesSection.EntryEdit]
    ) -> Bool {
        entries.contains { $0.id != rowID && $0.isIncluded && $0.matcherKind == .anyExternal }
    }
}

extension ProfilesSection.EntryEdit {
    /// The (size, HiDPI) bucket this row currently points at.
    var bucket: ProfilesSection.LiveMode.Bucket {
        ProfilesSection.LiveMode.Bucket(
            pointWidth: pointWidth,
            pointHeight: pointHeight,
            isHiDPI: isHiDPI
        )
    }

    /// What a flexible row calls itself: naming the monitor it was saved from
    /// would be a lie about a row that matches any external.
    var rowTitle: String {
        matcherKind == .anyExternal ? "Any external" : displayName
    }

    var savedModeDescription: String {
        var parts = ["\(pointWidth)×\(pointHeight)"]
        if let refreshHz { parts.append("\(refreshHz) Hz") }
        if isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }
}

extension ProfilesSection.LiveMode {
    /// One entry in the size picker.
    struct Bucket: Hashable {
        let pointWidth: Int
        let pointHeight: Int
        let isHiDPI: Bool

        var label: String {
            "\(pointWidth)×\(pointHeight)" + (isHiDPI ? " HiDPI" : "")
        }
    }

    /// The distinct sizes on offer, largest first, HiDPI before native at the
    /// same size.
    static func buckets(in modes: [ProfilesSection.LiveMode]) -> [Bucket] {
        var seen: Set<Bucket> = []
        var out: [Bucket] = []
        for mode in modes {
            let bucket = Bucket(
                pointWidth: mode.pointWidth,
                pointHeight: mode.pointHeight,
                isHiDPI: mode.isHiDPI
            )
            if seen.insert(bucket).inserted { out.append(bucket) }
        }
        return out.sorted { lhs, rhs in
            if lhs.pointWidth != rhs.pointWidth { return lhs.pointWidth > rhs.pointWidth }
            if lhs.pointHeight != rhs.pointHeight { return lhs.pointHeight > rhs.pointHeight }
            return lhs.isHiDPI && !rhs.isHiDPI
        }
    }

    /// The refresh rates available at one size, ascending, with "no rate
    /// reported" first.
    static func refreshOptions(
        in modes: [ProfilesSection.LiveMode],
        bucket: Bucket
    ) -> [Int?] {
        let matching = modes.filter {
            $0.pointWidth == bucket.pointWidth
                && $0.pointHeight == bucket.pointHeight
                && $0.isHiDPI == bucket.isHiDPI
        }
        return Set(matching.map(\.refreshHz)).sorted { a, b in
            switch (a, b) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (.some(x), .some(y)): return x < y
            }
        }
    }
}
