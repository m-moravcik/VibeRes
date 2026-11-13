import Foundation
import Observation

/// What a global shortcut does.
enum HotkeyOwner: Hashable, Sendable {
    case revert
    case profile(UUID)
}

/// Why a combination cannot be used, or why a saved one is not working.
enum HotkeyProblem: Equatable, Sendable {
    /// See `KeyCombo.hasValidShape`.
    case needsModifiers
    /// One of the shortcuts in System Settings → Keyboard → Keyboard Shortcuts.
    case reservedBySystem
    /// Another app holds it exclusively. Carbon reports only exclusive
    /// registrations, so an app that registered the same combination without
    /// asking for exclusivity goes unnoticed; whichever registered first wins.
    case usedByAnotherApp
    case usedByRevert
    case usedByProfile(name: String)
    /// Registration failed for a reason Carbon did not name.
    case notRegistered(status: Int32)
}

/// One shortcut the app wants: what it does, the keys, and a name to cite
/// when another shortcut clashes with it.
struct HotkeyBinding: Equatable, Sendable {
    let owner: HotkeyOwner
    let combo: KeyCombo
    let name: String
}

/// Result of asking the system for one combination.
enum HotkeyRegistration: Equatable, Sendable {
    case registered
    case takenByAnotherApp
    case failed(status: Int32)
}

/// The system side of global shortcuts, behind a protocol so the bookkeeping
/// in `HotkeyCenter` can be tested without claiming real key combinations on
/// the machine running the tests. `CarbonHotkeyRegistrar` is the real one.
@MainActor
protocol HotkeyRegistrar: AnyObject {
    /// Called with the id passed to `register` when that shortcut is pressed.
    var onPress: ((UInt32) -> Void)? { get set }
    func register(_ combo: KeyCombo, id: UInt32) -> HotkeyRegistration
    func unregister(id: UInt32)
    /// The system's own enabled shortcuts, read fresh: the user can change
    /// them in System Settings at any time.
    func reservedBySystem() -> Set<KeyCombo>
}

/// Owns the app's global shortcuts: registers what the profiles and the
/// preferences ask for, reports the ones that could not be registered, checks
/// a candidate before the recorder accepts it, and turns a key press into the
/// owner it belongs to.
@Observable
@MainActor
final class HotkeyCenter {
    /// Saved shortcuts that are not working, and why. Shown next to the
    /// recorder so a shortcut that silently does nothing cannot happen.
    private(set) var inactive: [HotkeyOwner: HotkeyProblem] = [:]

    /// Fired on the main actor when a registered shortcut is pressed.
    @ObservationIgnored var onPress: ((HotkeyOwner) -> Void)?

    @ObservationIgnored private let registrar: HotkeyRegistrar
    @ObservationIgnored private var bindings: [HotkeyBinding] = []
    @ObservationIgnored private var registered: [UInt32: HotkeyBinding] = [:]
    @ObservationIgnored private var nextID: UInt32 = 1
    @ObservationIgnored private var suspensions = 0

    /// Never handed out by `nextID`, so a probe cannot collide with a live
    /// registration.
    private static let probeID = UInt32.max

    init(registrar: HotkeyRegistrar) {
        self.registrar = registrar
        registrar.onPress = { [weak self] id in self?.handlePress(id: id) }
    }

    /// True while a recorder is listening; see `suspend()`.
    var isSuspended: Bool { suspensions > 0 }

    /// Replaces the wanted shortcuts. Earlier entries win a clash, so the
    /// caller decides precedence; `HotkeySync` puts Revert first.
    func setBindings(_ new: [HotkeyBinding]) {
        guard new != bindings else { return }
        bindings = new
        guard !isSuspended else { return }
        registerAll()
    }

    /// Releases every shortcut while a recorder listens, so pressing a
    /// combination VibeRes already owns reaches the recorder instead of
    /// running the action. Balanced by `resume()`.
    func suspend() {
        suspensions += 1
        if suspensions == 1 { unregisterAll() }
    }

    func resume() {
        guard suspensions > 0 else { return }
        suspensions -= 1
        if suspensions == 0 { registerAll() }
    }

    /// Why `combo` cannot be given to `owner`, or nil when it can.
    ///
    /// Ordered cheapest and most specific first: a clash with another VibeRes
    /// shortcut names that shortcut, which is more useful than "taken".
    func problem(with combo: KeyCombo, for owner: HotkeyOwner) -> HotkeyProblem? {
        guard combo.hasValidShape else { return .needsModifiers }
        if let other = bindings.first(where: { $0.combo == combo && $0.owner != owner }) {
            return Self.clash(with: other)
        }
        if registrar.reservedBySystem().contains(combo) { return .reservedBySystem }
        // Already ours and live: probing would only find ourselves.
        if registered.values.contains(where: { $0.owner == owner && $0.combo == combo }) { return nil }
        switch registrar.register(combo, id: Self.probeID) {
        case .registered:
            registrar.unregister(id: Self.probeID)
            return nil
        case .takenByAnotherApp:
            return .usedByAnotherApp
        case .failed(let status):
            return .notRegistered(status: status)
        }
    }

    // MARK: - Private

    private static func clash(with other: HotkeyBinding) -> HotkeyProblem {
        switch other.owner {
        case .revert: return .usedByRevert
        case .profile: return .usedByProfile(name: other.name)
        }
    }

    private func registerAll() {
        unregisterAll()
        let reserved = registrar.reservedBySystem()
        var claimed: [KeyCombo: HotkeyBinding] = [:]
        var problems: [HotkeyOwner: HotkeyProblem] = [:]
        for binding in bindings {
            // A hand-edited file or a shortcut taken over by System Settings
            // since it was recorded: same rules as the recorder, reported
            // instead of registered.
            if !binding.combo.hasValidShape {
                problems[binding.owner] = .needsModifiers
                continue
            }
            if reserved.contains(binding.combo) {
                problems[binding.owner] = .reservedBySystem
                continue
            }
            if let first = claimed[binding.combo] {
                problems[binding.owner] = Self.clash(with: first)
                continue
            }
            claimed[binding.combo] = binding
            let id = takeID()
            switch registrar.register(binding.combo, id: id) {
            case .registered:
                registered[id] = binding
            case .takenByAnotherApp:
                problems[binding.owner] = .usedByAnotherApp
            case .failed(let status):
                problems[binding.owner] = .notRegistered(status: status)
            }
        }
        if problems != inactive { inactive = problems }
        let summary = "\(registered.count) registered, \(problems.count) inactive"
        Log.app.info("hotkeys: \(summary)")
    }

    private func unregisterAll() {
        for id in registered.keys { registrar.unregister(id: id) }
        registered.removeAll()
    }

    private func takeID() -> UInt32 {
        let id = nextID
        nextID = nextID >= Self.probeID - 1 ? 1 : nextID + 1
        return id
    }

    private func handlePress(id: UInt32) {
        guard !isSuspended, let binding = registered[id] else { return }
        onPress?(binding.owner)
    }
}
