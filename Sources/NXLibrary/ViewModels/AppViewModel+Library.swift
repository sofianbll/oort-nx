import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// The library: dropped files, loading and scanning, importing existing builds, finding sources and the library folder (`applyCatalog`, which writes the published library, stays in the type).
extension AppViewModel {
    // MARK: - Drag and Drop & ZIP
    func handleDroppedURLs(_ urls: [URL]) {
        dropErrorMessage = nil
        guard let first = urls.first else { return }
        if let app = urls.first(where: { $0.isFileURL && $0.pathExtension.lowercased() == "app" }) {
            guard urls.count == 1 else {
                dropErrorMessage = L10n.text("Add one app at a time.")
                return
            }
            adoptLocalApp(app)
            return
        }
        guard first.isFileURL else { return }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir) {
            if isDir.boolValue {
                self.porting.selectedGameFolder = first
            } else {
                let parent = first.deletingLastPathComponent()
                self.porting.selectedGameFolder = parent
            }
        }
    }

    var canAdoptLocalApp: Bool {
        localAppAdoptionBlocker == nil
    }

    var localAppAdoptionBlocker: String? {
        if isBuilding { return L10n.text("Available after the active build finishes or is cancelled.") }
        if isCheckingCloudBuild { return L10n.text("Available after the cloud build check.") }
        if isScanningLibrary { return L10n.text("Available after the current library operation.") }
        if isCleaningStorage { return L10n.text("Available after storage cleanup.") }
        if isUpdatingApp { return L10n.text("Available after the Arcane update.") }
        if cloudLibrary.isChangingConnection { return L10n.text("Available after the cloud connection change.") }
        if cloudLibrary.isWorking { return L10n.text("Available after the cloud transfers.") }
        return nil
    }

    func chooseLocalApp() {
        guard canAdoptLocalApp else { return }
        OortFilePickerPresentation.open(.apps, title: L10n.text("Add ported app"),
                                        message: L10n.text("Choose a game app built with nxnative."),
                                        startingAt: gameAppsFolder) { [weak self] urls in
            if let url = urls.first { self?.adoptLocalApp(url) }
        }
    }

    private func adoptLocalApp(_ url: URL) {
        guard canAdoptLocalApp else { return }
        let folder = gameAppsFolder
        let existing = libraryGames
        let explicitFolder = libraryFolder != nil
        isScanningLibrary = true
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try GameAppDestination.prepareInitialFolder(folder, hasExplicitChoice: explicitFolder)
                    return try ImportService().prepareAdoption(from: url, into: folder, existing: existing)
                }
            }.value
            guard let self else { return }
            isScanningLibrary = false
            defer { if !isScanningLibrary && libraryRescanRequested { loadLibrary() } }
            do {
                let plan = try result.get()
                guard folder == gameAppsFolder, router?.route == .addGame, porting.buildWizardStep == 1 else { return }
                if plan.conflicts {
                    showSettingsNotice(title: L10n.text("Replace game app?"),
                        message: L10n.text("This title already exists. Replace it in the library with a copy of the selected app? The selected app stays where it is."),
                        actionTitle: L10n.text("Replace"), cancelTitle: L10n.text("Cancel")) { [weak self] in
                            self?.installLocalApp(plan, in: folder, replacing: true)
                        }
                } else {
                    installLocalApp(plan, in: folder, replacing: false)
                }
            } catch { alertMessage = error.localizedDescription }
        }
    }

    private func installLocalApp(_ plan: ImportService.Adoption, in folder: URL, replacing: Bool) {
        let importer = ImportService()
        var game = plan.existing ?? importer.makeGame(from: plan.app)
        guard canAdoptLocalApp, gameAppsFolder == folder, let title = game.titleId,
              plan.existing?.pendingInstall == nil, !appIcon.appIconsInFlight.contains(game.id),
              !buildQueue.contains(game.id), let release = acquireSaveInstallLease(for: game) else {
            alertMessage = CloudArchiveError.busy.localizedDescription
            return
        }
        game.url = plan.destination
        let destinationGame = game
        let archive = cloudLibrary.archive
        isScanningLibrary = true
        Task { @MainActor in
            defer {
                release()
                finishLocalAppWork()
                porting.scheduleNextBuild()
            }
            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    try await ImportService().stageAdoption(plan, replacing: replacing, archive: archive)
                }.value
                var published = false
                var needsRecovery = false
                defer {
                    if !needsRecovery {
                        let installed = published
                        Task.detached(priority: .utility) {
                            ImportService().cleanupAdoption(staged, published: installed)
                        }
                    }
                }
                guard folder == gameAppsFolder, archive === cloudLibrary.archive,
                      !isBuilding, !isCheckingCloudBuild, !cloudLibrary.isWorking,
                      RunningGameMonitor.runningApplication(for: destinationGame) == nil else { throw CloudArchiveError.busy }
                do {
                    try importer.publishAdoption(staged) { imported in
                        applyCatalog(try catalogRepository.recordLocalAppAdoption(importer.makeGame(from: imported),
                                                                                   replacing: plan.existing))
                    }
                    published = true
                } catch {
                    needsRecovery = error as? CloudArchiveError == .installFailed
                    throw error
                }
                if let installed = libraryGames.first(where: { $0.titleId == title }) {
                    librarySelection.selectedGameID = installed.id
                    if router?.route == .addGame, porting.buildWizardStep == 1, porting.selectedGameFolder == nil {
                        porting.addGameDidLeave()
                        router?.back()
                        router?.requestSpotlightSelect(installed.id)
                    }
                    let result = L10n.format("Added %@ to the library.", [installed.name])
                    logs.append(LogEntry(level: .success, message: result))
                    if staged.contentUnverified {
                        let warning = L10n.text("Content not verified")
                        logs.append(LogEntry(message: warning))
                        showSettingsNotice(title: result, message: warning, cancelTitle: L10n.text("Close"))
                    }
                    appIcon.reconcileAppIcons()
                    Task { await refreshCloudLibrary(installed) }
                }
            } catch { alertMessage = error.localizedDescription }
        }
    }

    private func finishLocalAppWork() {
        isScanningLibrary = false
        if libraryRescanRequested { loadLibrary() }
    }

    // MARK: - Library
    func refreshLibrary() {
        loadLibrary()
    }

    func loadLibrary() {
        guard !isScanningLibrary, !cloudLibrary.isWorking else { libraryRescanRequested = true; return }
        libraryRescanRequested = false
        do {
            let current = try catalogRepository.load()
            applyCatalog(current)
            scanLibrary(using: current)
        } catch { reportCatalogFailure(error) }
    }

    func resumeLibraryScanAfterCloud() {
        if libraryRescanRequested && !cloudLibrary.isWorking { loadLibrary() }
    }

    /// Startup consumes its already-validated document, without a second
    /// fallible read before publishing the shell or starting runtime hooks.
    func scanLibrary(using current: CatalogDocument) {
        guard !isScanningLibrary else { return }
        let choosingSwitch = !setupCompleted && firstRunSetup.page == .games
        guard current.source(.nxnative)?.isEnabled == true || choosingSwitch else { return }
        let existing = current.nxnativeGames
        isScanningLibrary = true
        let fm = FileManager.default
        let directories = [gameAppsFolder]
        let importer = importService
        let excluded = Set(AppData.preferences.stringArray(forKey: StorageKeys.onboardingExclusions) ?? [])
        let folderSnapshot = libraryFolder?.standardizedFileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanned = importer.scan(directories: directories)
            let scanWarnings = importer.scanWarnings
            let selected = importer.appsForLibrary(scanned: scanned, existing: existing).filter { app in
                !excluded.contains(app.id.uppercased()) || existing.contains { $0.titleId == app.titleId }
            }
            let importedGames = selected.map { importer.makeGame(from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.libraryFolder?.standardizedFileURL == folderSnapshot else {
                    self.isScanningLibrary = false
                    self.loadLibrary()
                    return
                }
                defer {
                    self.isScanningLibrary = false
                    if self.libraryRescanRequested {
                        self.libraryRescanRequested = false
                        self.loadLibrary()
                    }
                }
                var scannedByTitle: [String: ImportedApp] = [:]
                for app in selected {
                    if let titleId = app.titleId, scannedByTitle[titleId.uppercased()] == nil {
                        scannedByTitle[titleId.uppercased()] = app
                    }
                }
                do {
                    let catalog = try self.catalogRepository.mergeNXNative(scanned: importedGames, enableSource: choosingSwitch, observedFrom: existing) { games, acceptedIDs in
                        for index in games.indices where acceptedIDs.contains(games[index].id) {
                            let scannedApp = games[index].titleId
                                .flatMap { scannedByTitle[$0.uppercased()] }
                            if let scannedApp, !fm.fileExists(atPath: games[index].url.path),
                               fm.fileExists(atPath: scannedApp.appURL.path) {
                                games[index].url = scannedApp.appURL
                            }
                            if let scannedApp, fm.fileExists(atPath: scannedApp.appURL.path) {
                                games[index].sizeBytes = scannedApp.sizeBytes
                                games[index].versionString = scannedApp.version
                                    ?? games[index].versionString
                                games[index].bundleId = scannedApp.bundleId
                                    ?? games[index].bundleId
                            }
                            let appExists = fm.fileExists(atPath: games[index].url.path)
                            let sourcesExist = GameResourceState.sourcesAvailable(for: games[index], fileManager: fm)
                            games[index].status = GameResourceState.reconciledStatus(
                                for: games[index], appExists: appExists, sourcesAvailable: sourcesExist)
                        }
                    }
                    self.applyCatalog(catalog)
                    self.appIcon.reconcileAppIcons()
                } catch { self.reportCatalogFailure(error) }
                self.libraryScanWarnings = scanWarnings
                for warning in scanWarnings { self.logs.append(LogEntry(level: .warning, message: warning)) }
            }
        }
    }

    func importExistingBuilds() {
        AppData.preferences.removeObject(forKey: StorageKeys.onboardingExclusions)
        do { applyCatalog(try catalogRepository.configureSource(.nxnative, enabled: true, root: nil)); loadLibrary() }
        catch { reportCatalogFailure(error) }
    }

    /// Attach source files to an already-imported app. The app URL, version and
    /// build metadata stay intact; the library entry is merged, never duplicated.
    func locateSources(for game: PortedGame) {
        guard canAdoptLocalApp, !porting.isScanningGameFolder else { return }
        guard let titleId = game.titleId, SaveLocation.validID(titleId) else {
            alertMessage = L10n.text("This game has no valid title ID.")
            return
        }
        porting.chooseGameFiles(allowFolder: true) { [weak self] selected in
            self?.attachSources(selected, to: game, titleId: titleId)
        }
    }

    private func attachSources(_ selected: [URL], to game: PortedGame, titleId: String) {
        guard canAdoptLocalApp, !porting.isScanningGameFolder, let first = selected.first else { return }
        let isFolder = selected.count == 1 && first.hasDirectoryPath
        guard isFolder || !selected.contains(where: \.hasDirectoryPath) else {
            alertMessage = L10n.text("Choose game files or one folder, not both.")
            return
        }
        let folder = isFolder ? first : first.deletingLastPathComponent()

        porting.isScanningGameFolder = true
        let generation = UUID()
        porting.scanGeneration = generation
        let catalog = sourceCatalog
        let repo = URL(fileURLWithPath: setup.nxnativePath)
        let toolchain = setup.engineToolchain
        let keys = setup.isProdKeysValid ? setup.keyStore.keyURL : nil
        let developer = setup.resolvedDeveloperDir()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = isFolder ? (ExtractedSourceCatalog.recognizes(folder) ? [] : PortingModel.sourceFileURLs(in: folder)) : selected
            let outcome = Result { try PortingModel.scanSources(in: folder, files: urls, catalog: catalog,
                repo: repo, toolchain: toolchain, keys: keys, developerDir: developer, allowExtractedFolder: isFolder) }
            DispatchQueue.main.async {
                guard let self, self.porting.scanGeneration == generation else { return }
                self.porting.isScanningGameFolder = false
                do {
                    let detected = try outcome.get()
                    guard let match = SourceSelection.attachmentMatch(in: detected.games, titleID: titleId) else {
                        self.alertMessage = L10n.format("Choose playable source files for title ID %@.", [titleId])
                        return
                    }
                    let files = PortingModel.selectableGame(from: match).files
                    let choices = SourceSelection.initial(in: files)
                    let sources = files.filter { choices.contains($0.id) }.map {
                        var file = $0
                        file.isSymlink = true
                        return file
                    }
                    guard self.porting.supportsSources(sources), SourceSelection.hasGame(sources),
                          SourceSelection.matchesNUPProgram(sources, titleID: titleId) else {
                        throw NXLibraryError.environmentBlocked(L10n.text("These sources need an engine with extracted-folder or multi-title support."))
                    }
                    guard self.canAdoptLocalApp, !self.buildQueue.contains(game.id) else { throw CloudArchiveError.busy }
                    let scratch = BuildScratch.choose(core: self.core, appFolder: self.gameAppsFolder)
                    let workspace = WorkspaceManager(root: scratch.workspaces).plannedWorkspace(for: match, mode: .staged)
                    self.applyCatalog(try self.catalogRepository.updateNXNative(id: game.id) { stored in
                        guard stored.titleId == titleId, stored.sources == game.sources, stored.pendingInstall == nil else {
                            throw CatalogStoreError.staleRevision
                        }
                        stored.sources = sources
                        stored.workspacePath = stored.workspacePath ?? workspace.directory.path
                        stored.buildCachePath = stored.buildCachePath ?? workspace.buildCache.path
                        stored.status = GameResourceState.reconciledStatus(for: stored,
                            appExists: FileManager.default.fileExists(atPath: stored.url.path),
                            sourcesAvailable: GameResourceState.sourcesAvailable(for: stored))
                    })
                    self.logs.append(LogEntry(level: .success,
                        message: L10n.format("Sources attached to %@; rebuild is now available if the toolchain gate allows it.", [String(describing: game.name)])))
                } catch {
                    self.alertMessage = error.localizedDescription
                    self.logs.append(LogEntry(level: .error, message: error.localizedDescription))
                }
            }
        }
    }

    func selectLibraryFolder(startingAt start: URL? = nil, onPick: (() -> Void)? = nil, stage: ((URL) -> Void)? = nil) {
        OortFilePickerPresentation.open(.folder, title: L10n.text(GameFoldersCopy.appsTitle),
            message: GameFoldersCopy.appsPickerMessage, startingAt: start ?? libraryFolder,
            canCreateDirectories: stage == nil) { [weak self] urls in
            guard let self, let url = urls.first else { return }
            guard url.standardizedFileURL.path != "/" else {
                self.alertMessage = L10n.text("Choose the folder containing your game apps, rather than a whole disk.")
                return
            }
            if let stage { stage(url.standardizedFileURL); return }
            if let settingsStore = self.settingsStore, settingsStore.settings.launcherChoices.gameAppsPath != nil {
                settingsStore.settings.launcherChoices.gameAppsPath = url.path
            } else {
                AppData.preferences.set(url.path, forKey: StorageKeys.savedLibraryFolder)
            }
            self.useGameAppsPath(url.path)
            onPick?()
        }
    }

    func useGameAppsPath(_ path: String) {
        guard libraryFolder?.path != path else { return }
        libraryFolder = URL(fileURLWithPath: path)
        loadLibrary()
    }
}
