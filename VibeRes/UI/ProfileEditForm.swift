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
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ForEach($state.entries) { $entry in
                row(for: $entry)
            }

            Text("MAIN DISPLAY")
                .font(Design.Typography.sectionHeader)
                .foregroundStyle(.secondary)
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

                let rates = ProfilesSection.LiveMode.rateChoices(
                    in: value.availableModes,
                    bucket: value.bucket
                )
                if !rates.isEmpty {
                    Picker("Hz", selection: rateBinding(entry, choices: rates)) {
                        ForEach(rates, id: \.self) { rate in
                            rateLabel(rate).tag(Optional(rate))
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

    /// A rate is a (Hz, kind) pair now, so "160 Hz" and "160 Hz VRR" are two
    /// picks. The getter maps the saved pair onto what is on offer, so an
    /// entry saved before VRR support still shows its 120 Hz on ProMotion.
    private func rateBinding(
        _ entry: Binding<ProfilesSection.EntryEdit>,
        choices: [ProfilesSection.LiveMode.RateChoice]
    ) -> Binding<ProfilesSection.LiveMode.RateChoice?> {
        Binding(
            get: { entry.wrappedValue.selectedRate(in: choices) },
            set: { choice in
                guard let choice else { return }
                entry.wrappedValue.refreshHz = choice.hz
                entry.wrappedValue.isVariableRefresh = choice.isVariable
            }
        )
    }

    @ViewBuilder
    private func rateLabel(_ rate: ProfilesSection.LiveMode.RateChoice) -> some View {
        if let hz = rate.hz {
            if rate.isVRRTwin {
                Text("\(hz) Hz VRR")
            } else {
                Text("\(hz) Hz")
            }
        } else {
            Text(verbatim: "—")
        }
    }

    /// Changing the size has to re-pick the rate: the old one is very often
    /// not offered at the new size, and a stale value would be saved as-is.
    /// Picked by the same rule as a one-click apply, so a VRR entry stays VRR
    /// where the new size offers it.
    private func sizeBinding(_ entry: Binding<ProfilesSection.EntryEdit>) -> Binding<ProfilesSection.LiveMode.Bucket> {
        Binding(
            get: { entry.wrappedValue.bucket },
            set: { bucket in
                entry.wrappedValue.pointWidth = bucket.pointWidth
                entry.wrappedValue.pointHeight = bucket.pointHeight
                entry.wrappedValue.isHiDPI = bucket.isHiDPI
                let rates = ProfilesSection.LiveMode.rateChoices(
                    in: entry.wrappedValue.availableModes,
                    bucket: bucket
                )
                let picked = ProfilesSection.LiveMode.preferredRate(
                    in: rates,
                    stayVariable: entry.wrappedValue.isVariableRefresh
                )
                entry.wrappedValue.refreshHz = picked?.hz
                entry.wrappedValue.isVariableRefresh = picked?.isVariable ?? false
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

    /// The saved mode as text, for a row whose display is not connected. It
    /// says VRR whenever the entry is variable: with nothing attached there
    /// is no fixed twin to check for.
    var savedModeDescription: String {
        var parts = ["\(pointWidth)×\(pointHeight)"]
        if let refreshHz { parts.append(isVariableRefresh ? "\(refreshHz) Hz VRR" : "\(refreshHz) Hz") }
        if isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }

    /// The rate a row points at, among `choices`: the saved (Hz, kind) pair
    /// when it is on offer, otherwise the same Hz of the other kind. The
    /// fallback is what keeps a profile saved before VRR support (always
    /// "fixed") pointing at ProMotion's variable-only 120 Hz.
    func selectedRate(in choices: [ProfilesSection.LiveMode.RateChoice]) -> ProfilesSection.LiveMode.RateChoice? {
        choices.first { $0.hz == refreshHz && $0.isVariable == isVariableRefresh }
            ?? choices.first { $0.hz == refreshHz }
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

    /// One entry in the rate picker: a rate and its refresh kind.
    struct RateChoice: Hashable {
        let hz: Int?
        let isVariable: Bool
        /// Variable, and the same size offers this rate fixed too: the only
        /// case the picker labels it "VRR".
        let isVRRTwin: Bool
    }

    /// The rates available at one size as picker choices: ascending, "no rate
    /// reported" first, and a VRR twin right after its fixed rate.
    static func rateChoices(
        in modes: [ProfilesSection.LiveMode],
        bucket: Bucket
    ) -> [RateChoice] {
        let matching = modes.filter {
            $0.pointWidth == bucket.pointWidth
                && $0.pointHeight == bucket.pointHeight
                && $0.isHiDPI == bucket.isHiDPI
        }
        let fixedRates = Set(matching.filter { !$0.isVariable }.map(\.refreshHz))
        let choices = Set(matching.map {
            RateChoice(
                hz: $0.refreshHz,
                isVariable: $0.isVariable,
                isVRRTwin: $0.isVariable && fixedRates.contains($0.refreshHz)
            )
        })
        return choices.sorted { a, b in
            switch (a.hz, b.hz) {
            case (nil, nil): return !a.isVariable && b.isVariable
            case (nil, _): return true
            case (_, nil): return false
            case let (.some(x), .some(y)):
                return x != y ? x < y : (!a.isVariable && b.isVariable)
            }
        }
    }

    /// The choice a size change lands on. See `VariableRefresh.preferredIndex`.
    static func preferredRate(in choices: [RateChoice], stayVariable: Bool) -> RateChoice? {
        let rated = choices.filter { $0.hz != nil }
        guard let index = VariableRefresh.preferredIndex(
            rated.map { (hz: $0.hz ?? 0, isVariable: $0.isVariable) },
            stayVariable: stayVariable
        ) else { return choices.first }
        return rated[index]
    }
}
