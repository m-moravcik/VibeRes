import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records a global shortcut: click, press the keys, done.
///
/// Esc cancels, Delete clears, a click anywhere stops listening. A combination
/// `HotkeyCenter` refuses stays refused in place, and the recorder keeps
/// listening for another try. While it listens,
/// every VibeRes shortcut is released, so pressing one it already owns
/// records it instead of running it.
///
/// Two layouts. Without a title (the popover's Edit form) the reason sits
/// under the field. With one (a Settings row) the recorder is the whole row:
/// the field stays on the trailing edge and the reason goes under the title,
/// as System Settings does it. A reason inside the trailing column widened
/// it, which moved the field left or broke the row onto two lines every time
/// a message came or went.
struct ShortcutRecorder<Accessory: View>: View {
    let owner: HotkeyOwner
    @Binding var combo: KeyCombo?
    /// What is saved for `owner` right now. A "not active" warning describes
    /// that one, so it shows only while the field still holds it.
    let savedCombo: KeyCombo?
    var controlSize: SwiftUI.ControlSize = .regular
    /// The row's title in Settings; nil for the stacked popover layout.
    var title: Text?
    /// Shown before the field in a titled row (the "Use ⌃⌥⌘R" button).
    @ViewBuilder var accessory: () -> Accessory

    @Environment(HotkeyCenter.self) private var hotkeys
    @State private var session: RecorderSession
    private var isRecording: Bool {
        get { session.isRecording }
        nonmutating set { session.isRecording = newValue }
    }
    private var problem: HotkeyProblem? {
        get { session.problem }
        nonmutating set { session.problem = newValue }
    }
    private var showsUnrecordedHint: Bool {
        get { session.showsUnrecordedHint }
        nonmutating set { session.showsUnrecordedHint = newValue }
    }
    @State private var modifierOnlyPress = ModifierOnlyPress()
    @State private var monitor: Any?
    /// The click that stopped a recording, so the same click's release does
    /// not start a new one when it lands on the recorder itself.
    @State private var stoppingClick: Int?
    /// Go up on each accepted and each refused combination, for the glow and
    /// the shake.
    @State private var acceptances = 0
    @State private var refusals = 0

    init(
        owner: HotkeyOwner,
        combo: Binding<KeyCombo?>,
        savedCombo: KeyCombo?,
        controlSize: SwiftUI.ControlSize = .regular,
        title: Text? = nil,
        initialProblem: HotkeyProblem? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.owner = owner
        _combo = combo
        self.savedCombo = savedCombo
        self.controlSize = controlSize
        self.title = title
        self.accessory = accessory
        // Seeds a refusal for offscreen screenshots and layout checks.
        _session = State(initialValue: RecorderSession(problem: initialProblem))
    }

    var body: some View {
        Group {
            if let title {
                LabeledContent {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        accessory()
                        field
                    }
                } label: {
                    title
                    if let message {
                        message
                            .font(.caption)
                            .foregroundStyle(messageStyle)
                    }
                }
                .labeledContentStyle(ShortcutRowStyle())
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    field
                    if let message {
                        message
                            .font(Design.Typography.note)
                            .foregroundStyle(messageStyle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onDisappear(perform: stopRecording)
        // Covers the popover closing and the Settings window losing focus,
        // which would otherwise leave every shortcut suspended.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
    }

    private var field: some View {
        Button(action: toggleRecording) {
            label
                .lineLimit(1)
                // Keep short labels stable and leave room for the remove
                // button, while allowing longer translations to fit.
                .frame(minWidth: controlSize == .small ? 112 : 128)
                .fixedSize(horizontal: true, vertical: false)
        }
        .controlSize(controlSize)
        .recorderState(
            listening: isRecording,
            refused: isRecording && problem != nil,
            refusals: refusals,
            acceptances: acceptances,
            cornerRadius: controlSize == .small ? Design.Radius.recorderSmall : Design.Radius.recorder
        )
        .accessibilityLabel(isRecording ? Text("Recording shortcut") : Text("Shortcut"))
        .accessibilityValue(combo.map { Text(verbatim: $0.localizedDisplayString()) } ?? Text("None"))
        .accessibilityHint(Text("Press to record a new shortcut."))
        .overlay(alignment: .trailing) {
            if combo != nil, !isRecording {
                Button {
                    combo = nil
                    problem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 5)
                .help("Remove shortcut")
                .accessibilityLabel("Remove shortcut")
            }
        }
    }

    private var message: Text? {
        switch session.note(combo: combo, savedCombo: savedCombo, inactive: hotkeys.inactive[owner]) {
        case .unrecorded?:
            return Text("Nothing was recorded. If you pressed a key, another app already uses that combination. Try another.")
        case .refused(let problem)?:
            return Text(problem.message)
        case .listening?:
            return Text("Press the keys, or Esc to cancel.")
        case .notActive(let inactive)?:
            return Text("Not active: \(Text(inactive.message))")
        case nil:
            return nil
        }
    }

    /// The recording prompt is guidance; everything else is a warning.
    private var messageStyle: Color {
        isRecording && problem == nil && !showsUnrecordedHint ? .secondary : .orange
    }

    @ViewBuilder
    private var label: some View {
        if isRecording {
            Text("Type shortcut…")
                .foregroundStyle(.secondary)
        } else if let combo {
            Text(verbatim: combo.localizedDisplayString())
        } else {
            Text("Record Shortcut")
        }
    }

    private func toggleRecording() {
        if let current = NSApp.currentEvent, current.eventNumber == stoppingClick {
            stoppingClick = nil
            return
        }
        stoppingClick = nil
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        problem = nil
        modifierOnlyPress = ModifierOnlyPress()
        showsUnrecordedHint = modifierOnlyPress.modifiersChanged(KeyCombo.Modifiers(NSEvent.modifierFlags))
        isRecording = true
        hotkeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        session.stop()
        modifierOnlyPress = ModifierOnlyPress()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hotkeys.resume()
    }

    /// Consumes every key press while recording, so none of them reaches the
    /// popover's own shortcuts or a text field; lets clicks through after
    /// stopping.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            if modifierOnlyPress.modifiersChanged(KeyCombo.Modifiers(event.modifierFlags)) {
                showsUnrecordedHint = true
                problem = nil
            }
            return event
        }
        guard event.type == .keyDown else {
            // A mouse-up carries the number of its mouse-down.
            stoppingClick = event.eventNumber
            stopRecording()
            return event
        }
        modifierOnlyPress.keyPressed()
        showsUnrecordedHint = false
        let modifiers = KeyCombo.Modifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)
        if modifiers.isEmpty, keyCode == kVK_Escape {
            stopRecording()
            return nil
        }
        if modifiers.isEmpty, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            combo = nil
            problem = nil
            stopRecording()
            return nil
        }
        let candidate = KeyCombo(keyCode: UInt32(keyCode), modifiers: modifiers)
        // Ask while still suspended: the probe must not find our own shortcuts.
        if let refusal = hotkeys.problem(with: candidate, for: owner) {
            problem = refusal
            refusals += 1
            return nil
        }
        problem = nil
        combo = candidate
        acceptances += 1
        stopRecording()
        return nil
    }
}

/// What a recorder is doing and has to say, apart from the view so the rules
/// can be tested without AppKit events.
struct RecorderSession: Equatable {
    var isRecording = false
    /// The refusal of the combination just pressed. It belongs to that
    /// recording: kept while the recorder listens for another try, gone once
    /// it stops.
    var problem: HotkeyProblem?
    var showsUnrecordedHint = false

    /// The line under the field. The most urgent one wins.
    enum Note: Equatable {
        case unrecorded
        case refused(HotkeyProblem)
        case listening
        /// The saved shortcut is not registered, and why.
        case notActive(HotkeyProblem)
    }

    /// Ends a recording, by Esc, a click elsewhere, an accepted combination
    /// or the window closing. A refusal left behind used to stay up in
    /// orange after Esc and hid the "Not active" line beneath it.
    mutating func stop() {
        isRecording = false
        showsUnrecordedHint = false
        problem = nil
    }

    func note(combo: KeyCombo?, savedCombo: KeyCombo?, inactive: HotkeyProblem?) -> Note? {
        if showsUnrecordedHint { return .unrecorded }
        if let problem { return .refused(problem) }
        if isRecording { return .listening }
        if let combo, combo == savedCombo, let inactive { return .notActive(inactive) }
        return nil
    }
}

extension View {
    /// The recorder field's state, shown on its edge: an accent border that
    /// breathes while it listens, a shake for a refused combination, and the
    /// shared changed-glow for an accepted one. The message under the field
    /// stays the real signal; this only says it at a glance. Reduce Motion:
    /// the border holds still and turns orange for a refusal.
    func recorderState(
        listening: Bool, refused: Bool, refusals: Int, acceptances: Int, cornerRadius: CGFloat
    ) -> some View {
        modifier(RecorderState(
            listening: listening, refused: refused, refusals: refusals,
            acceptances: acceptances, cornerRadius: cornerRadius
        ))
    }
}

private struct RecorderState: ViewModifier {
    let listening: Bool
    let refused: Bool
    let refusals: Int
    let acceptances: Int
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if listening {
                    border
                        .allowsHitTesting(false)
                        .transition(.opacity.animation(Design.Motion.quick))
                }
            }
            .changedGlow(on: acceptances, cornerRadius: cornerRadius)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: refusals) { content, offset in
                // A render-time offset, not a layout one: with `.offset` the
                // breathing border's phaseAnimator layer kept its place while
                // the button shook out from under it.
                let dx = reduceMotion ? 0 : offset
                content.visualEffect { effect, _ in effect.offset(x: dx) }
            } keyframes: { _ in
                for offset in Design.Motion.recorderShake {
                    CubicKeyframe(offset, duration: Design.Motion.recorderShakeStep)
                }
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder private var border: some View {
        if reduceMotion {
            shape.strokeBorder(refused ? Color.orange : Color.accentColor,
                               lineWidth: Design.Motion.recorderBorderWidth)
        } else {
            // Breathes for as long as it is on screen, which is as long as
            // the recorder listens.
            shape.strokeBorder(Color.accentColor, lineWidth: Design.Motion.recorderBorderWidth)
                .phaseAnimator([1.0, Design.Motion.recorderBreathLow]) { border, opacity in
                    border.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: Design.Motion.recorderBreath / 2)
                }
        }
    }
}

/// Keep the controls beside the label even when Revert has an accessory.
/// The automatic Form style can put them below a multiline subtitle.
private struct ShortcutRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                configuration.label
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            configuration.content
                .fixedSize()
        }
    }
}

extension ShortcutRecorder where Accessory == EmptyView {
    init(
        owner: HotkeyOwner,
        combo: Binding<KeyCombo?>,
        savedCombo: KeyCombo?,
        controlSize: SwiftUI.ControlSize = .regular,
        title: Text? = nil,
        initialProblem: HotkeyProblem? = nil
    ) {
        self.init(
            owner: owner, combo: combo, savedCombo: savedCombo, controlSize: controlSize,
            title: title, initialProblem: initialProblem, accessory: { EmptyView() }
        )
    }
}

struct ModifierOnlyPress {
    private var modifiers: KeyCombo.Modifiers = []
    private var hadShortcutModifiers = false
    private var receivedKey = false

    mutating func modifiersChanged(_ modifiers: KeyCombo.Modifiers) -> Bool {
        self.modifiers = modifiers
        if modifiers.isEmpty {
            let showHint = hadShortcutModifiers && !receivedKey
            self = Self()
            return showHint
        }
        hadShortcutModifiers = hadShortcutModifiers || modifiers.hasValidShortcutShape
        return false
    }

    mutating func keyPressed() {
        receivedKey = !modifiers.isEmpty
    }
}

extension KeyCombo {
    @MainActor
    func localizedDisplayString(locale: Locale = .appLanguage) -> String {
        displayString(spaceName: String(localized: LocalizedStringResource("Space", locale: locale)))
    }
}

extension KeyCombo.Modifiers {
    /// The four modifiers a shortcut can carry; Caps Lock, Fn and the keypad
    /// flag describe the key, not the combination.
    init(_ flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: KeyCombo.Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }
}

extension HotkeyProblem {
    var message: LocalizedStringKey {
        switch self {
        case .needsModifiers:
            return "Use two modifier keys, one of them ⌃, ⌥ or ⌘. F1–F20 work on their own."
        case .reservedBySystem:
            return "macOS already uses this shortcut."
        case .usedByAnotherApp:
            return "Another app already uses this shortcut."
        case .usedByRevert:
            return "Revert already uses this shortcut."
        case .usedByProfile(let name):
            return "'\(name)' already uses this shortcut."
        case .notRegistered(let status):
            return "macOS did not accept this shortcut (error \(Int(status)))."
        }
    }
}
