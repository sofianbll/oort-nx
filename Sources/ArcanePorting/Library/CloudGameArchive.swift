import Darwin
import Foundation
import NXLibraryCore

public enum CloudArtifactKind: String, Codable, CaseIterable, Hashable, Sendable {
    case app, cache
}

public struct CloudArtifactStatus: Equatable, Sendable {
    public struct SkippedRoot: Equatable, Sendable {
        public let path: String
        public let bytes: Int64
    }

    public enum State: Equatable, Sendable {
        case notInCloud, cloudOnly, synchronized, newerOnThisMac, unknown
    }

    public let state: State
    public let hasLocalCopy: Bool
    public let bytes: Int64?
    public let uploadedAt: Date?
    public let skippedRoots: [SkippedRoot]
    public let remoteFolder: String?
    public var canMigrateArchive: Bool { state == .synchronized && uploadedAt != nil && remoteFolder == nil }

    public init(state: State, hasLocalCopy: Bool, bytes: Int64?, uploadedAt: Date?, skippedRoots: [SkippedRoot],
                remoteFolder: String? = nil) {
        self.state = state
        self.hasLocalCopy = hasLocalCopy
        self.bytes = bytes
        self.uploadedAt = uploadedAt
        self.skippedRoots = skippedRoots
        self.remoteFolder = remoteFolder
    }

    /// Presence alone cannot tell whether two copies have the same contents.
    static func availability(local: Bool?, artifact: CloudGameManifest.Artifact?, uploadedAt: Date?) -> Self {
        .init(state: artifact == nil ? .notInCloud : local == false ? .cloudOnly : .unknown,
              hasLocalCopy: local == true, bytes: artifact?.unpackedSize,
              uploadedAt: artifact == nil ? nil : uploadedAt, skippedRoots: [], remoteFolder: artifact?.files?.folder)
    }

    public static func needsUpload(_ statuses: [CloudArtifactKind: Self]) -> Bool {
        CloudArtifactKind.allCases.allSatisfy { statuses[$0]?.hasLocalCopy == true }
            && statuses.values.contains { $0.state == .notInCloud || $0.state == .newerOnThisMac || $0.canMigrateArchive }
    }

    public static func canUploadAlone(_ kind: CloudArtifactKind, statuses: [CloudArtifactKind: Self]) -> Bool {
        guard let copy = statuses[kind], copy.hasLocalCopy else { return false }
        if copy.canMigrateArchive { return true }
        let other = statuses[kind == .app ? .cache : .app]
        if kind == .app, other?.state == .notInCloud {
            return copy.state == .newerOnThisMac || (copy.state == .notInCloud && other?.hasLocalCopy == false)
        }
        if kind == .cache, copy.state == .notInCloud { return other?.state == .synchronized || other?.state == .cloudOnly }
        return copy.state == .newerOnThisMac && other?.uploadedAt != nil
    }
}

public struct CloudArchiveProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case preparing, uploading, verifying, downloading, restoring, readyToInstall }
    public let phase: Phase
    public let kind: CloudArtifactKind?
    public let transfer: StorageProgress?
    public let downloadComplete: Bool

    public init(_ phase: Phase, kind: CloudArtifactKind? = nil, transfer: StorageProgress? = nil,
                downloadComplete: Bool = false) {
        self.phase = phase
        self.kind = kind
        self.transfer = transfer
        self.downloadComplete = downloadComplete
    }
}

public struct CloudArchiveGame: Sendable {
    public let titleID: String
    public let locations: [CloudArtifactKind: URL]
    public let engineCommit: String?
    let cacheIsRegistered: Bool
    public let sourceSelection: CloudGameSources.ArchivedSelection?
    let installedApp: URL?

    public init(titleID: String, locations: [CloudArtifactKind: URL], engineCommit: String? = nil,
                cacheIsRegistered: Bool? = nil, sourceSelection: CloudGameSources.ArchivedSelection? = nil,
                installedApp: URL? = nil) {
        self.titleID = titleID.uppercased()
        self.locations = locations
        self.engineCommit = engineCommit
        self.cacheIsRegistered = cacheIsRegistered ?? (locations[.cache] != nil)
        self.sourceSelection = sourceSelection
        self.installedApp = installedApp ?? locations[.app]
    }

    func protectSaves(in tree: URL, incomingApp: URL? = nil) throws {
        try SaveLocation.requireArchiveSeparation(tree, titleID: titleID,
                                                  apps: [installedApp, incomingApp].compactMap { $0 })
    }
}

public struct CloudGameManifest: Codable, Equatable, Sendable {
    public struct Artifact: Codable, Equatable, Sendable {
        public let kind: CloudArtifactKind
        let size: Int64?
        let sha256: String?
        let md5: String?
        public let unpackedSize: Int64
        public let entryCount: Int
        public let inventorySHA256: String
        public let engineCommit: String?
        public let shaderChain: String?
        public let options: [String: String]
        let files: CloudArtifactFiles.Tree?
        let publishedAt: Date?

        init(kind: CloudArtifactKind, size: Int64? = nil, sha256: String? = nil, md5: String? = nil, unpackedSize: Int64,
             entryCount: Int, inventorySHA256: String, engineCommit: String?, shaderChain: String?,
             options: [String: String], files: CloudArtifactFiles.Tree? = nil, publishedAt: Date? = nil) {
            self.kind = kind
            self.size = size
            self.sha256 = sha256
            self.md5 = md5
            self.unpackedSize = unpackedSize
            self.entryCount = entryCount
            self.inventorySHA256 = inventorySHA256
            self.engineCommit = engineCommit
            self.shaderChain = shaderChain
            self.options = options
            self.files = files
            self.publishedAt = publishedAt
        }

        func legacyObject(titleID: String) -> StorageObject? {
            guard files == nil, let size, let sha256, let md5 else { return nil }
            return StorageObject(key: StorageObjectKey("\(titleID)/\(kind.rawValue)/\(sha256).aar"),
                                 size: size, hashes: ["sha256": sha256, "md5": md5])
        }

        func objects(titleID: String) -> [StorageObject] {
            files?.objects ?? [legacyObject(titleID: titleID)].compactMap { $0 }
        }

        func retainingPublication(from date: Date) -> Self {
            guard publishedAt == nil else { return self }
            return .init(kind: kind, size: size, sha256: sha256, md5: md5, unpackedSize: unpackedSize,
                         entryCount: entryCount, inventorySHA256: inventorySHA256, engineCommit: engineCommit,
                         shaderChain: shaderChain, options: options, files: files, publishedAt: date)
        }

        enum CodingKeys: String, CodingKey {
            case kind, size, sha256, md5, options, files
            case unpackedSize = "unpacked_size", entryCount = "entry_count", inventorySHA256 = "inventory_sha256"
            case engineCommit = "engine_commit", shaderChain = "shader_chain"
            case publishedAt = "published_at"
        }
    }

    public let version: Int
    public let titleID: String
    public let createdAt: Date
    public let artifacts: [Artifact]
    public let gameName: String?
    public let bundleName: String?
    public let libraryName: String?
    public let sourceSelection: CloudGameSources.ArchivedSelection?
    public var gameVersion: String? { artifacts.first { $0.kind == .app }?.options["CFBundleShortVersionString"] }

    package func prefersReference(_ reference: Self?, for kind: CloudArtifactKind) -> Bool {
        guard let reference, let candidate = reference.artifacts.first(where: { $0.kind == kind }) else { return false }
        guard let own = artifacts.first(where: { $0.kind == kind }) else { return true }
        return own.inventorySHA256 != candidate.inventorySHA256
            && (candidate.publishedAt ?? reference.createdAt) > (own.publishedAt ?? createdAt)
    }
    public var cloudOnlyApp: CloudArtifactStatus? {
        artifacts.first { $0.kind == .app }.map {
            .init(state: .cloudOnly, hasLocalCopy: false, bytes: $0.unpackedSize, uploadedAt: $0.publishedAt ?? createdAt,
                  skippedRoots: [], remoteFolder: $0.files?.folder)
        }
    }

    init(version: Int, titleID: String, createdAt: Date, artifacts: [Artifact],
         gameName: String? = nil, bundleName: String? = nil,
         sourceSelection: CloudGameSources.ArchivedSelection? = nil, libraryName: String? = nil) {
        self.version = version
        self.titleID = titleID
        self.createdAt = createdAt
        self.artifacts = artifacts
        self.gameName = gameName
        self.bundleName = bundleName
        self.sourceSelection = sourceSelection
        self.libraryName = libraryName
    }

    enum CodingKeys: String, CodingKey {
        case version, artifacts
        case titleID = "title_id", createdAt = "created_at"
        case gameName = "game_name", bundleName = "bundle_name"
        case sourceSelection = "source_selection"
        case libraryName = "library_name"
    }
}

public enum CloudArchiveError: LocalizedError, Equatable {
    public enum UploadDifference: String {
        case added, removed, type, size, linkTarget, permissions, parentDirectory
    }

    case busy, confirmationRequired, insufficientSpace, unsafePath, localMissing
    case noRemoteCopy, needsFullUpload, invalidManifest, invalidArchive, invalidApp, localChanged, excludedFiles, installFailed
    case sourcesConflict, unknownAppContents
    case uploadMismatch(CloudArtifactKind, path: String, reason: UploadDifference)

    public var diagnosticDetail: String? {
        guard case .uploadMismatch(let kind, let path, let reason) = self else { return nil }
        return DiagnosticsReport.scrub("Cloud upload: \(kind.rawValue) \(String(reflecting: path)) — \(reason.rawValue)",
                                       home: NSHomeDirectory())
    }

    public var errorDescription: String? {
        switch self {
        case .busy:
            return L10n.text("Close the game and wait for other operations to finish.")
        case .insufficientSpace:
            return L10n.text("Not enough free space on the destination drive.")
        case .invalidApp:
            return L10n.text("The app identity or signature could not be verified.")
        case .unknownAppContents:
            return L10n.text("Damaged files or unknown version: download it from Arcane")
        case .excludedFiles:
            return L10n.text("This folder contains files that must stay on this Mac.")
        case .localChanged:
            return L10n.text("The local copy changed. Check it before trying again.")
        case .needsFullUpload:
            return L10n.text("Send both the app and the build cache to create a complete cloud copy.")
        case .sourcesConflict:
            return L10n.text("A game file differs from its cloud copy. No existing copy is replaced.")
        case .uploadMismatch(let kind, let path, _):
            return L10n.format(kind == .app ? "The app changed during upload (%@). Try again."
                               : "The build cache changed during upload (%@). Try again.", [path])
        case .unsafePath, .localMissing:
            return L10n.text("A local folder is missing, unavailable or shared with another game.")
        case .invalidManifest, .invalidArchive:
            return L10n.text("The cloud copy could not be verified.")
        default:
            return L10n.text("The cloud operation could not be completed.")
        }
    }
}

public struct CacheVerificationError: LocalizedError {
    public let cause: Error
    public var errorDescription: String? { cause.localizedDescription }
}

public enum CloudRebuildDecision: Equatable, Sendable {
    case allowed, fullRebuild, missingSources, downloadCache

    static func decide(sourcesAvailable: Bool, remoteCache: Bool, localVerified: Bool,
                       withoutCache: Bool) -> Self {
        if !sourcesAvailable { return .missingSources }
        return remoteCache && !localVerified && !withoutCache ? .downloadCache : .allowed
    }
}

public actor CloudGameArchive {
    public typealias Progress = @Sendable (CloudArchiveProgress) -> Void
    private typealias Artifact = CloudGameManifest.Artifact
    private typealias Fingerprint = CloudArchiveFingerprintCache.Fingerprint
    private static let legacyManifestLimit = 64 * 1024
    private static let manifestLimit = 32 * 1024 * 1024
    let backend: any StorageBackend
    private let capacity: @Sendable (URL) -> Int64?
    private let trash: @Sendable (URL) throws -> Void
    package nonisolated let leases: CloudTitleLeases
    private let fingerprints: CloudArchiveFingerprintCache

    public init(backend: any StorageBackend) {
        self.init(backend: backend, trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                  fingerprints: .shared)
    }

    internal init(backend: any StorageBackend,
                  capacity: @escaping @Sendable (URL) -> Int64? = {
                      (try? FileManager.default.attributesOfFileSystem(forPath: $0.path)[.systemFreeSize] as? NSNumber)?.int64Value
                  },
                  trash: @escaping @Sendable (URL) throws -> Void,
                  fingerprints: CloudArchiveFingerprintCache = .init()) {
        self.backend = backend
        self.leases = (backend as? RcloneStorageBackend)?.leases ?? CloudTitleLeases()
        self.capacity = capacity
        self.trash = trash
        self.fingerprints = fingerprints
    }

    /// A failed manifest read is distinct from a successful lookup with no manifest.
    public func copyStatuses(_ game: CloudArchiveGame, manifest lookup: Result<CloudGameManifest?, Error>)
        async throws -> [CloudArtifactKind: CloudArtifactStatus] {
        let manifest = try? lookup.get()
        let readable: Bool
        if case .success = lookup { readable = manifest.map { $0.titleID == game.titleID } ?? true }
        else { readable = false }
        let cached = await fingerprints.entries()
        let worker = Task.detached(priority: .utility) {
            var statuses: [CloudArtifactKind: CloudArtifactStatus] = [:]
            var fingerprints: [String: Fingerprint] = [:]
            for kind in CloudArtifactKind.allCases {
                try Task.checkCancellation()
                let artifact = readable ? manifest?.artifacts.first { $0.kind == kind } : nil
                let uploadedAt = artifact.flatMap { $0.publishedAt ?? manifest?.createdAt }
                var state = CloudArtifactStatus.State.unknown
                var local = false
                var bytes = artifact?.unpackedSize
                var skippedRoots: [CloudArtifactStatus.SkippedRoot] = []
                if kind == .cache, readable, artifact == nil, !game.cacheIsRegistered, game.locations[.cache] == nil {
                    state = .notInCloud
                }
                if let url = try? self.location(kind, for: game),
                   let parent = try? CloudArchiveInventory.node(at: url.deletingLastPathComponent()),
                   parent.st_mode & S_IFMT == S_IFDIR {
                    do {
                        guard try self.existingNode(at: url) != nil else {
                            let confirmed = (try? self.sameDirectory(parent, at: url.deletingLastPathComponent())) == true
                            let missing: CloudArtifactStatus.State = artifact == nil ? .notInCloud : .cloudOnly
                            statuses[kind] = .init(state: readable && confirmed ? missing : .unknown,
                                                   hasLocalCopy: false, bytes: bytes,
                                                   uploadedAt: uploadedAt, skippedRoots: [],
                                                   remoteFolder: artifact?.files?.folder)
                            continue
                        }
                        let signature = try CloudArchiveInventory.signature(url, kind: kind)
                        skippedRoots = signature.skippedRoots.map {
                            .init(path: $0, bytes: DirectorySize.bytes(at: url.appendingPathComponent($0), includingHidden: true))
                        }
                        if signature.isSkippedOnly {
                            if readable { state = artifact == nil ? .notInCloud : .cloudOnly }
                        } else if !signature.hasExcludedFiles {
                            bytes = signature.bytes
                            local = true
                            if let artifact {
                                if artifact.files == nil && (signature.bytes != artifact.unpackedSize || signature.entries.count != artifact.entryCount) {
                                    state = .newerOnThisMac
                                } else {
                                    let key = CloudArchiveInventory.fingerprintKey(url, kind: kind, portable: artifact.files != nil)
                                    let fingerprint: Fingerprint
                                    if let previous = cached[key], previous.signature == signature.sha256 {
                                        fingerprint = previous
                                    } else {
                                        let snapshot = artifact.files == nil ? try CloudArchiveInventory.scan(url, kind: kind) : signature
                                        let digest = try artifact.files == nil ? snapshot.sha256
                                            : CloudArtifactFiles.digest(CloudArtifactFiles.entries(at: url, snapshot: signature))
                                        let after = try CloudArchiveInventory.signature(url, kind: kind)
                                        guard !snapshot.hasExcludedFiles, !after.hasExcludedFiles, signature.sha256 == after.sha256 else {
                                            throw CloudArchiveError.localChanged
                                        }
                                        fingerprint = .init(signature: signature.sha256, sha256: digest,
                                                            withoutRootMtime: snapshot.withoutRootMtime)
                                        fingerprints[key] = fingerprint
                                    }
                                    state = fingerprint.matches(artifact) ? .synchronized : .newerOnThisMac
                                    if kind == .cache, state == .newerOnThisMac, let tree = artifact.files,
                                       let files = try self.localFiles(at: url, kind: kind, snapshot: signature),
                                       files.count < tree.entries.count, CloudArtifactFiles.isUsableSubset(files, of: tree) {
                                        state = .cloudOnly
                                        local = false
                                        bytes = artifact.unpackedSize
                                    }
                                }
                            } else if readable {
                                state = .notInCloud
                            }
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        local = false
                    }
                }
                statuses[kind] = .init(state: state, hasLocalCopy: local, bytes: bytes,
                                       uploadedAt: uploadedAt, skippedRoots: skippedRoots,
                                       remoteFolder: artifact?.files?.folder)
            }
            return (statuses, fingerprints)
        }
        let (statuses, fresh) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        await fingerprints.save(fresh)
        return statuses
    }

    @MainActor public static func checkCatalogAvailability<Game>(_ games: [Game], titleID: (Game) -> String?,
                                                                visit: (Game) async throws -> Void) async rethrows {
        for game in games {
            guard !Task.isCancelled else { return }
            guard titleID(game).map(SaveLocation.validID) == true else { continue }
            try await visit(game)
        }
    }

    /// Hold the same title lease as upload, free and restore until the engine exits.
    public func beginBuild(titleID: String) throws -> UUID {
        try begin(titleID.uppercased())
    }

    public func endBuild(titleID: String, token: UUID) {
        leases.end(titleID.uppercased(), token: token)
    }

    /// A rebuild can reuse the local shader chain of the cloud app or, before an automatic cold rebuild,
    /// of the installed app. The engine still checks individual shaders.
    public func checkRebuild(_ game: CloudArchiveGame, sourcesAvailable: Bool, withoutCache: Bool,
                             lastSuccessfulBuild: ClosedRange<Date>? = nil, preferLocalCache: Bool = false,
                             appManifest: CloudGameManifest? = nil)
        async throws -> (decision: CloudRebuildDecision, verifiedCache: URL?, hasUsableLocalCache: Bool) {
        let local: (URL, String)?
        do {
            if !withoutCache, sourcesAvailable, game.cacheIsRegistered, game.locations[.cache] == nil {
                throw CloudArchiveError.unsafePath
            }
            if !withoutCache, sourcesAvailable, let cache = game.locations[.cache] {
                local = try LocalBuildCache.readChain(ofCache: cache).map { (cache, $0) }
            } else { local = nil }
        } catch { throw CacheVerificationError(cause: error) }
        let result: (decision: CloudRebuildDecision, verifiedCache: URL?, hasUsableLocalCache: Bool)
        do {
            result = try await decideRebuild(game, sourcesAvailable: sourcesAvailable, withoutCache: withoutCache,
                                             lastSuccessfulBuild: lastSuccessfulBuild, preferLocalCache: preferLocalCache,
                                             appManifest: appManifest)
        } catch where !(error is CancellationError) && !(error is CacheVerificationError) && sourcesAvailable && local != nil {
            // An offline rebuild only falls back to the chain in the installed app.
            if let (cache, _) = local, try LocalBuildCache.matchesInstalledApp(cache, app: game.locations[.app]) {
                return (.allowed, cache, true)
            }
            throw error
        }
        guard let (cache, chain) = local, result.verifiedCache == nil,
              result.decision == .fullRebuild || result.decision == .downloadCache else { return result }
        let manifest = try? await latest(titleID: game.titleID)
        let reference = (appManifest ?? manifest)?.artifacts.first { $0.kind == .app }?.shaderChain
            ?? manifest?.artifacts.first { $0.kind == .cache }?.shaderChain
        if reference == chain ||
            ((result.decision == .fullRebuild || reference == nil) &&
             (try? LocalBuildCache.matchesInstalledApp(cache, app: game.locations[.app])) == true) {
            return (.allowed, cache, true)
        }
        return result
    }

    private func decideRebuild(_ game: CloudArchiveGame, sourcesAvailable: Bool, withoutCache: Bool,
                               lastSuccessfulBuild: ClosedRange<Date>?, preferLocalCache: Bool,
                               appManifest: CloudGameManifest?)
        async throws -> (decision: CloudRebuildDecision, verifiedCache: URL?, hasUsableLocalCache: Bool) {
        try Task.checkCancellation()
        guard sourcesAvailable else { return (.missingSources, nil, false) }
        guard !withoutCache else { return (.allowed, nil, false) }
        guard let manifest = try await latest(titleID: game.titleID) else { return (.allowed, nil, false) }
        try Task.checkCancellation()
        guard let artifact = manifest.artifacts.first(where: { $0.kind == .cache }) else { return (.fullRebuild, nil, false) }
        let appManifest = appManifest ?? manifest
        if let app = appManifest.artifacts.first(where: { $0.kind == .app }) {
            let signatures = [(app.engineCommit, artifact.engineCommit), (app.shaderChain, artifact.shaderChain)]
                .compactMap { lhs, rhs in lhs.flatMap { lhs in rhs.map { (lhs, $0) } } }
            let olderCache = (artifact.publishedAt ?? manifest.createdAt) < (app.publishedAt ?? appManifest.createdAt)
            if signatures.contains(where: { $0 != $1 }) || olderCache && signatures.count < 2 {
                return (.fullRebuild, nil, false)
            }
        }
        guard let cache = try? location(.cache, for: game) else { return (.downloadCache, nil, false) }
        let key = CloudArchiveInventory.fingerprintKey(cache, kind: .cache, portable: artifact.files != nil)
        let cached = await fingerprints.entries()[key]
        let worker = Task.detached(priority: .utility) { () throws -> (CloudRebuildDecision, Bool, Fingerprint?) in
            do {
                guard try self.existingNode(at: cache) != nil else { return (.downloadCache, false, nil) }
                let signature = try CloudArchiveInventory.signature(cache, kind: .cache)
                guard !signature.hasExcludedFiles, !signature.isSkippedOnly else { return (.downloadCache, false, nil) }
                let usable = signature.entries.count > 1
                // A recent build record alone does not prove it wrote this cache.
                let newer = signature.latestFileWrite.map {
                    $0 > (artifact.publishedAt ?? manifest.createdAt) && lastSuccessfulBuild?.contains($0) == true
                } ?? false
                if usable && newer { return (.allowed, true, nil) }
                if let tree = artifact.files {
                    let hasFile = signature.entries.contains { $0.type == "F" }
                    let couldBePartial = hasFile && signature.entries.lazy.filter { $0.type != "D" }.count < tree.entries.count
                    if let cached, cached.signature == signature.sha256 {
                        if usable && preferLocalCache || (hasFile || tree.entries.isEmpty) && cached.matches(artifact) {
                            return (.allowed, usable, nil)
                        }
                        if !couldBePartial { return (.downloadCache, usable, nil) }
                    }
                    guard let files = try self.localFiles(at: cache, kind: .cache, snapshot: signature, strict: true) else {
                        return (.downloadCache, false, nil)
                    }
                    let fresh = Fingerprint(signature: signature.sha256, sha256: try CloudArtifactFiles.digest(files),
                                            withoutRootMtime: nil)
                    let allowed = CloudArtifactFiles.isUsableSubset(files, of: tree) || usable && preferLocalCache
                    return (allowed ? .allowed : .downloadCache, usable, fresh)
                }
                if let cached, cached.signature == signature.sha256 {
                    return (cached.matches(artifact) || usable && preferLocalCache ? .allowed : .downloadCache, usable, nil)
                }
                let snapshot = try CloudArchiveInventory.scan(cache, kind: .cache)
                let after = try CloudArchiveInventory.signature(cache, kind: .cache)
                guard !snapshot.hasExcludedFiles, !after.hasExcludedFiles, after.sha256 == signature.sha256 else {
                    throw CloudArchiveError.localChanged
                }
                let fresh = Fingerprint(signature: signature.sha256, sha256: snapshot.sha256,
                                        withoutRootMtime: snapshot.withoutRootMtime)
                return (fresh.matches(artifact) || usable && preferLocalCache ? .allowed : .downloadCache, usable, fresh)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw CacheVerificationError(cause: error)
            }
        }
        let (decision, usable, fresh) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        if let fresh { await fingerprints.save([key: fresh]) }
        return (decision, decision == .allowed ? cache : nil, usable)
    }

    public func latestManifests() async throws -> [CloudGameManifest] {
        try await latestManifests(in: backend.rootDirectories())
    }

    func latestManifests(in folders: [String]) async throws -> [CloudGameManifest] {
        try await scanManifests(in: folders, skippingInvalid: false).manifests
    }

    package func latestManifestsForImport() async throws -> (manifests: [CloudGameManifest], invalidTitles: [String]) {
        try await scanManifests(in: backend.rootDirectories(), skippingInvalid: true)
    }

    private func scanManifests(in folders: [String], skippingInvalid: Bool) async throws
        -> (manifests: [CloudGameManifest], invalidTitles: [String]) {
        var titles: [String: [String]] = [:]
        for folder in Set(folders) {
            if let title = CloudDriveFolders.titleID(in: folder) { titles[title, default: []].append(folder) }
        }
        guard titles.count <= 2_000 else { throw StorageBackendError.invalidResponse }
        var manifests: [CloudGameManifest] = []
        var invalidTitles: [String] = []
        for title in titles.keys.sorted() {
            try Task.checkCancellation()
            do {
                if let manifest = try await latest(titleID: title, folders: titles[title, default: []]) {
                    manifests.append(manifest)
                }
            } catch CloudArchiveError.invalidManifest where skippingInvalid {
                invalidTitles.append(title)
            }
        }
        try Task.checkCancellation()
        return (manifests, invalidTitles)
    }

    public func latest(titleID: String, expectingArchive: Bool = false) async throws -> CloudGameManifest? {
        let title = titleID.uppercased()
        guard SaveLocation.validID(title) else { throw CloudArchiveError.unsafePath }
        let folders = try await titleFolders(title)
        return try await latest(titleID: title, folders: folders, expectingArchive: expectingArchive)
    }

    private func titleFolders(_ title: String) async throws -> [String] {
        try await backend.rootDirectories().filter { CloudDriveFolders.titleID(in: $0) == title }
    }

    private func latest(titleID title: String, folders: [String], expectingArchive: Bool = false) async throws -> CloudGameManifest? {
        let entries = try await manifestObjects(for: title, in: folders, expectingArchive: expectingArchive)
        // The immutable filename starts with the publication timestamp. Named folders win exact ties.
        guard let newest = entries.max(by: { $0.name < $1.name })?.object else { return nil }
        guard entries.filter({ $0.object.key == newest.key }).count == 1 else { throw CloudArchiveError.invalidManifest }
        return try await readManifest(newest, titleID: title)
    }

    func adoptionManifests(titleID title: String) async throws -> [CloudGameManifest] {
        guard SaveLocation.validID(title) else { throw CloudArchiveError.unsafePath }
        let folders = try await titleFolders(title)
        let entries = try await manifestObjects(for: title, in: folders)
        guard Set(entries.map(\.object.key)).count == entries.count else { throw CloudArchiveError.invalidManifest }
        var manifests: [CloudGameManifest] = []
        for entry in entries {
            try Task.checkCancellation()
            let manifest = try await readManifest(entry.object, titleID: title)
            if manifest.version == 2 { manifests.append(manifest) }
        }
        return manifests
    }

    private func manifestObjects(for title: String, in folders: [String], expectingArchive: Bool = false)
        async throws -> [(name: Substring, object: StorageObject)] {
        var entries: [(name: Substring, object: StorageObject)] = []
        var foundDirectory = false
        for folder in folders.filter({ $0 != title }).sorted() + folders.filter({ $0 == title }) {
            try Task.checkCancellation()
            let directory = "\(folder)/manifests"
            let listed: [StorageObject]
            do { listed = try await backend.list(in: StorageObjectKey(directory)) }
            catch CloudLibraryFailure.folderMissing { continue }
            foundDirectory = true
            for object in listed where object.key.value.hasPrefix(directory + "/") && object.key.value.hasSuffix(".json") {
                entries.append((object.key.value.dropFirst(directory.count + 1), object))
            }
        }
        try Task.checkCancellation()
        if expectingArchive && !foundDirectory { throw CloudLibraryFailure.folderMissing }
        return entries
    }

    /// Fetch just the newest manifest; local availability uses a single stat per registered artifact.
    public func availability(_ game: CloudArchiveGame, expectingArchive: Bool = false) async throws -> [CloudArtifactKind: CloudArtifactStatus] {
        let manifest = try await latest(titleID: game.titleID, expectingArchive: expectingArchive)
        try Task.checkCancellation()
        return Dictionary(uniqueKeysWithValues: CloudArtifactKind.allCases.map { kind in
            let local: Bool?
            if let url = game.locations[kind] {
                do {
                    let node = try CloudArchiveInventory.node(at: url)
                    local = node.st_mode & S_IFMT == S_IFDIR ? true : nil
                } catch CloudArchiveError.localMissing { local = false }
                catch { local = nil }
            } else { local = false }
            let artifact = manifest?.artifacts.first { $0.kind == kind }
            return (kind, .availability(local: local, artifact: artifact,
                                        uploadedAt: artifact?.publishedAt ?? manifest?.createdAt))
        })
    }

    func readManifest(_ object: StorageObject, titleID title: String) async throws -> CloudGameManifest {
        let path = object.key.value.components(separatedBy: "/")
        guard path.count == 3, CloudDriveFolders.titleID(in: path[0]) == title, path[1] == "manifests",
              path[2].hasSuffix(".json") else { throw CloudArchiveError.invalidManifest }
        let name = path[2].dropLast(5)
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 16, Int64(parts[0]) != nil, Self.isHex(String(parts[1]), count: 64),
              (1...Int64(Self.manifestLimit)).contains(object.size) else { throw CloudArchiveError.invalidManifest }
        let stage = try staging(in: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: stage) }
        let file = stage.appendingPathComponent("manifest.json")
        try await backend.get(object.key, to: file)
        let data = try SaveFiles.readRegular(file, limit: Self.manifestLimit)
        guard Int64(data.count) == object.size,
              try CloudArchiveInventory.hashes(at: file, includeMD5: false)["sha256"] == String(parts[1])
        else { throw CloudArchiveError.invalidManifest }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(CloudGameManifest.self, from: data),
              [1, 2].contains(manifest.version), manifest.titleID == title,
              [[.app], CloudArtifactKind.allCases, [], [.cache]].contains(manifest.artifacts.map(\.kind)),
              manifest.cloudOnlyApp != nil || manifest.sourceSelection?.adopted(in: stage, titleID: title) != nil,
              manifest.version != 1 || data.count <= Self.legacyManifestLimit else { throw CloudArchiveError.invalidManifest }
        for artifact in manifest.artifacts {
            if let tree = artifact.files {
                guard manifest.version == 2, artifact.size == nil, artifact.sha256 == nil, artifact.md5 == nil,
                      artifact.unpackedSize >= 0, artifact.kind != .app || !tree.entries.isEmpty,
                      artifact.entryCount == tree.entries.count else { throw CloudArchiveError.invalidManifest }
                do {
                    try tree.validate(titleID: title, kind: artifact.kind, digest: artifact.inventorySHA256,
                                      bytes: artifact.unpackedSize)
                } catch CloudArchiveError.unsafePath {
                    throw CloudArchiveError.invalidManifest
                }
            } else {
                guard let object = artifact.legacyObject(titleID: title), object.size > 0, artifact.unpackedSize >= 0,
                      (1...CloudArchiveInventory.maximumEntries).contains(artifact.entryCount),
                      Self.isHex(object.hashes["sha256"] ?? "", count: 64), Self.isHex(artifact.inventorySHA256, count: 64),
                      Self.isHex(object.hashes["md5"] ?? "", count: 32) else { throw CloudArchiveError.invalidManifest }
            }
        }
        guard manifest.version != 2 || manifest.artifacts.isEmpty || manifest.artifacts.contains(where: { $0.files != nil })
        else { throw CloudArchiveError.invalidManifest }
        return manifest
    }

    public func upload(_ game: CloudArchiveGame, progress: Progress? = nil) async throws -> CloudGameManifest {
        try await upload(game, kinds: Set(CloudArtifactKind.allCases), progress: progress)
    }

    public func upload(_ game: CloudArchiveGame, kinds: Set<CloudArtifactKind>, progress: Progress? = nil,
                       beforePublication: @Sendable () throws -> Void = {}) async throws -> CloudGameManifest {
        guard (backend as? RcloneStorageBackend)?.isReference != true else { throw StorageBackendError.invalidConfiguration }
        let lease = try begin(game.titleID)
        defer { leases.end(game.titleID, token: lease) }
        guard let uploader = backend as? RcloneStorageBackend else { throw StorageBackendError.backendUnavailable }
        let selected = CloudArtifactKind.allCases.filter { kinds.contains($0) }
        guard !selected.isEmpty else { throw CloudArchiveError.needsFullUpload }
        for kind in selected { try game.protectSaves(in: location(kind, for: game)) }
        let folders = try await titleFolders(game.titleID)
        let previous: CloudGameManifest?
        do { previous = try await latest(titleID: game.titleID, folders: folders) }
        catch CloudArchiveError.invalidManifest where selected.count == 1 { throw CloudArchiveError.needsFullUpload }
        catch CloudArchiveError.invalidManifest { previous = nil }
        var artifacts = previous.map { manifest in
            manifest.artifacts.map { $0.retainingPublication(from: manifest.createdAt) }
        } ?? []
        var gameName = previous?.gameName
        var bundleName = previous?.bundleName
        var sourceSelection = game.sourceSelection ?? previous?.sourceSelection
        if let previous, let prior = previous.sourceSelection, sourceSelection?.sameFiles(as: prior) == true {
            sourceSelection?.publishedAt = prior.publishedAt ?? previous.createdAt
        }
        if selected.count == 1 {
            do {
                if let retained = previous?.artifacts.first(where: { !kinds.contains($0.kind) }) {
                    progress?(.init(.verifying))
                    try await verify(retained, titleID: game.titleID)
                } else {
                    guard selected == [.app], try previous != nil || hasNoLocalCache(game) else {
                        throw CloudArchiveError.needsFullUpload
                    }
                }
            } catch CloudArchiveError.invalidManifest, StorageBackendError.notFound, StorageBackendError.hashMismatch {
                throw CloudArchiveError.needsFullUpload
            }
        }
        let namedFolders = folders.filter { $0 != game.titleID }.sorted()
        var gameFolder = previous?.artifacts.compactMap { $0.files?.folder.components(separatedBy: "/").first }
            .first(where: namedFolders.contains) ?? namedFolders.first
        var current = previous
        var timestamp: Int64 = 0
        for kind in selected {
            progress?(.init(.preparing, kind: kind))
            let source = try location(kind, for: game)
            let parent = try CloudArchiveInventory.node(at: source.deletingLastPathComponent())
            let snapshot = try CloudArchiveInventory.signature(source, kind: kind)
            guard !snapshot.hasExcludedFiles else { throw CloudArchiveError.excludedFiles }
            guard !snapshot.isSkippedOnly else { throw CloudArchiveError.localMissing }
            let files = try CloudArtifactFiles.entries(at: source, snapshot: snapshot)
            try checkUpload(source, parent: parent, snapshot: snapshot, kind: kind)
            let info = kind == .app ? try await verifiedApp(source, titleID: game.titleID) : [:]
            if kind == .app {
                gameName = info["CFBundleDisplayName"] ?? info["CFBundleName"] ?? source.deletingPathExtension().lastPathComponent
                bundleName = source.lastPathComponent
            }
            gameFolder = gameFolder ?? CloudGameSources.folderName(local: "", title: gameName ?? "Game", titleID: game.titleID)
            guard let gameFolder else { throw CloudArchiveError.unsafePath }
            let digest = try CloudArtifactFiles.digest(files)
            let folder = "\(gameFolder)/\(kind.rawValue)/\(digest)" + (kind == .app ? "/" + source.lastPathComponent : "")
            let tree = CloudArtifactFiles.Tree(folder: folder, entries: files)
            let bytes = try CloudArtifactFiles.validate(files, kind: kind)
            try tree.validate(titleID: game.titleID, kind: kind, digest: digest, bytes: bytes)
            let old = previous?.artifacts.first { $0.kind == kind }?.files.flatMap { $0.entries.isEmpty ? nil : $0.key }
            let update = transfer(progress, phase: .uploading, kind: kind, total: bytes)
            try checkUpload(source, parent: parent, snapshot: snapshot, kind: kind)
            try game.protectSaves(in: source)
            do {
                try await uploader.copyFiles(files.map(\.path), from: source, to: tree.key,
                                             reusing: old == tree.key ? nil : old, progress: update)
            } catch {
                try checkUpload(source, parent: parent, snapshot: snapshot, kind: kind)
                throw error
            }
            progress?(.init(.verifying, kind: kind, transfer: .init(bytesTransferred: bytes, totalBytes: bytes)))
            try checkUpload(source, parent: parent, snapshot: snapshot, kind: kind)
            try await tree.verify(on: uploader)
            timestamp = max(timestamp + 1, Self.publicationTimestamp)
            let publication = Date(timeIntervalSince1970: Double(timestamp / 1000))
            let item = Artifact(kind: kind, unpackedSize: bytes, entryCount: files.count, inventorySHA256: digest,
                engineCommit: info["DMCommit"] ?? game.engineCommit, shaderChain: shaderChain(at: source, kind: kind),
                options: info.filter { ["DMLanguage", "CFBundleShortVersionString"].contains($0.key) }, files: tree,
                publishedAt: previous.flatMap { previous in
                    previous.artifacts.first { $0.kind == kind && $0.inventorySHA256 == digest }
                        .map { $0.publishedAt ?? previous.createdAt }
                } ?? publication)
            artifacts.removeAll { $0.kind == kind }
            if kind == .app { artifacts.insert(item, at: 0) }
            else { artifacts.append(item) }
            if sourceSelection?.publishedAt == nil { sourceSelection?.publishedAt = publication }
            if current?.artifacts == artifacts, current?.gameName == gameName,
               current?.bundleName == bundleName, current?.sourceSelection == sourceSelection {
                continue
            }
            let manifest = CloudGameManifest(version: 2, titleID: game.titleID, createdAt: publication,
                                             artifacts: artifacts, gameName: gameName, bundleName: bundleName,
                                             sourceSelection: sourceSelection)
            try await publishManifest(manifest, in: gameFolder, timestamp: timestamp) {
                try self.checkUpload(source, parent: parent, snapshot: snapshot, kind: kind)
                try beforePublication()
                try game.protectSaves(in: source)
            }
            current = manifest
        }
        guard let current else { throw CloudArchiveError.invalidManifest }
        return current
    }

    private static var publicationTimestamp: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func publishManifest(_ manifest: CloudGameManifest, in folder: String, timestamp: Int64,
                                 beforePublication: () throws -> Void) async throws {
        let stage = try staging(in: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: stage) }
        let file = stage.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        guard data.count <= Self.manifestLimit else { throw CloudArchiveError.invalidManifest }
        try data.write(to: file)
        let hashes = try CloudArchiveInventory.hashes(at: file)
        let key = StorageObjectKey("\(folder)/manifests/\(String(format: "%016lld", timestamp))-\(hashes["sha256"]!).json")
        try beforePublication()
        try await put(file, object: StorageObject(key: key, size: Int64(data.count), hashes: hashes), progress: nil)
    }

    public func free(_ kind: CloudArtifactKind, for game: CloudArchiveGame, confirmed: Bool,
                     beforeMutation: @Sendable () throws -> Void = {}) async throws {
        guard (backend as? RcloneStorageBackend)?.isReference != true else { throw StorageBackendError.invalidConfiguration }
        guard confirmed else { throw CloudArchiveError.confirmationRequired }
        let lease = try begin(game.titleID)
        defer { leases.end(game.titleID, token: lease) }
        let target = try location(kind, for: game)
        try game.protectSaves(in: target)
        if kind == .cache { try Self.recoverInterruptedFree(at: target, for: game) }
        let parent = target.deletingLastPathComponent()
        let volume = try CloudArchiveInventory.node(at: parent)
        let before = try CloudArchiveInventory.node(at: target)
        let artifact = try await remoteArtifact(kind, game)
        try await verify(artifact, titleID: game.titleID)
        let snapshot = try artifact.files == nil ? CloudArchiveInventory.scan(target, kind: kind)
            : CloudArchiveInventory.signature(target, kind: kind)
        guard !snapshot.hasExcludedFiles else { throw CloudArchiveError.excludedFiles }
        guard !snapshot.isSkippedOnly else { throw CloudArchiveError.localMissing }
        let digest = try artifact.files == nil ? snapshot.sha256
            : CloudArtifactFiles.digest(CloudArtifactFiles.entries(at: target, snapshot: snapshot))
        guard Fingerprint(signature: "", sha256: digest, withoutRootMtime: snapshot.withoutRootMtime).matches(artifact),
              try sameDirectory(volume, at: parent),
              try sameNode(before, at: target) else { throw CloudArchiveError.localChanged }
        try beforeMutation()
        try game.protectSaves(in: target)
        if artifact.files != nil, try CloudArchiveInventory.signature(target, kind: kind).sha256 != snapshot.sha256 {
            throw CloudArchiveError.localChanged
        }
        try Task.checkCancellation()
        if snapshot.skippedRoots.isEmpty {
            try trash(target)
        } else {
            let stage = try staging(in: parent)
            let bucket = stage.appendingPathComponent(target.lastPathComponent, isDirectory: true)
            var keepStage = false
            defer { if !keepStage { try? FileManager.default.removeItem(at: stage) } }
            try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: false)
            let roots = snapshot.entries.map(\.path).filter { !$0.isEmpty && !$0.contains("/") }
            try Self.withFreeRecovery(target: target, parent: parent, stage: stage, roots: roots) {
                try moving(roots, from: target, to: bucket, keepStage: &keepStage) { try trash(bucket) }
            }
        }
    }

    private func hasNoLocalCache(_ game: CloudArchiveGame) throws -> Bool {
        guard game.locations[.cache] != nil else { return !game.cacheIsRegistered }
        let cache = try location(.cache, for: game)
        let parent = try CloudArchiveInventory.node(at: cache.deletingLastPathComponent())
        if try existingNode(at: cache) == nil { return try sameDirectory(parent, at: cache.deletingLastPathComponent()) }
        let signature = try CloudArchiveInventory.signature(cache, kind: .cache)
        return signature.isSkippedOnly
    }

    /// Publishes in one same-volume rename. An existing copy is retained in the private staging directory.
    /// The UI only downloads missing artifacts; a caller that explicitly replaces gets the previous copy's location.
    @discardableResult
    public func restore(_ kind: CloudArtifactKind, for game: CloudArchiveGame,
                        onlyIfMissing: Bool = false, progress: Progress? = nil,
                        beforeMutation: @Sendable () throws -> Void = {}) async throws -> URL? {
        try await restore(kind, for: game, from: nil, onlyIfMissing: onlyIfMissing,
                          progress: progress, beforeMutation: beforeMutation)
    }

    @discardableResult
    package func restore(_ kind: CloudArtifactKind, for game: CloudArchiveGame, from manifest: CloudGameManifest?,
                         replacingCopyFrom older: CloudGameManifest? = nil,
                         appReplacement: ReferenceAppReplacement? = nil,
                         onlyIfMissing: Bool, progress: Progress?, beforeMutation: @Sendable () throws -> Void,
                         beforeAppInstall: (@MainActor @Sendable () async throws -> Void)? = nil) async throws -> URL? {
        let lease = try begin(game.titleID)
        defer { leases.end(game.titleID, token: lease) }
        progress?(.init(.verifying, kind: kind))
        let destination = try location(kind, for: game)
        try game.protectSaves(in: destination)
        if kind == .cache { try Self.recoverInterruptedFree(at: destination, for: game) }
        let parent = destination.deletingLastPathComponent()
        let volume = try CloudArchiveInventory.node(at: parent)
        let previous = try existingNode(at: destination)
        guard previous.map({ $0.st_mode & S_IFMT == S_IFDIR }) ?? true else {
            throw CloudArchiveError.unsafePath
        }
        let replacingReference = (backend as? RcloneStorageBackend)?.isReference == true && !onlyIfMissing
        let existing = previous != nil
            ? try CloudArchiveInventory.signature(destination, kind: kind) : nil
        guard existing?.hasExcludedFiles != true else { throw CloudArchiveError.excludedFiles }
        let skippedOnly = existing?.isSkippedOnly == true
        let artifact: Artifact
        if let manifest {
            guard manifest.titleID == game.titleID, let item = manifest.artifacts.first(where: { $0.kind == kind })
            else { throw CloudArchiveError.noRemoteCopy }
            artifact = item
        } else { artifact = try await remoteArtifact(kind, game) }
        if kind == .app, replacingReference, previous != nil || appReplacement != nil {
            guard let appReplacement else { throw CloudArchiveError.confirmationRequired }
            guard appReplacement.destination == destination,
                  appReplacement.localSignature == existing?.sha256,
                  appReplacement.remoteFingerprint == artifact.inventorySHA256 else { throw CloudArchiveError.localChanged }
        }
        if replacingReference, let existing, !existing.isSkippedOnly, let manifest,
           existing.latestFileWrite.map({ $0 >= (artifact.publishedAt ?? manifest.createdAt) }) == true {
            guard let older, older.prefersReference(manifest, for: kind),
                  try await copyStatuses(game, manifest: .success(older))[kind]?.state == .synchronized,
                  try CloudArchiveInventory.signature(destination, kind: kind).sha256 == existing.sha256
            else { throw CloudArchiveError.localChanged }
        }
        let partial = try kind == .cache && !skippedOnly && existing != nil
            && artifact.files.map { tree in
                guard let entries = try localFiles(at: destination, kind: .cache, snapshot: existing),
                      entries.count < tree.entries.count else { return false }
                return CloudArtifactFiles.isUsableSubset(entries, of: tree)
            } == true
        guard previous == nil || !onlyIfMissing || skippedOnly || partial else {
            throw CloudArchiveError.unsafePath
        }
        if let legacy = artifact.legacyObject(titleID: game.titleID) {
            try requireSpace(in: parent, bytes: artifact.unpackedSize, entries: artifact.entryCount, archive: legacy.size)
        }
        let stage = try staging(in: parent)
        var keepStage = false
        defer { if !keepStage { try? FileManager.default.removeItem(at: stage) } }
        let archive = stage.appendingPathComponent("item.aar")
        let incoming = stage.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        let resume: URL?
        if let files = artifact.files {
            resume = try await restoreFiles(files, kind: kind, titleID: game.titleID, destination: destination,
                                            incoming: incoming, progress: progress, partialCache: previous == nil || partial || skippedOnly,
                                            beforePartial: {
                try beforeMutation()
                try game.protectSaves(in: destination)
                guard try self.sameDirectory(volume, at: parent), try self.sameNode(previous, at: destination)
                else { throw CloudArchiveError.localChanged }
            })
        } else {
            resume = nil
            guard let legacy = artifact.legacyObject(titleID: game.titleID) else { throw CloudArchiveError.invalidManifest }
            try await backend.get(legacy.key, to: archive,
                                  progress: transfer(progress, phase: .downloading, kind: kind, total: legacy.size))
            progress?(.init(.verifying, kind: kind, downloadComplete: true))
            guard try CloudArchiveInventory.node(at: archive).st_size == legacy.size,
                  try CloudArchiveInventory.hashes(at: archive, includeMD5: false)["sha256"] == legacy.hashes["sha256"]
            else { throw StorageBackendError.hashMismatch }
            let entries = try await inventory(in: archive, kind: kind)
            guard entries.count == artifact.entryCount,
                  try CloudArchiveInventory.validate(entries, kind: kind) == artifact.unpackedSize
            else { throw CloudArchiveError.invalidArchive }
            try requireSpace(in: parent, bytes: artifact.unpackedSize, entries: artifact.entryCount)
            progress?(.init(.restoring, kind: kind, downloadComplete: true))
            _ = try await unpack(archive, to: incoming, kind: kind, titleID: game.titleID,
                                 listed: entries, fingerprint: artifact.inventorySHA256)
        }
        while true {
            if kind == .app { try await beforeAppInstall?() }
            guard try sameDirectory(volume, at: parent),
                  try sameNode(previous, at: destination) else { throw CloudArchiveError.localChanged }
            if replacingReference, let existing,
               try CloudArchiveInventory.signature(destination, kind: kind).sha256 != existing.sha256 {
                throw CloudArchiveError.localChanged
            }
            do { try beforeMutation() }
            catch CloudArchiveError.busy where kind == .app && beforeAppInstall != nil {
                // Finder may launch while the installed copy is being checked.
                continue
            }
            try Task.checkCancellation()
            break
        }
        // Never move the only local copy into staging. A crash during this loop
        // leaves the original visible; the next launch sees either whole tree.
        let kept = existing?.skippedRoots ?? []
        if !kept.isEmpty {
            let before = try CloudArchiveInventory.node(at: incoming)
            let copy = SaveFileIO().copy
            for name in kept {
                try Task.checkCancellation()
                try copy(destination.appendingPathComponent(name), incoming.appendingPathComponent(name))
            }
            var times = [before.st_atimespec, before.st_mtimespec]
            guard utimensat(AT_FDCWD, incoming.path, &times, AT_SYMLINK_NOFOLLOW) == 0,
                  try sameDirectory(volume, at: parent),
                  try sameNode(previous, at: destination) else { throw CloudArchiveError.localChanged }
            try beforeMutation()
        }
        try Task.checkCancellation()
        try game.protectSaves(in: destination, incomingApp: kind == .app ? incoming : nil)
        let flags = previous == nil ? RENAME_EXCL : RENAME_SWAP
        guard renamex_np(incoming.path, destination.path, UInt32(flags)) == 0 else {
            if errno == ENOSPC { throw CloudLibraryFailure.diskFull(at: parent) }
            throw CloudArchiveError.installFailed
        }
        if let resume { try? FileManager.default.removeItem(at: resume) }
        // An external writer may have added data while the old directory was still live.
        if previous != nil {
            keepStage = true
            try? FileManager.default.removeItem(at: archive)
            return incoming
        }
        return nil
    }

    package struct ReferenceAppReplacement: Equatable, Sendable {
        package let destination: URL
        fileprivate let localSignature: String
        fileprivate let remoteFingerprint: String
    }

    package struct ReferenceCopy: Equatable, Sendable {
        package let downloadBytes: Int64
        package let totalBytes: Int64
        package let legacy: Bool
        package let updatesLocal: Bool
        package let appReplacement: ReferenceAppReplacement?

        package init(downloadBytes: Int64, totalBytes: Int64, legacy: Bool, updatesLocal: Bool,
                     appReplacement: ReferenceAppReplacement? = nil) {
            self.downloadBytes = downloadBytes
            self.totalBytes = totalBytes
            self.legacy = legacy
            self.updatesLocal = updatesLocal
            self.appReplacement = appReplacement
        }
    }

    package func referenceCopy(_ kind: CloudArtifactKind, for game: CloudArchiveGame,
                               manifest: CloudGameManifest, status: CloudArtifactStatus?,
                               matchesOlderCopy: Bool = false) async throws -> ReferenceCopy? {
        guard let artifact = manifest.artifacts.first(where: { $0.kind == kind }),
              status?.state != .synchronized else { return nil }
        let worker = Task.detached(priority: .utility) { () throws -> ReferenceCopy? in
            let local = (try? self.location(kind, for: game)).flatMap { url in
                (try? CloudArchiveInventory.signature(url, kind: kind)).map { (url, $0) }
            }
            let updatesLocal = local.map { !$0.1.isSkippedOnly } == true
            if let (_, snapshot) = local, snapshot.hasExcludedFiles ||
                (updatesLocal && !matchesOlderCopy && status?.state != .cloudOnly &&
                 snapshot.latestFileWrite.map { $0 >= (artifact.publishedAt ?? manifest.createdAt) } == true) { return nil }
            let replacement = kind == .app && updatesLocal ? local.map {
                ReferenceAppReplacement(destination: $0.0, localSignature: $0.1.sha256,
                                        remoteFingerprint: artifact.inventorySHA256)
            } : nil
            if let tree = artifact.files {
                let entries = try local.flatMap { try self.localFiles(at: $0.0, kind: kind, snapshot: $0.1) } ?? []
                let changed = Self.changedFiles(in: tree, comparedWith: entries)
                return .init(downloadBytes: changed.reduce(0) { $0 + $1.size },
                             totalBytes: artifact.unpackedSize, legacy: false, updatesLocal: updatesLocal,
                             appReplacement: replacement)
            }
            guard let archivedBytes = artifact.size else { throw CloudArchiveError.invalidManifest }
            return .init(downloadBytes: archivedBytes, totalBytes: archivedBytes, legacy: true,
                         updatesLocal: updatesLocal, appReplacement: replacement)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    nonisolated func localFiles(at url: URL, kind: CloudArtifactKind, snapshot: CloudArchiveInventory.Snapshot? = nil,
                                strict: Bool = false)
        throws -> [CloudArtifactFiles.Entry]? {
        do {
            let snapshot = try snapshot ?? CloudArchiveInventory.signature(url, kind: kind)
            guard !snapshot.hasExcludedFiles, !snapshot.isSkippedOnly else { return nil }
            let entries = try CloudArtifactFiles.entries(at: url, snapshot: snapshot)
            guard try CloudArchiveInventory.signature(url, kind: kind).sha256 == snapshot.sha256 else {
                throw CloudArchiveError.localChanged
            }
            return entries
        } catch is CancellationError { throw CancellationError() }
        catch {
            if strict { throw CloudArchiveError.localChanged }
            return nil
        }
    }

    private func verify(_ artifact: Artifact, titleID: String) async throws {
        if let files = artifact.files {
            guard let uploader = backend as? RcloneStorageBackend else { throw StorageBackendError.backendUnavailable }
            try await files.verify(on: uploader)
        } else if let object = artifact.legacyObject(titleID: titleID) {
            try await backend.verify(object)
        } else {
            throw CloudArchiveError.invalidManifest
        }
    }

    private struct FreeRecovery: Codable {
        struct Identity: Codable, Equatable {
            let device: dev_t
            let inode: ino_t
            init(_ node: stat) { device = node.st_dev; inode = node.st_ino }
        }
        let target: Identity
        let name: String
        let roots: [String: Identity]
        static let fileName = "free-recovery.json"
    }

    private static let freeRecoveryLock = NSLock()

    private static func withFreeRecovery(target: URL, parent: URL, stage: URL, roots: [String],
                                         body: () throws -> Void) throws {
        freeRecoveryLock.lock()
        defer { freeRecoveryLock.unlock() }
        let identities = try roots.reduce(into: [String: FreeRecovery.Identity]()) { result, name in
            result[name] = .init(try CloudArchiveInventory.node(at: target.appendingPathComponent(name)))
        }
        let record = FreeRecovery(target: .init(try CloudArchiveInventory.node(at: target)),
                                  name: target.lastPathComponent, roots: identities)
        try SaveFiles.durableWrite(record, to: stage.appendingPathComponent(FreeRecovery.fileName))
        try SaveFiles.syncDirectory(parent)
        try body()
    }

    /// Resume a local, journalled Free up space without any remote access.
    public nonisolated static func recoverInterruptedFree(at target: URL, for game: CloudArchiveGame? = nil) throws {
        freeRecoveryLock.lock()
        defer { freeRecoveryLock.unlock() }
        let parent = target.deletingLastPathComponent().resolvingSymlinksInPath()
        let fm = FileManager.default
        guard fm.fileExists(atPath: parent.path) else { return }
        func node(_ url: URL) throws -> stat? {
            do { return try CloudArchiveInventory.node(at: url) }
            catch CloudArchiveError.localMissing { return nil }
        }
        for stage in try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
            guard stage.lastPathComponent.hasPrefix(".arcane-cloud-"),
                  UUID(uuidString: String(stage.lastPathComponent.dropFirst(".arcane-cloud-".count))) != nil,
                  let stageNode = try node(stage), stageNode.st_mode & S_IFMT == S_IFDIR else { continue }
            let file = stage.appendingPathComponent(FreeRecovery.fileName)
            guard try node(file) != nil else { continue }
            let record = try JSONDecoder().decode(FreeRecovery.self, from: SaveFiles.readRegular(file, limit: 16 * 1024 * 1024))
            guard record.name == target.lastPathComponent else { continue }
            let visible = parent.appendingPathComponent(record.name)
            try game?.protectSaves(in: visible)
            let bucket = stage.appendingPathComponent(record.name)
            if let bucketNode = try node(bucket) {
                guard bucketNode.st_mode & S_IFMT == S_IFDIR,
                      let targetNode = try node(visible), targetNode.st_mode & S_IFMT == S_IFDIR,
                      FreeRecovery.Identity(targetNode) == record.target else { throw CloudArchiveError.localChanged }
                for item in try fm.contentsOfDirectory(at: bucket, includingPropertiesForKeys: nil) {
                    let name = item.lastPathComponent
                    guard let expected = record.roots[name], let found = try node(item), expected == .init(found),
                          renamex_np(item.path, visible.appendingPathComponent(name).path, UInt32(RENAME_EXCL)) == 0 else {
                        throw CloudArchiveError.localChanged
                    }
                }
                try SaveFiles.syncDirectory(visible)
                guard rmdir(bucket.path) == 0 else { throw CloudArchiveError.localChanged }
            }
            try fm.removeItem(at: file)
            _ = rmdir(stage.path)
            try SaveFiles.syncDirectory(parent)
        }
    }

    private func moving(_ names: [String], from source: URL, to target: URL, keepStage: inout Bool,
                        publish: () throws -> Void) throws {
        guard !names.isEmpty else { return try publish() }
        let before = try CloudArchiveInventory.node(at: target)
        var moved: [String] = []
        do {
            for name in names {
                guard renamex_np(source.appendingPathComponent(name).path, target.appendingPathComponent(name).path,
                                 UInt32(RENAME_EXCL)) == 0 else { throw CloudArchiveError.installFailed }
                moved.append(name)
            }
            var times = [before.st_atimespec, before.st_mtimespec]
            guard utimensat(AT_FDCWD, target.path, &times, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw CloudArchiveError.installFailed
            }
            try publish()
        } catch {
            for name in moved.reversed() {
                if renamex_np(target.appendingPathComponent(name).path, source.appendingPathComponent(name).path,
                              UInt32(RENAME_EXCL)) != 0 { keepStage = true }
            }
            throw error
        }
    }

    private func begin(_ titleID: String) throws -> UUID {
        guard SaveLocation.validID(titleID) else { throw CloudArchiveError.unsafePath }
        guard let lease = leases.begin(titleID) else { throw CloudArchiveError.busy }
        return lease
    }

    private func remoteArtifact(_ kind: CloudArtifactKind, _ game: CloudArchiveGame) async throws -> Artifact {
        guard let artifact = try await latest(titleID: game.titleID)?.artifacts.first(where: { $0.kind == kind }) else {
            throw CloudArchiveError.noRemoteCopy
        }
        return artifact
    }

    private nonisolated func location(_ kind: CloudArtifactKind, for game: CloudArchiveGame) throws -> URL {
        guard let url = game.locations[kind], url.isFileURL else { throw CloudArchiveError.localMissing }
        let original = url.standardizedFileURL
        let parent = original.deletingLastPathComponent().resolvingSymlinksInPath()
        guard parent.path != "/", kind == .app ? original.pathExtension.lowercased() == "app"
              : original.lastPathComponent.uppercased() == "\(game.titleID)_BUILD" else {
            throw CloudArchiveError.unsafePath
        }
        return parent.appendingPathComponent(original.lastPathComponent, isDirectory: true)
    }

    nonisolated func existingNode(at url: URL) throws -> stat? {
        do { return try CloudArchiveInventory.node(at: url) }
        catch CloudArchiveError.localMissing { return nil }
    }

    private func sameNode(_ old: stat?, at url: URL) throws -> Bool {
        let current = try existingNode(at: url)
        guard let old, let current else { return old == nil && current == nil }
        return old.st_dev == current.st_dev && old.st_ino == current.st_ino
            && old.st_ctimespec.tv_sec == current.st_ctimespec.tv_sec && old.st_ctimespec.tv_nsec == current.st_ctimespec.tv_nsec
    }

    private nonisolated func sameDirectory(_ old: stat, at url: URL) throws -> Bool {
        try SaveFiles.safePath(url)
        let current = try CloudArchiveInventory.node(at: url)
        return current.st_mode & S_IFMT == S_IFDIR && old.st_dev == current.st_dev && old.st_ino == current.st_ino
    }

    private func staging(in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(".arcane-cloud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    func requireSpace(in directory: URL, bytes: Int64, entries: Int, archive: Int64 = 0) throws {
        guard let required = Self.requiredBytes(bytes: bytes, entries: entries, archive: archive),
              let free = capacity(directory), free >= required else {
            throw CloudArchiveError.insufficientSpace
        }
    }

    nonisolated static func requiredBytes(bytes: Int64, entries: Int, archive: Int64 = 0) -> Int64? {
        guard (0...CloudArchiveInventory.maximumEntries).contains(entries) else { return nil }
        let overhead = Int64(entries) * 16_384 + 1_048_576
        guard bytes >= 0, archive >= 0, bytes <= Int64.max - overhead, archive <= Int64.max - overhead - bytes
        else { return nil }
        return bytes + overhead + archive
    }

    private func inventory(in archive: URL, kind: CloudArtifactKind) async throws -> [CloudArchiveInventory.Entry] {
        let result = try await command("aa", ["list", "-i", archive.path, "-list-format", "json"])
        guard let entries = try? JSONDecoder().decode([CloudArchiveInventory.Entry].self, from: Data(result.utf8)),
              entries.count <= CloudArchiveInventory.maximumEntries else { throw CloudArchiveError.invalidArchive }
        _ = try CloudArchiveInventory.validate(entries, kind: kind)
        return entries
    }

    private func unpack(_ archive: URL, to incoming: URL, kind: CloudArtifactKind, titleID: String,
                        listed: [CloudArchiveInventory.Entry], fingerprint: String) async throws -> [String: String] {
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        _ = try await command("aa", ["extract", "-i", archive.path, "-d", incoming.path,
                                    "-exclude-field", "uid,gid,flg,acl"])
        let result = try CloudArchiveInventory.scan(incoming, kind: kind)
        guard ordered(result.entries) == ordered(listed), result.sha256 == fingerprint,
              !result.hasExcludedFiles, result.skippedRoots.isEmpty else { throw CloudArchiveError.invalidArchive }
        return kind == .app ? try await verifiedApp(incoming, titleID: titleID) : [:]
    }

    private func ordered(_ entries: [CloudArchiveInventory.Entry]) -> [CloudArchiveInventory.Entry] {
        entries.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
    }

    private func firstDifference(from initial: [CloudArchiveInventory.Entry], to listed: [CloudArchiveInventory.Entry])
        -> (String, CloudArchiveError.UploadDifference)? {
        let before = ordered(initial), after = ordered(listed)
        for (old, new) in zip(before, after) where old != new {
            if old.path != new.path {
                return old.path.utf8.lexicographicallyPrecedes(new.path.utf8)
                    ? (old.path, .removed) : (new.path, .added)
            }
            if old.type != new.type { return (old.path, .type) }
            if old.size != new.size { return (old.path, .size) }
            if old.link != new.link { return (old.path, .linkTarget) }
            return (old.path, .permissions)
        }
        if before.count > after.count { return (before[after.count].path, .removed) }
        if after.count > before.count { return (after[before.count].path, .added) }
        return nil
    }

    private func checkUpload(_ source: URL, parent: stat, snapshot: CloudArchiveInventory.Snapshot,
                             kind: CloudArtifactKind) throws {
        guard (try? sameDirectory(parent, at: source.deletingLastPathComponent())) == true else {
            throw CloudArchiveError.uploadMismatch(kind, path: "..", reason: .parentDirectory)
        }
        let current = try CloudArchiveInventory.signature(source, kind: kind)
        if let (path, reason) = firstDifference(from: snapshot.entries, to: current.entries) {
            throw CloudArchiveError.uploadMismatch(kind, path: path.isEmpty ? "." : path, reason: reason)
        }
        guard current.sha256 == snapshot.sha256, !current.hasExcludedFiles else { throw CloudArchiveError.localChanged }
    }

    func verifiedApp(_ app: URL, titleID: String) async throws -> [String: String] {
        let info = try ImportService.verifiedIdentity(of: app, titleID: titleID)
        _ = try await command("codesign", BuildOutputInstaller.signatureArguments(for: app), failure: .invalidApp)
        return info.compactMapValues { $0 as? String }
    }

    private func shaderChain(at source: URL, kind: CloudArtifactKind) -> String? {
        LocalBuildCache.chain(in: source.appendingPathComponent(kind == .app ? "Contents/Resources/msl" : "shader/cache"))
    }

    private static func isHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func command(_ tool: String, _ args: [String], failure: CloudArchiveError = .invalidArchive) async throws -> String {
        let result = try await SystemCommandRunner().runCancellable(URL(fileURLWithPath: "/usr/bin/" + tool), args, environment: nil)
        guard result.status == 0 else { throw failure }
        return result.stdout
    }

    private func put(_ file: URL, object: StorageObject, progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        do { try await backend.put(file, as: object, progress: progress) }
        catch StorageBackendError.alreadyExists { /* Reuse only after checking the exact object. */ }
        try await backend.verify(object)
    }

    func transfer(_ progress: Progress?, phase: CloudArchiveProgress.Phase, kind: CloudArtifactKind,
                          total: Int64) -> (@Sendable (StorageProgress) -> Void)? {
        guard let progress else { return nil }
        progress(.init(phase, kind: kind, transfer: StorageProgress(bytesTransferred: 0, totalBytes: total)))
        return { value in
            progress(value.isVerifying ? .init(.verifying, kind: kind) : .init(phase, kind: kind, transfer: value))
        }
    }
}
