import Foundation

/// Local, read-only discovery. No key store, engine process, artwork provider or app installation.
public struct OnboardingInventory {
    public struct Entry: Identifiable {
        public let id: String
        public let name: String
        public var game: PortedGame?
        public let alreadyInLibrary: Bool
        public var isApp: Bool { game?.isPlayableLocally == true }
    }

    public let entries: [Entry]
    public let incomplete: Bool

    public static func read(apps: [URL], files: URL?, existing: [PortedGame],
                            cancelled: () -> Bool = { false }) -> Self {
        let importer = ImportService()
        let installed = importer.appsForLibrary(scanned: importer.scan(directories: apps, measureSize: false,
                                                                        cancelled: cancelled), existing: existing)
        let known = Set(existing.compactMap { $0.titleId?.uppercased() })
        var entries = Dictionary(uniqueKeysWithValues: installed.compactMap { app -> (String, Entry)? in
            guard let id = app.titleId?.uppercased() else { return nil }
            return (id, Entry(id: id, name: app.name, game: importer.makeGame(from: app),
                              alreadyInLibrary: known.contains(id)))
        })
        var incomplete = cancelled() || !importer.scanWarnings.isEmpty
        var unresolved: [Entry] = []
        if let files {
            let fm = FileManager.default
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            let paths = fm.enumerator(at: files, includingPropertiesForKeys: Array(keys),
                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) { _, _ in
                incomplete = true
                return true
            }
            if paths == nil { incomplete = true }
            var sources: [URL] = []
            if let paths {
                for (index, item) in paths.enumerated() {
                    if cancelled() || index >= 20_000 { incomplete = true; break }
                    guard let url = item as? URL,
                          ["nsp", "nsz", "xci", "xcz", "nup"].contains(url.pathExtension.lowercased()),
                          let info = try? url.resourceValues(forKeys: keys),
                          info.isRegularFile == true, info.isSymbolicLink != true,
                          (info.fileSize ?? 0) > 0 else { continue }
                    sources.append(url)
                }
            }
            let reader = SourceCatalog()
            func cannotIdentify(_ url: URL) {
                unresolved.append(Entry(id: url.path, name: url.lastPathComponent, game: nil,
                    alreadyInLibrary: existing.contains { $0.sources.contains { $0.url == url } }))
            }
            // The keyless reader can infer an ID from a name. It cannot choose a program in a multi-title NUP.
            for url in sources where url.pathExtension.lowercased() == "nup" { cannotIdentify(url) }
            let groups = try? reader.scan(files: sources.filter { $0.pathExtension.lowercased() != "nup" },
                                          skippingUnreadable: true, onUnreadable: { url, _ in cannotIdentify(url) },
                                          cancelled: cancelled)
            for group in groups ?? [] {
                if cancelled() { incomplete = true; break }
                guard let base = group.base else {
                    for source in group.allSources { cannotIdentify(source.url) }
                    continue
                }
                let id = group.id
                var game = entries[id]?.game
                    ?? PortedGame(name: group.name, url: base.url, platform: .macApp, sizeBytes: group.totalSizeBytes,
                                  modificationDate: .now, titleId: id)
                game.sources = group.allSources.map {
                    GameFileItem(url: $0.url, kind: $0.kind, titleId: String(format: "%016llX", $0.titleId),
                                 versionString: $0.version.map(String.init), sizeBytes: $0.sizeBytes, isSymlink: true)
                }
                entries[id] = Entry(id: id, name: game.name, game: game, alreadyInLibrary: known.contains(id))
            }
        }
        let ordered = Array(entries.values) + unresolved
        return Self(entries: ordered.sorted {
            if $0.isApp != $1.isApp { return $0.isApp }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }, incomplete: incomplete)
    }
}
