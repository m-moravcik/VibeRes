import AppIntents
import CoreGraphics
import Foundation

/// Represents one connected display in Shortcuts.app's parameter pickers.
/// Lets users pick "Built-in Retina Display" or "Studio Display" by name
/// instead of typing raw CGDirectDisplayID numbers.
struct DisplayEntity: AppEntity {
    /// CGDirectDisplayID is UInt32 but AppIntents requires an EntityIdentifierConvertible
    /// type (Int, String, UUID). We marshal through Int.
    let id: Int
    let name: String

    var cgID: CGDirectDisplayID { CGDirectDisplayID(id) }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Display")

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = DisplayQuery()
}

struct DisplayQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [DisplayEntity] {
        let snapshot = await MainActor.run { DisplayManager.snapshot() }
        return snapshot
            .filter { identifiers.contains(Int($0.id)) }
            .map { DisplayEntity(id: Int($0.id), name: $0.name) }
    }

    func suggestedEntities() async throws -> [DisplayEntity] {
        let snapshot = await MainActor.run { DisplayManager.snapshot() }
        return snapshot.map { DisplayEntity(id: Int($0.id), name: $0.name) }
    }
}
