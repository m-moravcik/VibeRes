import Foundation
import Testing
@testable import VibeRes

@Suite("Preferences persistence")
@MainActor
struct PreferencesTests {
    private static let key = "VibeRes.AutoApplyOnDisplayChange"
    private static let simpleKey = "VibeRes.SimpleMode"

    @Test("Default value is true on first run (key absent in UserDefaults)")
    func defaultIsTrue() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let prefs = Preferences()
        #expect(prefs.autoApplyOnDisplayChange == true)
    }

    @Test("Simple Mode default is true on first run")
    func simpleModeDefaultIsTrue() {
        UserDefaults.standard.removeObject(forKey: Self.simpleKey)
        let prefs = Preferences()
        #expect(prefs.simpleMode == true)
        UserDefaults.standard.removeObject(forKey: Self.simpleKey)
    }

    @Test("Simple Mode toggle persists across instances")
    func simpleModePersists() {
        UserDefaults.standard.removeObject(forKey: Self.simpleKey)
        let p1 = Preferences()
        p1.simpleMode = false
        let p2 = Preferences()
        #expect(p2.simpleMode == false)
        UserDefaults.standard.removeObject(forKey: Self.simpleKey)
    }

    @Test("Setting false persists across instantiation")
    func togglePersists() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let p1 = Preferences()
        p1.autoApplyOnDisplayChange = false
        // New instance should read the persisted value, not the default.
        let p2 = Preferences()
        #expect(p2.autoApplyOnDisplayChange == false)
        // Cleanup so other tests aren't polluted.
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("Setting true after false persists")
    func toggleTrueAgain() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let p1 = Preferences()
        p1.autoApplyOnDisplayChange = false
        let p2 = Preferences()
        p2.autoApplyOnDisplayChange = true
        let p3 = Preferences()
        #expect(p3.autoApplyOnDisplayChange == true)
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

/// Who gets the confirmation timeout on, decided once per install. Run against
/// a private defaults suite, never the app's own preferences.
@Suite("Confirm resolution changes default")
@MainActor
struct ConfirmDefaultTests {
    // The stored keys, written out as the persisted contract in UserDefaults.
    private let confirmKey = "VibeRes.ConfirmDisplayChanges"
    private let onboardingKey = "VibeRes.OnboardingShown"

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "VibeResTests.confirm.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test("A fresh install starts with the timeout on, and keeps it after the tour")
    func freshInstallIsOn() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(Preferences.initialConfirmDisplayChanges(defaults))
        // Finishing the tour must not flip the answer on the next launch.
        defaults.set(true, forKey: onboardingKey)
        #expect(Preferences.initialConfirmDisplayChanges(defaults))
        #expect(defaults.object(forKey: confirmKey) as? Bool == true)
    }

    @Test("An install from before the new default keeps it off")
    func existingInstallStaysOff() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: onboardingKey)
        #expect(!Preferences.initialConfirmDisplayChanges(defaults))
        #expect(defaults.object(forKey: confirmKey) as? Bool == false)
    }

    @Test("A stored answer wins either way", arguments: [true, false])
    func storedAnswerWins(stored: Bool) {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(stored, forKey: confirmKey)
        #expect(Preferences.initialConfirmDisplayChanges(defaults) == stored)
        defaults.set(true, forKey: onboardingKey)
        #expect(Preferences.initialConfirmDisplayChanges(defaults) == stored)
    }

    // A launch argument (`-VibeRes.ConfirmDisplayChanges YES`, as the
    // screenshot and demo scripts pass) reaches UserDefaults as the string
    // "YES" or "NO", not a Bool. It is still the answer, and must not be
    // replaced by a computed default written to the persistent domain.
    @Test("A string answer from a launch argument wins and is not overwritten",
          arguments: [("YES", true), ("NO", false)])
    func stringAnswerWins(raw: String, expected: Bool) {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(raw, forKey: confirmKey)
        defaults.set("YES", forKey: onboardingKey)
        #expect(Preferences.initialConfirmDisplayChanges(defaults) == expected)
        #expect(defaults.object(forKey: confirmKey) as? String == raw)
    }
}
