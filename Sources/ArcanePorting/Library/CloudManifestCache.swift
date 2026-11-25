import CryptoKit
import Darwin
import Foundation
import NXLibraryCore
import Synchronization

/// Cloud game records already read, by the SHA-256 their own name carries: a record never changes under its name, so one
/// kept here and still matching it is the one Drive has. Only listings use it; a transfer reads its record again.
final class CloudManifestCache: Sendable {
    static let shared = CloudManifestCache(directory: AppData.cacheRoot.appendingPathComponent("CloudRecords", isDirectory: true))
    private let directory: URL
    private let capacity: Int
    private let read = Mutex([StorageObject: CloudGameManifest]())
    private static let readLimit = 512

    init(directory: URL, capacity: Int = 64 * 1024 * 1024) {
        self.directory = directory
        self.capacity = capacity
    }

    private func file(_ sha256: String) -> URL { directory.appendingPathComponent(sha256 + ".json") }

    /// A record this app already read and checked, for the very file Drive lists: same place, size and MD5.
    func manifest(_ object: StorageObject) -> CloudGameManifest? {
        object.md5 == nil ? nil : read.withLock { $0[object] }
    }

    func keep(_ manifest: CloudGameManifest, for object: StorageObject) {
        guard object.md5 != nil else { return }
        read.withLock {
            if $0.count >= Self.readLimit { $0.removeAll() }
            $0[object] = manifest
        }
    }

    /// The kept bytes, when they are still those of this name and Drive still lists them.
    func data(_ sha256: String, of object: StorageObject, limit: Int) -> Data? {
        guard let data = try? SaveFiles.readRegular(file(sha256), limit: limit), Int64(data.count) == object.size,
              CloudArchiveInventory.hex(SHA256.hash(data: data)) == sha256,
              object.md5.map({ $0 == CloudArchiveInventory.hex(Insecure.MD5.hash(data: data)) }) ?? true else { return nil }
        return data
    }

    func store(_ data: Data, sha256: String) {
        let fm = FileManager.default
        guard data.count <= capacity,
              (try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil
        else { return }
        try? data.write(to: file(sha256), options: .atomic)
        trim()
    }

    /// The oldest records leave first; a reader that misses one reads it from Drive again.
    private func trim() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? [])
            .compactMap { url in (try? url.resourceValues(forKeys: keys)).map { (url, $0.contentModificationDate ?? .distantPast, $0.fileSize ?? 0) } }
        var total = files.reduce(0) { $0 + $1.2 }
        for (url, _, size) in files.sorted(by: { $0.1 < $1.1 }) where total > capacity {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
