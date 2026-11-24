import AppKit
import Combine
import NXLibraryCore
import ArcanePorting

private extension CloudLibraryAction {
    var isUpload: Bool {
        switch self {
        case .upload, .uploadSources: return true
        default: return false
        }
    }
}

extension CloudLibraryItem {
    var primaryDownloadTitle: String { self == .sources ? "Download game files" : "Download" }

    var downloadAction: CloudLibraryAction { self == .sources ? .downloadSources : .restore(.app) }

    var title: String {
        switch self {
        case .app: return "Game app"
        case .cache: return "Build cache"
        case .sources: return "Game source files"
        }
    }
}

struct CloudSourceFiles: Equatable {
    let folderName: String
    let files: [URL]

    init?(_ game: PortedGame) {
        guard SourceSelection.hasGame(game.sources),
              game.sources.allSatisfy({ $0.layout != .extracted && $0.url.isFileURL }) else { return nil }
        let files = Set(game.sources.map { $0.url.standardizedFileURL })
        guard let folder = files.first?.deletingLastPathComponent(),
              files.allSatisfy({ $0.deletingLastPathComponent() == folder }),
              let id = game.titleId, let name = CloudGameSources.folderName(local: folder.lastPathComponent,
                                                                          title: game.name, titleID: id) else { return nil }
        self.folderName = name
        self.files = files.sorted { $0.path < $1.path }
    }
}

struct CloudFreeSelection {
    let sizes: [CloudLibraryItem: Int64]
    let available: Set<CloudLibraryItem>
    var selected: Set<CloudLibraryItem>

    init(state: CloudLibraryState) {
        sizes = Dictionary(uniqueKeysWithValues: CloudLibraryItem.allCases.compactMap { item in
            state.bytes(item).map { (item, $0) }
        })
        available = Set(CloudLibraryItem.allCases.filter {
            if let kind = $0.artifact { return state.copies[kind]?.state == .synchronized }
            return state.sources?.state == .synchronized && state.sourcesCanFree
        })
        selected = available.subtracting([.sources])
    }

    func allows(_ item: CloudLibraryItem) -> Bool { available.contains(item) }
    mutating func toggle(_ item: CloudLibraryItem) {
        guard allows(item) else { return }
        if selected.remove(item) == nil { selected.insert(item) }
    }
}

extension CloudLibraryAction {
    func item(during progress: CloudArchiveProgress?) -> CloudLibraryItem {
        switch self {
        case .upload(let kind): return .init(kind ?? progress?.kind ?? (progress == nil ? .app : .cache))
        case .restore(let kind): return .init(kind)
        case .restoreBuildCache: return .cache
        case .uploadSources, .downloadSources: return .sources
        case .free(let items): return progress.map { $0.kind.map(CloudLibraryItem.init) ?? .sources }
            ?? CloudLibraryItem.allCases.first(where: items.contains) ?? .app
        }
    }
}

struct CloudLibraryState {
    var copies: [CloudArtifactKind: CloudArtifactStatus] = [:]
    // Presence from the remote manifest, not proof that copies match.
    var availability: [CloudArtifactKind: CloudArtifactStatus] = [:]
    var referenceAvailability: [CloudArtifactKind: CloudArtifactStatus] = [:]
    var referenceCopies: [CloudArtifactKind: CloudGameArchive.ReferenceCopy] = [:]
    var referenceKinds: Set<CloudArtifactKind> = []
    var referenceSources: CloudSourcesStatus?
    var referenceSourceBytes: Int64?
    var sourceAvailability: CloudSourcesStatus?
    var sources: CloudSourcesStatus?
    var sourcesMessage: String?
    var sourceFailure: CloudLibraryFailure?
    var sourcesCanFree = false
    var action: CloudLibraryAction?
    var queued = false
    var progress: CloudArchiveProgress?
    var message: String?
    var failure: CloudLibraryFailure?
    var transferFailure: CloudLibraryFailure?
    var issue: (item: CloudLibraryItem, message: String, failed: Bool)?
    var completedItem: CloudLibraryItem?
    var failedTransferID: UUID?
    var previousApp: URL?
    var refreshing = false
    var mustResendBoth = false

    var activeItem: CloudLibraryItem? { action?.item(during: progress) }
    func transfer(for item: CloudLibraryItem? = nil) -> CloudTransferPresentation? {
        if let activeItem, item == nil || item == activeItem {
            return .init(progress: progress, queued: queued)
        }
        if let issue, issue.failed, item == nil || item == issue.item { return .failed }
        if let completedItem, item == nil || item == completedItem { return .ready }
        return nil
    }

    func coverLook(_ buildLook: PortingTileLook) -> PortingTileLook {
        guard buildLook.isAtRest,
              let transfer = transfer(), transfer.canCancel, !queued else { return buildLook }
        return .transfer(transfer.coverFraction)
    }

    var appAvailabilityKeys: [String] {
        var keys: [String] = []
        if let personal = copies[.app] ?? availability[.app], personal.uploadedAt != nil {
            keys.append("Copy in your cloud")
        }
        if referenceCopies[.app]?.updatesLocal == true { keys.append("Update available") }
        return keys
    }

    var combinedUploadTitle: String {
        needsCombinedUpload ? "Send app and build cache" : "Send update"
    }

    var showsCombinedUpload: Bool {
        canUploadBoth && !CloudArtifactKind.allCases.allSatisfy { copies[$0]?.canMigrateArchive == true }
    }
    var appIsCloudOnly: Bool { copy(.app) == .cloudOnly }
    func copy(_ item: CloudLibraryItem) -> CloudArtifactStatus.State? {
        if let kind = item.artifact {
            return (referenceAvailability[kind] ?? copies[kind] ?? availability[kind])?.state
        }
        return (referenceSources ?? sources ?? sourceAvailability)?.state
    }
    func bytes(_ item: CloudLibraryItem) -> Int64? {
        if let kind = item.artifact { return copies[kind]?.bytes }
        return sources.map { $0.state == .cloudOnly ? $0.remoteBytes : $0.localBytes }
    }
    func canUpload(_ kind: CloudArtifactKind) -> Bool {
        guard !mustResendBoth, let copy = copies[kind], copy.hasLocalCopy else { return false }
        switch copy.state {
        case .notInCloud, .newerOnThisMac, .unknown, .synchronized:
            return CloudArtifactStatus.canUploadAlone(kind, statuses: copies)
        case .cloudOnly: return false
        }
    }
    func personalCopyIsOlder(_ kind: CloudArtifactKind) -> Bool {
        referenceKinds.contains(kind) && referenceAvailability[kind]?.state == .synchronized
            && copies[kind]?.state == .newerOnThisMac && copies[kind]?.uploadedAt != nil
    }
    var needsCombinedUpload: Bool {
        CloudArtifactKind.allCases.allSatisfy {
            copies[$0]?.hasLocalCopy == true && (mustResendBoth || copies[$0]?.state == .notInCloud)
        }
    }
    var canUploadBoth: Bool {
        needsCombinedUpload || CloudArtifactKind.allCases.allSatisfy {
            (copies[$0]?.state == .newerOnThisMac || copies[$0]?.canMigrateArchive == true) && canUpload($0)
        }
    }
}

struct CloudWorkScope: Equatable {
    let title: String
    let paths: Set<String>

    init(title: String, urls: [URL]) {
        self.title = title.uppercased()
        paths = Set(urls.map {
            $0.resolvingSymlinksInPath().standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
        })
    }

    init(_ game: PortedGame) {
        self.init(title: game.titleId ?? "", urls: [game.url] + game.sources.map(\.url) +
                  [game.buildCachePath, game.workspacePath].compactMap { $0.map { URL(fileURLWithPath: $0) } })
    }

    func overlaps(_ other: Self) -> Bool {
        (!title.isEmpty && title == other.title) || paths.contains { lhs in
            other.paths.contains { rhs in
                lhs == rhs || lhs == "/" || rhs == "/" || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
            }
        }
    }
}

final class CloudLibraryModel: ObservableObject {
    /// Presence is for navigation only; never persist an equality verdict or transfer permission.
    struct LastKnown: Codable {
        var scope: [String]
        var personalApps: Set<UUID> = []
        var referenceApps: Set<UUID> = []
        var personalFiles: Set<UUID> = []
        var referenceFiles: Set<UUID> = []
    }

    private static let lastKnownKey = "NXLibrary_CloudLastKnownAvailability"
    @Published private(set) var lastKnown = LastKnown(scope: [])
    var localSourceIDs: Set<UUID> = []
    private var availabilityScope: [String] {
        [preference.storage ?? "", preference.sourcesRoot, preference.referenceFolder ?? ""]
    }

    func remember(_ change: (inout LastKnown) -> Void) {
        var snapshot = lastKnown
        change(&snapshot)
        guard snapshot.personalApps != lastKnown.personalApps || snapshot.referenceApps != lastKnown.referenceApps
            || snapshot.personalFiles != lastKnown.personalFiles || snapshot.referenceFiles != lastKnown.referenceFiles else { return }
        lastKnown = snapshot
        if let data = try? JSONEncoder().encode(snapshot) { AppData.preferences.set(data, forKey: Self.lastKnownKey) }
    }

    enum Recovery { case reconnect, archiveFolder, sourceFolder }
    struct ConnectionCheck {
        let date: Date
        let failure: CloudLibraryFailure?
        var explicit = false
        var onSources = false
    }
    struct Request {
        var token = UUID()
        let id: UUID
        let name: String
        let action: CloudLibraryAction
        let storage: String?
        let scope: CloudWorkScope
        let importDestination: URL?
        let sourceFiles: CloudSourceFiles?
        let onSuccess: (() -> Void)?
        var resumed = false
        var appReplacement: CloudGameArchive.ReferenceAppReplacement?

        var entry: CloudTransferQueue.Entry { .init(id: id, action: action, token: token, storage: storage) }
    }

    @Published private(set) var preference: CloudLibraryPreference
    @Published private(set) var chosenExecutable: URL?
    @Published private(set) var archive: CloudGameArchive?
    struct ReferenceCheck {
        let date: Date
        var name: String? = nil
        var count: Int? = nil
        var failure: CloudLibraryFailure? = nil
    }
    @Published var referenceCheck: ReferenceCheck?
    private(set) var referenceArchive: CloudGameArchive?
    private(set) var referenceSourceArchive: CloudGameSources?
    private(set) var referenceBackend: RcloneStorageBackend?
    var referenceManifests: [String: CloudGameManifest] = [:]
    var sourceDiscovery: [String: CloudGameSources.DiscoveredGame] = [:]
    var referenceDiscovery: [String: CloudGameSources.DiscoveredGame] = [:]

    struct SelectionCheck: Equatable {
        let game: PortedGame?
        let referenceCheckedAt: Date?
    }

    func selectionCheck(for game: PortedGame?) -> SelectionCheck {
        .init(game: game, referenceCheckedAt: referenceCheck?.date)
    }

    func downloadsCloudApp(_ game: PortedGame) -> Bool {
        guard archive != nil, !game.isPlayableLocally else { return false }
        return states[game.id]?.appIsCloudOnly == true || lastKnown.personalApps.contains(game.id)
            || lastKnown.referenceApps.contains(game.id)
    }

    func downloadItem(for game: PortedGame) -> CloudLibraryItem? {
        if downloadsCloudApp(game) { return .app }
        guard sourceArchive != nil, !game.isPlayableLocally, !localSourceIDs.contains(game.id) else { return nil }
        return states[game.id]?.copy(.sources) == .cloudOnly || lastKnown.personalFiles.contains(game.id)
            || lastKnown.referenceFiles.contains(game.id) ? .sources : nil
    }

    func discovery(for game: PortedGame) -> CloudGameSources.DiscoveredGame? {
        guard let title = game.titleId?.uppercased(), let directory = game.discoveredCloudSourceDirectory else { return nil }
        let candidate = (game.cloudReferenceFolder == nil ? sourceDiscovery : referenceDiscovery)[title]
        return candidate?.directory == directory ? candidate : nil
    }
    private(set) var sourceArchive: CloudGameSources?
    @Published var isChangingConnection = false {
        didSet {
            if isChangingConnection { catalogCheck?.task.cancel() }
            else { resumeCatalogCheck?() }
        }
    }
    @Published var importTask: Task<Void, Never>?
    @Published var checkFailure: CloudLibraryFailure?
    @Published var connectionCheck: ConnectionCheck?
    @Published var queueFailure: CloudLibraryFailure?
    @Published var startupFailure: CloudLibraryFailure?
    @Published var recovery: Recovery?
    var checkFailedDuringImport = false
    var checkFailureOnSources = false
    var triedAutomaticImport = false
    var resumeCatalogCheck: (() -> Void)?
    var catalogCheck: (token: UUID, task: Task<Void, Never>)?
    @Published var catalogChecked = false
    @Published var states: [UUID: CloudLibraryState] = [:]
    private var backend: RcloneStorageBackend?
    var reads: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    var queue: [Request] = []
    @Published var queuePause: CloudLibraryFailure?
    var active: (request: Request, task: Task<Void, Never>)?
    var appInstallWake: AsyncStream<Void>.Continuation?
    var appInstall: (title: String, release: () -> Void)?
    var playAfterAppInstall: ((PlayRefusal?) -> Void)?
    @Published var libraryMove: LibraryMoveActivity?
    var libraryMoveTask: Task<Void, Never>?
    let moveJournal = LibraryMoveJournal(in: AppData.supportRoot)
    private(set) var pendingMove: LibraryMoveJournal.Pending?
    private(set) var moveJournalUnreadable = false
    var hasPendingMove: Bool { pendingMove != nil || moveJournalUnreadable }
    let queueStore = CloudTransferQueue()
    var isRestoringQueue = false
    var isPublishingReconfirmation = false
    var hasRestoredQueue = false
    private(set) var isQuitting = false
    private(set) var hasQueueWrites = false
    var isWorking: Bool { active != nil || !queue.isEmpty || libraryMove != nil }

    func interruption(of token: UUID) -> CloudLibraryFailure? {
        queue.first?.token == token ? queuePause : nil
    }

    func storageScope(for action: CloudLibraryAction) -> String? {
        let storage: String?
        switch action {
        case .uploadSources, .downloadSources:
            storage = preference.sourcesStorage
        case .free(let items) where items.contains(.sources):
            return [preference.storage, preference.sourcesStorage].compactMap { $0 }.joined(separator: "\n")
        default:
            storage = preference.storage
        }
        switch action {
        case .restore, .restoreBuildCache, .downloadSources:
            if let storage, let folder = preference.referenceFolder { return "\(storage)\nreference:\(folder)" }
        default: break
        }
        return storage
    }

    @MainActor func persistQueue() {
        guard hasRestoredQueue, !isQuitting else { return }
        hasQueueWrites = true
        queueStore.save((active.map { [$0.request.entry] } ?? []) + queue.map(\.entry)) { [weak self] failure in
            Task { @MainActor in self?.queueFailure = failure }
        }
    }

    @MainActor func stopForQuit() -> Task<Void, Never>? {
        guard !isQuitting else { return nil }
        isQuitting = true
        importTask?.cancel()
        catalogCheck?.task.cancel()
        let transfer = active?.task
        transfer?.cancel()
        libraryMove?.isCancelling = true
        let move = libraryMoveTask
        return Task {
            await transfer?.value
            await move?.value
            await queueStore.flush()
        }
    }

    func conflicts(with scope: CloudWorkScope) -> Bool {
        active?.request.scope.overlaps(scope) == true || queue.contains { $0.scope.overlaps(scope) }
    }

    init() {
        let defaults = AppData.preferences
        preference = CloudLibraryPreference(storage: defaults.string(forKey: CloudLibraryPreference.storageKey),
            enabled: defaults.object(forKey: CloudLibraryPreference.enabledKey) as? Bool,
            sourcesRoot: defaults.string(forKey: CloudLibraryPreference.sourcesRootKey),
            referenceFolder: defaults.string(forKey: CloudLibraryPreference.referenceFolderKey))
        chosenExecutable = defaults.string(forKey: CloudLibraryPreference.executableKey).map { URL(fileURLWithPath: $0) }
        do { pendingMove = try moveJournal.load() }
        catch { moveJournalUnreadable = true }
        rebuildArchive()
    }

    @MainActor func setPendingMove(_ pending: LibraryMoveJournal.Pending?) {
        pendingMove = pending
        rebuildArchive()
    }

    @MainActor func recoverPendingMove() {
        do {
            let pending = try moveJournal.load()
            moveJournalUnreadable = false
            setPendingMove(pending)
        }
        catch { moveJournalUnreadable = true; rebuildArchive() }
    }

    func matchesPersistedStorage() -> Bool {
        let defaults = AppData.preferences
        guard defaults.synchronize() else { return false }
        let disk = CloudLibraryPreference(storage: defaults.string(forKey: CloudLibraryPreference.storageKey),
                                          enabled: defaults.object(forKey: CloudLibraryPreference.enabledKey) as? Bool,
                                          sourcesRoot: defaults.string(forKey: CloudLibraryPreference.sourcesRootKey))
        return disk.storage == preference.storage && disk.enabled == preference.enabled
            && disk.sourcesRootOverride == preference.sourcesRootOverride
    }

    /// `reload` restarts the backend for an unchanged preference, after new Google credentials replaced the remote's token.
    @MainActor func configure(remote: String?, root: String, enabled: Bool, sourcesRoot: String?, reload: Bool = false) {
        let next = CloudLibraryPreference(storage: "\(remote ?? ""):\(root)", enabled: enabled,
                                          sourcesRoot: sourcesRoot, referenceFolder: preference.referenceFolder)
        guard next != preference || reload else { return }
        AppData.preferences.set(next.storage, forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(next.enabled, forKey: CloudLibraryPreference.enabledKey)
        AppData.preferences.set(next.sourcesRootOverride, forKey: CloudLibraryPreference.sourcesRootKey)
        preference = next
        rebuildArchive()
    }

    @MainActor func chooseSourcesRoot(_ root: String) {
        guard CloudLibraryPreference.validSourcesRoot(root), root != preference.sourcesRootOverride else { return }
        AppData.preferences.set(root, forKey: CloudLibraryPreference.sourcesRootKey)
        preference = CloudLibraryPreference(storage: preference.storage, enabled: preference.enabled, sourcesRoot: root,
                                            referenceFolder: preference.referenceFolder)
        rebuildArchive()
    }

    @MainActor func setReferenceFolder(_ folder: String?) {
        guard folder != preference.referenceFolder else { return }
        AppData.preferences.set(folder, forKey: CloudLibraryPreference.referenceFolderKey)
        preference = .init(storage: preference.storage, enabled: preference.enabled,
                           sourcesRoot: preference.sourcesRootOverride, referenceFolder: folder)
        rebuildArchive()
    }

    @MainActor func chooseExecutable(_ executable: URL?) {
        guard chosenExecutable != executable else { return }
        AppData.preferences.set(executable?.path, forKey: CloudLibraryPreference.executableKey)
        chosenExecutable = executable
        rebuildArchive()
    }

    private func rebuildArchive() {
        importTask?.cancel()
        importTask = nil
        triedAutomaticImport = false
        catalogCheck?.task.cancel()
        catalogChecked = false
        checkFailure = nil
        connectionCheck = nil
        startupFailure = nil
        checkFailedDuringImport = false
        checkFailureOnSources = false
        stopRemoteControl()
        reads.values.forEach { $0.task.cancel() }
        reads.removeAll()
        states = [:]
        let saved = AppData.preferences.data(forKey: Self.lastKnownKey)
            .flatMap { try? JSONDecoder().decode(LastKnown.self, from: $0) }
        lastKnown = saved.flatMap { $0.scope == availabilityScope ? $0 : nil } ?? .init(scope: availabilityScope)
        sourceDiscovery = [:]
        referenceDiscovery = [:]
        backend = preference.enabled && !hasPendingMove ? preference.remote.map {
            RcloneStorageBackend(remote: $0, root: preference.root, executable: chosenExecutable)
        } : nil
        sourceArchive = backend.map {
            CloudGameSources(backend: $0, root: preference.sourcesRoot, usesDefaultRoot: preference.sourcesRootOverride == nil)
        }
        archive = backend.map { CloudGameArchive(backend: $0) }
        referenceCheck = nil
        referenceManifests = [:]
        referenceBackend = preference.referenceFolder.flatMap { backend?.reference(folderID: $0) }
        referenceArchive = referenceBackend.map { CloudGameArchive(backend: $0) }
        referenceSourceArchive = referenceBackend.map { CloudGameSources(backend: $0, root: "GameFiles", usesDefaultRoot: true) }
    }

    func stopRemoteControl() { backend?.stopRemoteControl() }

    @MainActor func update(_ id: UUID, _ change: (inout CloudLibraryState) -> Void) {
        var state = states[id] ?? CloudLibraryState()
        change(&state)
        states[id] = state
    }
}

extension AppViewModel {
    private struct CloudImportListing {
        var manifests: [CloudGameManifest] = []
        var invalidTitles: [String] = []
        var discovery: CloudGameSources.Discovery?
        var unlistedSources = false

        var warnings: [String] {
            func warning(_ key: String, _ names: [String]) -> String? {
                guard !names.isEmpty else { return nil }
                return L10n.format(key, [names.prefix(8).joined(separator: ", ") + (names.count > 8 ? ", …" : "")])
            }
            return [
                warning("Could not read cloud game records for: %@.", invalidTitles),
                warning("Ambiguous cloud game files: %@.", discovery?.ambiguous ?? []),
                warning("Unreadable cloud game files: %@.", discovery?.unreadable ?? []),
                unlistedSources ? L10n.text("Could not list cloud game files.") : nil,
            ].compactMap { $0 }
        }
    }

    private func cloudImportListing(_ archive: CloudGameArchive, sources: CloudGameSources?) async throws -> CloudImportListing {
        let (manifests, invalid) = try await archive.latestManifestsForImport()
        var listing = CloudImportListing(invalidTitles: invalid)
        if let sources {
            do { listing.discovery = try await sources.discover() }
            catch is CancellationError { throw CancellationError() }
            catch { listing.unlistedSources = true }
        }
        for manifest in manifests {
            if manifest.cloudOnlyApp != nil { listing.manifests.append(manifest); continue }
            if let selection = manifest.sourceSelection, let sources {
                do {
                    if try await sources.manifestFilesAvailable(selection, titleID: manifest.titleID) {
                        listing.manifests.append(manifest)
                        continue
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { /* Keep the title in the import result. */ }
            }
            listing.invalidTitles.append(manifest.titleID)
        }
        return listing
    }

    @MainActor private func recordCloudListing(_ listing: CloudImportListing, catalog: CatalogDocument,
                                               reference: Bool) {
        let manifests = Dictionary(uniqueKeysWithValues: listing.manifests.map { ($0.titleID, $0) })
        let discovered = Dictionary(uniqueKeysWithValues: (listing.discovery?.games ?? []).map { ($0.titleID, $0) })
        if reference {
            cloudLibrary.referenceManifests = manifests
            if listing.discovery != nil { cloudLibrary.referenceDiscovery = discovered }
        } else if listing.discovery != nil {
            cloudLibrary.sourceDiscovery = discovered
        }
        var apps = Set<UUID>(), files = Set<UUID>()
        var states = cloudLibrary.states
        for game in catalog.nxnativeGames where states[game.id]?.action == nil {
            guard let title = game.titleId?.uppercased() else { continue }
            if !game.isPlayableLocally, let app = manifests[title]?.cloudOnlyApp {
                apps.insert(game.id)
                if reference {
                    states[game.id, default: .init()].referenceAvailability[.app] = app
                    states[game.id, default: .init()].referenceKinds.insert(.app)
                } else { states[game.id, default: .init()].copies[.app] = app }
            } else if reference {
                states[game.id]?.referenceAvailability[.app] = nil
                states[game.id]?.referenceKinds.remove(.app)
            } else if !game.isPlayableLocally { states[game.id]?.copies[.app] = nil }
            guard game.cloudImportPending == true, (game.cloudReferenceFolder != nil) == reference else { continue }
            if let status = cloudLibrary.discovery(for: game)?.availability(for: game.sources,
                    in: CloudGameSources.importedFolder(for: game.id)), status.state == .cloudOnly {
                files.insert(game.id)
                if reference {
                    states[game.id, default: .init()].referenceSources = status
                    states[game.id, default: .init()].referenceSourceBytes = status.remoteBytes
                } else { states[game.id, default: .init()].sourceAvailability = status }
            } else if manifests[title]?.cloudOnlyApp == nil, manifests[title]?.sourceSelection != nil {
                files.insert(game.id)
            } else if listing.discovery != nil, game.discoveredCloudSourceDirectory != nil {
                if reference {
                    states[game.id]?.referenceSources = nil
                    states[game.id]?.referenceSourceBytes = nil
                } else { states[game.id]?.sourceAvailability = nil }
            }
        }
        cloudLibrary.states = states
        cloudLibrary.remember {
            if reference {
                $0.referenceApps = apps
                if !listing.unlistedSources { $0.referenceFiles = files }
            } else {
                $0.personalApps = apps
                if !listing.unlistedSources {
                    let checked = Set(catalog.nxnativeGames.filter {
                        $0.cloudImportPending == true && $0.cloudReferenceFolder == nil &&
                            ($0.isCloudSourcePlaceholder || $0.discoveredCloudSourceDirectory != nil)
                    }.map(\.id))
                    $0.personalFiles.subtract(checked)
                    $0.personalFiles.formUnion(files)
                }
            }
        }
    }

    @MainActor func followCloudReference(_ folder: String?) {
        guard canConfigureCloudLibrary, folder != cloudLibrary.preference.referenceFolder,
              folder.map({ CloudLibraryPreference.referenceFolderID($0) == $0 }) ?? true else { return }
        do {
            if let previous = cloudLibrary.preference.referenceFolder {
                // Cancel discovery before dropping its catalog placeholders.
                cloudLibrary.importTask?.cancel()
                applyCatalog(try catalogRepository.forgetCloudReference(previous))
            }
            cloudLibrary.setReferenceFolder(folder)
            importCloudGames()
        } catch { showSettingsNotice(title: L10n.text("Reference library"), message: error.localizedDescription) }
    }

    @MainActor private func importCloudReference(archive: CloudGameArchive) async -> (added: Bool, warnings: [String]) {
        guard let reference = cloudLibrary.referenceArchive, let backend = cloudLibrary.referenceBackend,
              let folder = cloudLibrary.preference.referenceFolder else { return (false, []) }
        do {
            let listing = try await cloudImportListing(reference, sources: cloudLibrary.referenceSourceArchive)
            let discovered = listing.discovery?.games ?? []
            // Do not enumerate other shared folders as part of discovery.
            let name = try await backend.referenceName()
            guard name != nil || !listing.manifests.isEmpty || !discovered.isEmpty else { throw CloudLibraryFailure.folderMissing }
            try Task.checkCancellation()
            guard cloudLibrary.archive === archive else { return (false, []) }
            let previousIDs = Set(libraryGames.map(\.id))
            let catalog = try catalogRepository.importCloudGames(listing.manifests, discovered: discovered,
                                                                  in: gameAppsFolder, referenceFolder: folder)
            recordCloudListing(listing, catalog: catalog, reference: true)
            cloudLibrary.referenceCheck = .init(date: .now, name: name ?? folder,
                count: Set(listing.manifests.map(\.titleID) + discovered.map(\.titleID)).count)
            if catalog.games != catalogGames { applyCatalog(catalog) }
            return (catalog.nxnativeGames.contains { !previousIDs.contains($0.id) }, listing.warnings)
        } catch {
            guard !Task.isCancelled, cloudLibrary.archive === archive else { return (false, []) }
            cloudLibrary.referenceCheck = .init(date: .now, failure: cloudFailure(for: error) ?? .unavailable)
            return (false, [cloudMessage(for: error)])
        }
    }

    @MainActor private func referenceManifest(titleID: String) async throws -> CloudGameManifest? {
        guard let referenceArchive = cloudLibrary.referenceArchive,
              cloudLibrary.referenceCheck == nil || cloudLibrary.referenceCheck?.failure != nil
                || cloudLibrary.referenceManifests[titleID.uppercased()] != nil else { return nil }
        return try await referenceArchive.latest(titleID: titleID)
    }

    @MainActor private func restoreReferenceManifest(titleID: String, kind: CloudArtifactKind,
                                                      personal: CloudGameManifest?) async throws -> CloudGameManifest? {
        do { return try await referenceManifest(titleID: titleID) }
        catch {
            try Task.checkCancellation()
            guard !(error is CancellationError), personal?.artifacts.contains(where: { $0.kind == kind }) == true
            else { throw error }
            // The personal artifact still goes through normal restore verification.
            return nil
        }
    }

    @MainActor func importCloudGames(manually: Bool = false) {
        cloudLibrary.resumeCatalogCheck = { [weak self] in self?.checkCloudCatalog() }
        guard manually || !cloudLibrary.triedAutomaticImport else {
            checkCloudCatalog()
            return
        }
        guard let archive = cloudLibrary.archive, cloudLibrary.importTask == nil,
                          !isScanningLibrary, !cloudLibrary.isQuitting else { return }
        cloudLibrary.catalogCheck?.task.cancel()
        cloudLibrary.triedAutomaticImport = true
        cloudLibrary.checkFailure = nil
        cloudLibrary.startupFailure = nil
        cloudLibrary.checkFailedDuringImport = false
        cloudLibrary.checkFailureOnSources = false
        cloudLibrary.catalogChecked = false
        cloudLibrary.importTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.cloudLibrary.archive === archive {
                    self.cloudLibrary.importTask = nil
                    self.checkCloudCatalog()
                }
            }
            let title = L10n.text("Import games from the cloud")
            var listedCloud = false
            var invalidOnly: String?
            var added = false
            var warnings: [String] = []
            do {
                let listing = try await self.cloudImportListing(archive, sources: self.cloudLibrary.sourceArchive)
                let manifests = listing.manifests
                let discovered = listing.discovery?.games ?? []
                try Task.checkCancellation()
                guard self.cloudLibrary.archive === archive else { return }
                warnings = listing.warnings
                if !listing.invalidTitles.isEmpty {
                    self.logs.append(LogEntry(level: .warning, message: L10n.format("Could not read cloud game records for: %@.",
                        [listing.invalidTitles.joined(separator: ", ")])))
                    if manifests.isEmpty, discovered.isEmpty {
                        invalidOnly = warnings.joined(separator: "\n")
                        throw CloudArchiveError.invalidManifest
                    }
                }
                listedCloud = true
                self.cloudLibrary.connectionCheck = .init(date: .now, failure: nil)
                let knownTitles = Set(self.libraryGames.compactMap { $0.titleId?.uppercased() })
                let missingNames = manifests.filter {
                    !knownTitles.contains($0.titleID) && $0.gameName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                }.map(\.titleID)
                let locale = L10n.context
                let worker = Task.detached(priority: .utility) {
                    let metadata = NintendoStoreMetadataService()
                    var names: [String: String] = [:]
                    for id in missingNames {
                        try Task.checkCancellation()
                        names[id] = metadata.cached(for: id, locale: locale)?.name
                    }
                    return names
                }
                let names = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard self.cloudLibrary.archive === archive else { return }
                let previousIDs = Set(self.libraryGames.map(\.id))
                let catalog = try self.catalogRepository.importCloudGames(manifests, discovered: discovered,
                                                                           in: self.gameAppsFolder, legacyNames: names)
                self.recordCloudListing(listing, catalog: catalog, reference: false)
                added = catalog.nxnativeGames.contains { !previousIDs.contains($0.id) }
                if catalog.games != self.catalogGames {
                    self.cloudLibrary.catalogCheck?.task.cancel()
                    self.cloudLibrary.catalogChecked = false
                    self.applyCatalog(catalog)
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.cloudLibrary.archive === archive else { return }
                let message = invalidOnly ?? self.cloudMessage(for: error)
                if invalidOnly == nil { self.logs.append(LogEntry(level: .warning, message: message)) }
                let failure = self.cloudFailure(for: error) ?? .unavailable
                if !listedCloud { self.cloudLibrary.connectionCheck = .init(date: .now, failure: failure) }
                self.cloudLibrary.checkFailedDuringImport = true
                self.cloudLibrary.checkFailure = failure
                if manually {
                    if self.cloudFailure(for: error) != nil {
                        self.showCloudFailure(failure, title: title) { [weak self] in self?.importCloudGames(manually: true) }
                    } else {
                        self.showSettingsNotice(title: title, message: message) { [weak self] in self?.importCloudGames(manually: true) }
                    }
                } else {
                    self.cloudLibrary.startupFailure = failure
                }
            }
            guard !Task.isCancelled else { return }
            let reference = await self.importCloudReference(archive: archive)
            guard manually, !Task.isCancelled, self.cloudLibrary.archive === archive,
                  !self.cloudLibrary.checkFailedDuringImport || reference.added else { return }
            let summary = L10n.text(added || reference.added ? "New cloud games are in your library." : "No new cloud games.")
            let referenceWarnings = reference.warnings.isEmpty ? [] : [L10n.text("Reference library")] + reference.warnings
            self.showSettingsNotice(title: title, message: ([summary] + warnings + referenceWarnings).joined(separator: "\n"))
        }
    }

    @MainActor func retryCloudCheck() {
        cloudLibrary.queuePause = nil
        startNextCloudOperation()
        if cloudLibrary.checkFailedDuringImport {
            importCloudGames(manually: true)
        } else {
            cloudLibrary.checkFailure = nil
            cloudLibrary.startupFailure = nil
            checkCloudCatalog()
        }
    }

    @MainActor func resumeCloudTransfer(_ token: UUID) {
        guard cloudLibrary.interruption(of: token) != nil else { return }
        cloudLibrary.queuePause = nil
        startNextCloudOperation()
    }

    @MainActor private func checkCloudCatalog() {
        guard let archive = cloudLibrary.archive, let sourceArchive = cloudLibrary.sourceArchive,
              cloudLibrary.hasRestoredQueue, cloudLibrary.triedAutomaticImport, cloudLibrary.importTask == nil,
              !isScanningLibrary, !cloudLibrary.isQuitting, !cloudLibrary.isChangingConnection,
              !cloudLibrary.isWorking, !cloudLibrary.catalogChecked, cloudLibrary.checkFailure == nil,
              cloudLibrary.catalogCheck == nil else { return }
        let token = UUID(), games = libraryGames
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                if self.cloudLibrary.catalogCheck?.token == token {
                    self.cloudLibrary.catalogCheck = nil
                    self.checkCloudCatalog()
                }
            }
            func current() -> Bool {
                !Task.isCancelled && self.cloudLibrary.catalogCheck?.token == token && self.cloudLibrary.archive === archive
            }
            var checkingSources = false
            var checkedCloud = false
            do {
                try await CloudGameArchive.checkCatalogAvailability(games, titleID: \.titleId) { game in
                    guard let title = game.titleId, self.libraryGames.contains(game),
                          self.porting.cloudBuildScope?.title != title.uppercased() else { return }
                    var locations: [CloudArtifactKind: URL] = [:]
                    if game.cloudImportPending != true, game.url.pathExtension.lowercased() == "app" { locations[.app] = game.url }
                    if let path = game.buildCachePath, path.hasPrefix("/") { locations[.cache] = URL(fileURLWithPath: path) }
                    checkingSources = false
                    let availability = try await archive.availability(.init(titleID: title, locations: locations),
                                                                      expectingArchive: game.cloudImportPending == true && !game.isCloudSourcePlaceholder
                                                                        && game.cloudReferenceFolder == nil)
                    checkedCloud = true
                    guard current(), self.libraryGames.contains(game),
                          self.porting.cloudBuildScope?.title != title.uppercased() else { return }
                    self.cloudLibrary.update(game.id) { $0.availability = availability }
                    self.cloudLibrary.remember {
                        if availability[.app]?.state == .cloudOnly { $0.personalApps.insert(game.id) }
                        else { $0.personalApps.remove(game.id) }
                    }
                    if game.discoveredCloudSourceDirectory != nil { return }
                    let reference = self.cloudLibrary.referenceManifests[title.uppercased()]
                    let needsEngineSources = game.isPlayableLocally && !self.gamesWithFilesHere.contains(game.id)
                    if let reference, reference.sourceSelection != nil, needsEngineSources {
                        let shared: ReferenceSources?
                        do {
                            let own = try await archive.latest(titleID: title)
                            shared = try await self.referenceSourceStatus(for: game, reference: reference, own: own)
                        } catch { shared = nil } // If the reference can't be checked, try the personal sources.
                        guard current(), self.libraryGames.contains(game),
                              self.porting.cloudBuildScope?.title != title.uppercased() else { return }
                        self.cloudLibrary.update(game.id) {
                            $0.referenceSources = shared?.status
                            $0.referenceSourceBytes = shared?.bytes
                        }
                        if shared != nil { return }
                    }
                    if let files = CloudSourceFiles(game), needsEngineSources || reference?.sourceSelection == nil {
                        checkingSources = true
                        let sources = try await sourceArchive.availability(folderName: files.folderName, files: files.files)
                        guard current(), self.libraryGames.contains(game),
                              self.porting.cloudBuildScope?.title != title.uppercased() else { return }
                        self.cloudLibrary.update(game.id) { $0.sourceAvailability = sources }
                        self.cloudLibrary.remember {
                            if sources.state == .cloudOnly { $0.personalFiles.insert(game.id) }
                            else { $0.personalFiles.remove(game.id) }
                        }
                    }
                }
                if current() {
                    self.cloudLibrary.catalogChecked = true
                    if checkedCloud { self.cloudLibrary.connectionCheck = .init(date: .now, failure: nil) }
                }
            } catch is CancellationError {
            } catch {
                if current() {
                    let failure = self.cloudFailure(for: error) ?? .unavailable
                    self.cloudLibrary.connectionCheck = .init(date: .now, failure: failure, onSources: checkingSources)
                    self.cloudLibrary.checkFailureOnSources = checkingSources
                    self.cloudLibrary.checkFailure = failure
                    self.cloudLibrary.startupFailure = failure
                }
            }
        }
        cloudLibrary.catalogCheck = (token, task)
    }

    @MainActor func restoreCloudQueue() {
        guard let archive = cloudLibrary.archive, !isScanningLibrary, !cloudLibrary.hasRestoredQueue,
              !cloudLibrary.isRestoringQueue, !cloudLibrary.isQuitting else { return }
        cloudLibrary.isRestoringQueue = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.cloudLibrary.isRestoringQueue = false }
            let entries = await self.cloudLibrary.queueStore.load()
            guard !self.cloudLibrary.isQuitting else { return }
            let knownGames = self.libraryGames
            let gameIDs = Set(knownGames.map(\.id))
            let reconfirmations = entries.filter { $0.action.isUpload || ($0.storage == nil && gameIDs.contains($0.id)) }
            if !reconfirmations.isEmpty {
                let rows = reconfirmations.map { entry in
                    (entry, knownGames.first(where: { $0.id == entry.id })?.name)
                }
                guard await self.publishCloudReconfirmations(rows) else { return }
            }
            guard !self.cloudLibrary.isQuitting else { return }
            guard self.cloudLibrary.archive === archive, !self.isScanningLibrary else {
                Task { @MainActor in self.restoreCloudQueue() }
                return
            }
            self.cloudLibrary.hasRestoredQueue = true
            defer { self.checkCloudCatalog(); self.porting.scheduleNextBuild() }
            let games = self.libraryGames
            guard !entries.isEmpty else { return }
            for entry in reconfirmations { self.showCloudReconfirmation(entry) }
            let resumable = entries.filter { !$0.action.isUpload && $0.storage != nil }
            let restored = CloudTransferQueue.restoring(resumable, gameIDs: Set(games.map(\.id)))
            self.objectWillChange.send()
            for entry in restored {
                let storage = self.cloudLibrary.storageScope(for: entry.action)
                guard let game = games.first(where: { $0.id == entry.id }),
                      game.titleId.map(SaveLocation.validID) == true else { continue }
                guard let approvedStorage = entry.storage, approvedStorage == storage else { continue }
                self.cloudLibrary.reads[game.id]?.task.cancel()
                self.cloudLibrary.reads[game.id] = nil
                self.cloudLibrary.update(game.id) {
                    $0.action = entry.action; $0.queued = true; $0.refreshing = false
                }
                let destination = self.cloudImportDestination(for: game, action: entry.action)
                self.cloudLibrary.queue.append(.init(token: entry.token ?? UUID(), id: game.id, name: game.name,
                    action: entry.action, storage: approvedStorage, scope: destination.map {
                    CloudWorkScope(title: game.titleId ?? "", urls: [$0])
                } ?? CloudWorkScope(game), importDestination: destination,
                             sourceFiles: CloudSourceFiles(game), onSuccess: nil, resumed: true))
            }
            self.startNextCloudOperation()
            await self.cloudLibrary.queueStore.flush()
        }
    }

    var hasCloudLibrary: Bool { cloudLibrary.archive != nil }

    func showsCloudLibrary(_ game: PortedGame) -> Bool {
        game.platform == .macApp
    }

    @MainActor func downloadCloudApp(_ game: PortedGame) {
        guard cloudLibrary.downloadsCloudApp(game) else { return }
        downloadCloudGame(game)
    }

    @MainActor func downloadCloudGame(_ game: PortedGame) {
        let state = cloudLibrary.states[game.id]
        guard let item = cloudLibrary.downloadItem(for: game),
              state?.action == nil, state?.refreshing != true,
              canChangeCloudLibrary(item.downloadAction, for: game) else {
            SoundEffectService.shared.play(.error)
            return
        }
        performCloudLibrary(item.downloadAction, for: game)
    }

    @MainActor func openCloudLibrary(for game: PortedGame) {
        if cloudLibrary.archive == nil { router?.openSettings(.cloudLibrary) }
        else { cloudLibraryGameID = game.id }
    }

    /// The catalog check is cheap; compare actual local content only for a selected,
    /// installed game with an app in the followed reference.
    @MainActor func prefetchCloudLibrary(_ game: PortedGame?) async {
        guard let game, showsCloudLibrary(game), !Task.isCancelled else { return }
        checkCloudCatalog()
        guard game.isPlayableLocally, let title = game.titleId?.uppercased(),
              cloudLibrary.referenceManifests[title]?.artifacts.contains(where: { $0.kind == .app }) == true,
              cloudLibraryGameID != game.id, cloudLibrary.reads[game.id] == nil else { return }
        await refreshCloudLibrary(game, includeSources: false)
    }

    var canConfigureCloudLibrary: Bool {
        canStartLibraryMove && !cloudLibrary.hasPendingMove
    }

    var canStartLibraryMove: Bool {
        !isBuilding && !isCheckingCloudBuild && !isUpdatingApp && !cloudLibrary.isWorking
            && !cloudLibrary.isRestoringQueue && !cloudLibrary.isChangingConnection
            && !cloudLibrary.isQuitting && !cloudQuitRequested
    }

    @MainActor func canChangeCloudLibrary(_ action: CloudLibraryAction, for game: PortedGame) -> Bool {
        guard game.titleId != nil else { return false }
        return porting.cloudBuildScope?.overlaps(CloudWorkScope(game)) != true &&
            !isCleaningStorage && !isUpdatingApp && !isScanningLibrary &&
            !cloudLibrary.isChangingConnection &&
            !appIcon.appIconsInFlight.contains(game.id) && game.pendingInstall == nil &&
            !savesAreBusy(for: game) &&
            (action.allowsPlay || RunningGameMonitor.runningApplication(for: game) == nil)
    }

    @MainActor func startCloudBuild(for game: PortedGame, archive: CloudGameArchive, extraArguments: [String],
                                    onStarted: (() -> Void)?, withoutCache: Bool,
                                    queuedName: String?, request: BuildRequest?, canStart: ((PortedGame) -> Bool)?,
                                    afterSourcesDownloaded: (() -> Void)?) async {
        let target = libraryGames.first(where: { $0.id == game.id }) ?? game
        guard let title = target.titleId, SaveLocation.validID(title) else {
            reportCloudBuildError(NXLibraryError.missingTitleId, queuedName: queuedName, request: request)
            return
        }
        do {
            if !GameResourceState.sourcesAvailable(for: target) {
                if request?.localSourcesOnly == true { throw NXLibraryError.missingSources }
                try await confirmCloudSourcesDownload(for: target, archive: archive, extraArguments: extraArguments,
                                                      onStarted: onStarted, withoutCache: withoutCache,
                                                      afterSourcesDownloaded: afterSourcesDownloaded, request: request)
                return
            }
            let token = try await archive.beginBuild(titleID: title)
            let release = { await archive.endBuild(titleID: title, token: token) }
            do {
                let locations = withoutCache ? CloudArchiveGame(titleID: title, locations: [:]) : await cloudLocations(for: target)
                let lastBuild = target.lastBuild.flatMap { record -> ClosedRange<Date>? in
                    guard record.exitCode == 0, !record.cancelled, let end = record.endedAt,
                          end >= record.startedAt else { return nil }
                    return record.startedAt...end
                }
                let check: (decision: CloudRebuildDecision, verifiedCache: URL?, hasUsableLocalCache: Bool)
                do {
                    let reference = withoutCache ? nil : try await referenceManifest(titleID: title)
                    let own = reference == nil ? nil : try await archive.latest(titleID: title)
                    let useReference = reference.map { referenceWins($0, over: own, kind: .cache) } == true
                    let appManifest = reference.flatMap { reference in
                        let referenceApp = referenceWins(reference, over: own, kind: .app)
                        return referenceApp == useReference ? nil : (referenceApp ? reference : own)
                    }
                    check = try await (useReference ? cloudLibrary.referenceArchive ?? archive : archive)
                        .checkRebuild(locations, sourcesAvailable: true, withoutCache: withoutCache,
                                                           lastSuccessfulBuild: lastBuild,
                                                           preferLocalCache: request?.preferLocalCache == true,
                                                           appManifest: appManifest)
                    try Task.checkCancellation()
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as CacheVerificationError {
                    throw error
                } catch {
                    try Task.checkCancellation()
                    // The cloud can't be checked (or its cache didn't come): a valid cache on this Mac serves, an empty
                    // work folder never replaces it.
                    if !cloudLibrary.isQuitting, !withoutCache, let path = target.buildCachePath,
                       let cache = locations.locations[.cache], cache.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path,
                       try LocalBuildCache.matchesInstalledApp(cache, app: locations.locations[.app]),
                       canStart?(target) != false {
                        try porting.beginBuild(for: target, extraArguments: extraArguments, verifiedCache: cache,
                                               releaseCloudBuild: release)
                        onStarted?()
                        return
                    }
                    await release()
                    try Task.checkCancellation()
                    if request != nil { porting.finishActivityBuild(.failed(cloudMessage(for: error))) }
                    guard !cloudLibrary.isQuitting else { return }
                    showCloudBuildNotice(for: target, archive: archive, extraArguments: extraArguments,
                                         onStarted: onStarted, canDownload: false)
                    return
                }
                switch check.decision {
                case .missingSources:
                    throw NXLibraryError.missingSources
                case .downloadCache:
                    await release()
                    try Task.checkCancellation()
                    if request != nil { porting.finishActivityBuild(.failed(L10n.text("Build needs a verified build cache."))) }
                    guard !cloudLibrary.isQuitting else { return }
                    showCloudBuildNotice(for: target, archive: archive, extraArguments: extraArguments,
                                         onStarted: onStarted, canDownload: true, hasLocalCache: check.hasUsableLocalCache)
                case .allowed, .fullRebuild:
                    guard !cloudLibrary.isQuitting else { await release(); return }
                    guard let current = libraryGames.first(where: { $0.id == target.id }),
                          current.titleId == target.titleId, current.workspacePath == target.workspacePath,
                          current.buildCachePath == target.buildCachePath else { throw CloudArchiveError.busy }
                    if canStart?(current) == false {
                        await release()
                        return
                    }
                    try porting.beginBuild(for: target, extraArguments: extraArguments, verifiedCache: check.verifiedCache,
                                   withoutCache: withoutCache || check.decision == .fullRebuild,
                                   releaseCloudBuild: release)
                    onStarted?()
                }
            } catch {
                await release()
                throw error
            }
        } catch where Task.isCancelled || error is CancellationError {
            if request != nil { porting.finishActivityBuild(.cancelled) }
        } catch {
            reportCloudBuildError(error, queuedName: queuedName, request: request)
        }
    }

    private func reportCloudBuildError(_ error: Error, queuedName: String?, request: BuildRequest?) {
        guard !cloudLibrary.isQuitting else { return }
        if request != nil { porting.finishActivityBuild(.failed(cloudMessage(for: error))) }
        if let queuedName { porting.logSkippedBuild(queuedName, reason: error.localizedDescription) }
        else { porting.presentBuildError(error) }
    }

    func canCheckCloudSources(for game: PortedGame) -> Bool {
        if game.discoveredCloudSourceDirectory != nil { return cloudLibrary.downloadItem(for: game) == .sources }
        let status = cloudLibrary.states[game.id]?.copy(.sources)
        let shared = game.titleId.flatMap { cloudLibrary.referenceManifests[$0.uppercased()]?.sourceSelection }
        return cloudLibrary.sourceArchive != nil && game.titleId.map(SaveLocation.validID) == true
            && (shared != nil || CloudSourceFiles(game) != nil && status != .notInCloud && status != .newerOnThisMac)
    }

    @MainActor private func confirmCloudSourcesDownload(for game: PortedGame, archive: CloudGameArchive,
                                                        extraArguments: [String], onStarted: (() -> Void)?,
                                                        withoutCache: Bool, afterSourcesDownloaded: (() -> Void)?,
                                                        request: BuildRequest?) async throws {
        guard let sources = cloudLibrary.sourceArchive else {
            throw NXLibraryError.missingSources
        }
        let reference = try await referenceManifest(titleID: game.titleId ?? "")
        let own = reference == nil ? nil : try await archive.latest(titleID: game.titleId ?? "")
        let bytes: Int64
        if let shared = try await referenceSourceStatus(for: game, reference: reference, own: own),
           let changed = shared.bytes {
            bytes = changed
        } else {
            guard let files = CloudSourceFiles(game),
                  try await sources.status(folderName: files.folderName, files: files.files).state == .cloudOnly
            else { throw NXLibraryError.missingSources }
            bytes = try await sources.downloadSize(folderName: files.folderName, files: files.files)
        }
        try Task.checkCancellation()
        guard !cloudLibrary.isQuitting else { return }
        if request != nil { porting.finishActivityBuild(.failed(L10n.text("Game files not found"))) }
        let size = bytes.formatted(.byteCount(style: .file).locale(L10n.context.formatLocale))
        showSettingsNotice(title: L10n.text("Rebuild"),
            message: L10n.format("Download %@ to rebuild?", [size]), actionTitle: "Download", cancelTitle: "Cancel") { [weak self] in
                guard let self else { return }
                guard self.cloudLibrary.archive === archive else {
                    self.porting.presentBuildError(CloudArchiveError.busy)
                    return
                }
                let queued = self.enqueueCloudLibrary(.downloadSources, for: game) { [weak self] in
                    guard let self else { return }
                    if self.cloudLibraryGameID == game.id { self.cloudLibraryGameID = nil }
                    if let afterSourcesDownloaded { afterSourcesDownloaded() }
                    else if let restored = self.libraryGames.first(where: { $0.id == game.id }) {
                        self.porting.submitBuild(for: restored, extraArguments: extraArguments, onStarted: onStarted,
                                         withoutCache: withoutCache, request: request)
                    }
                }
                if queued { self.cloudLibraryGameID = game.id }
                else { self.porting.presentBuildError(CloudArchiveError.busy) }
            }
    }

    @MainActor private func showCloudBuildNotice(for game: PortedGame, archive: CloudGameArchive,
                                                  extraArguments: [String], onStarted: (() -> Void)?, canDownload: Bool,
                                                  hasLocalCache: Bool = false) {
        let title = L10n.format("Rebuild %@", [game.name])
        let without = "Rebuild without cache"
        let download = "Download cache and rebuild"
        var details = [without: L10n.text("Takes longer.")]
        let rebuild: (Bool) -> Void = { [weak self] withoutCache in
            guard let self else { return }
            guard self.cloudLibrary.archive === archive else {
                self.porting.presentBuildError(CloudArchiveError.busy)
                return
            }
            self.porting.submitBuild(for: game, extraArguments: extraArguments, onStarted: onStarted,
                                     withoutCache: withoutCache, preferLocalCache: !withoutCache)
        }
        if canDownload {
            var alternatives: [(title: String, run: () -> Void)] = []
            if hasLocalCache {
                alternatives.append(("Rebuild with this Mac’s cache", { rebuild(false) }))
                // The grey line under the button says which cache a rebuild would use.
                details["Rebuild with this Mac’s cache"] = game.buildCachePath
                    .flatMap { LocalBuildCache.shaderCount(ofCache: URL(fileURLWithPath: $0)) }
                    .map { L10n.format("This Mac’s cache · %@ shaders", [NumberFormatter.localizedString(from: $0 as NSNumber, number: .decimal)]) }
                    ?? L10n.text("This Mac’s cache")
                details[download] = L10n.text("Keeps this Mac’s cache as a backup.")
            }
            alternatives.append((without, { rebuild(true) }))
            showSettingsNotice(title: title,
                message: hasLocalCache
                    ? L10n.text("The cloud cache differs from this Mac’s cache.")
                    : L10n.text("There’s no verified copy of the cloud cache on this Mac."),
                actionTitle: download, cancelTitle: "Cancel", alternatives: alternatives,
                primaryFirst: true, choiceDetails: details) { [weak self] in
                    guard let self else { return }
                    guard self.cloudLibrary.archive === archive else {
                        self.porting.presentBuildError(CloudArchiveError.busy)
                        return
                    }
                    let queued = self.enqueueCloudLibrary(.restoreBuildCache, for: game) { [weak self] in
                        guard let self, let restored = self.libraryGames.first(where: { $0.id == game.id }) else { return }
                        if self.cloudLibraryGameID == game.id { self.cloudLibraryGameID = nil }
                        self.porting.submitBuild(for: restored, extraArguments: extraArguments, onStarted: onStarted,
                                                 preferLocalCache: true)
                    }
                    if queued {
                        self.cloudLibraryGameID = game.id
                    } else {
                        self.showSettingsNotice(title: title, message: self.cloudMessage(for: CloudArchiveError.busy))
                    }
                }
        } else {
            showSettingsNotice(title: title,
                message: L10n.text("Arcane couldn’t verify the cloud cache."),
                actionTitle: without, cancelTitle: "Cancel", primaryFirst: true, choiceDetails: details) { rebuild(true) }
        }
    }

    @MainActor func refreshCloudLibrary(_ game: PortedGame, includeSources: Bool = true) async {
        guard let archive = cloudLibrary.archive, let game = libraryGames.first(where: { $0.id == game.id }),
              let titleID = game.titleId, SaveLocation.validID(titleID),
              !Task.isCancelled, cloudLibrary.states[game.id]?.action == nil else { return }
        let id = game.id, token = UUID()
        cloudLibrary.reads[id]?.task.cancel()
        cloudLibrary.update(id) { $0.refreshing = true; $0.message = nil; $0.failure = nil }
        let read = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.cloudLibrary.reads[id]?.token == token {
                    self.cloudLibrary.reads[id] = nil
                    self.cloudLibrary.update(id) { $0.refreshing = false }
                }
            }
            let discovered = game.discoveredCloudSourceDirectory != nil
            let files = includeSources && !discovered ? CloudSourceFiles(game) : nil
            async let sourceStatus = self.readCloudSourceStatus(files)
            async let localTarget = self.cloudLocations(for: game, allowManagedCache: self.cloudLibrary.referenceArchive != nil)
            let lookup: Result<CloudGameManifest?, Error>
            do { lookup = .success(try await archive.latest(titleID: titleID,
                expectingArchive: game.cloudImportPending == true && !game.isCloudSourcePlaceholder
                    && game.cloudReferenceFolder == nil)) }
            catch { lookup = .failure(error) }
            let target = await localTarget
            var copies = try? await archive.copyStatuses(target, manifest: lookup)
            if game.cloudImportPending == true, case .success(let manifest) = lookup, let app = manifest?.cloudOnlyApp {
                copies?[.app] = app
            }
            func isCurrent() -> Bool {
                guard !Task.isCancelled, self.cloudLibrary.reads[id]?.token == token, self.cloudLibrary.archive === archive,
                      let current = self.libraryGames.first(where: { $0.id == id }) else { return false }
                return current.titleId == titleID && current.url == game.url &&
                    current.buildCachePath == game.buildCachePath && current.workspacePath == game.workspacePath &&
                    current.modificationDate == game.modificationDate && current.sources == game.sources
            }
            guard let copies, isCurrent() else { return }
            let own = (try? lookup.get()) ?? nil
            let reference = (try? await self.referenceManifest(titleID: titleID)) ?? nil
            var referenceKinds: Set<CloudArtifactKind> = []
            var referenceCopies: [CloudArtifactKind: CloudGameArchive.ReferenceCopy] = [:]
            var referenceAvailability: [CloudArtifactKind: CloudArtifactStatus] = [:]
            if case .success = lookup, let reference, let referenceArchive = self.cloudLibrary.referenceArchive {
                referenceKinds = Set(CloudArtifactKind.allCases.filter { self.referenceWins(reference, over: own, kind: $0) })
                if !referenceKinds.isEmpty {
                    let compared = try? await referenceArchive.copyStatuses(target, manifest: .success(reference))
                    for kind in referenceKinds {
                        let status = kind == .app && game.cloudImportPending == true ? reference.cloudOnlyApp : compared?[kind]
                        referenceAvailability[kind] = status
                        if kind == .app && game.cloudImportPending == true || target.locations[kind] != nil {
                            referenceCopies[kind] = try? await referenceArchive.referenceCopy(kind, for: target,
                                manifest: reference, status: status, matchesOlderCopy: copies[kind]?.state == .synchronized)
                        }
                    }
                }
            }
            guard isCurrent() else { return }
            self.cloudLibrary.update(id) {
                $0.copies = copies
                $0.referenceAvailability = referenceAvailability
                $0.referenceKinds = referenceKinds
                $0.referenceCopies = referenceCopies
                if case .failure(let error) = lookup {
                    $0.message = self.cloudMessage(for: error)
                    $0.failure = self.cloudFailure(for: error)
                }
            }
            if case .success = lookup {
                self.cloudLibrary.remember {
                    if !game.isPlayableLocally && own?.cloudOnlyApp != nil { $0.personalApps.insert(id) }
                    else { $0.personalApps.remove(id) }
                }
            }
            guard includeSources else { return }
            if discovered {
                let status = self.cloudLibrary.discovery(for: game)?.availability(for: game.sources,
                    in: CloudGameSources.importedFolder(for: id))
                self.cloudLibrary.update(id) {
                    $0.sources = game.cloudReferenceFolder == nil ? status : nil
                    $0.referenceSources = game.cloudReferenceFolder != nil ? status : nil
                    $0.referenceSourceBytes = $0.referenceSources.flatMap { $0.state == .cloudOnly ? $0.remoteBytes : nil }
                    $0.sourcesCanFree = false
                }
                return
            }
            let sources = await sourceStatus
            let referenceSources = try? await self.referenceSourceStatus(for: game, reference: reference, own: own)
            guard isCurrent() else { return }
            let previous = self.cloudLibrary.states[id]?.sources?.state
            let status = try? sources?.get()
            if previous != status?.state { self.objectWillChange.send() }
            self.cloudLibrary.update(id) {
                $0.sources = status
                $0.referenceSources = referenceSources?.status
                $0.referenceSourceBytes = referenceSources?.bytes
                $0.sourcesCanFree = files.map { self.canFreeCloudSources($0, for: game) } ?? false
                $0.sourcesMessage = nil
                $0.sourceFailure = nil
                if referenceSources == nil, case .failure(let error) = sources {
                    $0.sourcesMessage = self.cloudMessage(for: error)
                    $0.sourceFailure = self.cloudFailure(for: error)
                }
            }
        }
        cloudLibrary.reads[id] = (token, read)
        await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
    }

    private func referenceWins(_ reference: CloudGameManifest, over own: CloudGameManifest?,
                               kind: CloudArtifactKind) -> Bool {
        own?.prefersReference(reference, for: kind) ?? reference.artifacts.contains { $0.kind == kind }
    }

    private struct ReferenceSources {
        let selection: [GameFileItem]
        let status: CloudSourcesStatus
        let bytes: Int64?
        var urls: [URL] { status.files.map(\.url) }
    }

    @MainActor private func referenceSourceStatus(for game: PortedGame, reference: CloudGameManifest?,
                                                  own: CloudGameManifest?) async throws -> ReferenceSources? {
        guard let reference, let selection = reference.sourceSelection,
              let title = game.titleId?.uppercased(),
              var items = selection.adopted(in: CloudGameSources.importedFolder(for: game.id), titleID: title),
              let sources = cloudLibrary.referenceSourceArchive,
              own.map({ own in
                  guard let personal = own.sourceSelection else { return true }
                  return (selection.publishedAt ?? reference.createdAt) > (personal.publishedAt ?? own.createdAt)
              }) ?? true else { return nil }
        let existing = CloudSourceFiles(game)
        let date = selection.publishedAt ?? reference.createdAt
        if let parent = existing?.files.first?.deletingLastPathComponent() {
            for index in items.indices {
                items[index].url = parent.appendingPathComponent(items[index].url.lastPathComponent)
            }
        } else if !game.sources.isEmpty { return nil } // Do not silently relink extracted or multi-volume sources.
        let urls = Array(Set(items.map(\.url))).sorted { $0.path < $1.path }
        let existingPaths = Set(existing?.files ?? [])
        let scope = CloudWorkScope(title: "", urls: urls)
        guard !libraryGames.contains(where: { $0.id != game.id && scope.overlaps(CloudWorkScope($0)) }),
              !scope.overlaps(.init(title: "", urls: [game.url] +
                [game.buildCachePath, game.workspacePath].compactMap { $0.map { URL(fileURLWithPath: $0) } })) else { return nil }
        let status = try await sources.status(folderName: selection.folderName, files: urls)
        guard status.files.allSatisfy({
                  guard $0.remoteBytes != nil else { return false }
                  if $0.state == .synchronized || $0.state == .cloudOnly { return true }
                  guard $0.state == .newerOnThisMac, existingPaths.contains($0.url),
                        let local = try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                  else { return false }
                  return local < date
              }) else { return nil }
        let changed = status.files.filter { $0.state != .synchronized }
        let relink = Set(urls) != existingPaths
        // Newer local inputs must also win if the reference no longer lists them.
        if relink, existing?.files.filter({ !urls.contains($0) }).contains(where: {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { $0 >= date } == true
        }) == true { return nil }
        return .init(selection: items, status: status, bytes: changed.isEmpty && !relink ? nil :
            changed.reduce(0) { $0 + ($1.remoteBytes ?? 0) })
    }

    @MainActor private func readCloudSourceStatus(_ files: CloudSourceFiles?) async -> Result<CloudSourcesStatus, Error>? {
        guard let sources = cloudLibrary.sourceArchive, let files else { return nil }
        do { return .success(try await sources.status(folderName: files.folderName, files: files.files)) }
        catch { return .failure(error) }
    }

    @MainActor private func canFreeCloudSources(_ files: CloudSourceFiles, for game: PortedGame) -> Bool {
        let scope = CloudWorkScope(title: "", urls: files.files)
        return !libraryGames.contains { $0.id != game.id && scope.overlaps(CloudWorkScope($0)) }
    }

    @MainActor func performCloudLibrary(_ action: CloudLibraryAction, for selected: PortedGame) {
        if action == .restore(.app), let replacement = cloudLibrary.states[selected.id]?.referenceCopies[.app]?.appReplacement {
            showSettingsNotice(title: L10n.text("Replace"),
                message: L10n.format("Replace %@ on this Mac with the app from the reference library? The previous app will be kept.",
                                     [replacement.destination.lastPathComponent]),
                actionTitle: "Replace", cancelTitle: "Cancel") { [weak self] in
                self?.enqueueCloudLibrary(action, for: selected, appReplacement: replacement)
            }
            return
        }
        enqueueCloudLibrary(action, for: selected)
    }

    @MainActor func retryCloudOperation(_ entry: CloudTransferQueue.Entry, token: UUID) -> Bool {
        if entry.storage == nil || entry.action.isUpload {
            showSettingsNotice(title: L10n.text("Cloud library"), message: cloudReconfirmationMessage(for: entry))
            if !cloudLibrary.hasRestoredQueue { restoreCloudQueue() }
            else if cloudLibrary.queue.first?.token == token { startNextCloudOperation() }
            return true
        }
        guard entry.storage == cloudLibrary.storageScope(for: entry.action),
              let game = libraryGames.first(where: { $0.id == entry.id }) else { return false }
        return enqueueCloudLibrary(entry.action, for: game, retryToken: token)
    }

    private func cloudReconfirmationMessage(for entry: CloudTransferQueue.Entry) -> String {
        let message = L10n.text("Open Cloud library to review and confirm this transfer again.")
        guard let previous = entry.storage, previous != cloudLibrary.storageScope(for: entry.action) else { return message }
        return [message, L10n.format("Previous destination: %@", [previous])].joined(separator: "\n")
    }

    @MainActor private func showCloudReconfirmation(_ entry: CloudTransferQueue.Entry) {
        let reason = cloudReconfirmationMessage(for: entry)
        cloudLibrary.update(entry.id) {
            $0.action = nil; $0.queued = false; $0.progress = nil
            $0.issue = (entry.action.item(during: nil), reason, true)
            $0.transferFailure = nil; $0.failedTransferID = nil
        }
    }

    @MainActor private func publishCloudReconfirmations(_ rows: [(CloudTransferQueue.Entry, String?)]) async -> Bool {
        await restoreActivity()
        for (entry, name) in rows {
            // A 0.3.0 row without a token is unique per game; keep its identity across interrupted handoffs.
            activityResults.record(id: entry.token ?? entry.id, job: .cloud(entry), name: name,
                                   outcome: .failed(cloudReconfirmationMessage(for: entry)))
        }
        hasActivityWrites = true
        do {
            try await activityStore.saveDurably(activityResults.entries)
            return true
        } catch {
            cloudLibrary.queueFailure = .queueNotSaved
            return false
        }
    }

    @MainActor @discardableResult
    private func enqueueCloudLibrary(_ action: CloudLibraryAction, for selected: PortedGame,
                                     retryToken: UUID? = nil,
                                     appReplacement: CloudGameArchive.ReferenceAppReplacement? = nil,
                                     onSuccess: (() -> Void)? = nil) -> Bool {
        guard cloudLibrary.archive != nil, !cloudLibrary.isQuitting, !cloudLibrary.isPublishingReconfirmation,
              cloudLibrary.hasRestoredQueue,
              let game = libraryGames.first(where: { $0.id == selected.id }),
              CloudWorkScope(game) == CloudWorkScope(selected),
              game.sources == selected.sources,
              game.titleId.map(SaveLocation.validID) == true,
              cloudLibrary.states[game.id]?.action == nil,
              retryToken != nil || onSuccess != nil || cloudLibrary.states[game.id]?.refreshing != true,
              canChangeCloudLibrary(action, for: game) else {
            cloudLibrary.update(selected.id) {
                $0.issue = (action.item(during: nil), cloudMessage(for: CloudArchiveError.busy), true)
            }
            return false
        }
        let state = cloudLibrary.states[game.id] ?? CloudLibraryState()
        let files = CloudSourceFiles(game)
        switch (action, retryToken != nil) {
        case (_, true): break // Retry rechecks current copies under the lease, after the FIFO wait.
        case (.upload(let kind), false):
            guard kind.map(state.canUpload) ?? state.canUploadBoth else { return false }
        case (.free(let items), false):
            let choices = CloudFreeSelection(state: state)
            guard !items.isEmpty, items.allSatisfy(choices.allows) else { return false }
        case (.uploadSources, false):
            guard files != nil, state.sources?.state == .notInCloud,
                  GameResourceState.sourcesAvailable(for: game) else { return false }
        case (.downloadSources, false):
            guard onSuccess != nil || cloudLibrary.downloadItem(for: game) == .sources
                || state.sources?.state == .cloudOnly || state.referenceSourceBytes != nil else { return false }
        default: break
        }
        cloudLibrary.reads[game.id]?.task.cancel()
        cloudLibrary.reads[game.id] = nil
        objectWillChange.send()
        let destination = cloudImportDestination(for: game, action: action)
        cloudLibrary.queue.append(.init(token: retryToken ?? UUID(), id: game.id, name: game.name,
            action: action, storage: cloudLibrary.storageScope(for: action), scope: destination.map {
            CloudWorkScope(title: game.titleId ?? "", urls: [$0])
        } ?? CloudWorkScope(game), importDestination: destination,
                                        sourceFiles: files, onSuccess: onSuccess, resumed: retryToken != nil,
                                        appReplacement: appReplacement))
        cloudLibrary.update(game.id) {
            $0.action = action; $0.queued = true; $0.progress = nil; $0.message = nil; $0.issue = nil; $0.refreshing = false
            $0.transferFailure = nil; $0.completedItem = nil; $0.failedTransferID = nil
        }
        startNextCloudOperation()
        return cloudLibrary.states[game.id]?.action == action
    }

    @MainActor func startNextCloudOperation() {
        guard cloudLibrary.hasRestoredQueue, !cloudLibrary.isQuitting, cloudLibrary.queuePause == nil,
              !cloudLibrary.isPublishingReconfirmation,
              let archive = cloudLibrary.archive else { return }
        defer { cloudLibrary.persistQueue() }
        guard cloudLibrary.active == nil else { return }
        while let request = cloudLibrary.queue.first {
            let id = request.id, action = request.action
            assert(cloudLibrary.states[id]?.action == action && cloudLibrary.states[id]?.queued == true)
            if request.resumed && action.isUpload {
                // The queue stores a destination, not a snapshot of the approved bytes.
                cloudLibrary.isPublishingReconfirmation = true
                Task { [weak self] in
                    guard let self else { return }
                    let saved = await self.publishCloudReconfirmations([(request.entry, request.name)])
                    if saved, !self.cloudLibrary.isQuitting, self.cloudLibrary.queue.first?.token == request.token {
                        self.cloudLibrary.queue.removeFirst()
                        self.showCloudReconfirmation(request.entry)
                        self.cloudLibrary.persistQueue()
                        await self.cloudLibrary.queueStore.flush()
                    }
                    self.cloudLibrary.isPublishingReconfirmation = false
                    if saved { self.startNextCloudOperation() }
                }
                return
            }
            guard let game = libraryGames.first(where: { $0.id == id }),
                  (request.importDestination != nil) == (game.cloudImportPending == true && action == .restore(.app)),
                  request.importDestination.map({ $0.deletingLastPathComponent().standardizedFileURL.path
                      == gameAppsFolder.standardizedFileURL.path }) ?? true,
                  (request.importDestination != nil || CloudWorkScope(game) == request.scope),
                  CloudSourceFiles(game) == request.sourceFiles else {
                cloudLibrary.queue.removeFirst()
                let reason = cloudMessage(for: CloudArchiveError.busy)
                cloudLibrary.update(id) {
                    $0.action = nil; $0.queued = false
                    $0.issue = (action.item(during: nil), reason, true)
                    $0.failedTransferID = request.token
                }
                recordActivity(request.token, job: .cloud(request.entry), name: request.name, outcome: .failed(reason))
                continue
            }
            guard porting.cloudBuildScope?.overlaps(request.scope) != true,
                  canChangeCloudLibrary(action, for: game),
                  let release = action.allowsPlay ? {} : acquireSaveInstallLease(for: game) else { return }
            cloudLibrary.queue.removeFirst()
            cloudLibrary.update(id) { $0.queued = false }
            cloudLibrary.active = (request, runCloudOperation(request, archive: archive, game: game, release: release))
            return
        }
        resumeLibraryScanAfterCloud()
        porting.scheduleNextBuild()
        checkCloudCatalog()
    }

    @MainActor private func runCloudOperation(_ request: CloudLibraryModel.Request, archive: CloudGameArchive,
                                             game: PortedGame, release: @escaping () -> Void) -> Task<Void, Never> {
        let id = request.id, action = request.action
        let catalogCheck = cloudLibrary.catalogCheck?.task
        catalogCheck?.cancel()
        return Task { [weak self] in
            guard let self else { release(); return }
            var outcome: ActivityHistory.Outcome = .cancelled
            var deferred = false
            defer {
                assert(self.cloudLibrary.active?.request.token == request.token)
                self.objectWillChange.send()
                self.cloudLibrary.active = nil
                release()
                self.cloudLibrary.appInstall?.release()
                self.cloudLibrary.appInstall = nil
                let play = self.cloudLibrary.playAfterAppInstall
                self.cloudLibrary.playAfterAppInstall = nil
                self.cloudLibrary.update(id) {
                    if action != .uploadSources && action != .downloadSources { $0.copies = [:] }
                    $0.availability = [:]; $0.sourceAvailability = nil
                    $0.completedItem = outcome == .succeeded ? action.item(during: $0.progress) : nil
                    $0.action = deferred ? action : nil; $0.queued = deferred; $0.progress = nil
                }
                if !self.cloudLibrary.isQuitting {
                    if deferred {
                        var paused = request
                        if action.isUpload { paused.resumed = true }
                        self.cloudLibrary.queue.insert(paused, at: 0)
                        self.cloudLibrary.persistQueue()
                        self.porting.scheduleNextBuild()
                    } else {
                        self.recordActivity(request.token, job: .cloud(request.entry), name: request.name, outcome: outcome)
                        if outcome == .succeeded { request.onSuccess?() }
                        self.startNextCloudOperation()
                    }
                    switch outcome {
                    case .succeeded: play?(nil)
                    case .failed: play?(.preparationFailed)
                    case .cancelled: play?(.notStarted)
                    }
                    self.appIcon.syncPendingAppIcons()
                    Task { await self.refreshCloudLibrary(game) }
                } else {
                    play?(.notStarted)
                }
            }
            await catalogCheck?.value
            let target = await self.cloudLocations(for: game, importDestination: request.importDestination,
                allowManagedCache: action == .restore(.cache) || action == .restoreBuildCache)
            let (updates, continuation) = AsyncStream.makeStream(of: CloudArchiveProgress.self, bufferingPolicy: .bufferingNewest(1))
            let listener = Task { @MainActor in
                for await value in updates {
                    guard self.cloudLibrary.active?.request.token == request.token else { break }
                    self.cloudLibrary.update(id) { $0.progress = value }
                }
            }
            defer { continuation.finish(); listener.cancel() }
            let progress: CloudGameArchive.Progress = { continuation.yield($0) }
            // Also catch a direct Finder launch, which does not take Arcane's lease.
            let gameClosed: @Sendable () throws -> Void = {
                if RunningGameMonitor.runningApplication(for: game) != nil { throw CloudArchiveError.busy }
            }
            do {
                try Task.checkCancellation()
                let lease = try self.cloudLibrary.moveJournal.acquire()
                defer { withExtendedLifetime(lease) {} }
                guard try self.cloudLibrary.moveJournal.load() == nil, self.cloudLibrary.matchesPersistedStorage() else {
                    throw CloudArchiveError.busy
                }
                let operation: CloudLibraryAction
                if request.resumed {
                    guard let eligible = try await self.resumableCloudAction(request, archive: archive, game: game, target: target)
                    else {
                        outcome = .failed(L10n.text("Cloud operation no longer available."))
                        self.cloudLibrary.update(id) {
                            $0.issue = (action.item(during: nil), L10n.text("Cloud operation no longer available."), true)
                            $0.failedTransferID = request.token
                        }
                        return
                    }
                    operation = eligible
                } else { operation = action }
                try Task.checkCancellation()
                switch operation {
                case .upload(let kind):
                    if !operation.allowsPlay { try gameClosed() }
                    _ = try await archive.upload(target, kinds: Set(kind.map { [$0] } ?? CloudArtifactKind.allCases),
                                                 progress: progress, beforePublication: operation.allowsPlay ? {} : gameClosed)
                    self.cloudLibrary.update(id) { $0.mustResendBoth = false }
                case .free(let items):
                    for item in CloudLibraryItem.allCases where items.contains(item) {
                        try Task.checkCancellation()
                        self.cloudLibrary.update(id) { $0.progress = .init(.verifying, kind: item.artifact) }
                        if let kind = item.artifact {
                            try await archive.free(kind, for: target, confirmed: true, beforeMutation: gameClosed)
                            if kind == .app {
                                self.applyCatalog(try self.catalogRepository.updateNXNative(id: id) { $0.status = .appMissing })
                            }
                        } else {
                            try await self.runCloudSources(.verifying, request: request, game: game,
                                                           progress: progress, gameClosed: gameClosed)
                        }
                    }
                case .uploadSources, .downloadSources:
                    try await self.runCloudSources(action == .uploadSources ? .uploading : .downloading,
                                                   request: request, game: game,
                                                   progress: progress, gameClosed: gameClosed)
                case .restore, .restoreBuildCache:
                    let kind: CloudArtifactKind
                    if case .restore(let selectedKind) = action { kind = selectedKind } else { kind = .cache }
                    if kind == .cache { try gameClosed() }
                    let beforeAppInstall: @MainActor @Sendable () async throws -> Void = {
                        // Drain verification updates before publishing the stable waiting state.
                        continuation.finish()
                        await listener.value
                        try await self.waitToInstallCloudApp(game)
                    }
                    let own = try await archive.latest(titleID: target.titleID)
                    let reference = try await self.restoreReferenceManifest(titleID: target.titleID, kind: kind, personal: own)
                    if kind == .app && game.cloudImportPending == true {
                        guard let destination = target.locations[.app] else { throw CloudArchiveError.unsafePath }
                        let folder = destination.deletingLastPathComponent()
                        try GameAppDestination.prepareInitialFolder(folder,
                            hasExplicitChoice: !self.requiresGameAppsFolderChoice)
                        if let problem = GameAppDestination.folderProblem(at: folder) {
                            throw BuildInstallError.replaceFailed(problem)
                        }
                    }
                    if kind == .cache, let cache = target.locations[.cache] {
                        let parent = cache.deletingLastPathComponent()
                        let root = BuildScratch.choose(core: AppData.supportRoot,
                            appFolder: self.gameAppsFolder).workspaces
                        if parent.standardizedFileURL.path == root.appendingPathComponent(target.titleID).standardizedFileURL.path,
                           !FileManager.default.fileExists(atPath: parent.path) {
                            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                        }
                    }
                    if let reference, let referenceArchive = self.cloudLibrary.referenceArchive,
                       self.referenceWins(reference, over: own, kind: kind) {
                        let statuses = try await referenceArchive.copyStatuses(target, manifest: .success(reference))
                        let personal = try await archive.copyStatuses(target, manifest: .success(own))
                        guard let copy = try await referenceArchive.referenceCopy(kind, for: target,
                            manifest: reference, status: statuses[kind], matchesOlderCopy: personal[kind]?.state == .synchronized)
                        else { throw CloudArchiveError.localChanged }
                        if kind == .app, let approval = request.appReplacement, copy.appReplacement != approval {
                            throw CloudArchiveError.localChanged
                        }
                        let previous = try await referenceArchive.restore(kind, for: target, from: reference,
                            replacingCopyFrom: own, appReplacement: request.appReplacement,
                            onlyIfMissing: !copy.updatesLocal || statuses[kind]?.state == .cloudOnly,
                            progress: progress, beforeMutation: gameClosed, beforeAppInstall: beforeAppInstall)
                        if kind == .app, let previous {
                            self.cloudLibrary.update(id) {
                                $0.previousApp = previous
                                $0.referenceCopies[.app] = nil
                            }
                        }
                    } else {
                        guard request.appReplacement == nil else { throw CloudArchiveError.localChanged }
                        try await archive.restore(kind, for: target, from: own, onlyIfMissing: action != .restoreBuildCache,
                                                  progress: progress, beforeMutation: gameClosed,
                                                  beforeAppInstall: beforeAppInstall)
                    }
                    if kind == .app, let url = target.locations[.app] {
                        GameIconProvider.forget(game)
                        self.applyCatalog(try self.catalogRepository.recordCloudAppRestore(id: id, at: url))
                    }
                    if kind == .cache, let url = target.locations[.cache], game.buildCachePath == nil {
                        self.applyCatalog(try self.catalogRepository.updateNXNative(id: id) {
                            $0.workspacePath = url.deletingLastPathComponent().path
                            $0.buildCachePath = url.path
                        })
                    }
                }
                // Once the app is published, record success even if cancellation arrived during the swap.
                if operation != .restore(.app) { try Task.checkCancellation() }
                outcome = .succeeded
            } catch is CancellationError {
                continuation.finish()
                await listener.value
                self.cloudLibrary.update(id) { $0.issue = (action.item(during: $0.progress), L10n.text("Transfer cancelled."), false) }
            } catch {
                continuation.finish()
                await listener.value
                if let detail = (error as? CloudArchiveError)?.diagnosticDetail {
                    self.logs.append(LogEntry(level: .error, message: detail))
                }
                let item = action.item(during: self.cloudLibrary.states[id]?.progress)
                let destination = item.artifact.flatMap { target.locations[$0] }
                    ?? request.sourceFiles?.files.first ?? CloudGameSources.importedFolder(for: id)
                let failure = self.cloudFailure(for: error, destination: destination)
                let needsConsent = action == .restore(.app) && ((error as? CloudArchiveError) == .confirmationRequired
                    || request.appReplacement != nil && (error as? CloudArchiveError) == .localChanged)
                let reason = needsConsent ? L10n.text("Open Cloud library to confirm replacing the app on this Mac.")
                    : failure?.message() ?? self.cloudMessage(for: error)
                if !Task.isCancelled, CloudTransferQueue.waitsForConnection(after: failure.map { $0 as Error } ?? error) {
                    deferred = true
                    let pause = failure ?? .offline
                    self.cloudLibrary.queuePause = pause
                    self.showCloudFailure(pause, title: L10n.text("Cloud library")) { [weak self] in
                        self?.retryCloudCheck()
                    }
                    return
                }
                outcome = Task.isCancelled ? .cancelled : .failed(reason)
                self.cloudLibrary.update(id) {
                    if (error as? CloudArchiveError) == .needsFullUpload { $0.mustResendBoth = true }
                    $0.issue = (action.item(during: $0.progress), reason, outcome != .cancelled)
                    if outcome != .cancelled {
                        $0.transferFailure = failure
                        $0.failedTransferID = needsConsent ? nil : request.token
                    }
                }
            }
        }
    }

    @MainActor func waitToInstallCloudApp(_ game: PortedGame) async throws {
        guard let title = game.titleId else { throw CloudArchiveError.unsafePath }
        let (events, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        cloudLibrary.appInstallWake = wake
        defer { cloudLibrary.appInstallWake = nil; wake.finish() }
        var changes = events.makeAsyncIterator()
        while true {
            try Task.checkCancellation()
            if let location = try? defaultSaveLocation(for: game), SaveTransaction.needsRecovery(location: location) {
                throw CloudArchiveError.busy
            }
            if RunningGameMonitor.runningApplication(for: game) == nil,
               cloudLibrary.appInstall != nil || !savesAreBusy(for: game) {
                if cloudLibrary.appInstall == nil, let release = acquireSaveInstallLease(for: game) {
                    cloudLibrary.appInstall = (title.uppercased(), release)
                }
                if cloudLibrary.appInstall != nil {
                    cloudLibrary.update(game.id) { $0.progress = .init(.restoring, kind: .app, downloadComplete: true) }
                    return
                }
                if RunningGameMonitor.runningApplication(for: game) == nil { throw CloudArchiveError.busy }
            }
            cloudLibrary.update(game.id) { $0.progress = .init(.readyToInstall, kind: .app, downloadComplete: true) }
            guard await changes.next() != nil else { throw CancellationError() }
        }
    }

    @MainActor private func resumableCloudAction(_ request: CloudLibraryModel.Request, archive: CloudGameArchive,
                                                 game: PortedGame, target: CloudArchiveGame) async throws -> CloudLibraryAction? {
        let action = request.action
        if action == .downloadSources {
            if game.discoveredCloudSourceDirectory != nil {
                return GameResourceState.sourcesAvailable(for: game) ? nil : action
            }
            let state = try await readCloudSourceStatus(request.sourceFiles)?.get()
            let reference = try await referenceManifest(titleID: target.titleID)
            let own = reference == nil ? nil : try await archive.latest(titleID: target.titleID)
            let shared = try await referenceSourceStatus(for: game, reference: reference, own: own)
            return state?.state == .cloudOnly || shared?.bytes != nil ? action : nil
        }
        var kinds = Set(CloudArtifactKind.allCases)
        if case .free(let items) = action { kinds = Set(items.compactMap(\.artifact)) }
        let manifest = kinds.isEmpty ? nil : try await archive.latest(titleID: target.titleID)
        let copies = kinds.isEmpty ? [:] : try await archive.copyStatuses(target, manifest: .success(manifest))
        switch action {
        case .restore(let kind):
            if let reference = try await restoreReferenceManifest(titleID: target.titleID, kind: kind, personal: manifest),
               let referenceArchive = cloudLibrary.referenceArchive, referenceWins(reference, over: manifest, kind: kind) {
                let status = try await referenceArchive.copyStatuses(target, manifest: .success(reference))
                return try await referenceArchive.referenceCopy(kind, for: target, manifest: reference,
                    status: status[kind], matchesOlderCopy: copies[kind]?.state == .synchronized) != nil ? action : nil
            }
            if kind == .app && game.cloudImportPending == true {
                return target.locations[.app] != nil && manifest?.cloudOnlyApp != nil ? action : nil
            }
            return copies[kind]?.state == .cloudOnly ? action : nil
        case .restoreBuildCache:
            if let reference = try await restoreReferenceManifest(titleID: target.titleID, kind: .cache, personal: manifest),
               referenceWins(reference, over: manifest, kind: .cache), target.locations[.cache] != nil { return action }
            return target.locations[.cache] != nil && manifest?.artifacts.contains(where: { $0.kind == .cache }) == true
                && copies[.cache]?.state != .synchronized ? action : nil
        case .free(let items):
            var synchronized = Set(kinds.filter { copies[$0]?.state == .synchronized }.map(CloudLibraryItem.init))
            if items.contains(.sources), let files = request.sourceFiles, canFreeCloudSources(files, for: game),
               let status = try await readCloudSourceStatus(files)?.get(),
               status.files.contains(where: { $0.state == .synchronized }),
               status.files.allSatisfy({ $0.state == .synchronized || $0.state == .cloudOnly }) {
                synchronized.insert(.sources)
            }
            return action.resumableFree(synchronized: synchronized)
        case .upload, .uploadSources, .downloadSources: return nil
        }
    }

    @MainActor private func runCloudSources(_ phase: CloudArchiveProgress.Phase, request: CloudLibraryModel.Request,
                                            game: PortedGame,
                                            progress: @escaping CloudGameArchive.Progress, gameClosed: () throws -> Void) async throws {
        guard let sources = cloudLibrary.sourceArchive else {
            throw CloudArchiveError.unsafePath
        }
        try Task.checkCancellation()
        try gameClosed()
        cloudLibrary.update(request.id) { $0.progress = .init(phase) }
        let transfer: CloudGameSources.Progress = { value in
            progress(.init(value.isVerifying ? .verifying : phase, transfer: value))
        }
        switch phase {
        case .uploading:
            guard let files = request.sourceFiles else { throw CloudArchiveError.unsafePath }
            try await sources.upload(folderName: files.folderName, files: files.files, progress: transfer)
        case .downloading:
            let title = game.titleId?.uppercased() ?? ""
            if let directory = game.discoveredCloudSourceDirectory {
                guard let owner = game.cloudReferenceFolder == nil ? sources :
                    (game.cloudReferenceFolder == cloudLibrary.preference.referenceFolder ? cloudLibrary.referenceSourceArchive : nil),
                    let parent = request.sourceFiles?.files.first?.deletingLastPathComponent() else {
                    throw CloudArchiveError.noRemoteCopy
                }
                try CloudGameSources.prepareImportedFolder(parent, for: game.id)
                try await owner.downloadDiscovered(titleID: title, directory: directory, files: game.sources,
                    in: CloudGameSources.importedFolder(for: game.id), progress: transfer)
            } else {
            let reference = try await referenceManifest(titleID: title)
            let own = reference == nil ? nil : try await cloudLibrary.archive?.latest(titleID: title)
            if let reference, let referenceSources = cloudLibrary.referenceSourceArchive,
               let selection = reference.sourceSelection,
               let shared = try await referenceSourceStatus(for: game, reference: reference, own: own) {
                if let parent = shared.urls.first?.deletingLastPathComponent() {
                    try CloudGameSources.prepareImportedFolder(parent, for: game.id)
                }
                try await referenceSources.download(folderName: selection.folderName, files: shared.urls,
                    replacingBefore: selection.publishedAt ?? reference.createdAt,
                    replacing: Set(request.sourceFiles?.files ?? []), progress: transfer)
                if shared.bytes != nil {
                    self.applyCatalog(try self.catalogRepository.updateNXNative(id: game.id) {
                        guard $0.sources == game.sources else { throw CloudArchiveError.localChanged }
                        $0.sources = shared.selection
                    })
                }
            } else {
                guard let files = request.sourceFiles else { throw CloudArchiveError.noRemoteCopy }
                if let parent = files.files.first?.deletingLastPathComponent() {
                    try CloudGameSources.prepareImportedFolder(parent, for: game.id)
                }
                try await sources.download(folderName: files.folderName, files: files.files, progress: transfer)
            }
            }
            guard let current = libraryGames.first(where: { $0.id == game.id }),
                  GameResourceState.sourcesAvailable(for: current) else { throw NXLibraryError.missingSources }
            cloudLibrary.localSourceIDs.insert(game.id)
            cloudLibrary.update(game.id) {
                $0.sources = nil; $0.sourceAvailability = nil
                $0.referenceSources = nil; $0.referenceSourceBytes = nil
            }
            cloudLibrary.remember { $0.personalFiles.remove(game.id); $0.referenceFiles.remove(game.id) }
        case .verifying:
            guard let files = request.sourceFiles else { throw CloudArchiveError.unsafePath }
            guard canFreeCloudSources(files, for: game) else { throw CloudArchiveError.unsafePath }
            _ = try await sources.free(folderName: files.folderName, files: files.files, confirmed: true)
        default:
            assertionFailure("Unexpected game-file transfer phase")
            throw CloudArchiveError.unsafePath
        }
    }

    @MainActor func cancelCloudLibrary(_ game: PortedGame) {
        guard let action = cloudLibrary.states[game.id]?.action else { return }
        if let request = cloudLibrary.queue.first(where: { $0.id == game.id && $0.action == action }) {
            cancelQueuedCloudLibrary(request.token)
        } else if let active = cloudLibrary.active, active.request.id == game.id, active.request.action == action {
            cancelActiveCloudLibrary(active.request.token)
        }
    }

    @MainActor func cancelActiveCloudLibrary(_ token: UUID) {
        guard let active = cloudLibrary.active, active.request.token == token else { return }
        active.task.cancel()
    }

    @MainActor func cancelQueuedCloudLibrary(_ token: UUID) {
        guard !cloudLibrary.isPublishingReconfirmation else { return }
        guard let index = cloudLibrary.queue.firstIndex(where: { $0.token == token }) else { return }
        objectWillChange.send()
        let request = cloudLibrary.queue.remove(at: index)
        cloudLibrary.update(request.id) { $0.action = nil; $0.queued = false }
        recordActivity(request.token, job: .cloud(request.entry), name: request.name, outcome: .cancelled)
        cloudLibrary.persistQueue()
        appIcon.syncPendingAppIcons()
        if index == 0 { cloudLibrary.queuePause = nil; startNextCloudOperation() }
        porting.scheduleNextBuild()
    }

    @MainActor private func cloudImportDestination(for game: PortedGame, action: CloudLibraryAction) -> URL? {
        guard game.cloudImportPending == true, action == .restore(.app) else { return nil }
        let pending = cloudLibrary.queue.compactMap(\.importDestination) + [cloudLibrary.active?.request.importDestination].compactMap { $0 }
        let reservedNames = Set(pending.map { $0.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased() })
        return GameAppDestination.url(name: game.url.deletingPathExtension().lastPathComponent,
                                      titleId: game.titleId, in: gameAppsFolder, reusingExisting: false,
                                      reservedNames: reservedNames)
    }

    @MainActor private func cloudLocations(for game: PortedGame, importDestination: URL? = nil,
                                           allowManagedCache: Bool = false) async -> CloudArchiveGame {
        let games = libraryGames
        let appFolder = gameAppsFolder
        let sourceSelection = CloudSourceFiles(game).flatMap {
            CloudGameSources.ArchivedSelection(folder: $0.folderName, files: game.sources, titleID: game.titleId?.uppercased() ?? "")
        }
        return await Task.detached(priority: .utility) {
            var locations: [CloudArtifactKind: URL] = [:]
            func path(_ url: URL) -> String {
                url.resolvingSymlinksInPath().standardizedFileURL.path
                    .precomposedStringWithCanonicalMapping.lowercased()
            }
            func overlaps(_ lhs: String, _ rhs: String) -> Bool {
                lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
            }
            let app = importDestination ?? game.url
            let appPath = path(app)
            let sources = games.flatMap(\.sources).map { path($0.url) }
            let otherApps = games.filter { $0.id != game.id && $0.cloudImportPending != true && $0.url.pathExtension.lowercased() == "app" }
            if (game.cloudImportPending != true || importDestination != nil), app.pathExtension.lowercased() == "app",
               !sources.contains(where: { overlaps(appPath, $0) }),
               !otherApps.contains(where: { overlaps(appPath, path($0.url)) }),
               !games.compactMap(\.workspacePath).contains(where: {
                   let workspace = path(URL(fileURLWithPath: $0))
                   return workspace == appPath || workspace.hasPrefix(appPath + "/")
               }) {
                locations[.app] = app
            }
            if let cache = try? StorageManager().cacheURL(for: game, protecting: games) {
                let cachePath = path(cache)
                if !sources.contains(where: { overlaps(cachePath, $0) }),
                   !games.filter({ $0.id != game.id }).compactMap(\.buildCachePath)
                    .contains(where: { overlaps(cachePath, path(URL(fileURLWithPath: $0))) }) {
                    locations[.cache] = cache
                }
            } else if allowManagedCache, game.workspacePath == nil, game.buildCachePath == nil,
                      let id = game.titleId?.uppercased(), SaveLocation.validID(id) {
                let workspace = BuildScratch.choose(core: AppData.supportRoot, appFolder: appFolder)
                    .workspaces.appendingPathComponent(id, isDirectory: true)
                let cache = workspace.appendingPathComponent("\(id)_build", isDirectory: true)
                if !(sources + games.map { path($0.url) } + games.compactMap {
                    $0.workspacePath.map { path(URL(fileURLWithPath: $0)) }
                }).contains(where: { overlaps(path(cache), $0) }) { locations[.cache] = cache }
            }
            return CloudArchiveGame(titleID: game.titleId ?? "", locations: locations,
                                    engineCommit: game.lastBuild?.exitCode == 0 ? game.lastBuild?.engineCommit : nil,
                                    cacheIsRegistered: game.buildCachePath != nil,
                                    sourceSelection: sourceSelection)
        }.value
    }

    private func cloudMessage(for error: Error) -> String {
        if let failure = cloudFailure(for: error) { return failure.message() }
        if let error = error as? CacheVerificationError { return error.localizedDescription }
        if let error = error as? CloudArchiveError { return error.localizedDescription }
        if let error = error as? NXLibraryError { return error.localizedDescription }
        if let error = error as? BuildInstallError { return error.localizedDescription }
        if error as? StorageBackendError == .hashMismatch {
            return L10n.text("The cloud copy could not be verified.")
        }
        return L10n.text("Cloud storage is unavailable. Check rclone and try again.")
    }

    private func cloudFailure(for error: Error, destination: URL? = nil) -> CloudLibraryFailure? {
        if let failure = error as? CloudLibraryFailure { return failure }
        if error as? CloudArchiveError == .insufficientSpace { return .diskFull(at: destination) }
        if let disk = CloudLibraryFailure.localWriteFailure(error, at: destination) { return disk }
        if let storage = error as? StorageBackendError {
            switch storage {
            case .backendUnavailable, .processFailed: return .unavailable
            default: break
            }
        }
        return nil
    }

    @MainActor func recoverCloud(_ action: CloudLibraryFailure.Action, sourceFolder: Bool = false, retry: () -> Void) {
        switch action {
        case .retry: retry()
        case .reconnect, .chooseFolder:
            guard canConfigureCloudLibrary, let router else { return }
            router.openSettings(.cloudLibrary)
            cloudLibrary.recovery = action == .reconnect ? .reconnect : (sourceFolder ? .sourceFolder : .archiveFolder)
        case .manageDriveStorage:
            NSWorkspace.shared.open(URL(string: "https://one.google.com/storage/management")!)
        case .freeMacStorage: router?.openSettings(.portingStorage)
        case .dismiss: break
        }
    }

    @MainActor func showCloudFailure(_ failure: CloudLibraryFailure, title: String, sourceFolder: Bool = false,
                                     retry: @escaping () -> Void) {
        let action = failure.action
        if action == .dismiss { showSettingsNotice(title: title, message: failure.message(), cancelTitle: action.titleKey) }
        else {
            showSettingsNotice(title: title, message: failure.message(),
                               actionTitle: action.titleKey, cancelTitle: "Cancel") { [weak self] in
                self?.recoverCloud(action, sourceFolder: sourceFolder, retry: retry)
            }
        }
    }
}
