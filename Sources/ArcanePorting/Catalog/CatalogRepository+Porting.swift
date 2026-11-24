import Foundation
import NXLibraryCore

extension CatalogDocument {
    /// A projection for the still-nxnative screens, never another writable store.
    public var nxnativeGames: [PortedGame] { games.compactMap(\.nxnativeGame) }
}

/// The nxnative changes to the catalog: one ported game, all of them, a library scan and a finished build.
extension CatalogRepository {
    @discardableResult
    public func updateNXNative(id: UUID, _ change: (inout PortedGame) throws -> Void) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
            guard var game = document.games[index].nxnativeGame else { throw CatalogModelError.wrongIntegration }
            try change(&game)
            try document.games[index].updateNXNative(game)
        }
    }

    @discardableResult
    public func updateNXNativeGames(_ change: (inout [PortedGame]) throws -> Void) throws -> CatalogDocument {
        try mutateNXNativeGames(enablingSource: false, requiringEnabledSource: false, change)
    }

    private func mutateNXNativeGames(enablingSource: Bool, requiringEnabledSource: Bool,
                                     _ change: (inout [PortedGame]) throws -> Void) throws -> CatalogDocument {
        try transaction { document in
            if requiringEnabledSource && !enablingSource && document.source(.nxnative)?.isEnabled != true { throw CatalogScanError.sourceDisabled }
            var games = document.nxnativeGames
            try change(&games)
            guard Set(games.map(\.id)).count == games.count else { throw CatalogModelError.duplicateGameID }
            var updates = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
            document.games = try document.games.compactMap { record in
                guard record.integration == .nxnative else { return record }
                guard let updated = updates.removeValue(forKey: record.id) else { return nil }
                var result = record
                try result.updateNXNative(updated)
                return result
            }
            for game in games where updates[game.id] != nil { document.games.append(.init(nxnative: game)) }
            if enablingSource {
                var config = document.source(.nxnative) ?? .init(integration: .nxnative)
                if !config.isEnabled { config.generation = UUID() }
                config.isEnabled = true
                if let index = document.sources.firstIndex(where: { $0.integration == .nxnative }) { document.sources[index] = config }
                else { document.sources.append(config) }
            }
        }
    }

    @discardableResult
    public func mergeNXNative(scanned: [PortedGame], replacingSources: Bool = false, enableSource: Bool = false,
                              observedFrom baseline: [PortedGame]? = nil,
                              reconcile: (inout [PortedGame], Set<UUID>) throws -> Void = { _, _ in }) throws -> CatalogDocument {
        try mutateNXNativeGames(enablingSource: enableSource, requiringEnabledSource: true) { games in
            let baselineByID = baseline.map { Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
            let protected = Set(games.filter { current in
                if current.status == .building { return true }
                guard let baselineByID else { return false }
                guard let earlier = baselineByID[current.id] else { return true }
                return !Self.sameObservationGeneration(earlier, current)
            }.map(\.id))
            let accepted = scanned.filter { observation in
                let current = games.first { candidate in
                    candidate.id == observation.id || (observation.titleId.map {
                        candidate.titleId?.caseInsensitiveCompare($0) == .orderedSame
                    } ?? false)
                }
                return current.map { !protected.contains($0.id) } ?? true
            }
            games = NXNativeLibraryMerge.merge(scanned: accepted, into: games, replacingSources: replacingSources)
            try reconcile(&games, Set(games.map(\.id)).subtracting(protected))
        }
    }

    private static func sameObservationGeneration(_ earlier: PortedGame, _ current: PortedGame) -> Bool {
        earlier.url == current.url && earlier.status == current.status && earlier.modificationDate == current.modificationDate
            && earlier.lastBuild == current.lastBuild && earlier.pendingInstall == current.pendingInstall
            && earlier.toolchain == current.toolchain && earlier.sources == current.sources
            && earlier.workspacePath == current.workspacePath && earlier.buildCachePath == current.buildCachePath
            && earlier.appIconPending == current.appIconPending
    }

    /// Cloud discovery only adds missing titles; no local observation or personal choice is replaced.
    public func importCloudGames(_ manifests: [CloudGameManifest], in folder: URL,
                                 legacyNames: [String: String] = [:],
                                 sourceRoot: URL = AppData.supportRoot,
                                 referenceFolder: String? = nil) throws -> CatalogDocument {
        try transactionIfChanged { draft in
            let count = draft.games.count
            var seen = draft.cloudImportExclusions ?? []
            let known = Dictionary(draft.games.enumerated().compactMap { index, record in
                record.nxnativeGame?.titleId.map { ($0.uppercased(), index) }
            }, uniquingKeysWith: { first, _ in first })
            var adopted = false
            for manifest in manifests {
                let title = manifest.titleID.uppercased()
                guard SaveLocation.validID(title), let app = manifest.artifacts.first(where: { $0.kind == .app }),
                      seen.insert(title).inserted else { continue }
                if let index = known[title] {
                    guard var game = draft.games[index].nxnativeGame, game.cloudImportPending == true else { continue }
                    let previous = game
                    if referenceFolder == nil { game.cloudReferenceFolder = nil }
                    if game.sources.isEmpty, let sources = manifest.sourceSelection?.adopted(
                        in: CloudGameSources.importedFolder(for: game.id, in: sourceRoot), titleID: title) { game.sources = sources }
                    guard game != previous else { continue }
                    try draft.games[index].updateNXNative(game)
                    adopted = true
                    continue
                }
                let name = [manifest.gameName, legacyNames[title]].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty } ?? title
                let bundle = manifest.bundleName.flatMap { value -> String? in
                    guard (5...200).contains(value.utf8.count), !value.hasPrefix("."),
                          value.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)) == nil,
                          value.lowercased().hasSuffix(".app") else { return nil }
                    return value
                } ?? "\(title).app"
                var game = PortedGame(name: name,
                    url: folder.appendingPathComponent(bundle, isDirectory: true), platform: .macApp,
                    sizeBytes: app.unpackedSize, modificationDate: manifest.createdAt,
                    titleId: title, versionString: manifest.gameVersion)
                game.status = .appMissing
                game.cloudImportPending = true
                game.cloudReferenceFolder = referenceFolder
                game.sources = manifest.sourceSelection?.adopted(
                    in: CloudGameSources.importedFolder(for: game.id, in: sourceRoot), titleID: title) ?? []
                draft.games.append(.init(nxnative: game))
            }
            guard draft.games.count != count else { return adopted }
            var source = draft.source(.nxnative) ?? .init(integration: .nxnative)
            if !source.isEnabled {
                source.isEnabled = true
                source.generation = UUID()
                if let index = draft.sources.firstIndex(where: { $0.integration == .nxnative }) { draft.sources[index] = source }
                else { draft.sources.append(source) }
            }
            return true
        }
    }

    /// Forget only catalog placeholders. Installed apps, downloaded sources and caches never get deleted here.
    package func forgetCloudReference(_ folder: String) throws -> CatalogDocument {
        try transactionIfChanged { document in
            let count = document.games.count
            document.games.removeAll { record in
                guard let game = record.nxnativeGame, game.cloudReferenceFolder == folder,
                      game.cloudImportPending == true, game.workspacePath == nil, game.buildCachePath == nil else { return false }
                return !game.sources.contains { FileManager.default.fileExists(atPath: $0.url.path) }
            }
            return document.games.count != count
        }
    }

    public func removeNXNative(id: UUID) throws -> CatalogDocument {
        try transaction { try Self.removeNXNative(id: id, from: &$0) }
    }

    package func removeNXNativeFiles(id: UUID, from catalog: CatalogDocument, files: [URL], keeping game: PortedGame?,
                                      beforeTrash: () throws -> Void) throws -> CatalogDocument {
        try transactionRemovingFiles(from: catalog, gameID: id, files: files, beforeTrash: beforeTrash) { document in
            guard let game else { return try Self.removeNXNative(id: id, from: &document) }
            guard let index = document.games.firstIndex(where: { $0.id == id }) else {
                throw CatalogRepositoryError.gameNotFound
            }
            try document.games[index].updateNXNative(game)
        }
    }

    private static func removeNXNative(id: UUID, from document: inout CatalogDocument) throws {
        guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
        guard let game = document.games[index].nxnativeGame else { throw CatalogModelError.wrongIntegration }
        if let title = game.titleId, SaveLocation.validID(title) {
            document.cloudImportExclusions = (document.cloudImportExclusions ?? []).union([title.uppercased()])
        }
        document.games.remove(at: index)
    }

    /// Records an app after the archive service has verified and published it.
    public func recordCloudAppRestore(id: UUID, at url: URL) throws -> CatalogDocument {
        try updateNXNative(id: id) { game in
            game.url = url
            game.cloudImportPending = nil
            game.cloudReferenceFolder = nil
            game.status = GameResourceState.sourcesAvailable(for: game) ? .built : .builtSourcesMissing
            game.versionString = BuildOutputInstaller.version(of: url)
            game.bundleId = Bundle(url: url)?.bundleIdentifier
            game.modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        }
    }

    /// Adopt a verified local build without borrowing the replaced app's build record.
    public func recordLocalAppAdoption(_ imported: PortedGame, replacing expected: PortedGame?) throws -> CatalogDocument {
        try mutateNXNativeGames(enablingSource: true, requiringEnabledSource: true) { games in
            guard let index = games.firstIndex(where: { $0.titleId?.uppercased() == imported.titleId }) else {
                guard expected == nil else { throw CatalogStoreError.staleRevision }
                games.append(imported)
                return
            }
            guard let expected, expected.id == games[index].id,
                  Self.sameObservationGeneration(expected, games[index]), games[index].status != .building,
                  games[index].pendingInstall == nil else { throw CatalogStoreError.staleRevision }
            games[index].url = imported.url
            games[index].sizeBytes = imported.sizeBytes
            games[index].modificationDate = imported.modificationDate
            games[index].bundleId = imported.bundleId
            games[index].versionString = imported.versionString
            games[index].toolchain = imported.toolchain
            games[index].lastBuild = nil
            games[index].portingFailure = nil
            games[index].cloudImportPending = nil
            games[index].status = GameResourceState.sourcesAvailable(for: games[index]) ? .built : .builtSourcesMissing
        }
    }
}

extension CatalogRepository {
    /// Apply only fields owned by the finished build. In-flight personal/runtime
    /// changes must not be replaced by the build's earlier payload snapshot.
    @discardableResult
    public func recordNXNativeBuild(_ outcome: PortedGame) throws -> CatalogDocument {
        try updateNXNative(id: outcome.id) { game in
            try game.applyCatalogBuildOutcome(outcome)
        }
    }
}
