import AppKit
import ArcanePorting
import NXLibraryCore

@MainActor
final class GameInboxModel: ObservableObject {
    unowned let app: AppViewModel
    @Published private(set) var entries: [GameInbox.Entry] = []
    @Published private(set) var hasWaitingFiles = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var folder: URL
    private var dropped: [URL] = []
    private static let folderKey = "NXNative_GameInboxFolder"

    static var gamesRoot: URL { AppData.profile.home.appendingPathComponent("Games/Switch/Games", isDirectory: true) }

    init(app: AppViewModel) {
        self.app = app
        let custom = AppData.preferences.string(forKey: Self.folderKey)
        folder = custom.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? AppData.profile.home.appendingPathComponent("Games/Inbox", isDirectory: true)
    }

    var needsGameFilesCorrection: Bool {
        app.porting.gameFilesFolder?.standardizedFileURL.path != Self.gamesRoot.standardizedFileURL.path
    }

    private var isEnabled: Bool { app.settingsStore?.settings.gameInboxEnabled ?? true }

    func updateAvailability() async {
        guard isEnabled, !Task.isCancelled else { return }
        let folder = folder
        let probe = Task.detached(priority: .utility) {
            !Task.isCancelled && !((try? GameInbox.files(in: folder)) ?? []).isEmpty
        }
        let hasFiles = await withTaskCancellationHandler { await probe.value } onCancel: { probe.cancel() }
        guard isEnabled, !Task.isCancelled, folder == self.folder, !busy else { return }
        hasWaitingFiles = hasFiles || !dropped.isEmpty
    }

    func chooseFolder() {
        guard isEnabled, !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = L10n.text("Choose folder")
        guard panel.runModal() == .OK, isEnabled, let path = panel.url else { return }
        AppData.preferences.set(path.path, forKey: Self.folderKey)
        folder = path
        refresh()
    }

    func offerGameFilesCorrection() {
        guard isEnabled else { return }
        let root = Self.gamesRoot
        app.showSettingsNotice(title: L10n.text("Change Game files?"),
                               message: L10n.format("Use %@ as the Game files folder. No files will move.", [root.path]),
                               actionTitle: L10n.text("Change folder"), cancelTitle: L10n.text("Cancel"), primaryFirst: true) { [weak self] in
            guard let self, self.isEnabled, !self.busy else { return }
            AppData.preferences.set(root.path, forKey: PortingModel.savedGameFolderKey)
            self.refresh()
        }
    }

    func accept(_ urls: [URL]) -> Bool {
        guard isEnabled, !busy, urls.contains(where: \.isFileURL) else { return false }
        dropped.append(contentsOf: urls.filter(\.isFileURL))
        refresh()
        return true
    }

    func refresh() {
        guard isEnabled, !busy else { return }
        message = nil
        beginScan()
    }

    private func beginScan() {
        guard isEnabled else { busy = false; return }
        busy = true
        let folder = folder, dropped = dropped, root = Self.gamesRoot
        let repo = URL(fileURLWithPath: app.setup.nxnativePath)
        let reader = packageReader()
        let installed = app.libraryGames
        Task {
            guard isEnabled else { busy = false; return }
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let inputs = GameInbox.inputs(try GameInbox.files(in: folder) + dropped)
                    let packages = inputs.filter(\.canRead).map { (url: $0.url, alreadyIdentified: false) }
                    let reading = Result { try reader?.contents(of: packages) ?? [:] }
                    let metadata = NintendoStoreMetadataService()
                    let entries = GameInbox.plan(inputs: inputs, readings: reader == nil ? nil : (try? reading.get()) ?? [:],
                                                 root: root) { id in
                        let titleID = String(format: "%016llX", id)
                        let profile = repo.appendingPathComponent("dm/games/\(titleID)/game.tsv")
                        if let text = try? String(contentsOf: profile, encoding: .utf8),
                           let name = text.split(separator: "\n").first(where: { $0.hasPrefix("name\t") }) {
                            return String(name.dropFirst(5))
                        }
                        if let name = metadata.cached(for: titleID)?.name { return name }
                        let names = Set(installed.filter { $0.titleId?.uppercased() == titleID }.map(\.name))
                        return names.count == 1 ? names.first : nil
                    }
                    let warning = packages.isEmpty ? nil : reading.failureDescription
                    return (entries, warning)
                }
            }.value
            switch result {
            case .success(let (entries, warning)):
                self.entries = entries
                hasWaitingFiles = !entries.isEmpty
                if message == nil { message = warning }
            case .failure(let error):
                entries = []
                message = error.localizedDescription
            }
            busy = false
        }
    }

    static func confirmation(for entries: [GameInbox.Entry]) -> (title: String, message: String) {
        let duplicates = entries.filter(\.duplicate).count
        return (
            L10n.format("Sort %@ selected files?", [String(entries.count)]),
            L10n.format("Arcane checks the copies before moving the originals to Trash. Identical copies already in Game files: %@.",
                        [String(duplicates)])
        )
    }

    func confirm(_ requested: [GameInbox.Entry]) {
        guard isEnabled, !busy, !needsGameFilesCorrection, !requested.isEmpty,
              requested.allSatisfy({ $0.destination != nil && entries.contains($0) }) else { return }
        let copy = Self.confirmation(for: requested)
        app.showSettingsNotice(title: copy.title, message: copy.message, actionTitle: L10n.text("Sort and move to Trash"),
                               cancelTitle: L10n.text("Cancel"), primaryFirst: true) { [weak self] in
            self?.store(requested)
        }
    }

    private func store(_ requested: [GameInbox.Entry]) {
        guard isEnabled, !busy, !needsGameFilesCorrection, let reader = packageReader() else { return }
        guard app.canAdoptLocalApp, app.buildQueue.isEmpty, !app.porting.isScanningGameFolder else {
            message = L10n.text("Wait for porting and transfers to finish before sorting.")
            return
        }
        let linked = Set(app.libraryGames.flatMap(\.sources).map { $0.url.resolvingSymlinksInPath().path })
        busy = true
        message = nil
        let root = Self.gamesRoot
        Task {
            let (sorted, failures) = await Task.detached(priority: .userInitiated) {
                var sorted = Set<URL>()
                var failures: [String] = []
                for entry in requested {
                    do {
                        guard !linked.contains(entry.source.resolvingSymlinksInPath().path) else {
                            throw NXLibraryError.environmentBlocked(L10n.text("This file is linked to a library game."))
                        }
                        try GameInbox.store(entry, root: root, discover: { destination, content in
                            guard PortingModel.sourceFileURLs(in: destination.deletingLastPathComponent()).contains(where: {
                                $0.standardizedFileURL.path == destination.standardizedFileURL.path
                            }), case .contents(let rows)? = try reader.contents(of: [(destination, false)])[destination],
                                  rows == [content] else { return false }
                            let games = try SourceCatalog().scan(files: [destination], contentsReader: { _ in rows })
                            return games.contains { game in
                                game.baseTitleId == SourceCatalog.baseTitleId(for: content.titleId, kind: content.kind)
                                    && game.allSources.contains { $0.url == destination && $0.titleId == content.titleId }
                            }
                        }, withTrashPermission: { source, commit in
                            // Attach Sources publishes on the main actor. Check and Trash in the same turn.
                            try DispatchQueue.main.sync {
                                try MainActor.assumeIsolated {
                                    guard !self.app.porting.isScanningGameFolder else {
                                        throw NXLibraryError.environmentBlocked(L10n.text("Wait for porting and transfers to finish before sorting."))
                                    }
                                    let sourcePath = source.resolvingSymlinksInPath().path
                                    let games = try self.app.catalogRepository.load().nxnativeGames
                                    guard !games.lazy.flatMap(\.sources).contains(where: {
                                        $0.url.resolvingSymlinksInPath().path == sourcePath
                                    }) else {
                                        throw NXLibraryError.environmentBlocked(L10n.text("This file is linked to a library game."))
                                    }
                                    try commit()
                                }
                            }
                        })
                        sorted.insert(entry.source)
                    } catch {
                        failures.append("\(entry.source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return (sorted, failures)
            }.value
            dropped.removeAll { sorted.contains($0) }
            message = failures.isEmpty ? L10n.format("Files sorted: %@.", [String(sorted.count)]) : failures.joined(separator: "\n")
            beginScan()
        }
    }

    private func packageReader() -> EnginePackageReader? {
        guard app.setup.isProdKeysValid else { return nil }
        return EnginePackageReader(repo: URL(fileURLWithPath: app.setup.nxnativePath), toolchain: app.setup.engineToolchain,
                                   keys: app.setup.keyStore.keyURL, developerDir: app.setup.resolvedDeveloperDir())
    }
}

private extension Result {
    var failureDescription: String? {
        if case .failure(let error) = self { return error.localizedDescription }
        return nil
    }
}
