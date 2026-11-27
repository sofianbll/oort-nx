import Darwin
import Foundation
import OortLibrary

extension CloudGameArchive {
    nonisolated static func changedFiles(in tree: CloudArtifactFiles.Tree, comparedWith local: [CloudArtifactFiles.Entry])
        -> [CloudArtifactFiles.Entry] {
        let known = Dictionary(uniqueKeysWithValues: local.map { ($0.path, $0) })
        return tree.entries.filter { known[$0.path] != $0 }
    }

    func restoreFiles(_ tree: CloudArtifactFiles.Tree, kind: CloudArtifactKind, titleID: String,
                      destination: URL, incoming: URL, progress: Progress?, partialCache: Bool,
                      beforePartial: () throws -> Void) async throws -> URL {
        guard let downloader = backend as? RcloneStorageBackend else { throw StorageBackendError.backendUnavailable }
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let token = CloudArchiveInventory.fingerprintKey(destination, kind: kind, portable: true)
        let digest = try CloudArtifactFiles.digest(tree.entries)
        let resume = parent.appendingPathComponent(".arcane-cloud-files-\(token)-\(digest)", isDirectory: true)
        try SaveFiles.safePath(resume)
        let existing = try existingNode(at: resume)
        if let existing {
            guard existing.st_mode & S_IFMT == S_IFDIR, existing.st_uid == getuid(), existing.st_mode & 0o777 == 0o700
            else { throw CloudArchiveError.unsafePath }
        }
        let local = Dictionary(uniqueKeysWithValues: (try localFiles(at: destination, kind: kind) ?? []).map { ($0.path, $0) })
        var pending: [CloudArtifactFiles.Entry] = []
        var reused: [String: URL] = [:]
        var reserved: Int64 = 0
        for entry in tree.entries {
            let raw = resume.appendingPathComponent(entry.path)
            if try entry.matches(raw) { continue }
            if let node = try existingNode(at: raw) {
                // This is our private download directory, never the installed copy.
                guard node.st_mode & S_IFMT == S_IFREG else { throw CloudArchiveError.unsafePath }
                try fm.removeItem(at: raw)
            }
            if local[entry.path] == entry {
                reused[entry.path] = destination.appendingPathComponent(entry.relative)
                if !entry.isLink { reserved += entry.size }
            } else { pending.append(entry) }
        }
        let bytes = pending.reduce(Int64(0)) { $0 + $1.size }
        try requireSpace(in: parent, bytes: bytes + reserved, entries: tree.entries.count)
        try await tree.verify(on: downloader)
        if existing == nil {
            try fm.createDirectory(at: resume, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        do {
            let report = transfer(progress, phase: .downloading, kind: kind, total: bytes)
            if downloader.isReference {
                // Fetch sidecars as plain bytes. The assembler checks the MD5 and confines link targets.
                try await downloader.downloadFiles(pending.filter(\.isLink).map(\.path), from: tree.key, to: resume, progress: nil)
                try await downloader.downloadFiles(pending.filter { !$0.isLink }.map(\.path), from: tree.key, to: resume,
                                                   decodeLinks: true, progress: report)
            } else {
                try await downloader.downloadFiles(pending.map(\.path), from: tree.key, to: resume, progress: report)
            }
        } catch {
            if kind == .cache && partialCache {
                let ready = await Task.detached(priority: .utility) {
                    pending.filter {
                        !$0.isLink && (try? $0.matches(resume.appendingPathComponent($0.path))) == true
                    }
                }.value
                if !ready.isEmpty {
                    try beforePartial()
                    for entry in ready {
                        let file = destination.appendingPathComponent(entry.path)
                        try SaveFiles.makeDirectory(file.deletingLastPathComponent())
                        guard renamex_np(resume.appendingPathComponent(entry.path).path, file.path, UInt32(RENAME_EXCL)) == 0
                            || errno == EEXIST else {
                            if errno == ENOSPC { throw CloudLibraryFailure.diskFull(at: parent) }
                            throw CloudArchiveError.installFailed
                        }
                    }
                }
            }
            throw error
        }
        progress?(.init(.verifying, kind: kind, downloadComplete: true))
        try fm.createDirectory(at: incoming, withIntermediateDirectories: false)
        for entry in tree.entries {
            try Task.checkCancellation()
            let raw = resume.appendingPathComponent(entry.path)
            let target = incoming.appendingPathComponent(entry.relative)
            try SaveFiles.makeDirectory(target.deletingLastPathComponent())
            if let old = reused[entry.path] {
                try SaveFiles.safePath(old.deletingLastPathComponent())
                if entry.isLink {
                    let targetText = try fm.destinationOfSymbolicLink(atPath: old.path)
                    let sidecar = incoming.appendingPathComponent(entry.path)
                    try Data(targetText.utf8).write(to: sidecar, options: .withoutOverwriting)
                    guard try entry.matches(sidecar) else { throw StorageBackendError.hashMismatch }
                    try CloudArtifactFiles.restoreLink(sidecar, to: target, relative: entry.relative, kind: kind)
                    try fm.removeItem(at: sidecar)
                } else {
                    try SaveFiles.safePath(old)
                    guard clonefile(old.path, target.path, UInt32(CLONE_NOFOLLOW)) == 0 ||
                            copyfile(old.path, target.path, nil, copyfile_flags_t(COPYFILE_DATA | COPYFILE_EXCL | COPYFILE_NOFOLLOW)) == 0
                    else {
                        if errno == ENOSPC { throw CloudLibraryFailure.diskFull(at: parent) }
                        throw StorageBackendError.hashMismatch
                    }
                    guard try entry.matches(target) else { throw StorageBackendError.hashMismatch }
                }
            } else {
                guard try entry.matches(raw) else { throw StorageBackendError.hashMismatch }
                if entry.isLink {
                    try CloudArtifactFiles.restoreLink(raw, to: target, relative: entry.relative, kind: kind)
                } else {
                    guard link(raw.path, target.path) == 0 else {
                        if errno == ENOSPC { throw CloudLibraryFailure.diskFull(at: parent) }
                        throw CloudArchiveError.installFailed
                    }
                }
            }
        }
        if kind == .app {
            let entries = try CloudArchiveInventory.signature(incoming, kind: .app).entries
            try ImportService.repairAdoptionCopy(incoming, entries: entries)
            _ = try await verifiedApp(incoming, titleID: titleID)
        }
        progress?(.init(.restoring, kind: kind, downloadComplete: true))
        return resume
    }
}
