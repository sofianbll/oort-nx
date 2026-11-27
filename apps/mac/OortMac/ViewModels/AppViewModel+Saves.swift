import AppKit
import OortLibrary
import NxnativeAdapter

extension AppViewModel {
    func showAllSaveBackups() {
        guard (try? requireReadableSaveProfile()) != nil else {
            showSettingsNotice(title: L10n.text("Folder unavailable"), message: SaveFailure.profilesUnavailable.localizedDescription)
            return
        }
        do {
            try FileManager.default.createDirectory(at: saveBackupRoot, withIntermediateDirectories: true)
            NSWorkspace.shared.open(saveBackupRoot)
        } catch {
            showSettingsNotice(title: L10n.text("Folder unavailable"), message: L10n.text("The backup folder could not be opened."))
        }
    }

    var saveBackupRoot: URL {
        let base = AppData.supportRoot.appendingPathComponent("SaveBackups")
        return secondarySaveProfile.map { base.appendingPathComponent("Profiles/\($0)") } ?? base
    }
    var secondarySaveProfile: UUID? {
        guard let profiles = localProfiles, let active = profiles.active, active.id != profiles.originalID else { return nil }
        return active.id
    }
    func requireReadableSaveProfile() throws {
        let failed = Thread.isMainThread ? localProfiles?.failed : DispatchQueue.main.sync { self.localProfiles?.failed }
        if failed == true { throw SaveFailure.profilesUnavailable }
    }
    func profileSaveLocation(for game: PortedGame, profileID: UUID) throws -> SaveLocation {
        try requireReadableSaveProfile()
        if profileID == localProfiles?.originalID { return try legacySaveLocation(for: game) }
        return try SaveLocation.profileLocation(titleID: game.titleId ?? "", profileID: profileID, in: AppData.supportRoot)
    }
    func legacySaveLocation(for game: PortedGame) throws -> SaveLocation {
        try SaveLocation.defaultLocation(titleID: game.titleId ?? "", home: FileManager.default.homeDirectoryForCurrentUser)
    }
    func saveContext(for game: PortedGame, launchProfileID: UUID? = nil) throws -> SaveContext {
        try requireReadableSaveProfile()
        guard let id = game.titleId else { throw SaveFailure.invalidTitleID }
        func settings() -> (UUID?, String?) {
            let scoped: UUID? = if let launchProfileID {
                launchProfileID == localProfiles?.originalID ? nil : launchProfileID
            } else { secondarySaveProfile }
            return (scoped, settingsStore?.settings.cloudSaves.folderURL()?.path)
        }
        let (scoped, libraryFolder) = Thread.isMainThread
            ? settings() : DispatchQueue.main.sync { settings() }
        var gameCloud: String?
        if let domain = game.effectiveBundleId {
            CFPreferencesAppSynchronize(domain as CFString)
            if let value = CFPreferencesCopyAppValue(CloudSaves.preferenceKey as CFString, domain as CFString) {
                guard let text = value as? String else { throw SaveFailure.unreadableConfiguration }
                gameCloud = text
            }
        }
        // The installed launcher's Info.plist decides its data directory. Do not redirect an inconsistent record.
        let plist = game.url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let installedID = info["DMTitleID"] as? String,
              SaveLocation.validID(installedID), installedID.uppercased() == id.uppercased() else {
            throw SaveFailure.invalidTitleID
        }
        if let scoped {
            return SaveContext(location: try SaveLocation.profileLocation(titleID: id, profileID: scoped, in: AppData.supportRoot),
                               cloudReason: nil)
        }
        let environment = NSWorkspaceLauncher.inheritedGameEnvironment()
        let home = environment["HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        return try SaveLocation.inspect(titleID: id, appURL: game.url, home: home, environment: environment,
            gameCloudFolder: gameCloud, libraryCloudFolder: libraryFolder)
    }
    func saveIdentity(for game: PortedGame) -> SaveIdentity {
        SaveIdentity(titleID: (game.titleId ?? "").uppercased(), gameName: game.name,
                     version: game.versionString, buildID: CheatLocator.buildID(appURL: game.url))
    }
    func defaultSaveLocation(for game: PortedGame) throws -> SaveLocation {
        try requireReadableSaveProfile()
        let scoped = Thread.isMainThread ? secondarySaveProfile : DispatchQueue.main.sync { self.secondarySaveProfile }
        if let scoped { return try SaveLocation.profileLocation(titleID: game.titleId ?? "", profileID: scoped, in: AppData.supportRoot) }
        return try legacySaveLocation(for: game)
    }
    /// Covers the complete replace operation, also when a successful build arrives from its background queue.
    func acquireSaveInstallLease(for game: PortedGame) -> (() -> Void)? {
        try? requireSaveInstallLease(for: game)
    }

    func requireSaveInstallLease(for game: PortedGame) throws -> (() -> Void)? {
        guard let tid = game.titleId else { return nil }
        let location: SaveLocation?
        do { location = try defaultSaveLocation(for: game) }
        catch SaveFailure.profilesUnavailable { throw SaveFailure.profilesUnavailable }
        catch { location = nil }
        if let location, SaveTransaction.needsRecovery(location: location) { return nil }
        guard let token = saveGate.begin(titleID: tid, recoveryLocation: location) else { return nil }
        if RunningGameMonitor.runningApplication(for: game) != nil {
            saveGate.end(titleID: tid, token: token); return nil
        }
        return { [saveGate] in saveGate.end(titleID: tid, token: token) }
    }
    func savesAreBusy(for game: PortedGame) -> Bool {
        guard let tid = game.titleId else { return false }
        return saveGate.isBusy(titleID: tid, recoveryLocation: try? defaultSaveLocation(for: game))
    }
    func savesPermitPlay(_ game: PortedGame) -> Bool {
        guard let tid = game.titleId else { return true }
        if localProfiles?.failed == true {
            alertMessage = SaveFailure.profilesUnavailable.localizedDescription
            return false
        }
        let location = try? defaultSaveLocation(for: game)
        if let location, SaveTransaction.needsRecovery(location: location) {
            recoverSavesAtStartup()
            alertMessage = L10n.format("This game’s save needs recovery. Wait for recovery to finish, then press Play again. Backups are in %@.", [saveBackupRoot.path])
            return false
        }
        if saveGate.isBusy(titleID: tid, recoveryLocation: location) {
            alertMessage = L10n.text("This game’s saves are being managed or need recovery. Finish that operation, then press Play.")
            return false
        }
        return true
    }
    /// Only app-owned journals for known games; no startup walk through save contents.
    func recoverSavesAtStartup() {
        // Imported launcher records do not authorize repair of a real game save.
        guard !AppData.profile.isDevelopment, (try? requireReadableSaveProfile()) != nil else { return }
        for game in libraryGames {
            guard let location = try? defaultSaveLocation(for: game), SaveTransaction.needsRecovery(location: location),
                  RunningGameMonitor.runningApplication(for: game) == nil,
                  let token = saveGate.begin(titleID: location.titleID, recoveryLocation: location, recovering: true) else { continue }
            saveGate.setRecoveryBlocked(true, location: location)
            let backupRoot = saveBackupRoot
            let store = SaveSnapshotStore(root: backupRoot)
            saveQueue.async { [weak self] in
                guard let self else { return }
                var failure: Error?
                do { try SaveTransaction(store: store, isRunning: { RunningGameMonitor.runningApplication(for: game) != nil }).recover(location: location) }
                catch { failure = error }
                self.saveGate.setRecoveryBlocked(failure != nil, location: location)
                self.saveGate.end(titleID: location.titleID, token: token)
                let message = failure?.localizedDescription
                DispatchQueue.main.async {
                    if let message {
                        self.logs.append(LogEntry(level: .error, message: L10n.format("Save recovery for %@: %@ Backups: %@", [game.name, message, backupRoot.path])))
                    } else {
                        self.logs.append(LogEntry(level: .info, message: L10n.format("Save recovery completed for %@.", [String(describing: game.name)])))
                        self.installPendingBuilds()
                    }
                }
            }
        }
    }
}
