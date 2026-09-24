import SwiftUI
import os.log

private let autoApplyLog = Logger(subsystem: "sk.moravcik.VibeRes", category: "autoApply")

/// Compact profiles strip shown above the displays list. Each saved profile is one
/// pill button; tap to apply, right-click for actions. "+" pill expands an inline
/// save form letting users include/exclude displays and mark externals as flexible.
struct ProfilesSection: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(DisplayStore.self) private var displays
    @Environment(Preferences.self) private var preferences
    @State private var mode: Mode = .idle
    @State private var lastNote: NoteBody?
    @State private var lastNoteTone: ApplyOutcomeNote.Tone = .info
    /// Tracks the last auto-apply signal we acted on so we don't re-apply the
    /// same display/wake event multiple times if the popover redraws.
    @State private var lastObservedAutoApplyToken: Int = -1
    @FocusState private var nameFieldFocused: Bool
    /// Opens the save form on appear, for the screenshot harness. See `RootView`.
    private let opensSaveForm: Bool

    init(opensSaveForm: Bool = false) {
        self.opensSaveForm = opensSaveForm
    }

    /// What the note under the pills is currently showing.
    ///
    /// Apply results arrive as a structured `ApplyOutcomeNote` so they can be
    /// localised from values rather than from pre-formatted English. The ad-hoc
    /// confirmations ("Updated 'Desk'") are String Catalog keys.
    enum NoteBody: Equatable {
        case outcome(ApplyOutcomeNote)
        case message(LocalizedStringKey)

        var text: Text {
            switch self {
            // Already resolved through the String Catalog, so verbatim — a
            // second lookup would search for the translated sentence as a key.
            case let .outcome(note): return Text(verbatim: note.localizedDescription)
            case let .message(key): return Text(key)
            }
        }
    }

    /// What the section is currently showing.
    enum Mode: Equatable {
        case idle
        case saving(SaveFormState)
        case renaming(profileID: UUID, newName: String)
        case editing(EditFormState)
        /// Partial-match warning before a manual apply commits. Shows which
        /// entries will be skipped / which live displays go untouched, plus
        /// Apply Anyway / Cancel buttons. Kept inline (not NSAlert) so the
        /// popover doesn't dismiss while the user reads.
        case confirmingApply(ConfirmApplyState)
        /// Deleting a profile is the one irreversible action in the app —
        /// there is no undo and `⌘Z` is wired to display revert, not to the
        /// profile store. Inline for the same reason as `confirmingApply`: an
        /// NSAlert dismisses the popover out from under the question.
        case confirmingDelete(profileID: UUID, name: String)
    }

    struct ConfirmApplyState: Equatable {
        let profileID: UUID
        let profileName: String
        let preview: ProfileApplyPreview
        let classification: DisplaySetClassifier.Classification
    }

    /// State of the inline "Save profile" form.
    struct SaveFormState: Equatable {
        var name: String = ""
        /// Per-display: include? + how to bind (specific vs anyExternal)
        var perDisplay: [DisplayChoice] = []
        /// Which included display becomes main on apply; nil = don't change.
        var mainDisplayID: CGDirectDisplayID?
    }

    struct DisplayChoice: Equatable, Identifiable {
        let displayID: CGDirectDisplayID
        let displayName: String
        let isBuiltIn: Bool
        let currentModeDescription: String
        var isIncluded: Bool
        var matchAnyExternal: Bool   // only meaningful for non-built-in
        var id: CGDirectDisplayID { displayID }
    }

    /// State of the inline "Edit profile" form. Each row corresponds to one
    /// existing Profile.Entry; the user can flip its include flag, switch
    /// between specific/anyExternal matchers (externals only), and tweak
    /// the recorded mode (point size + Hz + HiDPI). When the matched live
    /// display is connected we offer real available modes; when it isn't,
    /// we let the user keep or hand-edit the snapshotted values.
    struct EditFormState: Equatable {
        let profileID: UUID
        var name: String
        var entries: [EntryEdit]
        /// Row whose display becomes main on apply; nil = don't change.
        var mainRowID: UUID?
    }

    struct EntryEdit: Equatable, Identifiable {
        let id: UUID  // synthesised per-row, stable across binding renders
        var matcherKind: MatcherKind     // specific (edid/builtIn) vs anyExternal
        var isBuiltIn: Bool              // immutable — derived from original matcher
        var vendor: UInt32               // remembered for restore on specific switch
        var model: UInt32
        var serial: UInt32
        var displayName: String
        var pointWidth: Int
        var pointHeight: Int
        var refreshHz: Int?
        var isHiDPI: Bool
        var isIncluded: Bool
        /// Live modes available right now for the bound display, if any. Empty
        /// when the matcher doesn't bind to a connected display — user keeps
        /// the snapshotted values without a picker.
        var availableModes: [LiveMode]
    }

    enum MatcherKind: Equatable {
        case specific
        case anyExternal
    }

    /// Trimmed CGDisplayMode info captured at form-build time so the picker
    /// menus don't keep CG references alive across re-renders.
    struct LiveMode: Equatable, Hashable {
        let pointWidth: Int
        let pointHeight: Int
        let refreshHz: Int?
        let isHiDPI: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("PROFILES")
                    .font(Design.Typography.sectionHeader)
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                    // Tooltip moved off the standalone info-circle icon (which read
                    // as "click me" but only reacted to hover) onto the label
                    // itself. Power users still get the explanation on hover; the
                    // header no longer mis-signals an interactive control.
                    .help("Profiles save the resolution and refresh rate of each chosen display so you can apply them with one click. Externals can be locked to a specific monitor or set to match any external (handy for presentations).")
                Spacer()
            }
            .padding(.horizontal, Design.Spacing.l)
            .padding(.top, Design.Spacing.s)

            switch mode {
            case .idle:
                idlePillBar
            case .saving:
                saveForm
            case .renaming:
                renameForm
            case .editing:
                editForm
            case .confirmingApply:
                confirmApplyPanel
            case .confirmingDelete:
                confirmDeletePanel
            }

            // Watch for display add/remove events and settled wake refreshes;
            // mode-only changes (user manually picks a different resolution)
            // don't bump the token, so they're ignored.
            EmptyView()
                .onChange(of: displays.autoApplyToken) { _, newToken in
                    autoApplyLog.notice("token onChange: new=\(newToken) lastObserved=\(lastObservedAutoApplyToken) autoApplyEnabled=\(preferences.autoApplyOnDisplayChange)")
                    guard preferences.autoApplyOnDisplayChange else { return }
                    guard newToken != lastObservedAutoApplyToken else { return }
                    lastObservedAutoApplyToken = newToken
                    autoApplyMatchingProfile()
                }

            if let note = lastNote {
                // Clickable: a note that says a monitor fell back to 60 Hz is
                // the only explanation the user gets, and it used to vanish on
                // a six-second timer whether or not anyone had read it. Now
                // only the reassuring ones expire on their own — see
                // `scheduleNoteClear` — and any of them can be dismissed.
                Button {
                    lastNote = nil
                } label: {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: lastNoteTone == .problem ? "exclamationmark.triangle.fill"
                                           : (lastNoteTone == .fallback ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill"))
                            .font(.system(size: 10))
                            .accessibilityHidden(true)
                        note.text.font(Design.Typography.note).lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(noteColor)
                .padding(.horizontal, Design.Spacing.l)
                .padding(.top, 2)
                .help("Dismiss")
            }
        }
        .padding(.bottom, Design.Spacing.xs)
        .onAppear {
            if opensSaveForm, mode == .idle {
                mode = .saving(buildInitialFormState())
            }
        }
    }

    private var noteColor: Color {
        switch lastNoteTone {
        case .info: return .green
        case .fallback: return .orange
        case .problem: return .red
        }
    }

    // MARK: - Idle pills

    @ViewBuilder
    private var idlePillBar: some View {
        if profiles.profiles.isEmpty {
            HStack {
                Text("Save a multi-display preset")
                    .font(Design.Typography.footer)
                    .foregroundStyle(.secondary)
                Spacer()
                saveButton
            }
            .padding(.horizontal, Design.Spacing.l)
        } else {
            // Resolved once per render rather than once per pill: the check
            // walks every entry against every live display, so asking it
            // inside the loop made the pill bar quadratic in the thing users
            // add most.
            let active = activeProfileIDs
            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                    ProfilePill(
                        profile: profile,
                        isCurrentlyFlexible: isFlexible(profile),
                        isActive: active.contains(profile.id),
                        previewProvider: { profiles.previewApply(profile, against: displays.displays) }
                    ) {
                        // Classify before applying. Clean fit (.exactMatch)
                        // commits immediately. Anything else routes through
                        // the inline confirmation panel so the user sees
                        // what will be skipped or left alone before the
                        // apply mutates display state.
                        let classification = DisplaySetClassifier.classify(profile, against: displays.displays)
                        if DisplaySetClassifier.isCleanApply(classification) {
                            commitApply(profile)
                        } else {
                            let preview = profiles.previewApply(profile, against: displays.displays)
                            mode = .confirmingApply(ConfirmApplyState(
                                profileID: profile.id,
                                profileName: profile.name,
                                preview: preview,
                                classification: classification
                            ))
                        }
                    } onRename: {
                        mode = .renaming(profileID: profile.id, newName: profile.name)
                    } onUpdateCurrent: {
                        _ = profiles.updateFromCurrent(profile, displays: displays.displays)
                        announce("Updated '\(profile.name)' with current setup", tone: .info)
                    } onToggleFlexible: {
                        let result = profiles.toggleFlexible(profile, displays: displays.displays)
                        switch result {
                        case .madeFlexible:
                            announce("'\(profile.name)' now matches any external monitor", tone: .info)
                        case .madeSpecific:
                            announce("'\(profile.name)' is locked to current monitors", tone: .info)
                        case .blockedNoExternal:
                            announce("Connect the external monitor first to lock '\(profile.name)' to it.", tone: .problem)
                        }
                    } onEdit: {
                        mode = .editing(buildInitialEditState(for: profile))
                    } onDelete: {
                        mode = .confirmingDelete(profileID: profile.id, name: profile.name)
                    }
                    // ⌘1…⌘9 while the popover has key focus. Not a global
                    // hotkey — those were rejected in the backlog because they
                    // collide with whatever the user is actually working in.
                    // Only the first nine get one; a tenth profile would need
                    // ⌘0, which reads as "zero" not "tenth".
                    .modifier(ProfileShortcut(index: index))
                }
                saveButton
            }
            .padding(.horizontal, Design.Spacing.l)
        }
    }

    /// The profiles whose saved setup is what the displays are doing right
    /// now — the pills that draw the checkmark and the accent border.
    private var activeProfileIDs: Set<UUID> {
        let live = displays.displays
        return Set(
            profiles.profiles
                .filter { profiles.isCurrentState($0, displays: live) }
                .map(\.id)
        )
    }

    /// Applies ⌘<n> to the first nine pills and nothing to the rest.
    private struct ProfileShortcut: ViewModifier {
        let index: Int

        func body(content: Content) -> some View {
            if index < 9, let key = KeyEquivalent(exactly: index + 1) {
                content.keyboardShortcut(key)
            } else {
                content
            }
        }
    }

    private var saveButton: some View {
        Button {
            mode = .saving(buildInitialFormState())
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Save")
                    .font(Design.Typography.footer)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
        }
        .buttonStyle(.plain)
        .help("Save displays into a profile")
        .accessibilityLabel("Save current displays into a profile")
    }

    // Removed: previously rendered an info.circle icon that only fired
    // on hover. Users read it as a clickable button (macOS convention)
    // and tried to click — nothing happened. Tooltip moved to the
    // PROFILES label above.

    private func buildInitialFormState() -> SaveFormState {
        var state = SaveFormState()
        state.name = suggestedName
        state.perDisplay = displays.displays.map { d in
            DisplayChoice(
                displayID: d.id,
                displayName: d.name,
                isBuiltIn: d.isMain || CGDisplayIsBuiltin(d.id) != 0,
                currentModeDescription: d.currentMode.map(currentModeDescription) ?? "",
                isIncluded: true,
                matchAnyExternal: false
            )
        }
        return state
    }

    private var suggestedName: String {
        Profile.suggestedName(
            displayNames: displays.displays.map(\.name),
            existingNames: Set(profiles.profiles.map(\.name))
        )
    }

    /// Tells the user when two of the monitors they just saved report the same
    /// EDID, because the saved entries cannot tell those two apart: at apply
    /// time each entry binds to every display its matcher accepts, so one entry
    /// drives both screens.
    ///
    /// A warning rather than a rejection — the displays really are
    /// indistinguishable, so there is nothing the user could fix in the form.
    private func warnIfDisplaysAreIndistinguishable(selection: [CGDirectDisplayID: ProfileMatchKind]) {
        let specific = displays.displays.filter { selection[$0.id] == .specific }
        let ambiguous = DisplayIdentity.ambiguous(specific.map { DisplayIdentity.capture($0.id) })
        guard !ambiguous.isEmpty else { return }

        let names = specific
            .filter { ambiguous.contains(DisplayIdentity.capture($0.id)) }
            .map(\.name)
        let listed = Set(names).sorted().joined(separator: ", ")
        announce(
            "Saved, but \(listed) report the same identity — this profile cannot tell them apart and will set both the same way.",
            tone: .fallback
        )
    }

    private func currentModeDescription(_ m: CGDisplayMode) -> String {
        var parts = ["\(m.width)×\(m.height)"]
        if let hz = m.refreshHz { parts.append("\(hz)Hz") }
        if m.isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }

    /// Performs the actual apply on a background task and announces the
    /// outcome. Extracted so both the clean-apply path and the
    /// "Apply anyway" confirmation button share the same code.
    /// Applies the profile and announces the outcome. Shared by the
    /// clean-apply path and the "Apply anyway" confirmation button.
    ///
    /// Deliberately on the main actor. This used to be wrapped in a
    /// `Task.detached` whose entire body was two `MainActor.run` calls, which
    /// moved no work off the UI actor and only made readers believe it had.
    /// The cost here is `CGCompleteDisplayConfiguration`, and moving that off
    /// the main actor buys nothing observable — the desktop is blanked for the
    /// duration either way — while needing `@unchecked Sendable` holes for
    /// `CGDisplayMode`. Measured in the 2026-08-01 audit: scoring three
    /// displays against a real 60-mode list takes 86 µs.
    private func commitApply(_ profile: Profile) {
        let result = profiles.applyDetailed(
            profile,
            displays: displays.displays,
            revert: displays.revert
        )
        announceOutcome(result)
    }

    // MARK: - Confirmation panels
    //
    // The panels themselves live in ProfileConfirmationPanels.swift. What
    // stays here is the wiring: which profile, and what the buttons do.

    @ViewBuilder
    private var confirmApplyPanel: some View {
        if case .confirmingApply(let state) = mode {
            ProfileApplyConfirmation(
                profileName: state.profileName,
                preview: state.preview,
                classification: state.classification,
                apply: {
                    if let p = profiles.profiles.first(where: { $0.id == state.profileID }) {
                        commitApply(p)
                    }
                    mode = .idle
                },
                cancel: { mode = .idle }
            )
        }
    }

    @ViewBuilder
    private var confirmDeletePanel: some View {
        if case .confirmingDelete(let id, let name) = mode {
            ProfileDeleteConfirmation(
                profileName: name,
                delete: {
                    if let profile = profiles.profiles.first(where: { $0.id == id }) {
                        profiles.delete(profile)
                        announce("Deleted '\(name)'", tone: .info)
                    }
                    mode = .idle
                },
                cancel: { mode = .idle }
            )
        }
    }

    // MARK: - Save form
    //
    // The form lives in ProfileSaveForm.swift and owns its own state through
    // one binding; what stays here is where that state comes from and what
    // Save does with it.

    @ViewBuilder
    private var saveForm: some View {
        if case .saving = mode {
            ProfileSaveForm(
                state: saveFormState,
                save: commitSave,
                cancel: { mode = .idle }
            )
        }
    }

    /// A binding into the `Mode` enum's associated value. One of these
    /// replaced five per-field bindings that each re-found their display.
    private var saveFormState: Binding<SaveFormState> {
        Binding(
            get: {
                if case .saving(let s) = mode { return s }
                return SaveFormState()
            },
            set: { mode = .saving($0) }
        )
    }

    // MARK: - Rename form

    @ViewBuilder
    private var renameForm: some View {
        if case .renaming(let id, _) = mode {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rename profile")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("Profile name", text: bindingForRenameText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .focused($nameFieldFocused)
                        .onSubmit { commitRename(id: id) }
                    Button("Rename") { commitRename(id: id) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(currentRenameText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { mode = .idle }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, Design.Spacing.l)
            .onAppear { nameFieldFocused = true }
        }
    }

    private var currentRenameText: String {
        if case .renaming(_, let n) = mode { return n }
        return ""
    }

    // MARK: - Bindings

    private var bindingForRenameText: Binding<String> {
        Binding(
            get: { currentRenameText },
            set: { newValue in
                if case .renaming(let id, _) = mode {
                    mode = .renaming(profileID: id, newName: newValue)
                }
            }
        )
    }

    // MARK: - Edit form
    //
    // The form lives in ProfileEditForm.swift. What stays here is where its
    // state is built from a saved profile, and what Save does with it.

    @ViewBuilder
    private var editForm: some View {
        if case .editing = mode {
            ProfileEditForm(
                state: editFormState,
                save: commitEdit,
                cancel: { mode = .idle }
            )
        }
    }

    /// A binding into the `Mode` enum's associated value. Replaced six
    /// per-field bindings that each re-found their row by id.
    private var editFormState: Binding<EditFormState> {
        Binding(
            get: {
                if case .editing(let s) = mode { return s }
                return EditFormState(profileID: UUID(), name: "", entries: [])
            },
            set: { mode = .editing($0) }
        )
    }

    private func buildInitialEditState(for profile: Profile) -> EditFormState {
        let entries: [EntryEdit] = profile.entries.map { e -> EntryEdit in
            let isBuiltIn: Bool = {
                if case .builtIn = e.matcher { return true }
                return false
            }()
            let kind: MatcherKind = {
                if case .anyExternal = e.matcher { return .anyExternal }
                return .specific
            }()
            let (vendor, model, serial): (UInt32, UInt32, UInt32) = {
                switch e.matcher {
                case let .edid(v, m, s): return (v, m, s)
                case let .builtIn(v, m, s): return (v, m, s)
                case .anyExternal: return (0, 0, 0)
                }
            }()
            // Find the live displays the matcher binds to so we can populate
            // the mode picker. .specific and .builtIn bind to exactly one
            // monitor (or none if unplugged). .anyExternal binds to *every*
            // connected external — we union all their mode lists so the user
            // sees every resolution any connected external can do.
            //
            // Union (not intersection) reflects how applyDetailed actually
            // behaves: it picks the closest available mode per monitor via
            // bestMatch() scoring. So a user saving 2560×1440 for "any
            // external" on a setup with both a 4K and a 1080p monitor will
            // get 2560×1440 on the 4K monitor and a fallback to 1920×1080
            // on the 1080p one — exactly what they expect.
            let boundDisplays: [DisplayInfo] = displays.displays.filter { d in
                switch e.matcher {
                case .anyExternal: return CGDisplayIsBuiltin(d.id) == 0
                case .builtIn: return CGDisplayIsBuiltin(d.id) != 0
                case let .edid(v, m, s):
                    return CGDisplayVendorNumber(d.id) == v
                        && CGDisplayModelNumber(d.id) == m
                        && CGDisplaySerialNumber(d.id) == s
                }
            }
            // Dedup by (size, refresh, HiDPI) so the picker doesn't show
            // the same resolution twice when multiple monitors support it.
            var seen: Set<LiveMode> = []
            var live: [LiveMode] = []
            for d in boundDisplays {
                for m in d.modes {
                    let mode = LiveMode(
                        pointWidth: m.width,
                        pointHeight: m.height,
                        refreshHz: m.refreshHz,
                        isHiDPI: m.isHiDPI
                    )
                    if seen.insert(mode).inserted { live.append(mode) }
                }
            }
            return EntryEdit(
                id: UUID(),
                matcherKind: kind,
                isBuiltIn: isBuiltIn,
                vendor: vendor,
                model: model,
                serial: serial,
                displayName: e.displayName,
                pointWidth: e.pointWidth,
                pointHeight: e.pointHeight,
                refreshHz: e.refreshHz,
                isHiDPI: e.isHiDPI,
                isIncluded: true,
                availableModes: live
            )
        }
        var state = EditFormState(profileID: profile.id, name: profile.name, entries: entries)
        // Preselect the row that would save the same matcher the profile
        // already stores. A hand-edited mainDisplay matching no row shows as
        // "Don't change" and is dropped on save — the edit form owns the field.
        state.mainRowID = entries.first(where: { profile.mainDisplay == rowMatcher($0) })?.id
        return state
    }

    private func commitEdit() {
        guard case .editing(let s) = mode else { return }
        let trimmed = s.name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let profile = profiles.profiles.first(where: { $0.id == s.profileID }) else {
            mode = .idle
            return
        }
        let kept = s.entries.filter(\.isIncluded)
        guard !kept.isEmpty else { return }

        // Name first. `replaceEntries` writes to disk, so a name the store will
        // refuse has to be caught before the entries are committed — otherwise
        // the user gets half a save and an error explaining the other half.
        guard !profiles.nameIsTaken(trimmed, excluding: s.profileID) else {
            announce("A profile named '\(trimmed)' already exists. Pick another name.", tone: .problem)
            return
        }

        let newEntries: [Profile.Entry] = kept.map { e in
            let matcher = rowMatcher(e)
            return Profile.Entry(
                matcher: matcher,
                displayName: e.displayName,
                pointWidth: e.pointWidth,
                pointHeight: e.pointHeight,
                refreshHz: e.refreshHz,
                isHiDPI: e.isHiDPI
            )
        }
        // Replace entries first so the multiple-anyExternal guard fires
        // before we rename. If save is rejected, surface the reason and
        // keep the user in the form so they can fix the conflict.
        switch profiles.replaceEntries(profile, with: newEntries) {
        // Re-fetch after replaceEntries: `profile` was captured before it and
        // still carries the old entries — updating with it would silently undo
        // the entry edits that replaceEntries just saved.
        case .saved, .savedWithMissingDisplays:
            if var fresh = profiles.profiles.first(where: { $0.id == s.profileID }) {
                fresh.name = trimmed
                fresh.mainDisplay = kept.first(where: { $0.id == s.mainRowID }).map(rowMatcher)
                guard profiles.update(fresh) == .saved else {
                    // The entries are already saved; only the name and main
                    // pick did not land. Say so rather than claim an update.
                    announce("Entries saved, but the name could not be changed.", tone: .problem)
                    return
                }
                announce("Updated '\(trimmed)'", tone: .info)
                mode = .idle
            } else {
                // replaceEntries just saved, but the profile vanished before
                // the re-fetch — unreachable in practice, but the prior code
                // announced success here regardless.
                announce("Could not update the profile — it no longer exists.", tone: .problem)
                mode = .idle
            }
        case .rejectedMultipleAnyExternal:
            announce("Only one entry can match 'any external monitor' — remove or lock the duplicates first.", tone: .problem)
        case .rejectedEmpty:
            announce("Keep at least one entry to save the profile.", tone: .problem)
        case .rejectedDuplicateName(let name):
            announce("A profile named '\(name)' already exists. Pick another name.", tone: .problem)
        case .rejectedEmptyName:
            announce("Give the profile a name.", tone: .problem)
        case .rejectedNotFound:
            announce("Could not update the profile — it no longer exists.", tone: .problem)
            mode = .idle
        }
    }

    /// The matcher a row would save as — single source of truth for
    /// commitEdit and for preselecting the main-display picker.
    private func rowMatcher(_ e: EntryEdit) -> DisplayMatcher {
        switch e.matcherKind {
        case .anyExternal:
            return .anyExternal
        case .specific:
            return e.isBuiltIn
                ? .builtIn(vendor: e.vendor, model: e.model, serial: e.serial)
                : .edid(vendor: e.vendor, model: e.model, serial: e.serial)
        }
    }

    // MARK: - Commit

    private func commitSave() {
        guard case .saving(let s) = mode else { return }
        let trimmed = s.name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var selection: [CGDirectDisplayID: ProfileMatchKind] = [:]
        for c in s.perDisplay where c.isIncluded {
            selection[c.displayID] = c.matchAnyExternal ? .anyExternal : .specific
        }
        guard !selection.isEmpty else { return }

        switch profiles.captureCurrent(
            name: trimmed,
            displays: displays.displays,
            selection: selection,
            mainSelection: s.perDisplay.first(where: { $0.isIncluded && $0.displayID == s.mainDisplayID })?.displayID
        ) {
        case .saved:
            mode = .idle
            warnIfDisplaysAreIndistinguishable(selection: selection)
        case .savedWithMissingDisplays(let count):
            mode = .idle
            announce(
                "Saved, but \(count) selected display(s) were disconnected before saving and are not in the profile.",
                tone: .fallback
            )
        case .rejectedMultipleAnyExternal:
            announce("Only one display can be set to 'match any external monitor' — lock the others to a specific monitor instead.", tone: .problem)
        case .rejectedEmpty:
            announce("Pick at least one display to save.", tone: .problem)
        case .rejectedDuplicateName(let name):
            // Stay in the form: the name field is right there and is the only
            // thing that needs changing.
            announce("A profile named '\(name)' already exists. Pick another name.", tone: .problem)
        case .rejectedEmptyName:
            announce("Give the profile a name.", tone: .problem)
        case .rejectedNotFound:
            announce("Could not save the profile — it is no longer in the list.", tone: .problem)
        }
    }

    /// Whether the profile contains any .anyExternal matcher.
    private func isFlexible(_ profile: Profile) -> Bool {
        profile.entries.contains {
            if case .anyExternal = $0.matcher { return true }
            return false
        }
    }

    /// Triggered by DisplayStore.autoApplyToken bumps. Looks for a saved
    /// profile that matches the new display set and applies it. Silent on
    /// no-match so users without saved profiles aren't bothered.
    /// Also silent when every entry was already at its target mode — no
    /// point announcing "applied" if nothing actually changed.
    private func autoApplyMatchingProfile() {
        guard let match = profiles.profileMatchingExactly(displays.displays) else {
            autoApplyLog.notice("autoApply: no matching profile, skipping")
            return
        }
        autoApplyLog.notice("autoApply: invoking applyDetailed for '\(match.name, privacy: .public)' across \(displays.displays.count) display(s)")
        let result = profiles.applyDetailed(match, displays: displays.displays)
        autoApplyLog.notice("autoApply: outcomes=\(result.outcomes.count) didChange=\(result.didChangeAnything)")
        if result.didChangeAnything {
            announce("Applied '\(match.name)' for the new display setup.", tone: .info)
        }
    }

    /// Sets a transient note with the given tone, auto-clearing after 6s.
    private func announce(_ key: LocalizedStringKey, tone: ApplyOutcomeNote.Tone) {
        lastNote = .message(key)
        lastNoteTone = tone
        scheduleNoteClear()
    }

    /// Auto-clears a note after six seconds — but only a reassuring one.
    ///
    /// A `.fallback` or `.problem` note is the one place the user is told that
    /// a monitor did not get what the profile asked for. Expiring that on a
    /// timer means whoever glanced away never finds out, so those stay until
    /// they are clicked or replaced by the next apply.
    private func scheduleNoteClear() {
        guard lastNoteTone == .info else { return }
        let token = lastNote
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if lastNote == token { lastNote = nil }
        }
    }

    /// Translates outcome list into a single coloured note shown under the pills.
    /// Priority: any problem > any fallback > applied success > all already-at-target.
    private func announceOutcome(_ result: ProfileStore.ProfileApplyResult) {
        // Aggregation lives in ApplyOutcomeNote so the precedence rules are
        // testable and the copy is localisable. See ApplyOutcomeNoteTests.
        guard let note = ApplyOutcomeNote.make(from: result.outcomes, mainChange: result.mainChange) else {
            lastNote = nil
            return
        }
        lastNoteTone = note.tone
        lastNote = .outcome(note)
        scheduleNoteClear()
    }

    private func commitRename(id: UUID) {
        guard case .renaming(_, let n) = mode else { return }
        let trimmed = n.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              var profile = profiles.profiles.first(where: { $0.id == id }) else {
            mode = .idle
            return
        }
        profile.name = trimmed
        switch profiles.update(profile) {
        case .saved, .savedWithMissingDisplays:
            mode = .idle
        case .rejectedDuplicateName(let name):
            // Keep the user in the rename field — the fix is one keystroke away.
            announce("A profile named '\(name)' already exists. Pick another name.", tone: .problem)
        case .rejectedEmptyName, .rejectedEmpty, .rejectedMultipleAnyExternal, .rejectedNotFound:
            announce("Could not rename the profile.", tone: .problem)
            mode = .idle
        }
    }
}
