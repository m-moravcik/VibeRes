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
