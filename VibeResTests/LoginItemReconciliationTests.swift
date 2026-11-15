import Foundation
import Testing
@testable import VibeRes

/// `SMAppService` is the only thing that knows whether VibeRes is registered to
/// launch at login, and it can stop saying yes without anyone asking — the app
/// bundle gets replaced, moved, or restored from a backup. With no record of
/// what the user actually wanted, the Settings toggle silently reads "off" and
/// the app cannot tell that it regressed; the user finds out weeks later when
/// VibeRes stops appearing after a reboot.
///
/// Storing the intent separately makes that detectable, and these tests pin the
/// decision table down without touching the real service.
@Suite("Launch-at-login reconciliation")
struct LoginItemReconciliationTests {
    @Test("A registration that vanished is restored")
    func intentedButSystemForgot() {
        #expect(LoginItem.reconciliation(storedIntent: true, status: .disabled) == .reRegister)
    }

    @Test("A registration the user turned off is removed again")
    func notIntendedButSystemHasIt() {
        #expect(LoginItem.reconciliation(storedIntent: false, status: .enabled) == .unregister)
    }

    @Test("With no stored intent yet, the system's current state becomes the intent")
    func firstRunAdoptsSystemState() {
        // Upgrading users already have a registration (or not); adopting it
        // avoids flipping the setting under them on the first launch after
        // this change ships.
        #expect(LoginItem.reconciliation(storedIntent: nil, status: .enabled)
                == .adoptSystemState(enabled: true))
        #expect(LoginItem.reconciliation(storedIntent: nil, status: .disabled)
                == .adoptSystemState(enabled: false))
    }

    @Test("VibeRes turned off in System Settings is not registered over")
    func turnedOffInSystemSettingsIsRespected() {
        // `.requiresApproval` is what SMAppService reports once the user
        // switches VibeRes off under General → Login Items. Re-registering at
        // every launch overrode that choice.
        #expect(LoginItem.reconciliation(storedIntent: true, status: .requiresApproval) == .nothingToDo)
        #expect(LoginItem.reconciliation(storedIntent: false, status: .requiresApproval) == .unregister)
        #expect(LoginItem.reconciliation(storedIntent: nil, status: .requiresApproval)
                == .adoptSystemState(enabled: false))
    }

    @Test("Settings explains a login item held off by System Settings")
    func noteForApproval() {
        #expect(LoginItem.toggleIsOn(.requiresApproval))
        #expect(LoginItem.note(status: .requiresApproval, storedIntent: true, lastChangeFailed: false)
                == .needsApproval)
    }

    @Test("Settings reports a change that did not take, and a wanted registration that is missing")
    func noteForFailure() {
        #expect(LoginItem.note(status: .enabled, storedIntent: false, lastChangeFailed: true) == .couldNotChange)
        #expect(LoginItem.note(status: .disabled, storedIntent: true, lastChangeFailed: false) == .couldNotChange)
        #expect(!LoginItem.toggleIsOn(.disabled))
        #expect(LoginItem.note(status: .disabled, storedIntent: false, lastChangeFailed: false) == nil)
        #expect(LoginItem.note(status: .enabled, storedIntent: true, lastChangeFailed: false) == nil)
    }

    @Test("Diagnostics report what macOS says, and the wish when it differs")
    func diagnosticsLabel() {
        #expect(Diagnostics.loginItemLabel(.enabled, intent: true) == "on")
        #expect(Diagnostics.loginItemLabel(.disabled, intent: true) == "off (wanted on)")
        #expect(Diagnostics.loginItemLabel(.requiresApproval, intent: true) == "off in System Settings (wanted on)")
        #expect(Diagnostics.loginItemLabel(.disabled, intent: nil) == "off")
    }

    @Test("Agreement needs no action")
    func agreementIsLeftAlone() {
        #expect(LoginItem.reconciliation(storedIntent: true, status: .enabled) == .nothingToDo)
        #expect(LoginItem.reconciliation(storedIntent: false, status: .disabled) == .nothingToDo)
    }
}
