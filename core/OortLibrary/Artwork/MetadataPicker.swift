import Foundation
import Observation

/// The details a player can choose, field by field, in Change metadata.
public enum MetadataField: String, CaseIterable, Codable, Sendable {
    case description, genres, developer, publisher, releaseDate

    public var title: String {
        switch self {
        case .description: return L10n.text("Description")
        case .genres: return L10n.text("Genres")
        case .developer: return L10n.text("Developer")
        case .publisher: return L10n.text("Publisher")
        case .releaseDate: return L10n.text("Release date")
        }
    }
}

/// One value a source offers for a field. Genres are one comma-separated line.
public struct MetadataOption: Equatable, Hashable, Sendable {
    public let field: MetadataField
    /// "Nintendo store", "Title DB", "GameTDB", "IGDB".
    public let source: String
    public let value: String

    public init(field: MetadataField, source: String, value: String) {
        self.field = field
        self.source = source
        self.value = value
    }
}

/// The details a player chose, per title, in `metadata-picks.json`. They are laid
/// over the store's metadata wherever it shows, and never overwritten by a refresh.
@Observable
public final class MetadataPicks {
    // Main thread only, like its views; the app's models that use it are not yet main-actor types.
    @ObservationIgnored nonisolated(unsafe) public static let shared = MetadataPicks()

    public let directory: URL
    /// Bumps on every change, so screens redraw.
    public private(set) var revision = 0
    @ObservationIgnored package private(set) var table: [String: [String: String]]

    private var fileURL: URL { directory.appendingPathComponent("metadata-picks.json") }

    public init(directory: URL = AppData.supportRoot) {
        self.directory = directory
        let url = directory.appendingPathComponent("metadata-picks.json")
        table = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) } ?? [:]
    }

    public func value(titleID: String, field: MetadataField) -> String? {
        table[titleID]?[field.rawValue]
    }

    /// A blank value takes the pick back.
    public func set(_ value: String, titleID: String, field: MetadataField) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return try remove(titleID: titleID, field: field) }
        var updated = table
        updated[titleID, default: [:]][field.rawValue] = value
        try save(updated)
    }

    public func remove(titleID: String, field: MetadataField) throws {
        var updated = table
        updated[titleID]?[field.rawValue] = nil
        if updated[titleID]?.isEmpty == true { updated[titleID] = nil }
        try save(updated)
    }

    private func save(_ updated: [String: [String: String]]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
        table = updated
        revision += 1
    }
}
