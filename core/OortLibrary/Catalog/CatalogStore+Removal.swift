import Foundation

extension CatalogStore {
    private var removalJournal: URL { directory.appendingPathComponent(LibraryPaths.removalJournal) }

    /// A copy made before path repair may contain the old library's live journal. Keep its bytes, never replay it.
    /// The caller holds the copy's catalog lock.
    static func preserveInheritedRemoval(in root: URL, from old: URL) throws {
        let journal = root.appendingPathComponent(LibraryPaths.removalJournal)
        guard let data = try LibraryPaths.read(journal) else { return }
        let targetsOld = (try? JSONDecoder().decode(RemovalPaths.self, from: data))?.items.contains {
            LibraryMove.contains($0.source, in: old) || LibraryMove.contains($0.target, in: old)
        } == true
        guard targetsOld || (try? LibraryPaths.read(old.appendingPathComponent(LibraryPaths.removalJournal))) == data else { return }
        var archive = root.appendingPathComponent(LibraryPaths.inheritedRemoval)
        if try RemovalIdentity.read(archive) != nil {
            archive = root.appendingPathComponent(UUID().uuidString + "-" + LibraryPaths.inheritedRemoval)
        }
        guard renamex_np(journal.path, archive.path, UInt32(RENAME_EXCL)) == 0 else {
            throw CatalogRemovalRecovery(journal: journal)
        }
        try CatalogPublication.synchronize(root)
    }

    func refusePendingRemoval() throws {
        if try RemovalIdentity.read(removalJournal) != nil { throw CatalogRemovalRecovery(journal: removalJournal) }
    }

    func removeFiles(from original: CatalogDocument, saving draft: CatalogDocument, gameID: UUID, files: [URL],
                     beforeTrash: () throws -> Void) throws -> CatalogDocument {
        try locked {
            try recoverRemoval()
            guard try removalDocument() == original,
                  let index = original.games.firstIndex(where: { $0.id == gameID }) else {
                throw CatalogStoreError.staleRevision
            }
            let fm = FileManager.default
            let moveRevision = UUID()
            let items: [RemovalIntent.Item]
            do {
                items = try files.enumerated().map { index, file in
                    guard file.isFileURL else { throw CatalogStoreError.staleRevision }
                    let parent = file.deletingLastPathComponent().resolvingSymlinksInPath()
                    let source = parent.appendingPathComponent(file.lastPathComponent)
                    let trash = try removalTrashDirectory(source).resolvingSymlinksInPath()
                    let bucket = trash.appendingPathComponent("Oort NX - \(moveRevision)-\(index)")
                    let target = bucket.appendingPathComponent(source.lastPathComponent)
                    guard let identity = try RemovalIdentity.read(source),
                          let origin = try RemovalIdentity.read(parent), origin.isDirectory,
                          let trashIdentity = try RemovalIdentity.read(trash), trashIdentity.isDirectory,
                          origin.device == identity.device, trashIdentity.device == identity.device,
                          !source.path.hasPrefix(trash.path + "/"), !trash.path.hasPrefix(source.path + "/")
                    else { throw CatalogRemovalFailure.trashUnavailable }
                    return .init(source: source, target: target, identity: identity, origin: origin, trash: trashIdentity)
                }
            } catch { throw CatalogRemovalFailure.trashUnavailable }
            guard Set(items.map(\.identity)).count == items.count else { throw CatalogRemovalFailure.duplicateFiles }
            let intent = RemovalIntent(original: original.revision, moved: moveRevision, restored: UUID(),
                                       record: original.games[index], index: index,
                                       exclusions: original.cloudImportExclusions, items: items)
            do {
                let bytes = try JSONEncoder().encode(intent)
                guard bytes.count <= RemovalIntent.maximumBytes else { throw CatalogRemovalFailure.writeFailed }
                let stage = try CatalogPublication.stage(bytes, in: directory)
                defer { try? fm.removeItem(at: stage) }
                try CatalogPublication.atomic.publish(stage, removalJournal, false) {}
                try CatalogPublication.synchronize(directory)
            } catch {
                try refusePendingRemoval()
                throw CatalogRemovalFailure.writeFailed
            }
            let saved: CatalogDocument
            do {
                saved = try saveLocked(draft, expectedRevision: original.revision, revision: moveRevision)
                for item in items {
                    try beforeTrash()
                    try item.checkParents()
                    guard try RemovalIdentity.read(item.source) == item.identity else {
                        throw CatalogStoreError.staleRevision
                    }
                    guard mkdir(item.bucket.path, 0o700) == 0 else { throw CatalogRemovalFailure.trashUnavailable }
                    try CatalogPublication.synchronize(item.trashRoot)
                    guard try RemovalIdentity.read(item.source) == item.identity else {
                        throw CatalogStoreError.staleRevision
                    }
                    try item.rename(from: item.source, to: item.target)
                    guard try RemovalIdentity.read(item.target) == item.identity else {
                        throw CatalogStoreError.staleRevision
                    }
                }
                try verifyTrashed(items)
            } catch {
                try recoverRemoval()
                if error is CatalogStoreError || error is CatalogRemovalFailure { throw error }
                throw CatalogRemovalFailure.writeFailed
            }
            do { try finishRemoval() }
            catch { throw CatalogRemovalRecovery(journal: removalJournal) }
            return saved
        }
    }

    private func verifyTrashed(_ items: [RemovalIntent.Item]) throws {
        for item in items {
            try item.checkParents()
            guard try RemovalIdentity.read(item.target) == item.identity,
                  try RemovalIdentity.read(item.source) == nil else { throw CatalogStoreError.staleRevision }
        }
    }

    // Always undo an interrupted removal, including one that moved all files but still has its intent.
    func recoverRemoval() throws {
        do {
            guard try RemovalIdentity.read(removalJournal) != nil else { return }
            if LibraryMove.moved(directory) {
                let previous = directory.deletingLastPathComponent().appendingPathComponent("NXLibrary", isDirectory: true)
                try Self.preserveInheritedRemoval(in: directory, from: previous)
                if try RemovalIdentity.read(removalJournal) == nil { return }
            }
            let data = try InstallationFileSnapshot.read(at: removalJournal, maximumBytes: RemovalIntent.maximumBytes).data
            let intent = try kinds.decoder().decode(RemovalIntent.self, from: data)
            var catalog = try removalDocument()
            guard intent.version == 1, intent.index >= 0,
                  [intent.original, intent.moved, intent.restored].contains(catalog.revision)
            else { throw CatalogStoreError.staleRevision }
            let counts = Dictionary(grouping: intent.items, by: \.identity).mapValues(\.count)
            func undo(_ item: RemovalIntent.Item, deferringAliases: Bool) throws -> Bool {
                try item.checkParents()
                let source = try RemovalIdentity.read(item.source)
                let target = try RemovalIdentity.read(item.target)
                if source == item.identity && target == nil {
                    // A previous recovery may have stopped just after the rename.
                    try CatalogPublication.synchronize(item.source.deletingLastPathComponent())
                    if try RemovalIdentity.read(item.bucket)?.isDirectory == true {
                        try CatalogPublication.synchronize(item.bucket)
                    }
                } else if catalog.revision == intent.moved, source == nil, target == item.identity {
                    try item.rename(from: item.target, to: item.source)
                    guard try RemovalIdentity.read(item.source) == item.identity else { throw CatalogStoreError.staleRevision }
                } else if deferringAliases, catalog.revision == intent.moved, source == nil, target == nil,
                          counts[item.identity, default: 0] > 1 {
                    // Old plans could put the only directory entry in another item's bucket.
                    return false
                } else { throw CatalogStoreError.staleRevision }
                if rmdir(item.bucket.path) == 0 { try CatalogPublication.synchronize(item.trashRoot) }
                return true
            }
            let deferred = try intent.items.reversed().filter { try !undo($0, deferringAliases: true) }
            for item in deferred { _ = try undo(item, deferringAliases: false) }
            if catalog.revision == intent.moved {
                catalog.games.removeAll { $0.id == intent.record.id }
                catalog.games.insert(intent.record, at: min(intent.index, catalog.games.count))
                catalog.cloudImportExclusions = intent.exclusions
                _ = try saveLocked(catalog, expectedRevision: intent.moved, revision: intent.restored)
            }
            // Includes a rollback catalog publication whose directory flush previously failed.
            try CatalogPublication.synchronize(directory)
            try finishRemoval()
        } catch { throw CatalogRemovalRecovery(journal: removalJournal) }
    }

    private func finishRemoval() throws {
        try FileManager.default.removeItem(at: removalJournal)
        try CatalogPublication.synchronize(directory)
    }
}

private struct RemovalPaths: Decodable {
    struct Item: Decodable { let source: URL; let target: URL }
    let items: [Item]
}

private struct RemovalIntent: Codable {
    static let maximumBytes = 16 * 1024 * 1024
    var version = 1
    let original: UUID
    let moved: UUID
    let restored: UUID
    let record: CatalogGame
    let index: Int
    let exclusions: Set<String>?
    let items: [Item]

    struct Item: Codable {
        let source: URL
        let target: URL
        let identity: RemovalIdentity
        let origin: RemovalIdentity
        let trash: RemovalIdentity
        var bucket: URL { target.deletingLastPathComponent() }
        var trashRoot: URL { bucket.deletingLastPathComponent() }

        func checkParents() throws {
            guard try RemovalIdentity.read(source.deletingLastPathComponent()) == origin,
                  try RemovalIdentity.read(trashRoot) == trash else { throw CatalogStoreError.staleRevision }
            if let current = try RemovalIdentity.read(bucket) {
                guard current.isDirectory, current.device == trash.device else { throw CatalogStoreError.staleRevision }
            }
        }

        func rename(from: URL, to: URL) throws {
            guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 else {
                throw CatalogRemovalFailure.trashUnavailable
            }
            try CatalogPublication.synchronize(bucket)
            try CatalogPublication.synchronize(source.deletingLastPathComponent())
        }
    }
}

private struct RemovalIdentity: Codable, Hashable {
    let device: dev_t
    let inode: ino_t
    let type: mode_t
    let birthSeconds: Int
    let birthNanoseconds: Int
    var isDirectory: Bool { type == mode_t(S_IFDIR) }

    static func read(_ url: URL) throws -> Self? {
        var status = stat()
        if lstat(url.path, &status) != 0 {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return Self(device: status.st_dev, inode: status.st_ino, type: status.st_mode & mode_t(S_IFMT),
                    birthSeconds: status.st_birthtimespec.tv_sec, birthNanoseconds: status.st_birthtimespec.tv_nsec)
    }
}

package enum CatalogRemovalFailure: LocalizedError {
    case trashUnavailable, writeFailed, gameBusy, duplicateFiles

    package var errorDescription: String? {
        switch self {
        case .trashUnavailable: return L10n.text("Trash is unavailable on this volume. The files were kept.")
        case .writeFailed: return L10n.text("The removal could not be saved. The files were kept.")
        case .gameBusy: return L10n.text("Close the game before removing its files. Do not launch it from Finder during the removal.")
        case .duplicateFiles: return L10n.text("Several selected paths refer to the same file. The files were kept.")
        }
    }
}

package struct CatalogRemovalRecovery: LocalizedError {
    let journal: URL

    package var errorDescription: String? {
        L10n.format("Removal could not be fully undone. Recovery record: %@", [journal.path])
    }
}
