import AppIntents
import Foundation

/// One saved profile in Shortcuts.app's parameter picker, so a Shortcut names
/// "Desk" or "Presentation" instead of a typed string that stops matching the
/// day the profile is renamed. The id is the profile's own, which survives a
/// rename.
struct ProfileEntity: AppEntity {
    let id: UUID
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profile")

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = ProfileQuery()
}

struct ProfileQuery: EntityQuery {
    /// The saved profiles, in the order the popover lists them. Fails with
    /// `appNotReady` before the app has registered its store.
    @MainActor
    func suggestedEntitiesNow() throws -> [ProfileEntity] {
        try IntentRuntime.requireProfiles().profiles.map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    /// A Shortcut stores the id; a profile deleted since is simply absent, and
    /// Shortcuts asks for a new one.
    @MainActor
    func entitiesNow(for identifiers: [UUID]) throws -> [ProfileEntity] {
        try suggestedEntitiesNow().filter { identifiers.contains($0.id) }
    }

    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        try await entitiesNow(for: identifiers)
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        try await suggestedEntitiesNow()
    }
}
