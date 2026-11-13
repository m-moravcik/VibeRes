import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut: one physical key plus modifier keys.
///
/// The key is a virtual key code, the position on the keyboard that Carbon's
/// `RegisterEventHotKey` listens for, not the character it types. That is what
/// makes a shortcut survive a layout switch, and why `displayString` asks the
/// current layout what to call the key: on a Slovak QWERTZ keyboard the key US
/// layouts label "Y" reads "Z".
///
/// Lives in Core so the CLI can print a profile's shortcut. Registering one is
/// the app's business (`HotkeyCenter`).
struct KeyCombo: Hashable, Sendable {
    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: UInt8
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        /// The ones that make a combination a shortcut rather than typing.
        /// Shift alone only changes what a key types.
        static let commandLike: Modifiers = [.control, .option, .command]

        var hasValidShortcutShape: Bool {
            let count = [Self.control, .option, .shift, .command].filter(contains).count
            return count >= 2 && !isDisjoint(with: .commandLike)
        }
    }

    /// Virtual key codes stop at 0x7F (`kVK_F20` is 0x5A, the highest used).
    static let keyCodeRange: ClosedRange<UInt32> = 0...0x7F

    let keyCode: UInt32
    let modifiers: Modifiers

    init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The combination the Settings window offers for Revert with one click.
    /// R for Revert, behind all three command-like modifiers so it collides
    /// with nothing a Mac ships.
    static let suggestedRevert = KeyCombo(
        keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option, .command]
    )

    // MARK: Carbon

    /// Modifiers in the form `RegisterEventHotKey` and `CopySymbolicHotKeys` use.
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    /// Reads a Carbon key code and modifier mask; nil for a code past the
    /// virtual key range, which is how macOS marks a symbolic hotkey that has
    /// no key at all (65535).
    init?(carbonKeyCode: Int, carbonModifiers: Int) {
        guard carbonKeyCode >= 0, Self.keyCodeRange.contains(UInt32(carbonKeyCode)) else { return nil }
        var mods: Modifiers = []
        if carbonModifiers & controlKey != 0 { mods.insert(.control) }
        if carbonModifiers & optionKey != 0 { mods.insert(.option) }
        if carbonModifiers & shiftKey != 0 { mods.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { mods.insert(.command) }
        self.init(keyCode: UInt32(carbonKeyCode), modifiers: mods)
    }

    /// The enabled system shortcuts in a `CopySymbolicHotKeys` list (Spotlight,
    /// Mission Control, screenshots, input source switching and the rest of
    /// System Settings → Keyboard → Keyboard Shortcuts).
    ///
    /// A pure function of the list so it can be checked against a fixture; the
    /// app reads the live list in `CarbonHotkeyRegistrar`.
    static func reserved(fromSymbolicHotKeys entries: [[String: Any]]) -> Set<KeyCombo> {
        var result: Set<KeyCombo> = []
        for entry in entries {
            guard (entry["kHISymbolicHotKeyEnabled"] as? Bool) == true,
                  let code = entry["kHISymbolicHotKeyCode"] as? Int,
                  let mods = entry["kHISymbolicHotKeyModifiers"] as? Int,
                  let combo = KeyCombo(carbonKeyCode: code, carbonModifiers: mods)
            else { continue }
            result.insert(combo)
        }
        return result
    }

    // MARK: Shape

    /// F1-F20. The only keys that make a shortcut without a modifier: nothing
    /// types them, so claiming one globally takes no character from any app.
    var isFunctionKey: Bool {
        Self.functionKeyNames[Int(keyCode)] != nil
    }

    /// True when the combination is safe to take from every other app.
    ///
    /// Two modifiers, at least one of them ⌃, ⌥ or ⌘. One is not enough: ⌘ plus
    /// a key is some app's menu command, ⌥ plus a key types a character (⌥E is
    /// the accent key) and ⌃ plus a key drives the terminal and every text field.
    /// A global shortcut wins over all of them, so a single-modifier combination
    /// would quietly break typing or a menu everywhere else. F-keys are free.
    var hasValidShape: Bool {
        isFunctionKey || modifiers.hasValidShortcutShape
    }

    // MARK: Display

    /// "⌃⌥⌘R", modifiers in the order macOS menus print them.
    @MainActor
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    /// What the key is called on the current keyboard layout, upper-cased the
    /// way menus print shortcuts. Main actor: Text Input Sources must be read
    /// on the main thread.
    @MainActor
    static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeyNames[Int(keyCode)] ?? functionKeyNames[Int(keyCode)] {
            return special
        }
        if let typed = typedCharacter(for: keyCode) {
            return typed.uppercased()
        }
        return "#\(keyCode)"
    }

    /// The character the key types without modifiers on the current layout, or
    /// on the ASCII-capable one when the current source has no key layout (an
    /// input method such as Japanese Kana).
    @MainActor
    private static func typedCharacter(for keyCode: UInt32) -> String? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
        ]
        for case let source? in sources {
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            let character: String? = data.withUnsafeBytes { buffer in
                guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, chars.count, &length, &chars
                )
                guard status == noErr, length > 0 else { return nil }
                let text = String(utf16CodeUnits: chars, count: length)
                // A control character would print as nothing.
                return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } ? text : nil
            }
            if let character, !character.trimmingCharacters(in: .whitespaces).isEmpty {
                return character
            }
        }
        return nil
    }

    /// Keys whose name is a symbol rather than what they type.
    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_DownArrow: "↓", kVK_UpArrow: "↑", kVK_ANSI_KeypadEnter: "⌤",
        kVK_ANSI_KeypadClear: "⌧", kVK_Help: "?⃝",
    ]

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
}

/// Stored as `{"keyCode": 15, "modifiers": ["control", "option", "command"]}`:
/// readable in a hand-edited profiles.json, and independent of Carbon's bit
/// values. Anything else is refused, never guessed at.
extension KeyCombo: Codable {
    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers
    }

    private static let modifierNames: [(Modifiers, String)] = [
        (.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "command"),
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = try c.decode(UInt32.self, forKey: .keyCode)
        guard Self.keyCodeRange.contains(code) else {
            throw DecodingError.dataCorruptedError(
                forKey: .keyCode, in: c, debugDescription: "key code out of range"
            )
        }
        var mods: Modifiers = []
        for name in try c.decode([String].self, forKey: .modifiers) {
            guard let mod = Self.modifierNames.first(where: { $0.1 == name })?.0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .modifiers, in: c, debugDescription: "unknown modifier"
                )
            }
            mods.insert(mod)
        }
        self.init(keyCode: code, modifiers: mods)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(Self.modifierNames.filter { modifiers.contains($0.0) }.map(\.1), forKey: .modifiers)
    }
}
