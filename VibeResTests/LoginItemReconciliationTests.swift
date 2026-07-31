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
        #expect(LoginItem.reconciliation(storedIntent: true, systemEnabled: false) == .reRegister)
    }

    @Test("A registration the user turned off is removed again")
    func notIntendedButSystemHasIt() {
        #expect(LoginItem.reconciliation(storedIntent: false, systemEnabled: true) == .unregister)
    }

    @Test("With no stored intent yet, the system's current state becomes the intent")
    func firstRunAdoptsSystemState() {
        // Upgrading users already have a registration (or not); adopting it
        // avoids flipping the setting under them on the first launch after
        // this change ships.
        #expect(LoginItem.reconciliation(storedIntent: nil, systemEnabled: true)
                == .adoptSystemState(enabled: true))
        #expect(LoginItem.reconciliation(storedIntent: nil, systemEnabled: false)
                == .adoptSystemState(enabled: false))
    }

    @Test("Agreement needs no action")
    func agreementIsLeftAlone() {
        #expect(LoginItem.reconciliation(storedIntent: true, systemEnabled: true) == .nothingToDo)
        #expect(LoginItem.reconciliation(storedIntent: false, systemEnabled: false) == .nothingToDo)
    }
}
