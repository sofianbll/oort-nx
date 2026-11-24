import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// Launching a Switch game: the launch screen, its checks and watching the launch.
extension AppViewModel {
    @MainActor func playNXNative(_ target: PlayTarget, profile: PlayProfile, observe: PlayObserver?,
                                 acceptsLocalFallback: Bool = false) -> PlayResult {
        // One launch at a time: the launch screen covers the library, and input reaching it changes nothing.
        guard !profile.blocksPlay else { return .refused(.profileLocked) }
        guard launchingGameId == nil, launchOverlay == nil else { return .refused(.launchInProgress) }
        guard target.installationAvailability != .unavailable(.sourceDisabled) else { return .refused(.sourceDisabled) }
        guard let requested = target.game.nxnativeGame else { return .refused(.invalidGame) }
        // Resume the same request after preparation, or report its refusal without trying to launch.
        @MainActor func resume(acceptsLocalFallback: Bool) -> (PlayRefusal?) -> Void {
            { [weak self] refusal in
                if let refusal {
                    observe?(.result(.refused(refusal)))
                    return
                }
                guard let self else { return }
                guard self.playProfile == profile else {
                    observe?(.result(.refused(.profileLocked)))
                    return
                }
                guard let current = self.libraryGames.first(where: { $0.id == requested.id }) else {
                    observe?(.result(.refused(.missingTarget)))
                    return
                }
                let result = self.playNXNative(self.playTarget(for: .init(nxnative: current)), profile: profile,
                                               observe: observe, acceptsLocalFallback: acceptsLocalFallback)
                if result != .accepted(.pending) { observe?(.result(result)) }
            }
        }
        if let title = requested.titleId, cloudLibrary.appInstall?.title == title.uppercased() {
            guard cloudLibrary.playAfterAppInstall == nil else { return .refused(.launchInProgress) }
            cloudLibrary.playAfterAppInstall = resume(acceptsLocalFallback: acceptsLocalFallback)
            return .accepted(.pending)
        }
        // A running game is brought forward, never started a second time.
        if let running = RunningGameMonitor.runningApplication(for: requested) {
            let known = gameSaveLaunches[requested.id].flatMap {
                $0.pid == running.processIdentifier && $0.date == running.launchDate ? $0 : nil
            }
            guard known?.profile == secondarySaveProfile else {
                alertMessage = L10n.text("Close the game before managing its saves. Keep it closed until this operation finishes.")
                return .refused(.savesUnavailable)
            }
            if let runningGameMonitor { Task { @MainActor in runningGameMonitor.resume(requested) } }
            else { RunningGameMonitor.activate(running) }
            return .accepted(.gameOpened)
        }
        guard savesPermitPlay(requested) else { return .refused(.savesUnavailable) }
        // Installing a waiting build can itself start an icon update: check after installation too.
        let game = installingPendingBuild(of: requested)
        // The app is being signed again with a new icon: starting it now could read a half-written bundle.
        guard !appIcon.appIconsInFlight.contains(game.id) else {
            appIcon.waitForAppIconBeforeLaunching(game)
            return .accepted(.pending)
        }
        if !FileManager.default.fileExists(atPath: game.url.path),
           game.isPlayableLocally || game.status == .appMissing {
            let reason = GameUnavailableReason.appMissing
            lastError = reason.title + ". " + reason.detail
            alertMessage = lastError
            updateStoredStatus(.appMissing, for: game)
            SoundEffectService.shared.play(.error)
            return .refused(.installationMissing)
        }
        guard game.isPlayableLocally else {
            let reason = GameResourceState.unavailableReason(for: game)
            let message = reason.map { $0.title + ". " + $0.detail }
                ?? L10n.text("This game is not built yet. Build it first.")
            lastError = message
            alertMessage = message
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: message))
            return .refused(.installationMissing)
        }
        guard FileManager.default.fileExists(atPath: game.url.path) else {
            let reason = GameUnavailableReason.appMissing
            lastError = reason.title + ". " + reason.detail
            alertMessage = lastError
            updateStoredStatus(.appMissing, for: game)
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return .refused(.installationMissing)
        }
        guard let titleId = game.titleId, !titleId.isEmpty else {
            lastError = NXLibraryError.missingTitleId.localizedDescription
            alertMessage = lastError
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return .refused(.invalidGame)
        }

        let gameSettings = runtimeSettings.gameSettings(for: game)
        let appSettings = settingsStore?.settings ?? AppSettings()
        let isGuest = profile.isGuest
        let multiplayer = isGuest ? nil : gameSettings?.multiplayerLaunch(settings: appSettings, adapters: .current())
        if multiplayer?.warning != nil && !acceptsLocalFallback {
            let playLocally = resume(acceptsLocalFallback: true)
            showMultiplayerVPNFallback { playLocally(nil) }
            return .refused(.confirmationRequired)
        }
        guard let saveLaunchToken = saveGate.begin(titleID: titleId) else {
            alertMessage = SaveFailure.busy.localizedDescription
            return .refused(.savesUnavailable)
        }
        let saveEnvironment: [String: String]
        do {
            if let profileID = secondarySaveProfile {
                saveEnvironment = try profileSaveLocation(for: game, profileID: profileID)
                    .profileLaunchEnvironment(shared: legacySaveLocation(for: game))
            } else { saveEnvironment = [:] }
        } catch {
            saveGate.end(titleID: titleId, token: saveLaunchToken)
            alertMessage = error.localizedDescription
            return .refused(.savesUnavailable)
        }
        var overlayData = gameOverlayData()
        if let profile = overlayData.snapshot.profile,
           let pack = localAchievementPack(for: game, profile: profile.id),
           let progress = localAchievementStore.progress(for: pack, profile: profile.id) {
            overlayData.snapshot.achievements = pack.summary(progress, language: L10n.context.language)
        }
        launchingGameId = game.id
        playSessionStore?.expectStart(gameID: game.id)
        let setting = gameSettings.flatMap { NextendoLaunch.networkSetting(in: $0.settings) }
        let multiplayerEnvironment = (isGuest ? NextendoLaunch.guestEnvironment() : multiplayer?.environment ?? [:])
            .merging(saveEnvironment) { _, save in save }
        let mode = multiplayerEnvironment[NextendoLaunch.networkKey] ?? gameSettings?.effectiveLaunchValue(NextendoLaunch.networkKey)
        if NextendoLaunch.requiresSignIn(setting: setting, mode: mode) {
            let scoped = !usesSharedNextendo
            let tokenStore = NextendoLaunch.tokenStore(profileID: profile.id, originalID: localProfiles?.originalID)
            let profile = localProfiles?.active
            let clientID = settingsStore?.settings.nextendoClientID ?? NextendoLaunch.buildClientID
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let presence = try await Task.detached(priority: .userInitiated) {
                        try NextendoLaunch.presenceEnvironment(profile: profile, in: game.url)
                    }.value
                    // Validate access under the engine's lock, including credentials written by other frontends.
                    if scoped {
                        let supported = await Task.detached(priority: .userInitiated) {
                            NextendoLaunch.supportsProfileLogin(in: game.url)
                        }.value
                        guard supported else { throw NextendoError.profileHost }
                    }
                    var checkedOverlay = overlayData
                    let environment = try await NextendoLaunch.environment(setting: setting, mode: mode, clientID: clientID,
                                                                           tokenStore: tokenStore) { client in
                        guard let username = try await NextendoOAuth(store: tokenStore).accountName(clientID: client) else { return false }
                        if checkedOverlay.snapshot.nextendoName != username {
                            checkedOverlay.snapshot.nextendoName = username
                            checkedOverlay.snapshot.presence = nil
                            checkedOverlay.snapshot.friends = nil
                        }
                        return true
                    }
                    let result = self.startGame(game, titleId: titleId, token: saveLaunchToken, gameSettings: gameSettings,
                                                overlayData: checkedOverlay,
                                                environment: multiplayerEnvironment.merging(environment) { _, online in online }
                                                    .merging(presence) { _, policy in policy }, observe: observe)
                    if case .refused = result { observe?(.result(result)) }
                } catch {
                    self.playSessionStore?.abandonStart(gameID: game.id)
                    self.saveGate.end(titleID: titleId, token: saveLaunchToken)
                    self.launchingGameId = nil
                    let problem = error as? NextendoError ?? .service
                    let hint = problem.localizedDescription
                    SoundEffectService.shared.play(.error)
                    if [.clientID, .signedOut, .expired, .authorization].contains(problem) {
                        self.showSettingsNotice(title: "Nextendo", message: hint, actionTitle: "Nextendo settings") { [weak self] in
                            guard let self else { return }
                            self.gameForSettingsSheet = nil
                            self.router?.openSettings(.profileNextendo)
                        }
                    } else {
                        self.showSettingsNotice(title: "Nextendo", message: hint)
                    }
                    observe?(.result(.refused(.preparationFailed)))
                }
            }
            return .accepted(.pending)
        }
        return startGame(game, titleId: titleId, token: saveLaunchToken, gameSettings: gameSettings,
                         overlayData: overlayData, environment: multiplayerEnvironment, observe: observe)
    }

    func showMultiplayerVPNFallback(_ proceed: @escaping () -> Void) {
        showSettingsNotice(title: "VPN unavailable",
                           message: L10n.text("This game can start on your local network instead. Players on the VPN will not be reachable."),
                           actionTitle: "Play on the local network", cancelTitle: "Cancel", primaryFirst: true, retry: proceed)
    }

    @MainActor private func startGame(_ game: PortedGame, titleId: String, token saveLaunchToken: UUID,
                                      gameSettings: NXNativeGameSettings?,
                                      overlayData: (snapshot: GameOverlaySnapshot, total: String?), environment: [String: String],
                                      observe: PlayObserver?) -> PlayResult {
        launchOverlay = LaunchOverlayState(game: .nxnative(game))
        SoundEffectService.shared.play(.launch)

        // A saved-choices build reads the game's own store; only an older build takes env.txt and the environment.
        let config = GameRuntimeConfig.load(for: game)
        do {
            if let gameSettings {
                try gameSettings.migrate()
            } else {
                try launchService.writeEnvironment(settings: config, titleId: titleId)
            }
        } catch {
            playSessionStore?.abandonStart(gameID: game.id)
            saveGate.end(titleID: titleId, token: saveLaunchToken)
            launchingGameId = nil
            launchOverlay = nil
            lastError = error.localizedDescription
            alertMessage = lastError
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error,
                                 message: L10n.format("Could not write the runtime environment: %@", [String(describing: error.localizedDescription)])))
            return .refused(.preparationFailed)
        }

        if environment["DM_SAVE"] == nil, let choice = settingsStore?.settings.cloudSaves, let domain = game.effectiveBundleId {
            do {
                try cloudSavesPreferences.applyBeforeLaunch(choice, domain: domain)
            } catch {
                logs.append(LogEntry(level: .warning, message: L10n.format("Cloud saves: %@", [String(describing: error.localizedDescription)])))
                showSettingsNotice(title: L10n.text("Cloud unavailable"),
                                   message: L10n.text("Cloud sync could not be updated for this launch. Check Games → Cloud saves."))
            }
        }

        // Play can come straight from the row. Reconcile removed mod folders before the game reads its overlay.
        let store = modStore(for: game)
        if let store { _ = performModChange { try store.sync() } }

        Task { @MainActor in
            let appURL = game.url
            let supported = await InstalledEngineCapabilities.shared.supportsHomeMenu(in: appURL, engineFolder: setup.nxnativePath)
            let homeMenu = HomeMenu.environment(supported: supported, launcherBundleID: Bundle.main.bundleIdentifier)
            let online = environment[NextendoLaunch.clientIDKey] != nil
            let codeMods = await Task.detached(priority: .userInitiated) {
                store?.codeModsLaunchEnvironment(app: appURL, build: game.lastBuild, online: online) ?? [:]
            }.value
            let overlay = await InstalledEngineCapabilities.shared.gameOverlay(in: appURL)
            var cover: URL?
            if overlay.supportsCover {
                let key = personalizations.nxnativeKey(for: game)
                cover = ArtworkPicks.shared.url(titleID: key, slot: .cover)
                    ?? ArtworkStore().cachedURL(titleID: key, kind: .boxart)
            }
            var overrides = (gameSettings == nil ? config.toEnvironmentDict() : [:])
                .merging(environment) { _, prepared in prepared }
                .merging(homeMenu) { _, launcher in launcher }
                .merging(codeMods) { _, mods in mods }
                .merging(overlay.environment(palette: ThemeStore.shared.palette,
                                             playtime: playSessionStore?.totalDuration(for: game.id),
                                             cover: cover, profilePlaytime: overlayData.total)) { _, session in session }
            if await InstalledEngineCapabilities.shared.supportsGameDisplay(in: appURL),
               GameDisplay.fileOverride(for: game) == nil {
                let settings = settingsStore?.settings
                let choice = settings?.gameDisplayOverrides[titleId.uppercased()] ?? settings?.gameDisplay ?? ""
                let connected = NSScreen.screens.compactMap(GameDisplay.init(screen:))
                let arcane = (LibraryWindow.mainWindow?.screen ?? NSScreen.main).flatMap(GameDisplay.init(screen:))?.id
                overrides[GameDisplay.key] = GameDisplay.resolve(choice, connected: connected, arcane: arcane).id?.uuidString
            } else {
                overrides[GameDisplay.key] = nil
            }
            openGame(game, titleId: titleId, token: saveLaunchToken, environment: overrides,
                     overlay: overlay, snapshot: overlayData.snapshot, observe: observe)
        }
        return .accepted(.pending)
    }

    @MainActor private func gameOverlayData() -> (snapshot: GameOverlaySnapshot, total: String?) {
        var snapshot = GameOverlaySnapshot()
        guard let profile = localProfiles?.active, localProfiles?.failed == false else { return (snapshot, nil) }
        snapshot.profile = profile
        snapshot.color = SelenePaletteCatalog.resolve(profile.look.theme, in: ThemeStore.shared.palettes).glyph
        if let nextendo = profileNextendo, !nextendo.isSigningOut {
            snapshot.nextendoName = nextendo.overlayUsername
            if profile.sharesPresence, nextendo.presenceShared == true { snapshot.presence = .online }
            snapshot.friends = nextendo.overlayFriends
            snapshot.friendGameTitles = nextendo.knownGameTitles
            for friend in nextendo.overlayFriends ?? [] where friend.game == nil {
                guard let id = friend.gameID?.uppercased(), snapshot.friendGameTitles[id] == nil else { continue }
                snapshot.friendGameTitles[id] = libraryGames.first(where: { $0.titleId?.uppercased() == id })?.name
            }
        }
        guard let history = playSessionStore, history.loadError == nil,
              history.profileID == (usesSharedNextendo ? nil : profile.id) else { return (snapshot, nil) }
        let sessions = history.sessions
        // shortcut: folded sessions are included in the lifetime total, but lack dates for a weekly breakdown.
        let week = Activity.summary(sessions: sessions, now: .now, calendar: .current).thisWeek
        if Int(exactly: (week / 60).rounded(.down)) != nil { snapshot.week = LibraryPresentation.duration(week) }
        let gameIDs = Set(sessions.map(\.gameID)).union(history.carried.keys).union(history.external.keys)
        let total = gameIDs.reduce(0.0) { $0 + history.totalDuration(for: $1) }
        return (snapshot, Int(exactly: (total / 60).rounded(.down)) == nil ? nil : LibraryPresentation.duration(total))
    }

    @MainActor private func openGame(_ game: PortedGame, titleId: String, token saveLaunchToken: UUID,
                                     environment: [String: String], overlay: GameOverlayLaunch, snapshot: GameOverlaySnapshot,
                                     observe: PlayObserver?) {
        let evaluate = snapshot.profile.flatMap { localAchievementExit(for: game, profile: $0.id, environment: environment) }
        let onExit: (() -> Void)? = if let observe {
            { evaluate?(); DispatchQueue.main.async { observe(.exited) } }
        } else { evaluate }
        launchService.launch(appURL: game.url, environment: environment,
                             homeButton: settingsStore?.settings.inGameHomeButton ?? .auto,
                             overlay: overlay, snapshot: snapshot,
                             onExit: onExit) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveGate.end(titleID: titleId, token: saveLaunchToken)
                if success {
                    if let running = RunningGameMonitor.runningApplication(for: game) {
                        self.gameSaveLaunches[game.id] = (running.processIdentifier, running.launchDate, snapshot.profile.flatMap {
                            $0.id == self.localProfiles?.originalID ? nil : $0.id
                        })
                    }
                    self.lastError = nil
                    self.playSessionStore?.start(for: game)
                    self.logs.append(LogEntry(level: .success, message: L10n.format("Launched game: %@", [String(describing: game.name)])))
                    self.watchLaunch(of: game, observe: observe)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if self.launchingGameId == game.id { self.launchingGameId = nil }
                    }
                    observe?(.result(.accepted(.gameOpened)))
                } else {
                    self.playSessionStore?.abandonStart(gameID: game.id)
                    let message = error ?? NXLibraryError.launchFailed(game.name).localizedDescription
                    self.launchingGameId = nil
                    self.launchOverlay = nil
                    self.lastError = message
                    self.alertMessage = message
                    SoundEffectService.shared.play(.error)
                    self.logs.append(LogEntry(level: .error, message: message))
                    observe?(.result(.refused(.openFailed)))
                }
            }
        }
    }

    func localAchievementSummary(for game: PortedGame, profile: UUID) -> AchievementSummary? {
        guard let pack = localAchievementPack(for: game, profile: profile) else { return nil }
        return pack.summary(localAchievementStore.progress(for: pack, profile: profile), language: L10n.context.language)
    }

    private func localAchievementPack(for game: PortedGame, profile: UUID) -> LocalAchievementPack? {
        guard let pack = LocalAchievementPack.linksAwakening,
              pack.matches(titleID: game.titleId, gameVersion: game.versionString),
              localProfiles?.failed == false,
              localProfiles?.profiles.contains(where: { $0.id == profile }) == true else { return nil }
        return pack
    }

    private func localAchievementExit(for game: PortedGame, profile: UUID,
                                      environment: [String: String]) -> (() -> Void)? {
        guard !AppData.profile.isDevelopment, let pack = localAchievementPack(for: game, profile: profile),
              pack.matches(titleID: game.titleId, gameVersion: BuildOutputInstaller.version(of: game.url)),
              environment["HOME"] == nil,
              let location = try? saveContext(for: game, launchProfileID: profile).location else { return nil }
        let usesLegacySave = profile == localProfiles?.originalID
        let launchedAccount = environment["DM_SAVE"]
        guard usesLegacySave ? launchedAccount == nil : location.matchesLaunchAccount(launchedAccount) else { return nil }
        return { [weak self] in
            // LaunchService can observe an instant exit before its successful open callback releases the lease.
            DispatchQueue.main.async { [weak self] in
                self?.evaluateLocalAchievements(for: game, pack: pack, profile: profile, location: location)
            }
        }
    }

    private func evaluateLocalAchievements(for game: PortedGame, pack: LocalAchievementPack,
                                           profile: UUID, location: SaveLocation) {
        guard localAchievementPack(for: game, profile: profile) != nil,
              let token = saveGate.begin(titleID: location.titleID) else { return }
        let date = Date.now
        saveQueue.async { [weak self, saveGate] in
            let counts: [LocalAchievementPack.Metric: Int]?
            if !SaveTransaction.needsRecovery(location: location),
               RunningGameMonitor.runningApplication(for: game) == nil {
                switch pack.reader {
                case .linksAwakening: counts = LinksAwakeningAchievements.readPrimary(from: location)
                }
            } else {
                counts = nil
            }
            DispatchQueue.main.async {
                defer { saveGate.end(titleID: location.titleID, token: token) }
                guard let self, let counts, self.localAchievementPack(for: game, profile: profile) != nil else { return }
                let ids = self.localAchievementStore.record(counts, in: pack, profile: profile, at: date)
                self.localAchievementRevision &+= 1
                let names = pack.summary(self.localAchievementStore.progress(for: pack, profile: profile),
                                         language: L10n.context.language).rows(.unlocked)
                    .filter { ids.contains($0.id) }.map(\.name)
                if !names.isEmpty { self.localAchievementUnlocks.send((profile, names)) }
            }
        }
    }

    /// Marks the launch screen ready once the game shows a window, or after the probe times out.
    @MainActor private func watchLaunch(of game: PortedGame, observe: PlayObserver?) {
        launchProbeTask?.cancel()
        guard let bundleID = game.effectiveBundleId else {
            launchOverlay?.isReady = true
            return
        }
        launchProbeTask = Task { [weak self] in
            let visible = await LaunchReadinessProbe().waitUntilVisible(bundleID: bundleID)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.launchOverlay?.game.id == game.id else { return }
                if visible {
                    SoundEffectService.shared.play(.gameReady)
                } else {
                    self.logs.append(LogEntry(level: .warning,
                                              message: L10n.format("%@ showed no window within 60 s; launch screen closed.", [String(describing: game.name)])))
                }
                self.launchOverlay?.isReady = true
                if visible { observe?(.ready) }
            }
        }
    }

    /// Called by the launch screen after its fade out.
    func dismissLaunchOverlay() {
        launchProbeTask?.cancel()
        launchProbeTask = nil
        launchOverlay = nil
    }
}
