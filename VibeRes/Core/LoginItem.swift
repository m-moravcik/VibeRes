import Foundation
import ServiceManagement

/// Wrapper around SMAppService.mainApp — the modern macOS 13+ way to register
/// a menubar app to launch at login. No helper bundle needed.
enum LoginItem {
    /// What macOS says about the registration, reduced to what VibeRes acts on.
    enum Status: Equatable {
        case enabled
        case disabled
        /// Registered, but switched off in System Settings → General → Login
        /// Items (or never approved there). Only the user can change that,
        /// and registering again would not.
        case requiresApproval
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled
        }
    }

    static var isEnabled: Bool { status == .enabled }

    /// What to do when the stored user intent and the system's registration
    /// disagree. Pure so the decision can be tested without SMAppService.
    enum Reconciliation: Equatable {
        case nothingToDo
        case reRegister
        case unregister
        case adoptSystemState(enabled: Bool)
    }

    static func reconciliation(storedIntent: Bool?, status: Status) -> Reconciliation {
        // No record yet: this is the first launch after the intent key shipped.
        // Take the system's word for it rather than flipping the setting under
        // an existing user.
        guard let storedIntent else { return .adoptSystemState(enabled: status == .enabled) }

        switch (storedIntent, status) {
        case (true, .enabled), (false, .disabled):
            return .nothingToDo
        case (true, .requiresApproval):
            // The user turned VibeRes off in System Settings. Registering
            // again at every launch overrode them; Settings shows why it is
            // off and links there instead.
            return .nothingToDo
        case (true, .disabled):
            return .reRegister
        case (false, .enabled), (false, .requiresApproval):
            return .unregister
        }
    }

    /// Applies `reconciliation` and returns the intent that should be stored.
    ///
    /// Called once at launch. If a re-registration fails the intent is kept, not
    /// cleared: the user still wants launch-at-login, and silently forgetting
    /// that is the bug this whole mechanism exists to prevent.
    @discardableResult
    static func reconcile(storedIntent: Bool?) -> Bool {
        let current = status
        switch reconciliation(storedIntent: storedIntent, status: current) {
        case .nothingToDo:
            return storedIntent ?? (current == .enabled)
        case .adoptSystemState(let enabled):
            return enabled
        case .reRegister:
            setEnabled(true)
            return true
        case .unregister:
            setEnabled(false)
            return false
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    /// Whether the Settings toggle reads on: registered, including when
    /// System Settings holds it off, which the note under it then explains.
    static func toggleIsOn(_ status: Status) -> Bool {
        status != .disabled
    }

    /// What Settings says under the toggle, when anything.
    enum Note: Equatable {
        /// Turned off in System Settings; the note links there.
        case needsApproval
        /// The last change did not take, or a wanted registration is missing
        /// (a re-registration at launch failed).
        case couldNotChange
    }

    static func note(status: Status, storedIntent: Bool?, lastChangeFailed: Bool) -> Note? {
        if status == .requiresApproval { return .needsApproval }
        if lastChangeFailed { return .couldNotChange }
        if storedIntent == true, status == .disabled { return .couldNotChange }
        return nil
    }

    /// Opens System Settings → General → Login Items.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// For diagnostics: the system's state, in plain English.
    static func diagnosticLabel(_ status: Status) -> String {
        switch status {
        case .enabled: return "on"
        case .disabled: return "off"
        case .requiresApproval: return "off in System Settings"
        }
    }
}
