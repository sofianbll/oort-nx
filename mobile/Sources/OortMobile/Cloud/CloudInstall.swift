import Foundation
import OortCore
import ShellHost

/// Puts a build that was downloaded and checked where the app loads its games from. Saves and the cloud are never touched.
struct CloudInstall: Sendable {
    /// What stays beside an installed build: which files are its own, to replace or remove them later.
    struct Receipt: Codable { let version: String, data: [String] }

    let store: ShelfStore
    let crypto: ShelfCrypto
    /// `Documents/Frameworks` and `Documents/games`.
    let frameworks: URL
    let games: URL
    let check: @Sendable (URL) -> String?

    private var fm: FileManager { .default }
    private func receiptFile(_ title: String, _ digest: String) -> URL {
        store.root.appendingPathComponent(title).appendingPathComponent(digest).appendingPathComponent("receipt.json")
    }
    func framework(_ title: String) -> URL { frameworks.appendingPathComponent("DmGame\(title.uppercased()).framework", isDirectory: true) }

    /// The digest of each title that is installed from here: its receipt, and its framework still there.
    func installed() -> [String: (digest: String, version: String)] {
        var result: [String: (digest: String, version: String)] = [:]
        for title in (try? fm.contentsOfDirectory(atPath: store.root.path)) ?? [] where ShelfNames.isTitleID(title) && fm.fileExists(atPath: framework(title).path) {
            for digest in digests(title) {
                guard let data = try? Data(contentsOf: receiptFile(title, digest)), let receipt = try? JSONDecoder().decode(Receipt.self, from: data) else { continue }
                result[title] = (digest, receipt.version)
            }
        }
        return result
    }

    /// `data/…` goes beside the game's saves, the framework where games are loaded from, whole or not at all.
    func install(_ build: ShelfBuild, freeSpace: @escaping (URL) -> Int64?) throws {
        let source = store.visible(build), package = source.appendingPathComponent(build.package, isDirectory: true)
        let folder = games.appendingPathComponent(build.titleID, isDirectory: true)
        var data: [(from: URL, name: String)] = []
        for entry in build.entries {
            let file = source.appendingPathComponent(entry.path)
            if entry.path.hasPrefix(build.package + "/") {
                // The code is read again just before it is used.
                guard try digest(file) == entry.sha256 else { throw ShelfError.wrongDigest }
            } else {
                guard entry.path.hasPrefix("data/"), !GameDeletion.isSave(String(entry.path.dropFirst(5)).lowercased()) else { throw ShelfError.unsafeName }
                let name = String(entry.path.dropFirst(5))
                let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
                guard size == entry.size else { throw ShelfError.filesMissing }
                data.append((file, name))
            }
        }
        guard let manifest = try? GameManifest.parse(Data(contentsOf: package.appendingPathComponent("game.manifest.json"))),
              manifest.titleID.uppercased() == build.titleID.uppercased() else { throw FrameworkImport.Failure.notAGame }
        if let refusal = check(package.appendingPathComponent(manifest.frameworkExecutable)) { throw FrameworkImport.Failure.wrongSigner(refusal) }
        let previous = previousReceipts(build)
        // Beside the game first: the swap that follows is only renames on one volume.
        let staging = folder.appendingPathComponent(".oort-new", isDirectory: true)
        try? fm.removeItem(at: staging)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for (from, name) in data {
                let to = staging.appendingPathComponent(name)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: from, to: to)
            }
            try FrameworkImport.run(package, into: frameworks, freeSpace: freeSpace, check: check)
        } catch {
            // Back where it was: the player can try again without downloading.
            for (from, name) in data where !fm.fileExists(atPath: from.path) { try? fm.moveItem(at: staging.appendingPathComponent(name), to: from) }
            try? fm.removeItem(at: staging)
            throw error
        }
        do {
            for (_, name) in data {
                let to = folder.appendingPathComponent(name), from = staging.appendingPathComponent(name)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: to.path) { _ = try fm.replaceItemAt(to, withItemAt: from) } else { try fm.moveItem(at: from, to: to) }
                BackupExclusion.exclude(to)
            }
            try? fm.removeItem(at: staging)
            let names = data.map(\.name)
            for name in Set(previous.flatMap(\.data)).subtracting(names) { remove(name, in: folder) }
            try JSONEncoder().encode(Receipt(version: build.gameVersion, data: names)).write(to: receiptFile(build.titleID, build.digest), options: .atomic)
        } catch { throw ShelfError.localFile }
        // The framework was copied (the file system shares its blocks): the download goes.
        for name in (try? fm.contentsOfDirectory(atPath: source.path)) ?? [] where name != "receipt.json" { try? fm.removeItem(at: source.appendingPathComponent(name)) }
        for digest in digests(build.titleID) where digest != build.digest { try? fm.removeItem(at: store.root.appendingPathComponent(build.titleID).appendingPathComponent(digest)) }
    }

    /// What was downloaded and not installed.
    func discard(_ title: String) {
        let installed = installed()[title]?.digest
        for digest in digests(title) where digest != installed { try? fm.removeItem(at: store.root.appendingPathComponent(title).appendingPathComponent(digest)) }
        let incoming = store.root.appendingPathComponent(".incoming")
        for name in (try? fm.contentsOfDirectory(atPath: incoming.path)) ?? [] where name.hasPrefix(title + "-") { try? fm.removeItem(at: incoming.appendingPathComponent(name)) }
    }

    /// After the app removed the game itself: the receipt goes too.
    func forget(_ title: String) { try? fm.removeItem(at: store.root.appendingPathComponent(title)) }

    func isDownloaded(_ build: ShelfBuild) -> Bool {
        fm.fileExists(atPath: store.visible(build).appendingPathComponent(build.package).path)
    }

    /// What the downloads that are not installed take.
    func waitingBytes() -> Int64 {
        guard let walk = fm.enumerator(at: store.root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walk { total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        return total
    }

    private func digests(_ title: String) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: store.root.appendingPathComponent(title).path)) ?? []).filter { ShelfNames.isHex($0, count: 64) }
    }

    private func previousReceipts(_ build: ShelfBuild) -> [Receipt] {
        digests(build.titleID).compactMap { try? JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptFile(build.titleID, $0))) }
    }

    private func remove(_ name: String, in folder: URL) {
        guard ShelfNames.isSafePath(name), !GameDeletion.isSave(name.lowercased()) else { return }
        try? fm.removeItem(at: folder.appendingPathComponent(name))
    }

    private func digest(_ file: URL) throws -> String {
        guard let input = try? FileHandle(forReadingFrom: file) else { throw ShelfError.filesMissing }
        defer { try? input.close() }
        var hasher = crypto.sha256(), more = true
        while more {
            try autoreleasepool {
                guard let data = try input.read(upToCount: 1 << 20), !data.isEmpty else { more = false; return }
                hasher.update(data)
            }
        }
        return hasher.hex()
    }
}
