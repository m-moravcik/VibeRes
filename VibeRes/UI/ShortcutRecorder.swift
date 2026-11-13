import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records a global shortcut: click, press the keys, done.
///
/// Esc cancels, Delete clears, a click anywhere stops listening. A combination
/// `HotkeyCenter` refuses stays refused in place, with the reason under the
/// field, and the recorder keeps listening for another try. While it listens,
/// every VibeRes shortcut is released, so pressing one it already owns
/// records it instead of running it.
struct ShortcutRecorder: View {
    let owner: HotkeyOwner
    @Binding var combo: KeyCombo?
    /// What is saved for `owner` right now. A "not active" warning describes
    /// that one, so it shows only while the field still holds it.
    let savedCombo: KeyCombo?
    var controlSize: SwiftUI.ControlSize = .regular

    @Environment(HotkeyCenter.self) private var hotkeys
    @State private var isRecording = false
    @State private var problem: HotkeyProblem?
    @State private var monitor: Any?
    /// The click that stopped a recording, so the same click's release does
    /// not start a new one when it lands on the recorder itself.
    @State private var stoppingClick: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: toggleRecording) {
                label
                    .lineLimit(1)
                    // One width for every recorder, so a column of them lines
                    // up whether a field is empty, recording or set, and the
                    // remove button has room inside the field.
                    .frame(width: controlSize == .small ? 112 : 128)
            }
            .controlSize(controlSize)
            .accessibilityLabel(isRecording ? Text("Recording shortcut") : Text("Shortcut"))
            .accessibilityValue(combo.map { Text(verbatim: $0.displayString) } ?? Text("None"))
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

            if let problem {
                Text(problem.message)
                    .font(Design.Typography.note)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isRecording {
                Text("Press the keys, or Esc to cancel.")
                    .font(Design.Typography.note)
                    .foregroundStyle(.secondary)
            } else if let combo, combo == savedCombo, let inactive = hotkeys.inactive[owner] {
                Text("Not active: \(Text(inactive.message))")
                    .font(Design.Typography.note)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stopRecording)
        // Covers the popover closing and the Settings window losing focus,
        // which would otherwise leave every shortcut suspended.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
    }

    @ViewBuilder
    private var label: some View {
        if isRecording {
            Text("Type shortcut…")
                .foregroundStyle(.secondary)
        } else if let combo {
            Text(verbatim: combo.displayString)
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
        isRecording = true
        hotkeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hotkeys.resume()
    }

    /// Consumes every key press while recording, so none of them reaches the
    /// popover's own shortcuts or a text field; lets clicks through after
    /// stopping.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else {
            // A mouse-up carries the number of its mouse-down.
            stoppingClick = event.eventNumber
            stopRecording()
            return event
        }
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
