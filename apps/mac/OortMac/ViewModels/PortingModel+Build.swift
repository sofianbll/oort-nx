import AppKit
import Foundation
import UniformTypeIdentifiers
import OortLibrary
import ArcanePorting

/// Starting a porting: the keys against the selection, adding the game, the build and its controls.
extension PortingModel {
    // MARK: - Keys against the selection
    /// Keys that are too old or do not open the game disable Add and port.
    var keyCheckBlocks: Bool { keyCheck?.blocks == true }

    /// Re-runs the check off the main thread when the keys file or the selected sources changed;
    /// a result that arrives after a newer change is dropped.
    func refreshKeyCheck() {
        let sources = selectedSources
        let files = KeyCheck.parts(sources.map { ($0.kind, $0.url) })
        guard SourceSelection.requiresKeys(sources), app.setup.isProdKeysValid, !files.isEmpty else {
            keyCheck = nil
            keyCheckToken = nil
            return
        }
        let keysURL = app.setup.managedKeysURL
        let modified = (try? FileManager.default.attributesOfItem(atPath: keysURL.path)[.modificationDate]) as? Date
        let token = ([String(modified?.timeIntervalSince1970 ?? 0)]
            + sources.map { "\($0.url.path)|\($0.sizeBytes)" }.sorted()).joined(separator: "\n")
        guard token != keyCheckToken else { return }
        keyCheckToken = token
        keyCheck = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = KeyCheck.run(keysURL: keysURL, files: files)
            guard let self else { return }
            await MainActor.run {
                guard self.keyCheckToken == token else { return }
                self.keyCheck = outcome
            }
        }
    }

    // MARK: - Build run
    private func buildScope(title: String, appURL: URL, registered: [URL], workspace: URL?) -> CloudWorkScope {
        let scratch = BuildScratch.choose(core: app.core, appFolder: appURL.deletingLastPathComponent(), existingWorkspace: workspace)
        return CloudWorkScope(title: title, urls: registered + [appURL, scratch.workspaces.appendingPathComponent(title.uppercased())])
    }

    private func buildScope(for game: PortedGame) -> CloudWorkScope {
        let workspace = game.workspacePath.map { URL(fileURLWithPath: $0) }
        return buildScope(title: game.titleId ?? "", appURL: finalAppURL(for: game),
                          registered: [game.url] + game.sources.map(\.url) +
                              [workspace, game.buildCachePath.map { URL(fileURLWithPath: $0) }].compactMap { $0 },
                          workspace: workspace)
    }

    private var selectedFolderWorkspace: URL? {
        guard selectedPackageURLs == nil, detectedGames.count == 1,
              let selectedGame, selectedSources.count == selectedGame.files.count,
              selectedSources.allSatisfy({ $0.layout == .package }) else { return nil }
        return selectedGameFolder
    }

    var canStartBuild: Bool {
        !app.isBuilding
            && !app.setup.isSwitchingEngine
            && !app.isCheckingCloudBuild
            && app.buildQueue.isEmpty
            && !app.cloudLibrary.isChangingConnection
            && (!app.cloudLibrary.isWorking || selectedGame?.titleId.map { title in
                let existing = selectedLibraryGame
                let workspace = existing?.workspacePath.map { URL(fileURLWithPath: $0) } ?? selectedFolderWorkspace
                return !app.cloudLibrary.conflicts(with: buildScope(title: title, appURL: selectedBuildAppURL,
                    registered: [existing?.url, workspace, existing?.buildCachePath.map { URL(fileURLWithPath: $0) }]
                        .compactMap { $0 } + selectedSources.map(\.url), workspace: workspace))
            } == true)
            && !app.isCleaningStorage
            && !app.isUpdatingApp
            && self.canAddSelectedGame
            && supportsSources(self.selectedSources)
            && (!self.selectedSourcesRequireKeys || app.setup.isProdKeysValid)
            && !self.keyCheckBlocks
            && app.setup.isNxnativeValid
            && app.setup.environmentStatus?.canBuild == true
            && !self.isDiskSpaceLow
            && self.buildDestinationProblem == nil
            && app.setup.canPassToolchainGate
    }

    func buildLogTail(_ url: URL, maxBytes: Int = 64 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    #if DEBUG
    /// Feeds sample events through the same reducer as a real build, for
    /// SwiftUI previews and UI work without running nxnative.
    func previewBuild() {
        app.isBuilding = true
        self.buildState = .running
        self.buildWizardStep = 3
        app.currentBuildGameID = app.libraryGames.first?.id
        app.logs.removeAll()
        self.buildStages.removeAll()
        self.currentStageName = "Preparing build"
        self.currentStepName = ""
        self.progressFraction = 0
        self.etaSeconds = nil
        handleBuildEvent(.stage(k: 1, n: 8, name: "extract", step: "reading NSP"))
        handleBuildEvent(.stageEnd(name: "extract", ok: true, elapsed: 1.2, summary: L10n.text("done")))
        handleBuildEvent(.stage(k: 2, n: 8, name: "translate shaders", step: "metal"))
        handleBuildEvent(.progress(fraction: 0.34, done: 120, total: 350, unit: "MB", eta: 42))
        handleBuildEvent(.say("Sample event: this is the live build reducer."))
    }
    #endif

    func addSelectedGame(buildNow: Bool = false) {
        guard !buildNow || canStartBuild else { return }
        guard let selection = self.selectedGame else {
            presentBuildError(NXLibraryError.noSelectedGame)
            return
        }
        let files = self.selectedSources
        if buildNow, !files.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) {
            guard let archive = app.cloudLibrary.archive, let existing = selectedLibraryGame,
                  app.canCheckCloudSources(for: existing),
                  Set(existing.sources.map(\.url)) == Set(files.map(\.url)) else {
                presentBuildError(NXLibraryError.missingSources)
                return
            }
            let selectionID = selection.id
            requestCloudBuild(for: existing, archive: archive, extraArguments: [], onStarted: nil,
                              afterSourcesDownloaded: { [weak self] in
                guard let self, self.selectedGame?.id == selectionID, self.selectedSources == files else { return }
                self.addSelectedGame(buildNow: true)
            })
            return
        }
        let sources = files.compactMap(Self.detectedSource(from:))
        // A NUP with no base game has only its updates: the selected one is taken as the whole game.
        guard SourceSelection.hasGame(files),
              let baseTitleId = UInt64(selection.titleId ?? "", radix: 16) else {
            presentBuildError(NXLibraryError.baseRequired)
            return
        }
        var detected = DetectedGame(
            baseTitleId: baseTitleId,
            name: selection.name,
            base: sources.first(where: { $0.kind == .base }),
            updates: sources.filter { $0.kind == .update },
            dlcs: sources.filter { $0.kind == .dlc }
        )
        let customName = self.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customName.isEmpty { detected.name = customName }
        do {
            let game = try addGame(
                detected: detected,
                selected: sources,
                folder: selectedFolderWorkspace,
                bundleId: self.bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : self.bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // Existing titles start Review with their saved settings. The
            // values the user confirms are the values used at the next launch.
            if let gameSettings = app.runtimeSettings.gameSettings(for: game) {
                try gameSettings.migrate()
                try gameSettings.apply(pendingRuntimeConfig, changedFrom: gameSettings.runtimeConfig())
            } else {
                try pendingRuntimeConfig.save(for: game)
            }
            app.librarySelection.selectedGameID = game.id
            app.logs.append(LogEntry(level: .success, message: L10n.format("Added %@ to the library.", [String(describing: game.name)])))
            if buildNow {
                startBuild(for: game)
            } else {
                self.resetWizard()
            }
        } catch {
            presentBuildError(error)
        }
    }

    @discardableResult
    func addGame(detected: DetectedGame, selected: [DetectedSource],
                        folder: URL?, bundleId: String? = nil) throws -> PortedGame {
        guard !app.cloudLibrary.isChangingConnection else { throw CloudArchiveError.busy }
        let selectedGame = DetectedGame(
            baseTitleId: detected.baseTitleId,
            name: detected.name,
            base: selected.first(where: { $0.kind == .base }),
            updates: selected.filter { $0.kind == .update },
            dlcs: selected.filter { $0.kind == .dlc }
        )
        guard selectedGame.hasGame else { throw NXLibraryError.baseRequired }
        let mode: WorkspaceMode = folder.map { .folder($0) } ?? .staged
        // Register the path without creating a workspace while the cloud gate still needs to run.
        let root = BuildScratch.choose(core: app.core, appFolder: app.gameAppsFolder).workspaces
        let titleId = String(format: "%016llX", detected.baseTitleId)
        let manager = WorkspaceManager(root: root)
        let existing = app.hasCloudLibrary ? app.libraryGames.first { $0.titleId?.caseInsensitiveCompare(titleId) == .orderedSame } : nil
        let workspace: Workspace
        if app.hasCloudLibrary {
            if let directory = existing?.workspacePath, let cache = existing?.buildCachePath {
                workspace = Workspace(directory: URL(fileURLWithPath: directory), buildCache: URL(fileURLWithPath: cache), links: [])
            } else {
                workspace = manager.plannedWorkspace(for: selectedGame, mode: mode)
            }
        } else {
            workspace = try manager.makeWorkspace(for: selectedGame, mode: mode)
        }
        let updateVersion = selected.filter { $0.kind == .update }
            .compactMap { $0.version }.max().map(String.init)

        var game = PortedGame(
            name: detected.name,
            url: existing.flatMap { $0.url.pathExtension.lowercased() == "app" ? $0.url : nil } ?? workspace.directory,
            platform: .macApp,
            sizeBytes: selectedGame.totalSizeBytes,
            modificationDate: Date(),
            bundleId: bundleId ?? "org.nxnative.\(titleId.lowercased())",
            titleId: titleId,
            versionString: updateVersion
        )
        game.sources = selected.map {
            GameFileItem(url: $0.url, kind: $0.kind,
                         titleId: String(format: "%016llX", $0.titleId),
                         versionString: $0.version.map(String.init),
                         sizeBytes: $0.sizeBytes, isSymlink: folder == nil, sourceLayout: $0.layout,
                         requiresTitleSelection: $0.requiresTitleSelection, nupProgram: $0.nupProgram)
        }
        game.workspacePath = workspace.directory.path
        game.buildCachePath = workspace.buildCache.path
        game.status = existing?.status ?? .notBuilt
        if let existing { game.toolchain = existing.toolchain; game.lastBuild = existing.lastBuild }
        game.settings = pendingRuntimeConfig

        if app.cloudLibrary.isWorking || checkingCloudBuildScope != nil {
            let scope = buildScope(for: game)
            guard !app.cloudLibrary.conflicts(with: scope), checkingCloudBuildScope?.overlaps(scope) != true else {
                throw CloudArchiveError.busy
            }
        }
        let catalog = try app.catalogRepository.mergeNXNative(scanned: [game], replacingSources: true, enableSource: true)
        app.applyCatalog(catalog)
        return catalog.nxnativeGames.first(where: { $0.titleId == titleId }) ?? game
    }

    /// A queued build starts in the background, without reopening the UI that requested it.
    func startBuild(for game: PortedGame, extraArguments: [String] = [], onStarted: (() -> Void)? = nil) {
        submitBuild(for: game, extraArguments: extraArguments, onStarted: onStarted)
    }

    func submitBuild(for game: PortedGame, extraArguments: [String], onStarted: (() -> Void)?,
                     withoutCache: Bool = false, preferLocalCache: Bool = false, request: BuildRequest? = nil) {
        let rebuild = game.url.pathExtension.lowercased() == "app" && game.cloudImportPending != true
        var request = request ?? BuildRequest(gameID: game.id, name: game.name, arguments: extraArguments,
                                              withoutCache: withoutCache, rebuild: rebuild || withoutCache)
        if preferLocalCache { request.preferLocalCache = true }
        guard !app.cloudLibrary.isQuitting, activeBuildRequest?.gameID != game.id,
              checkingCloudBuild?.id != game.id, !app.buildQueue.contains(game.id) else { return }
        if !hasRestoredBuildQueue || app.isBuilding || app.isCheckingCloudBuild || app.setup.isSwitchingEngine || !app.buildQueue.isEmpty ||
            (app.cloudLibrary.archive != nil && !app.cloudLibrary.hasRestoredQueue) {
            enqueueBuild(request)
            scheduleNextBuild()
            return
        }
        startBuildImmediately(for: game, request: request, onStarted: onStarted, queued: false)
    }

    func cancelQueuedBuild(_ id: UUID) {
        guard let request = pendingBuilds.remove(id) else { return }
        app.recordActivity(request.id, job: .build(request), name: request.name, outcome: .cancelled)
        publishBuildQueue()
        scheduleNextBuild()
    }

    func restoreBuildQueue(_ stored: [BuildRequest]) {
        let submitted = pendingBuilds.entries.map(\.value)
        for request in submitted { pendingBuilds.cancel(request.gameID) }
        for request in BuildRequest.restoring(stored) + submitted {
            enqueueBuild(request)
        }
        hasRestoredBuildQueue = true
        if !stored.isEmpty || !submitted.isEmpty { publishBuildQueue() }
        scheduleNextBuild()
    }

    func retryBuild(_ request: BuildRequest) -> Bool {
        // Only automatic resume is local-only. An explicit retry can ask to recover missing files.
        var retry = request
        retry.localSourcesOnly = false
        guard hasRestoredBuildQueue, !app.cloudLibrary.isQuitting, enqueueBuild(retry) else { return false }
        scheduleNextBuild()
        return true
    }

    @discardableResult
    private func enqueueBuild(_ request: BuildRequest) -> Bool {
        guard pendingBuilds.enqueue(request, id: request.gameID,
                                    activeID: activeBuildRequest?.gameID ?? checkingCloudBuild?.id) else { return false }
        publishBuildQueue()
        return true
    }

    func publishBuildQueue() {
        app.buildQueue = pendingBuilds.ids
        guard hasRestoredBuildQueue else { return }
        hasBuildQueueWrites = true
        buildQueueStore.save([activeBuildRequest].compactMap { $0 } + pendingBuilds.entries.map(\.value)) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let message = L10n.text("The build queue could not be saved. Builds may not resume after quitting.")
                self.app.logs.append(LogEntry(level: .error, message: message))
                self.app.alertMessage = message
            }
        }
    }

    func scheduleNextBuild() {
        guard !app.buildQueue.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in self?.startNextBuild() }
    }

    private func startNextBuild() {
        guard hasRestoredBuildQueue, !app.isBuilding, !app.isCheckingCloudBuild, !app.isScanningLibrary,
              !app.setup.isSwitchingEngine,
              !app.cloudQuitRequested, !app.cloudLibrary.isQuitting,
              !app.cloudLibrary.isChangingConnection, !app.isCleaningStorage, !app.isUpdatingApp,
              app.settingsNotice == nil,
              app.cloudLibrary.archive == nil || app.cloudLibrary.hasRestoredQueue else { return }
        while !app.isBuilding && !app.isCheckingCloudBuild {
            var target: PortedGame?
            guard let first = pendingBuilds.entries.first?.value,
                  let entry = pendingBuilds.takeNext({ id in
                guard let game = app.libraryGames.first(where: { $0.id == id }) else { return .skip }
                guard !buildTitleBusy(game) else { return .wait }
                let sourcesAvailable = GameResourceState.sourcesAvailable(for: game)
                guard first.localSourcesOnly ? first.canResumeAutomatically(game)
                    : (sourcesAvailable || app.canCheckCloudSources(for: game)) else {
                    return .skip
                }
                if sourcesAvailable && app.setup.environmentStatus == nil && app.setup.isNxnativeValid {
                    if !app.setup.isCheckingEnvironment { app.setup.refreshCompatibility() }
                    return .wait
                }
                target = game
                return .start
            }) else { return }
            guard let target else {
                let reason = L10n.text("Game, app or source files not found.")
                logSkippedBuild(entry.value.name, reason: reason)
                app.recordActivity(entry.value.id, job: .build(entry.value), name: entry.value.name, outcome: .failed(reason))
                publishBuildQueue()
                continue
            }
            startBuildImmediately(for: target, request: entry.value, onStarted: nil, queued: true)
        }
    }

    func logSkippedBuild(_ name: String, reason: String) {
        app.logs.append(LogEntry(level: .warning, message: L10n.format("Skipped build for %@: %@", [name, reason])))
    }

    private func buildTitleBusy(_ game: PortedGame) -> Bool {
        app.appIcon.appIconsInFlight.contains(game.id)
            || RunningGameMonitor.runningApplication(for: game) != nil
            || app.cloudLibrary.conflicts(with: buildScope(for: game))
            || app.savesAreBusy(for: game)
    }

    private func startBuildImmediately(for game: PortedGame, request: BuildRequest, onStarted: (() -> Void)?,
                                       queued: Bool) {
        activeBuildRequest = request
        publishBuildQueue()
        if let archive = app.cloudLibrary.archive {
            requestCloudBuild(for: game, archive: archive, extraArguments: request.arguments, onStarted: onStarted,
                              withoutCache: request.withoutCache, queuedName: queued ? request.name : nil,
                              request: request, canStart: queued ? { [weak self] target in
                    guard let self else { return false }
                    guard !self.buildTitleBusy(target) else {
                        self.activeBuildRequest = nil
                        self.pendingBuilds.retryFirst((request.gameID, request))
                        self.publishBuildQueue()
                        return false
                    }
                    return true
                } : nil)
            return
        }
        do {
            try beginBuild(for: game, extraArguments: request.arguments, withoutCache: request.withoutCache)
            onStarted?()
        } catch {
            finishActivityBuild(.failed(error.localizedDescription))
            if queued { logSkippedBuild(request.name, reason: error.localizedDescription) }
            else { presentBuildError(error) }
        }
    }

    func finishActivityBuild(_ outcome: ActivityHistory.Outcome) {
        guard let request = activeBuildRequest, !app.cloudLibrary.isQuitting else { return }
        app.recordActivity(request.id, job: .build(request), name: request.name, outcome: outcome)
        activeBuildRequest = nil
        publishBuildQueue()
    }

    func requestCloudBuild(for game: PortedGame, archive: CloudGameArchive, extraArguments: [String],
                           onStarted: (() -> Void)?, withoutCache: Bool = false,
                           queuedName: String? = nil, request: BuildRequest? = nil,
                           canStart: ((PortedGame) -> Bool)? = nil,
                           afterSourcesDownloaded: (() -> Void)? = nil) {
        guard !app.isCheckingCloudBuild else { return }
        let target = app.libraryGames.first(where: { $0.id == game.id }) ?? game
        do { try checkBuildIdle(for: target) }
        catch {
            if request != nil { finishActivityBuild(.failed(error.localizedDescription)) }
            if let queuedName { logSkippedBuild(queuedName, reason: error.localizedDescription) }
            else { presentBuildError(error) }
            return
        }
        checkingCloudBuild = (target.id, buildScope(for: target))
        app.isCheckingCloudBuild = true
        cloudBuildCheckTask = Task { @MainActor in
            guard !Task.isCancelled else {
                if request != nil { finishActivityBuild(.cancelled) }
                finishCloudBuildCheck()
                return
            }
            if let afterSourcesDownloaded, GameResourceState.sourcesAvailable(for: target) {
                finishCloudBuildCheck()
                afterSourcesDownloaded()
                return
            }
            defer {
                if request?.id == activeBuildRequest?.id, request != nil, !app.isBuilding {
                    finishActivityBuild(Task.isCancelled ? .cancelled : .failed(L10n.text("Build needs your attention.")))
                }
                finishCloudBuildCheck()
            }
            await app.startCloudBuild(for: game, archive: archive, extraArguments: extraArguments,
                                      onStarted: onStarted, withoutCache: withoutCache,
                                      queuedName: queuedName, request: request, canStart: canStart,
                                      afterSourcesDownloaded: afterSourcesDownloaded)
        }
    }

    private func finishCloudBuildCheck() {
        cloudBuildCheckTask = nil
        checkingCloudBuild = nil
        app.isCheckingCloudBuild = false
        scheduleNextBuild()
    }

    @discardableResult
    func cancelCloudBuildCheck(for id: UUID) -> Bool {
        guard checkingCloudBuild?.id == id, let cloudBuildCheckTask else { return false }
        cloudBuildCheckTask.cancel()
        return true
    }

    private func checkBuildIdle(for game: PortedGame) throws {
        guard !app.isBuilding else { throw NXLibraryError.buildAlreadyRunning }
        guard !app.setup.isSwitchingEngine else {
            throw NXLibraryError.environmentBlocked(L10n.text("Wait for the engine change to finish."))
        }
        guard RunningGameMonitor.runningApplication(for: game) == nil else { throw CloudArchiveError.busy }
        guard !app.cloudLibrary.isChangingConnection,
              !app.cloudLibrary.isWorking || !app.cloudLibrary.conflicts(with: buildScope(for: game)) else {
            throw CloudArchiveError.busy
        }
        guard !app.isCleaningStorage else { throw NXLibraryError.environmentBlocked(L10n.text("wait for storage cleanup to finish")) }
        guard !app.isUpdatingApp else { throw NXLibraryError.environmentBlocked(L10n.text("wait for the app update to finish")) }
        guard !app.appIcon.appIconsInFlight.contains(game.id) else {
            throw NXLibraryError.environmentBlocked(L10n.text("wait for the app icon update to finish"))
        }
    }

    func beginBuild(for game: PortedGame, extraArguments: [String] = [], verifiedCache: URL? = nil,
                    withoutCache: Bool = false, releaseCloudBuild: (() async -> Void)? = nil) throws {
        var target = app.libraryGames.first(where: { $0.id == game.id }) ?? game
        try checkBuildIdle(for: target)
        if let request = activeBuildRequest, request.localSourcesOnly,
           !request.canResumeAutomatically(target) {
            throw NXLibraryError.missingSources
        }
        guard let titleId = target.titleId,
              UInt64(titleId, radix: 16) != nil else {
            throw NXLibraryError.missingTitleId
        }
        guard GameResourceState.sourcesAvailable(for: target) else {
            throw NXLibraryError.missingSources
        }
        // Snapshot the destination before any build work. Changing folders later cannot redirect this build.
        let finalApp = finalAppURL(for: target)
        let expectedDestination = BuildOutputInstaller.expectedDestination(at: finalApp)
        let reservedScope = buildScope(for: target)
        if let problem = GameAppDestination.folderProblem(at: finalApp.deletingLastPathComponent()) {
            throw NXLibraryError.environmentBlocked(problem)
        }
        let requiresKeys = SourceSelection.requiresKeys(target.sources)
        guard supportsSources(target.sources) else {
            throw NXLibraryError.environmentBlocked(L10n.text("These sources need an engine with extracted-folder or multi-title support."))
        }
        guard SourceSelection.matchesNUPProgram(target.sources, titleID: titleId) else {
            throw NXLibraryError.environmentBlocked(L10n.text("The selected NUP program no longer matches this game. Choose the source again."))
        }
        if !requiresKeys && !app.setup.engineSourceCapabilities.extractedFolders {
            throw NXLibraryError.environmentBlocked(L10n.text("This engine does not support extracted folders."))
        }
        guard app.setup.isNxnativeValid else { throw NXLibraryError.engineMissing }
        guard let environmentStatus = app.setup.environmentStatus else {
            throw NXLibraryError.environmentBlocked(L10n.text("the environment check is still running"))
        }
        guard environmentStatus.canBuild else {
            throw NXLibraryError.environmentBlocked(environmentStatus.issues.joined(separator: "; "))
        }

        // Re-check at build time: the engine tree, Metal compiler or CLI may
        // have changed since the last Settings/launch check.
        let (workshop, report) = app.setup.engineAdapter(developerDir: app.setup.resolvedDeveloperDir(),
                                                        keys: requiresKeys ? app.setup.keysDirectory : nil)
            .compatibility(toolchain: app.setup.engineToolchain)
        if requiresKeys {
            switch workshop.localKeys {
            case .required: throw NXLibraryError.missingKeys
            case .invalid(let issue): throw NXLibraryError.invalidKeys(issue)
            case .available: break
            }
            // Verify against the actual sources before extraction starts.
            let keyOutcome = KeyCheck.run(keysURL: app.setup.managedKeysURL,
                                          files: KeyCheck.parts(target.sources.map { ($0.kind, $0.url) }))
            if keyOutcome.blocks, let reason = PortingFailureReason.from(keyOutcome) {
                throw NXLibraryError.keyCheck(reason, game: target.name)
            }
        }
        app.setup.compatibilityReport = report
        if !report.ok && !app.setup.allowUntestedToolchain {
            let reason = report.checks.filter { $0.status == .block }
                .map { "\($0.title): \($0.detail)" }.joined(separator: "; ")
            throw NXLibraryError.incompatibleToolchain(reason)
        }
        app.setup.environmentCheckGeneration = UUID()
        app.setup.isCheckingEnvironment = false
        let certified = report.ok && !app.setup.allowUntestedToolchain && !app.setup.usesNewestEngine
        activeBuildToolchain = ToolchainInfo(engineCommit: workshop.versions.expected,
            metalVersion: environmentStatus.metalVersion, xcodeVersion: environmentStatus.xcodeVersion,
            verified: certified,
            note: certified ? "Certified toolchain"
                : app.setup.usesNewestEngine ? "Newest engine, not yet tested by Arcane"
                : "Untested toolchain (explicit override)")

        let merged = try app.catalogRepository.mergeNXNative(scanned: [target], enableSource: true)
        app.applyCatalog(merged)
        guard let stored = merged.nxnativeGames.first(where: { $0.titleId == titleId }) else {
            throw NXLibraryError.missingSources
        }
        target = stored
        buildPreviousStatus = target.status

        let workspace: Workspace
        if !withoutCache, verifiedCache == nil, let path = target.buildCachePath {
            _ = try LocalBuildCache.readChain(ofCache: URL(fileURLWithPath: path))
        }
        let existingDirectory = target.workspacePath.map { URL(fileURLWithPath: $0) }
        let existingNames = Set(existingDirectory.flatMap {
            (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? []
        } ?? [])
        let expectedNames = target.sources.map { $0.url.lastPathComponent }
        let existingLinksOK = existingDirectory.map { directory in
            FileManager.default.fileExists(atPath: directory.path)
                && app.workspaceManager.brokenLinks(in: directory).isEmpty
                && expectedNames.allSatisfy { existingNames.contains($0) }
        } ?? false
        // On the app's drive when it can hold builds: the Mac's disk needs no room, the install is a rename.
        let scratch = BuildScratch.choose(core: app.core, appFolder: finalApp.deletingLastPathComponent(),
                                          existingWorkspace: existingDirectory)
        let managed = existingDirectory.map { BuildScratch.isManaged($0, core: app.core) } ?? false
        if let directory = existingDirectory, existingLinksOK, !managed,
           target.sources.allSatisfy({ source in
               source.layout == .package && (!app.hasCloudLibrary || !source.isSymlink) && source.url.resolvingSymlinksInPath()
                   == directory.appendingPathComponent(source.url.lastPathComponent).resolvingSymlinksInPath()
           }) {
            let cache = target.buildCachePath.map(URL.init(fileURLWithPath:))
                ?? directory.appendingPathComponent("\(titleId)_build")
            if !withoutCache && verifiedCache == nil {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            }
            workspace = Workspace(directory: directory, buildCache: cache, links: [])
        } else {
            let detected = try detectedGame(from: target)
            workspace = try WorkspaceManager(root: scratch.workspaces).makeWorkspace(
                for: detected, mode: .staged, createCache: verifiedCache == nil && !withoutCache)
            if target.buildCachePath == nil {
                target.workspacePath = workspace.directory.path
                target.buildCachePath = workspace.buildCache.path
            }
        }

        do {
            app.applyCatalog(try app.catalogRepository.updateNXNative(id: target.id) {
                $0.workspacePath = target.workspacePath
                $0.buildCachePath = target.buildCachePath
            })
        } catch { app.reportCatalogFailure(error); throw error }

        let requiredDisk = SourceSelection.uniqueSize(target.sources) * 2 + 10_000_000_000
        var measured = Set<UInt64>()
        for volume in [workspace.directory, verifiedCache ?? workspace.buildCache, scratch.temp, finalApp.deletingLastPathComponent()] {
            if let device = BuildScratch.Volume.of(volume)?.device, !measured.insert(device).inserted { continue }
            if let free = freeBytes(at: volume), free < requiredDisk {
                let freeText = AppViewModel.formatBytes(free)
                let requiredText = AppViewModel.formatBytes(requiredDisk)
                let why = scratch.appDriveUnsupported
                    ? L10n.text(" The Game apps folder's drive can't hold build files (it needs APFS or Mac OS Extended), so the build uses this Mac's disk.")
                    : ""
                throw NXLibraryError.environmentBlocked(
                    L10n.format("Not enough free space at %@: %@ available, %@ needed.%@", [String(describing: volume.path), String(describing: freeText), String(describing: requiredText), String(describing: why)]))
            }
        }

        let repo = URL(fileURLWithPath: app.setup.nxnativePath)
        let toolchain = app.setup.engineToolchain
        guard FileManager.default.isExecutableFile(atPath: toolchain.python.path) else {
            throw NXLibraryError.environmentBlocked(toolchain.isBundled
                ? L10n.text("the bundled Python is missing; reinstall Arcane")
                : L10n.text("the nxnative venv Python is missing"))
        }

        let tempRoot = scratch.temp.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        var started = false
        defer { if !started { try? FileManager.default.removeItem(at: tempRoot) } }
        let tempApp = tempRoot.appendingPathComponent(finalApp.lastPathComponent)
        let logURL = app.core.appendingPathComponent("Logs").appendingPathComponent("\(titleId).log")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logURL.path) {
            try FileManager.default.trashItem(at: logURL, resultingItemURL: nil)
        }

        let capabilities = app.setup.engineSourceCapabilities
        let codeMods: URL?
        do {
            codeMods = try BuildService.stageCodeMods(app.modStore(for: target), in: tempRoot,
                                                     engineSupportsMods: capabilities.codeMods)
        } catch let error as ModStoreError {
            throw NXLibraryError.environmentBlocked(AppViewModel.modMessage(error))
        }
        let stagedCodeMods = try codeMods.map { try FileManager.default.contentsOfDirectory(atPath: $0.path).sorted() }
        let movingCache = verifiedCache == nil && !withoutCache && target.buildCachePath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path != workspace.buildCache.standardizedFileURL.path
        } == true
        let workDir = withoutCache || movingCache ? tempRoot.appendingPathComponent("\(titleId)_build") : verifiedCache
        // A successful build without the old cache leaves its work folder as the game's cache.
        let cacheDestination = movingCache ? workspace.buildCache
            : withoutCache ? target.buildCachePath.map(URL.init(fileURLWithPath:)) ?? workspace.buildCache : nil
        // With --work-dir alone nxnative can still copy a profile from the old cache.
        let freshProfile = withoutCache || movingCache ? workDir.map { ["--profile-out", $0.appendingPathComponent("profile").path] } ?? [] : []
        let command = BuildCommandBuilder.make(
            repo: repo,
            toolchain: toolchain,
            workspace: workspace.directory,
            workDir: workDir,
            keys: requiresKeys ? app.setup.managedKeysURL : nil,
            output: tempApp,
            developerDir: app.setup.resolvedDeveloperDir(),
            appName: target.name,
            bundleId: target.bundleId ?? "org.nxnative.\(titleId.lowercased())",
            language: app.runtimeSettings.loadRuntimeConfig(for: target).languageForBuild,
            titleId: capabilities.titleSelection ? titleId : nil,
            programIndex: SourceSelection.programIndex(for: target.sources, titleID: titleId,
                                                       nupPrograms: capabilities.nupPrograms),
            packageVersion: capabilities.titleSelection
                ? SourceSelection.packageVersion(for: target.sources, stagedSelection: !workspace.links.isEmpty) : nil,
            allowUntestedToolchain: app.setup.allowUntestedToolchain,
            nextendoClientID: app.settingsStore?.settings.nextendoClientID ?? NextendoLaunch.buildClientID,
            codeModsFolder: codeMods,
            extraArguments: extraArguments + freshProfile
        )
        lastPortingCommand = [command.executable.path] + command.arguments
        let nextendoRequested = command.environment[NextendoLaunch.clientIDKey] != nil

        stopStageElapsedTimer()
        buildStartedAt = Date()
        buildTempDirectory = tempRoot
        app.buildLogURL = logURL
        currentBuildCacheURL = workDir ?? workspace.buildCache
        activeCloudBuildScope = reservedScope
        isPollingPipelineArchive = false
        self.buildWizardStep = 3
        app.currentBuildGameID = target.id
        app.lastBuildGameID = target.id
        app.isBuilding = true
        // The request belongs to an accepted porting, never to startup or Steam-only use.
        NotificationService.shared.requestAuthorization()
        self.isCancellingBuild = false
        self.isInstallingBuild = false
        self.buildState = .running
        self.buildError = nil
        self.portingFailureReason = nil
        app.lastError = nil
        self.buildSuccessPath = nil
        self.buildHeldGameID = nil
        self.progressFraction = 0
        self.currentStageName = "Preparing build"
        self.currentStepName = ""
        self.stageIndex = 0
        self.totalStages = 0
        self.etaSeconds = nil
        self.buildStages.removeAll()
        app.portingProgress = PortingProgress()
        app.frontGameID = target.id
        app.logs.append(LogEntry(level: .info,
                             message: L10n.format("Build started for %@ (%@).", [String(describing: target.name), String(describing: titleId)])))
        app.logs.append(LogEntry(level: .info,
                             message: L10n.format("Workspace: %@", [String(describing: workspace.directory.path)])))
        app.logs.append(LogEntry(
            level: .info,
            message: report.ok
                ? L10n.text("Toolchain gate: certified.")
                : L10n.text("Toolchain gate: overridden; this build will be recorded as untested.")
        ))

        let service = BuildService()
        buildService = service
        started = true
        service.start(
            command: command,
            logURL: logURL,
            tempApp: tempApp,
            finalApp: finalApp,
            expectedDestination: expectedDestination,
            // Replacing the app under its running game can crash it: the new app waits for the game to quit.
            holdInstall: { [target] in RunningGameMonitor.runningApplication(for: target) != nil },
            acquireInstall: { [weak self, target] in try self?.app.requireSaveInstallLease(for: target) },
            onInstalling: { [weak self, weak service] in
                DispatchQueue.main.async {
                    guard let self, let service, self.buildService === service else { return }
                    self.stopStageElapsedTimer()
                    self.isInstallingBuild = true
                }
            },
            eventHandler: { [weak self, weak service] event in
                DispatchQueue.main.async {
                    guard let service, self?.buildService === service else { return }
                    self?.handleBuildEvent(event)
                }
            },
            completion: { [weak self, weak service] result in
                Task { @MainActor in
                    guard let self, let service, self.buildService === service else {
                        if let releaseCloudBuild { await releaseCloudBuild() }
                        return
                    }
                    await self.finishBuild(result, gameID: target.id,
                                      finalApp: finalApp, tempDir: tempRoot,
                                      adoptingCache: workDir.flatMap { work in cacheDestination.map { (work, $0) } },
                                      relocatedCache: movingCache,
                                      nextendoRequested: nextendoRequested, stagedCodeMods: stagedCodeMods,
                                      releaseCloudBuild: releaseCloudBuild)
                }
            }
        )
    }

    func cancelBuild() {
        guard app.isBuilding, buildService?.cancel() == true else { return }
        stopStageElapsedTimer()
        self.isCancellingBuild = true
        self.currentStageName = "Cancelling build..."
        app.logs.append(LogEntry(level: .warning, message: L10n.text("Cancelling build...")))
    }

    func openOutputInFinder() {
        guard let path = self.buildSuccessPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openBuildLog() {
        guard let url = app.buildLogURL else {
            app.lastError = "No build log is available yet."
            app.logs.append(LogEntry(level: .warning, message: app.lastError!))
            return
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        }
    }

    func retryLastBuild() {
        guard let id = app.lastBuildGameID,
              let game = app.libraryGames.first(where: { $0.id == id }) else {
            app.lastError = "The last built game is no longer in the library."
            app.logs.append(LogEntry(level: .error, message: app.lastError!))
            return
        }
        if app.canRetryReadyInstall {
            app.installPendingBuilds(only: id, automatic: false)
            return
        }
        startBuild(for: game)
    }
}
