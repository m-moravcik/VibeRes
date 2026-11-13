import Carbon.HIToolbox
import Foundation

/// Global shortcuts through Carbon's `RegisterEventHotKey`.
///
/// Still the only public API for a system-wide shortcut that needs no
/// permission: an `NSEvent` global monitor sees key presses only with
/// Accessibility access, and cannot stop the key from also reaching the app in
/// front. A hotkey registered here is consumed, and asks for nothing.
///
/// Registers exclusively. Verified on macOS 27: an exclusive registration fails
/// with `eventHotKeyExistsErr` when another process holds the same combination
/// exclusively, and succeeds over a non-exclusive one. That is the only
/// "already taken" signal the API gives, so it is the one `HotkeyCenter` uses.
@MainActor
final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    /// "VRES", so the handler can ignore hotkey events that are not ours.
    nonisolated static let signature: OSType = 0x5652_4553

    var onPress: ((UInt32) -> Void)?

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    func register(_ combo: KeyCombo, id: UInt32) -> HotkeyRegistration {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &ref
        )
        switch status {
        case noErr:
            if let ref { refs[id] = ref }
            return .registered
        case OSStatus(eventHotKeyExistsErr):
            return .takenByAnotherApp
        default:
            return .failed(status: status)
        }
    }

    func unregister(id: UInt32) {
        guard let ref = refs.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(ref)
    }

    func reservedBySystem() -> Set<KeyCombo> {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr,
              let entries = list?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return KeyCombo.reserved(fromSymbolicHotKeys: entries)
    }

    /// One handler for every shortcut, installed on first use. It lives as
    /// long as the app: the registrar is owned by the app's `HotkeyCenter`.
    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == CarbonHotkeyRegistrar.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let id = hotKeyID.id
            // The application event target dispatches on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(context).takeUnretainedValue().onPress?(id)
            }
            return noErr
        }, 1, &spec, context, &handler)
        if status != noErr {
            Log.app.error("hotkeys: event handler not installed (\(status))")
        }
    }
}
