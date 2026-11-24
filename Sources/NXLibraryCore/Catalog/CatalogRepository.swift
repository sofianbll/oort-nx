import Foundation

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
}

extension CatalogRepository {
    public func addMacShortcut(at url: URL) throws -> CatalogDocument {
        let shortcut = try MacShortcutRecord(chosenURL: url)
        return try transactionIfChanged { document in
            guard !document.games.contains(where: { $0.macShortcut?.url.path == shortcut.url.path }) else { return false }
            document.games.append(.init(record: shortcut, personalizationKey: shortcut.key))
            if let index = document.sources.firstIndex(where: { $0.integration == .macShortcut }) {
                document.sources[index].isEnabled = true
            } else {
                document.sources.append(.init(integration: .macShortcut, isEnabled: true))
            }
            return true
        }
    }

    public func relinkMacShortcut(id: UUID, at url: URL) throws -> CatalogDocument {
        try transactionIfChanged { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }),
                  var shortcut = document.games[index].macShortcut else { throw CatalogRepositoryError.gameNotFound }
            let previous = shortcut.url
            try shortcut.relink(to: url)
            guard shortcut.url.path != previous.path else { return false }
            guard !document.games.contains(where: { $0.macShortcut?.url.path == shortcut.url.path }) else {
                throw MacShortcutError.alreadyLinked
            }
            try document.games[index].replaceRecord(shortcut)
            return true
        }
    }

    public func removeMacShortcut(id: UUID) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id && $0.macShortcut != nil }) else {
                throw CatalogRepositoryError.gameNotFound
            }
            document.games.remove(at: index)
        }
    }

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
