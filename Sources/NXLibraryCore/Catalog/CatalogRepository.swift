import Foundation
import Darwin

public enum CatalogRepositoryError: Error, Equatable { case gameNotFound }

/// Typed transactions against one authoritative catalog. No cached second
/// document and no automatic replay of closures with game-file side effects.
public struct CatalogRepository {
    private let store: CatalogStore
    public init(store: CatalogStore) { self.store = store }
    public func load() throws -> CatalogDocument { try store.loadOrMigrate() }

    package func transaction(_ change: (inout CatalogDocument) throws -> Void) throws -> CatalogDocument {
        try transactionIfChanged { draft in
            try change(&draft)
            return true
        }
    }

    package func transactionIfChanged(_ change: (inout CatalogDocument) throws -> Bool) throws -> CatalogDocument {
        let current = try load()
        var draft = current
        guard try change(&draft) else { return current }
        return try store.save(draft, expectedRevision: current.revision)
    }

    /// A recovery trace precedes both publication and Trash. A failed Trash must not leave a
    /// removed catalog entry, or overwrite a new file at the original location during rollback.
    package func transactionRemovingFiles(from original: CatalogDocument, gameID: UUID, files: [URL],
                                          beforeTrash: () throws -> Void,
                                          _ change: (inout CatalogDocument) throws -> Void) throws -> CatalogDocument {
        var draft = original
        try change(&draft)
        guard !files.isEmpty else { return try store.save(draft, expectedRevision: original.revision) }
        let identities = try files.map(Self.removalIdentity)
        let journal = store.directory.appendingPathComponent("catalog-removal-\(UUID()).json")
        let record = original.games.first { $0.id == gameID }
        var trace = RemovalTrace(revision: original.revision, game: record, files: files,
                                 cloudImportExclusions: original.cloudImportExclusions)
        func saveTrace(replacing: Bool) throws {
            let stage = try CatalogPublication.stage(JSONEncoder().encode(trace), in: store.directory)
            defer { try? FileManager.default.removeItem(at: stage) }
            try CatalogPublication.atomic.publish(stage, journal, replacing) {}
            try CatalogPublication.synchronize(store.directory)
        }
        try saveTrace(replacing: false)
        func finish() { try? FileManager.default.removeItem(at: journal) }
        func rollback(from latest: CatalogDocument) throws {
            var restored = original
            restored.revision = latest.revision
            _ = try store.save(restored, expectedRevision: latest.revision)
        }

        let saved: CatalogDocument
        do {
            saved = try store.save(draft, expectedRevision: original.revision)
        } catch CatalogStoreError.commitUncertain {
            do {
                let latest = try load()
                draft.revision = latest.revision
                guard latest == draft else { throw CatalogStoreError.staleRevision }
                try rollback(from: latest)
                finish()
            } catch { throw CatalogRemovalRecovery(journal: journal) }
            throw CatalogStoreError.commitUncertain
        } catch {
            finish()
            throw error
        }
        var unidentifiedTrash = false
        do {
            for (file, identity) in zip(files, identities) {
                try beforeTrash()
                let found = try Self.removalIdentity(file)
                guard found == identity else { throw CatalogStoreError.staleRevision }
                var destination: NSURL?
                do {
                    try FileManager.default.trashItem(at: file, resultingItemURL: &destination)
                } catch {
                    if let destination = destination as URL? {
                        trace.trashed.append(.init(original: file, destination: destination))
                        try? saveTrace(replacing: true)
                    } else if (try? Self.removalIdentity(file)).map({ $0 == identity }) != true {
                        unidentifiedTrash = true
                    }
                    throw error
                }
                guard let destination = destination as URL? else {
                    unidentifiedTrash = true
                    throw CatalogStoreError.commitUncertain
                }
                trace.trashed.append(.init(original: file, destination: destination))
                try saveTrace(replacing: true)
            }
        } catch {
            var restored = !unidentifiedTrash
            for item in trace.trashed.reversed() {
                if renamex_np(item.destination.path, item.original.path, UInt32(RENAME_EXCL)) != 0 { restored = false }
            }
            do { try rollback(from: saved) }
            catch { restored = false }
            guard restored else { throw CatalogRemovalRecovery(journal: journal) }
            finish()
            throw error
        }
        finish()
        return saved
    }

    private static func removalIdentity(_ url: URL) throws -> (dev_t, ino_t, mode_t) {
        var status = stat()
        guard url.isFileURL, lstat(url.path, &status) == 0 else { throw CatalogStoreError.staleRevision }
        return (status.st_dev, status.st_ino, status.st_mode)
    }

    private struct RemovalTrace: Encodable {
        struct Trashed: Encodable { let original: URL; let destination: URL }
        let version = 1
        let revision: UUID
        let game: CatalogGame?
        let files: [URL]
        let cloudImportExclusions: Set<String>?
        var trashed: [Trashed] = []
    }
}

package struct CatalogRemovalRecovery: LocalizedError {
    let journal: URL

    package var errorDescription: String? {
        L10n.format("Removal could not be fully undone. Recovery record: %@", [journal.path])
    }
}

extension CatalogRepository {
    @discardableResult
    public func configureSource(_ integration: CatalogIntegration, enabled: Bool, root: URL?) throws -> CatalogDocument {
        try transaction { document in
            var config = document.source(integration) ?? .init(integration: integration)
            let nextRoot = root.map { $0.resolvingSymlinksInPath().standardizedFileURL } ?? config.rootURL
            if config.isEnabled != enabled || config.rootURL != nextRoot { config.generation = UUID() }
            config.isEnabled = enabled; config.rootURL = nextRoot
            if let index = document.sources.firstIndex(where: { $0.integration == integration }) { document.sources[index] = config }
            else { document.sources.append(config) }
        }
    }

    @discardableResult
    public func toggleFavorite(for id: UUID) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
            document.games[index].setFavorite(!document.games[index].isFavorite)
        }
    }

    @discardableResult
    public func setFavorite(_ value: Bool, for id: UUID) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
            document.games[index].setFavorite(value)
        }
    }
    @discardableResult
    public func setHidden(_ value: Bool, for id: UUID) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
            document.games[index].setHidden(value)
        }
    }

    @discardableResult
    public func applySteam(_ snapshot: SteamLibrarySnapshot, expectedSource: CatalogSourceConfiguration) throws -> CatalogDocument {
        let current = try load()
        guard expectedSource.integration == .steam, expectedSource.isEnabled,
              current.source(.steam) == expectedSource else { throw CatalogScanError.staleScan }
        let draft = try SteamCatalogReconciler.applying(snapshot, ticket: current.steamScanTicket(), to: current)
        return try store.save(draft, expectedRevision: current.revision)
    }
}
