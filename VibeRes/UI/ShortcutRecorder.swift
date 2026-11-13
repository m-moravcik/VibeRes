import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records a global shortcut: click, press the keys, done.
///
/// Esc cancels, Delete clears, a click anywhere stops listening. A combination
/// `HotkeyCenter` refuses stays refused in place, with the reason next to the
/// field, and the recorder keeps listening for another try. While it listens,
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
    @State private var isRecording = false
    @State private var problem: HotkeyProblem?
    @State private var modifierOnlyPress = ModifierOnlyPress()
    @State private var showsUnrecordedHint = false
    @State private var monitor: Any?
    /// The click that stopped a recording, so the same click's release does
    /// not start a new one when it lands on the recorder itself.
    @State private var stoppingClick: Int?

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
        // Only the screenshot harness passes one, to render a refusal.
        _problem = State(initialValue: initialProblem)
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
                    // A second Text in a Form label is its subtitle: it wraps
                    // in the label column instead of widening the row.
                    if let message {
                        message
                            .foregroundStyle(messageStyle)
                    }
                }
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

    /// What to say next to the field right now, most urgent first.
    private var message: Text? {
        if showsUnrecordedHint {
            return Text("Nothing was recorded. If you pressed a key, another app already uses that combination. Try another.")
        }
        if let problem { return Text(problem.message) }
        if isRecording { return Text("Press the keys, or Esc to cancel.") }
        if let combo, combo == savedCombo, let inactive = hotkeys.inactive[owner] {
            return Text("Not active: \(Text(inactive.message))")
        }
        return nil
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
        isRecording = false
        showsUnrecordedHint = false
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
            return nil
        }
        problem = nil
        combo = candidate
        stopRecording()
        return nil
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
