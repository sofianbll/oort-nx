import Foundation
import NXLibraryCore

/// The app's catalog store reads every kind it knows (`CatalogRecordKinds.standard`) and converts a first catalog from
/// nxnative's `library.json`.
extension CatalogStore {
    public init(directory: URL) { self.init(directory: directory, kinds: .standard, legacy: .nxnative) }
    init(directory: URL, publication: CatalogPublication) {
        self.init(directory: directory, publication: publication, kinds: .standard, legacy: .nxnative)
    }
    public static func decode(_ data: Data) throws -> CatalogDocument { try decode(data, kinds: .standard) }

    /// A copied catalog cannot take ownership of a build waiting in the previous version.
    package func loadForStartup(previousLibrary: URL) throws -> (catalog: CatalogDocument, keptPreviousBuild: Bool) {
        var catalog = try loadOrMigrate()
        guard LibraryMove.moved(directory) else { return (catalog, false) }
        var changed = false
        for index in catalog.games.indices {
            guard var game = catalog.games[index].nxnativeGame, let pending = game.pendingInstall else { continue }
            let previousPath = [pending.tempApp, pending.finalApp].contains { LibraryMove.contains($0, in: previousLibrary) }
            let destination = pending.finalApp.standardizedFileURL
            // A repair may already have rebased the URL but left the original bundle's inode in the receipt.
            let priorDestination = destination.pathComponents.dropFirst(directory.pathComponents.count)
                .reduce(previousLibrary) { $0.appendingPathComponent($1) }
            let copiedDestination = destination.pathComponents.starts(with: directory.pathComponents)
                && pending.expectedDestination != .vacant && pending.expectedDestination != nil
                && pending.expectedDestination == BuildOutputInstaller.expectedDestination(at: priorDestination)
                && pending.expectedDestination != BuildOutputInstaller.expectedDestination(at: destination)
            guard previousPath || copiedDestination else { continue }
            game.pendingInstall = nil
            try catalog.games[index].updateNXNative(game)
            changed = true
        }
        guard changed else { return (catalog, false) }
        return (try save(catalog, expectedRevision: catalog.revision), true)
    }
}

extension CatalogLegacyImport {
    /// nxnative's library (`library.json` and its backup), with the Switch source switched on.
    public static let nxnative = Self(primary: "library.json", backup: "library.json.bak") { data, origin in
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try CatalogDocument.converting(decoder.decode(LibraryFile.self, from: data), origin: origin)
    }
}

extension CatalogDocument {
    public static func converting(_ legacy: LibraryFile, origin: CatalogLegacyOrigin = .absent) throws -> Self {
        guard legacy.schemaVersion == 1 else { throw CatalogModelError.unsupportedSchema(legacy.schemaVersion) }
        let result = Self(legacyOrigin: origin, sources: [.init(integration: .nxnative, isEnabled: true), .init(integration: .steam)],
                          games: legacy.games.map { .init(nxnative: $0) })
        try result.validate()
        return result
    }
}
