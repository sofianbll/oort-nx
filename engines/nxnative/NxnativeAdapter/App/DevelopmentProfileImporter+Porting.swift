import Foundation
import OortLibrary

extension DevelopmentProfileImporter {
    /// The copy with the Porting checks.
    public init(fileManager: FileManager = .default) {
        self.init(fileManager: fileManager, checks: Self.portingChecks)
    }

    /// The legacy nxnative library (`library.json`) must still decode, and the catalog must decode with every known
    /// record kind and come from the copied library when it was imported from one.
    public static let portingChecks: [String: Check] = [
        "library.json": { data, _ in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            _ = try decoder.decode(LibraryFile.self, from: data)
        },
        "catalog.json": checkCatalog,
        "catalog.json.bak": checkCatalog,
    ]

    private static let checkCatalog: Check = { data, copy in
        let document = try CatalogStore.decode(data)
        try CatalogStore(directory: copy).validateImportedOrigin(document)
    }

    package static func clearCopiedOperations(in stage: URL) throws {
        let fm = FileManager.default
        func clean(_ original: PortedGame) -> PortedGame {
            var game = original
            game.pendingInstall = nil
            game.appIconPending = false
            game.usesPickedAppIcon = false
            game.appIconOnMac = false
            if game.status == .building { game.status = game.url.pathExtension == "app" ? .builtSourcesMissing : .notBuilt }
            return game
        }
        let main = stage.appendingPathComponent("catalog.json")
        if fm.fileExists(atPath: main.path) {
            for name in ["catalog.json", "catalog.json.bak"] {
                let file = stage.appendingPathComponent(name)
                guard fm.fileExists(atPath: file.path) else { continue }
                let source = try CatalogStore.decode(Data(contentsOf: file))
                let games = try source.games.map { entry in
                    var entry = entry
                    if let game = entry.nxnativeGame { try entry.updateNXNative(clean(game)) }
                    return entry
                }
                let sources = source.sources.map { $0.integration == .steam ? .init(integration: .steam) : $0 }
                let catalog = CatalogDocument(sources: sources, games: games,
                                              preservedGames: source.preservedGames, preservedSources: source.preservedSources)
                try catalog.validate()
                try JSONEncoder().encode(catalog).write(to: file, options: .atomic)
            }
            // This new profile has its own baseline; only discard legacy files inside our disposable stage.
            for name in ["library.json", "library.json.bak"] {
                let file = stage.appendingPathComponent(name)
                if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            }
        } else {
            for name in ["library.json", "library.json.bak"] {
                let file = stage.appendingPathComponent(name)
                guard fm.fileExists(atPath: file.path) else { continue }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var library = try decoder.decode(LibraryFile.self, from: Data(contentsOf: file))
                library.games = library.games.map(clean)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(library).write(to: file, options: .atomic)
            }
        }
    }
}

extension AppData {
    /// Prepares the profile with the Porting checks.
    public static func prepare(contents: DevelopmentProfileImporter.Contents = .legacy) throws {
        try prepare(checks: DevelopmentProfileImporter.portingChecks, contents: contents,
                    sanitizeLibrary: DevelopmentProfileImporter.clearCopiedOperations)
    }
}
