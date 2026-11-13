import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

// Virtual key codes and Carbon modifier bits, written out from Apple's
// published values (HIToolbox Events.h) rather than read from the code under
// test, so a wrong constant in the app cannot agree with itself here.
private let keyR: UInt32 = 0x0F
private let keyA: UInt32 = 0x00
private let keyE: UInt32 = 0x0E
private let keyF5: UInt32 = 0x60
private let keySpace: UInt32 = 0x31
private let carbonCmd = 256
private let carbonShift = 512
private let carbonOption = 2048
private let carbonControl = 4096

@Suite("Global shortcut combinations")
struct KeyComboTests {
    @Test("A shortcut needs two modifiers, one of them control, option or command",
          arguments: [
              // ⌘A is Select All in every app; ⌥E is the accent dead key.
              (keyA, KeyCombo.Modifiers.command, false),
              (keyE, KeyCombo.Modifiers.option, false),
              (keyA, KeyCombo.Modifiers.control, false),
              (keyA, KeyCombo.Modifiers.shift, false),
              (keyA, KeyCombo.Modifiers([]), false),
              (keyR, KeyCombo.Modifiers([.control, .option]), true),
              (keyR, KeyCombo.Modifiers([.shift, .command]), true),
              (keySpace, KeyCombo.Modifiers([.control, .option, .command]), true),
          ])
    func shapeRule(keyCode: UInt32, modifiers: KeyCombo.Modifiers, accepted: Bool) {
        #expect(KeyCombo(keyCode: keyCode, modifiers: modifiers).hasValidShape == accepted)
    }

    @Test("Function keys work alone, since they type nothing")
    func functionKeysStandAlone() {
        #expect(KeyCombo(keyCode: keyF5, modifiers: []).hasValidShape)
        #expect(KeyCombo(keyCode: keyF5, modifiers: .shift).hasValidShape)
    }

    @Test("Modifiers convert to the bits RegisterEventHotKey expects")
    func carbonModifierBits() {
        let combo = KeyCombo(keyCode: keyR, modifiers: [.control, .option, .command])
        #expect(combo.carbonModifiers == UInt32(carbonControl + carbonOption + carbonCmd))
        let back = KeyCombo(carbonKeyCode: Int(keyR), carbonModifiers: carbonShift + carbonCmd)
        #expect(back == KeyCombo(keyCode: keyR, modifiers: [.shift, .command]))
    }

    @Test("The suggested Revert shortcut is control-option-command-R and a valid shortcut")
    func suggestedRevert() {
        #expect(KeyCombo.suggestedRevert == KeyCombo(keyCode: keyR, modifiers: [.control, .option, .command]))
        #expect(KeyCombo.suggestedRevert.hasValidShape)
    }

    @Test("Modifiers print in menu order: control, option, shift, command")
    @MainActor
    func displayOrder() {
        let text = KeyCombo(keyCode: keyF5, modifiers: [.command, .shift, .option, .control]).displayString
        #expect(text == "⌃⌥⇧⌘F5")
        #expect(KeyCombo(keyCode: keySpace, modifiers: [.control, .option]).displayString == "⌃⌥Space")
    }

    @Test("The UI localizes Space while the CLI keeps its English name",
          arguments: [("en", "Space"), ("sk", "Medzerník"), ("cs", "Mezerník"),
                      ("de", "Leertaste"), ("es", "Espacio"), ("fr", "Espace")])
    @MainActor
    func localizedSpace(language: String, name: String) {
        let combo = KeyCombo(keyCode: keySpace, modifiers: [.control, .option])
        #expect(combo.localizedDisplayString(locale: Locale(identifier: language)) == "⌃⌥" + name)
        #expect(combo.displayString == "⌃⌥Space")
        #expect(KeyCombo.suggestedRevert.localizedDisplayString(locale: Locale(identifier: language)) == "⌃⌥⌘R")
        #expect(KeyCombo(keyCode: keyF5, modifiers: []).localizedDisplayString(locale: Locale(identifier: language)) == "F5")
    }

    @Test("Enabled system shortcuts are reserved; disabled ones and keyless entries are not")
    func reservedFromSymbolicHotKeys() {
        // Shaped like CopySymbolicHotKeys output on macOS 27.
        let entries: [[String: Any]] = [
            // ⌘Space, Spotlight.
            ["kHISymbolicHotKeyEnabled": true, "kHISymbolicHotKeyCode": Int(keySpace),
             "kHISymbolicHotKeyModifiers": carbonCmd],
            // Disabled: the user turned it off, so it is free.
            ["kHISymbolicHotKeyEnabled": false, "kHISymbolicHotKeyCode": Int(keyR),
             "kHISymbolicHotKeyModifiers": carbonControl + carbonCmd],
            // 65535 is "no key assigned".
            ["kHISymbolicHotKeyEnabled": true, "kHISymbolicHotKeyCode": 65535,
             "kHISymbolicHotKeyModifiers": carbonCmd],
        ]
        let reserved = KeyCombo.reserved(fromSymbolicHotKeys: entries)
        #expect(reserved == [KeyCombo(keyCode: keySpace, modifiers: .command)])
    }

    @Test("Stored as a key code and named modifiers, the profiles.json contract")
    func encodedForm() throws {
        let data = try JSONEncoder().encode(KeyCombo(keyCode: keyR, modifiers: [.command, .control]))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["keyCode"] as? Int == Int(keyR))
        #expect(object["modifiers"] as? [String] == ["control", "command"])
    }

    @Test("Unknown modifiers and impossible key codes are refused, not guessed",
          arguments: [
              #"{"keyCode": 15, "modifiers": ["hyper"]}"#,
              #"{"keyCode": 4000, "modifiers": ["command", "option"]}"#,
              #"{"modifiers": ["command", "option"]}"#,
          ])
    func refusesMalformed(json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(KeyCombo.self, from: Data(json.utf8))
        }
    }
}

@Suite("Shortcut modifier-only presses")
struct ModifierOnlyPressTests {
    @Test("Two shortcut modifiers released without a key show the hint",
          arguments: [KeyCombo.Modifiers([.control, .option]), [.shift, .command]])
    func modifiersWithoutKey(modifiers: KeyCombo.Modifiers) {
        var press = ModifierOnlyPress()
        let hints = [press.modifiersChanged(modifiers), press.modifiersChanged([]), press.modifiersChanged([])]
        #expect(hints == [false, true, false])
    }

    @Test("A delivered key suppresses the hint until the next press")
    func deliveredKey() {
        var press = ModifierOnlyPress()
        let firstDown = press.modifiersChanged([.control, .command])
        press.keyPressed()
        let hints = [firstDown, press.modifiersChanged([]),
                     press.modifiersChanged([.control, .command]), press.modifiersChanged([])]
        #expect(hints == [false, false, false, true])
    }

    @Test("A single modifier does not suggest a swallowed shortcut",
          arguments: [KeyCombo.Modifiers.shift, .command, .control, .option])
    func singleModifier(modifier: KeyCombo.Modifiers) {
        var press = ModifierOnlyPress()
        let hints = [press.modifiersChanged(modifier), press.modifiersChanged([])]
        #expect(hints == [false, false])
    }

    @Test("Partial release and re-press show the hint only on full release")
    func partialRelease() {
        var press = ModifierOnlyPress()
        let hints = [press.modifiersChanged([.control, .option]), press.modifiersChanged(.control),
                     press.modifiersChanged([.control, .option]), press.modifiersChanged([]),
                     press.modifiersChanged([])]
        #expect(hints == [false, false, false, true, false])
    }

    @Test("A key before the second modifier still suppresses the hint")
    func keyBeforeValidModifiers() {
        var press = ModifierOnlyPress()
        let firstDown = press.modifiersChanged(.command)
        press.keyPressed()
        let hints = [firstDown, press.modifiersChanged([.shift, .command]), press.modifiersChanged([])]
        #expect(hints == [false, false, false])
    }

    @Test("An unmodified key does not suppress a later modifier-only press")
    func unmodifiedKeyBeforePress() {
        var press = ModifierOnlyPress()
        press.keyPressed()
        let hints = [press.modifiersChanged([.control, .option]), press.modifiersChanged([])]
        #expect(hints == [false, true])
    }
}

@Suite("Profile shortcuts on disk")
@MainActor
struct ProfileHotkeyPersistenceTests {
    private func makeDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-hotkey-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let entry = Profile.Entry(
        matcher: .edid(vendor: 1, model: 2, serial: 3),
        displayName: "Desk",
        pointWidth: 1920, pointHeight: 1080, refreshHz: 60, isHiDPI: true
    )

    private func profileJSON(hotkey: String?) -> String {
        let field = hotkey.map { #", "hotkey": \#($0)"# } ?? ""
        return """
        [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Desk", "createdAt": 0,
          "entries": [{"matcher": {"kind": "edid", "vendor": 1, "model": 2, "serial": 3},
                       "displayName": "Desk", "pointWidth": 1920, "pointHeight": 1080,
                       "refreshHz": 60, "isHiDPI": true}]\(field)}]
        """
    }

    @Test("A profile written before shortcuts existed loads with none")
    func legacyProfileHasNoShortcut() throws {
        let profiles = try JSONDecoder().decode([Profile].self, from: Data(profileJSON(hotkey: nil).utf8))
        #expect(profiles.count == 1)
        #expect(profiles[0].hotkey == nil)
    }

    @Test("An unreadable shortcut drops the shortcut, not the profile")
    func malformedShortcutKeepsProfile() throws {
        let json = profileJSON(hotkey: #"{"keyCode": 15, "modifiers": ["hyper"]}"#)
        let profiles = try JSONDecoder().decode([Profile].self, from: Data(json.utf8))
        #expect(profiles.count == 1)
        #expect(profiles[0].name == "Desk")
        #expect(profiles[0].hotkey == nil)
    }

    @Test("A profile without a shortcut writes no hotkey key")
    func noKeyWhenUnset() throws {
        let data = try JSONEncoder().encode(Profile(name: "Desk", entries: [entry]))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["hotkey"] == nil)
    }

    @Test("setHotkey persists across a reload and touches only that profile")
    func setHotkeyPersists() throws {
        let dir = makeDirectory()
        let store = ProfileStore(directory: dir)
        let desk = Profile(name: "Desk", entries: [entry])
        let sofa = Profile(name: "Sofa", entries: [entry])
        store.add(desk)
        store.add(sofa)
        let combo = KeyCombo(keyCode: keyR, modifiers: [.control, .option])

        #expect(store.setHotkey(combo, for: desk.id) == .saved)

        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles.first { $0.id == desk.id }?.hotkey == combo)
        #expect(reloaded.profiles.first { $0.id == sofa.id }?.hotkey == nil)

        #expect(reloaded.setHotkey(nil, for: desk.id) == .saved)
        #expect(ProfileStore(directory: dir).profiles.first { $0.id == desk.id }?.hotkey == nil)
    }

    @Test("setHotkey on a profile that is gone says so")
    func setHotkeyUnknownProfile() {
        let store = ProfileStore(directory: makeDirectory())
        #expect(store.setHotkey(.suggestedRevert, for: UUID()) == .rejectedNotFound)
    }

    @Test("Editing the entries keeps the shortcut")
    func replaceEntriesKeepsShortcut() {
        let store = ProfileStore(directory: makeDirectory())
        let combo = KeyCombo(keyCode: keyR, modifiers: [.control, .option])
        let desk = Profile(name: "Desk", entries: [entry], hotkey: combo)
        store.add(desk)
        var wider = entry
        wider.pointWidth = 2560
        store.replaceEntries(desk, with: [wider])
        #expect(store.profiles.first?.hotkey == combo)
    }

    /// `capped` used to rebuild an oversized profile field by field, which
    /// dropped every field added after it was written.
    @Test("Trimming an oversized profile keeps its main display and shortcut")
    func cappingKeepsFields() {
        let combo = KeyCombo(keyCode: keyR, modifiers: [.control, .option])
        let oversized = Profile(
            name: "Wall",
            entries: Array(repeating: entry, count: ProfileStore.maximumEntriesPerProfile + 5),
            mainDisplay: .anyExternal,
            hotkey: combo
        )
        let capped = ProfileStore.capped([oversized])[0]
        #expect(capped.entries.count == ProfileStore.maximumEntriesPerProfile)
        #expect(capped.mainDisplay == .anyExternal)
        #expect(capped.hotkey == combo)
    }
}

@Suite("Revert shortcut preference")
@MainActor
struct RevertHotkeyPreferenceTests {
    private let key = "VibeRes.RevertHotkey"

    @Test("Unset by default: VibeRes claims no shortcut on its own")
    func unsetByDefault() {
        UserDefaults.standard.removeObject(forKey: key)
        #expect(Preferences().revertHotkey == nil)
    }

    @Test("A recorded shortcut persists, and clearing it removes it")
    func persistsAndClears() {
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences().revertHotkey = .suggestedRevert
        #expect(Preferences().revertHotkey == .suggestedRevert)
        Preferences().revertHotkey = nil
        #expect(Preferences().revertHotkey == nil)
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    @Test("Unreadable stored data reads as no shortcut")
    func garbageReadsAsUnset() {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(Data("not json".utf8), forKey: key)
        #expect(Preferences().revertHotkey == nil)
    }
}

/// Stands in for Carbon: records what is registered and lets a test decide
/// what macOS and other apps already hold.
@MainActor
private final class FakeRegistrar: HotkeyRegistrar {
    var onPress: ((UInt32) -> Void)?
    var live: [UInt32: KeyCombo] = [:]
    var registerCalls = 0
    var takenElsewhere: Set<KeyCombo> = []
    var reserved: Set<KeyCombo> = []

    func register(_ combo: KeyCombo, id: UInt32) -> HotkeyRegistration {
        registerCalls += 1
        if takenElsewhere.contains(combo) { return .takenByAnotherApp }
        live[id] = combo
        return .registered
    }

    func unregister(id: UInt32) { live[id] = nil }
    func reservedBySystem() -> Set<KeyCombo> { reserved }

    func press(_ combo: KeyCombo) {
        guard let id = live.first(where: { $0.value == combo })?.key else { return }
        onPress?(id)
    }
}

@Suite("Hotkey registration")
@MainActor
struct HotkeyCenterTests {
    private let desk = UUID()
    private let sofa = UUID()
    private let comboA = KeyCombo(keyCode: 0x12, modifiers: [.control, .option]) // ⌃⌥1
    private let comboB = KeyCombo(keyCode: 0x13, modifiers: [.control, .option]) // ⌃⌥2

    private func make() -> (HotkeyCenter, FakeRegistrar) {
        let registrar = FakeRegistrar()
        return (HotkeyCenter(registrar: registrar), registrar)
    }

    @Test("Each binding is registered, and a press reaches its owner")
    func registersAndDispatches() {
        let (center, registrar) = make()
        var pressed: [HotkeyOwner] = []
        center.onPress = { pressed.append($0) }
        center.setBindings([
            HotkeyBinding(owner: .revert, combo: comboA, name: "Revert"),
            HotkeyBinding(owner: .profile(desk), combo: comboB, name: "Desk"),
        ])
        #expect(Set(registrar.live.values) == [comboA, comboB])
        #expect(center.inactive.isEmpty)

        registrar.press(comboB)
        registrar.press(comboA)
        #expect(pressed == [.profile(desk), .revert])
    }

    @Test("Two shortcuts on one combination: the first keeps it, the second is reported")
    func duplicateIsReported() {
        let (center, registrar) = make()
        center.setBindings([
            HotkeyBinding(owner: .revert, combo: comboA, name: "Revert"),
            HotkeyBinding(owner: .profile(desk), combo: comboA, name: "Desk"),
            HotkeyBinding(owner: .profile(sofa), combo: comboB, name: "Sofa"),
        ])
        #expect(registrar.live.values.filter { $0 == comboA }.count == 1)
        #expect(center.inactive == [.profile(desk): .usedByRevert])
    }

    @Test("A combination macOS or another app holds is reported, not registered")
    func unavailableIsReported() {
        let (center, registrar) = make()
        registrar.reserved = [comboA]
        registrar.takenElsewhere = [comboB]
        center.setBindings([
            HotkeyBinding(owner: .profile(desk), combo: comboA, name: "Desk"),
            HotkeyBinding(owner: .profile(sofa), combo: comboB, name: "Sofa"),
        ])
        #expect(registrar.live.isEmpty)
        #expect(center.inactive == [.profile(desk): .reservedBySystem, .profile(sofa): .usedByAnotherApp])
    }

    @Test("A hand-edited single-modifier shortcut is reported, not registered")
    func badShapeFromFileIsReported() {
        let (center, registrar) = make()
        center.setBindings([HotkeyBinding(owner: .revert, combo: KeyCombo(keyCode: keyA, modifiers: .command), name: "Revert")])
        #expect(registrar.live.isEmpty)
        #expect(center.inactive == [.revert: .needsModifiers])
    }

    @Test("Suspending releases every shortcut and ignores presses; resuming restores them")
    func suspendAndResume() {
        let (center, registrar) = make()
        var pressed = 0
        center.onPress = { _ in pressed += 1 }
        center.setBindings([HotkeyBinding(owner: .revert, combo: comboA, name: "Revert")])

        center.suspend()
        #expect(registrar.live.isEmpty)
        // Bindings changed while suspended wait for resume.
        center.setBindings([HotkeyBinding(owner: .revert, combo: comboB, name: "Revert")])
        #expect(registrar.live.isEmpty)

        center.resume()
        #expect(Array(registrar.live.values) == [comboB])
        registrar.press(comboB)
        #expect(pressed == 1)
    }

    @Test("Unchanged bindings do not re-register")
    func unchangedIsNoOp() {
        let (center, registrar) = make()
        let bindings = [HotkeyBinding(owner: .revert, combo: comboA, name: "Revert")]
        center.setBindings(bindings)
        let calls = registrar.registerCalls
        center.setBindings(bindings)
        #expect(registrar.registerCalls == calls)
    }

    @Test("A candidate is checked in order: shape, VibeRes clash, macOS, other apps")
    func problemOrder() {
        let (center, registrar) = make()
        center.setBindings([HotkeyBinding(owner: .profile(sofa), combo: comboA, name: "Sofa")])

        #expect(center.problem(with: KeyCombo(keyCode: keyA, modifiers: .command), for: .revert) == .needsModifiers)
        #expect(center.problem(with: comboA, for: .revert) == .usedByProfile(name: "Sofa"))
        // A profile re-recording its own combination is not a clash.
        #expect(center.problem(with: comboA, for: .profile(sofa)) == nil)

        registrar.reserved = [comboB]
        #expect(center.problem(with: comboB, for: .revert) == .reservedBySystem)
        registrar.reserved = []
        registrar.takenElsewhere = [comboB]
        #expect(center.problem(with: comboB, for: .revert) == .usedByAnotherApp)
        registrar.takenElsewhere = []
        #expect(center.problem(with: comboB, for: .revert) == nil)
    }

    @Test("Checking a free combination leaves nothing registered behind")
    func probeCleansUp() {
        let (center, registrar) = make()
        #expect(center.problem(with: comboA, for: .revert) == nil)
        #expect(registrar.live.isEmpty)
    }

    @Test("Bindings put Revert first and skip profiles without a shortcut")
    func syncBindings() {
        let withKey = Profile(name: "Desk", entries: [], hotkey: comboB)
        let without = Profile(name: "Sofa", entries: [])
        let bindings = HotkeySync.bindings(profiles: [withKey, without], revert: comboA)
        #expect(bindings.map(\.owner) == [.revert, .profile(withKey.id)])
        #expect(bindings.map(\.combo) == [comboA, comboB])
    }
}

/// What a press does. Displays are staged with IDs no real display has and
/// every apply is injected, so nothing here reconfigures the machine.
@Suite("Shortcut actions", .serialized)
@MainActor
struct ShortcutActionTests {
    private let ids: [CGDirectDisplayID] = [101, 102]

    private func realModes() throws -> [CGDisplayMode] {
        let modes = CGDisplayCopyAllDisplayModes(CGMainDisplayID(), nil) as? [CGDisplayMode]
        let all = try #require(modes, "no display modes available on this machine")
        let distinct = all.reduce(into: [CGDisplayMode]()) { acc, mode in
            if !acc.contains(where: { $0.width == mode.width && $0.height == mode.height }) {
                acc.append(mode)
            }
        }
        try #require(distinct.count >= 2, "need two differently-sized modes")
        return distinct
    }

    /// Unknown display IDs read every EDID field as 0xFFFFFFFF, so this
    /// matcher binds both fake displays and nothing real (see BatchApplyTests).
    private func entry(_ mode: CGDisplayMode, matcher: DisplayMatcher = .edid(vendor: .max, model: .max, serial: .max)) -> Profile.Entry {
        Profile.Entry(matcher: matcher, displayName: "Fake", pointWidth: mode.width,
                      pointHeight: mode.height, refreshHz: nil, isHiDPI: mode.isHiDPI)
    }

    private struct Rig {
        let displays: DisplayStore
        let profiles: ProfileStore
        var batches: () -> Int
        var alerts: () -> Int
    }

    private func rig(current: CGDisplayMode, modes: [CGDisplayMode]) -> Rig {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResTests-shortcut-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let profiles = ProfileStore(directory: dir)
        let displays = DisplayStore.forTesting()
        displays.showForDemo(ids.map {
            DisplayInfo(id: $0, name: "Mon \($0)", isMain: false, modes: modes, currentMode: current, groups: [])
        })
        var batches = 0
        profiles.applyBatch = { changes, _ in
            batches += 1
            return ResolutionSwitcher.BatchOutcome(applied: Set(changes.map(\.display)), rejected: [:])
        }
        var alerts = 0
        ShortcutActions.alert = { alerts += 1 }
        return Rig(displays: displays, profiles: profiles, batches: { batches }, alerts: { alerts })
    }

    @Test("A profile that fits applies silently and can be reverted")
    func cleanApply() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)

        ShortcutActions.perform(.profile(profile.id), displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == 1)
        #expect(r.alerts() == 0)
        #expect(r.displays.revert.canRevert)
    }

    @Test("A shortcut does not switch when the live mode already matches despite a stale cached mode")
    func liveTargetIsAlreadyApplied() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)
        r.displays.demoSnapshot = {
            ids.map {
                DisplayInfo(id: $0, name: "Live \($0)", isMain: false,
                            modes: modes, currentMode: modes[0], groups: [])
            }
        }
        let setChangeToken = r.displays.setChangeToken
        let autoApplyToken = r.displays.autoApplyToken

        ShortcutActions.perform(.profile(profile.id), displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == 0)
        #expect(r.alerts() == 0)
        #expect(!r.displays.revert.canRevert)
        #expect(r.displays.displays.allSatisfy { $0.currentMode?.ioDisplayModeID == modes[1].ioDisplayModeID })
        #expect(r.displays.setChangeToken == setChangeToken)
        #expect(r.displays.autoApplyToken == autoApplyToken)
    }

    @Test("A shortcut switches a stale cached target and records the actual live mode for Revert")
    func liveModeIsRecordedForRevert() throws {
        let modes = try realModes()
        let r = rig(current: modes[0], modes: modes)
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)
        r.displays.demoSnapshot = {
            ids.map {
                DisplayInfo(id: $0, name: "Live \($0)", isMain: false,
                            modes: modes, currentMode: modes[1], groups: [])
            }
        }

        ShortcutActions.perform(.profile(profile.id), displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == 1)
        #expect(r.alerts() == 0)
        #expect(r.displays.revert.entries.map(\.displayID).sorted() == ids)
        #expect(r.displays.revert.entries.allSatisfy { $0.before.ioDisplayModeID == modes[1].ioDisplayModeID })
        #expect(r.displays.displays.allSatisfy { $0.currentMode?.ioDisplayModeID == modes[0].ioDisplayModeID })
    }

    @Test("Shortcut classification uses live connections when the cached display set is stale",
          arguments: [false, true])
    func liveConnectionsDetermineApply(connected: Bool) throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let connectedDisplays = r.displays.displays
        if connected { r.displays.showForDemo([]) }
        r.displays.demoSnapshot = { connected ? connectedDisplays : [] }
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)

        ShortcutActions.perform(.profile(profile.id), displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == (connected ? 1 : 0))
        #expect(r.alerts() == (connected ? 0 : 1))
        #expect(r.displays.revert.canRevert == connected)
        #expect(r.displays.displays.isEmpty == connected)
    }

    @Test("A profile whose displays are all missing does nothing and sounds the alert")
    func disjointDoesNothing() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = Profile(name: "Away", entries: [entry(modes[0], matcher: .edid(vendor: 1, model: 2, serial: 3))])
        r.profiles.add(profile)

        ShortcutActions.perform(.profile(profile.id), displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == 0)
        #expect(r.alerts() == 1)
        #expect(!r.displays.revert.canRevert)
    }

    @Test("A profile missing one of its displays applies the rest and sounds the alert")
    func partialAppliesAndAlerts() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = Profile(name: "Desk", entries: [
            entry(modes[0]),
            entry(modes[0], matcher: .edid(vendor: 1, model: 2, serial: 3)),
        ])
        r.profiles.add(profile)

        ShortcutActions.perform(.profile(profile.id), displays: r.displays, profiles: r.profiles)

        #expect(r.batches() == 1)
        #expect(r.alerts() == 1)
    }

    @Test("A shortcut for a deleted profile sounds the alert")
    func unknownProfile() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        ShortcutActions.perform(.profile(UUID()), displays: r.displays, profiles: r.profiles)
        #expect(r.batches() == 0)
        #expect(r.alerts() == 1)
    }

    @Test("Revert with nothing to undo sounds the alert and ends any confirmation",
          arguments: [false, true])
    func revertWithNothingToUndo(pendingConfirmation: Bool) throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        var restores = 0
        r.displays.applyMode = { _, _, _ in restores += 1 }
        if pendingConfirmation {
            r.displays.armConfirmationForTesting(mode: modes[0], display: 101)
        }

        ShortcutActions.perform(.revert, displays: r.displays, profiles: r.profiles)

        #expect(restores == 0)
        #expect(r.alerts() == 1)
        #expect(r.displays.confirmationSecondsRemaining == nil)
    }

    @Test("Revert undoes what a profile shortcut applied")
    func revertAfterProfile() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        var restored: [CGDirectDisplayID] = []
        r.displays.applyMode = { _, id, _ in restored.append(id) }
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)

        ShortcutActions.perform(.profile(profile.id), displays: r.displays, profiles: r.profiles)
        ShortcutActions.perform(.revert, displays: r.displays, profiles: r.profiles)

        #expect(restored.sorted() == ids)
        #expect(r.alerts() == 0)
        #expect(!r.displays.revert.canRevert)
    }

    @Test("A profile shortcut ends old confirmation and its history survives Keep and timeout")
    func profileSupersedesConfirmation() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        let profile = Profile(name: "Desk", entries: [entry(modes[0])])
        r.profiles.add(profile)
        r.displays.revert.record(displayID: 999, displayName: "Old action", before: modes[0])
        r.displays.armConfirmationForTesting(mode: modes[1], display: 999)
        var commits = 0
        r.displays.applyMode = { _, _, _ in commits += 1 }

        ShortcutActions.perform(.profile(profile.id), displays: r.displays, profiles: r.profiles)
        r.displays.confirmDisplayChange()
        r.displays.updateConfirmation(at: .distantFuture)

        #expect(r.displays.confirmationSecondsRemaining == nil)
        #expect(r.batches() == 1)
        #expect(r.alerts() == 0)
        #expect(commits == 0)
        #expect(r.displays.revert.entries.map(\.displayID).sorted() == ids)
    }

    @Test("A global Revert ends old confirmation before a late Keep")
    func globalRevertSupersedesConfirmation() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        r.displays.revert.record(displayID: 101, displayName: "Fake", before: modes[0])
        r.displays.armConfirmationForTesting(mode: modes[1], display: 101)
        var committedModes: [Int32] = []
        r.displays.applyMode = { mode, _, _ in committedModes.append(mode.ioDisplayModeID) }

        ShortcutActions.perform(.revert, displays: r.displays, profiles: r.profiles)
        r.displays.confirmDisplayChange()
        r.displays.updateConfirmation(at: .distantFuture)

        #expect(committedModes == [modes[0].ioDisplayModeID])
        #expect(r.displays.confirmationSecondsRemaining == nil)
        #expect(!r.displays.revert.canRevert)
        #expect(r.alerts() == 0)
    }

    @Test("Revert sounds one alert when one display fails and keeps it retryable")
    func partialRevertAlerts() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        var restored: [CGDirectDisplayID] = []
        r.displays.applyMode = { _, id, _ in
            if id == 102 { throw ResolutionSwitcher.Failure.applyMode(.cannotComplete) }
            restored.append(id)
        }
        r.displays.revert.recordBatch(ids.map { (id: $0, name: "Fake", before: modes[0]) })

        ShortcutActions.perform(.revert, displays: r.displays, profiles: r.profiles)

        #expect(restored == [101])
        #expect(r.alerts() == 1)
        #expect(r.displays.revert.canRevert)
        #expect(r.displays.revert.consume().entries.map(\.displayID) == [102])
    }

    @Test("Revert sounds one alert when modes restore but the main display fails")
    func mainRevertFailureAlerts() throws {
        let modes = try realModes()
        let r = rig(current: modes[1], modes: modes)
        var restored: [CGDirectDisplayID] = []
        r.displays.applyMode = { _, id, _ in restored.append(id) }
        r.displays.liveArrangement = {
            (main: 101, bounds: [
                101: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                102: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            ])
        }
        r.displays.applyOrigins = { _, _ in throw ResolutionSwitcher.Failure.originCoverage }
        r.displays.revert.recordBatch(
            ids.map { (id: $0, name: "Fake", before: modes[0]) }, beforeMain: 102
        )

        ShortcutActions.perform(.revert, displays: r.displays, profiles: r.profiles)

        #expect(restored.sorted() == ids)
        #expect(r.alerts() == 1)
        #expect(r.displays.revert.canRevert)
        let remaining = r.displays.revert.consume()
        #expect(remaining.entries.isEmpty)
        #expect(remaining.beforeMain == 102)
    }
}

/// The real Carbon glue, on a combination nothing ships with (⌃⌥⇧⌘F19), held
/// for a few milliseconds. Checks what the fakes above take on trust: that an
/// exclusive registration reports a holder, and that releasing frees it.
@Suite("Carbon hotkey registration")
@MainActor
struct CarbonHotkeyRegistrarTests {
    private let combo = KeyCombo(keyCode: 0x50, modifiers: [.control, .option, .shift, .command]) // F19

    @Test("A held combination is reported as taken, and is free again once released")
    func exclusiveHolding() {
        let holder = CarbonHotkeyRegistrar()
        let other = CarbonHotkeyRegistrar()
        defer {
            holder.unregister(id: 1)
            other.unregister(id: 2)
        }
        #expect(holder.register(combo, id: 1) == .registered, "⌃⌥⇧⌘F19 is held elsewhere on this Mac")
        #expect(other.register(combo, id: 2) == .takenByAnotherApp)
        holder.unregister(id: 1)
        #expect(other.register(combo, id: 2) == .registered)
    }
}
