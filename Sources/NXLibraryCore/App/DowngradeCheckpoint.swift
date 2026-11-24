import CryptoKit
import Darwin
import Foundation

/// The first writer of a new data generation must leave the old launcher data readable elsewhere.
package enum DowngradeCheckpoint {
    private static let maximumBytes = 128 * 1024 * 1024
    private static let maximumEntries = 8_192
    private static let fixedFiles = [
        "catalog.json", "catalog.json.bak", "catalog-removal-pending.json", "library.json", "library.json.bak",
        "settings.json", "profiles.json", "profiles-active", "play-sessions.json", "play-sessions-totals.json",
        SessionHistoryState.filename, "cloud-transfer-queue.json", "cloud-library-move.json", "activity-results.json",
        "build-queue.json", "metadata-picks.json", "integrations/steam/metadata-picks.json",
        "integrations/steam/personal/personal.json", "integrations/steam/playtime-baselines.json",
    ]
    private static let preferenceKeys: Set<String> = [
        CloudLibraryPreference.storageKey, CloudLibraryPreference.enabledKey, CloudLibraryPreference.sourcesRootKey,
        CloudLibraryPreference.executableKey, CloudLibraryPreference.referenceFolderKey, "cloudSaves.folder",
        "NXLibrary_CloudLastKnownAvailability", "NXLibrary_SetupSteamChoice", "NXLibrary_SetupSteamExplicitChoice",
    ]

    private struct Item: Codable, Equatable {
        var data: Data
        var sha256: Data
        init(_ data: Data) {
            self.data = data
            sha256 = Data(SHA256.hash(data: data))
        }
        var verified: Bool { sha256 == Data(SHA256.hash(data: data)) }
    }
    private struct Snapshot: Codable, Equatable {
        var generation: Int
        var id = UUID()
        var files: [String: Item]
        var preferences: Item?
        var needsWarning: Bool { !files.isEmpty || preferences != nil }
    }

    /// Returns true only when launch may continue. A retry never replaces a verified checkpoint of this generation.
    package static func prepare(in root: URL, generation: Int = 1, acceptingWarning: Bool = false,
                                preferences: () throws -> [String: Any]) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try requireDirectory(root)
        let folder = root.appendingPathComponent("DowngradeProtection", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try requireDirectory(folder)
        let fd = open(folder.appendingPathComponent(".lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }
        defer { close(fd) }
        _ = try InstallationFileObservation.capture(fileDescriptor: fd, url: folder.appendingPathComponent(".lock"))
        guard flock(fd, LOCK_EX) == 0 else { throw posixError() }

        let current = folder.appendingPathComponent("checkpoint.plist")
        let previous = folder.appendingPathComponent("previous.plist")
        let acknowledged = folder.appendingPathComponent("acknowledged")
        let old = try readSnapshot(current)
        let snapshot: Snapshot
        if let old, old.generation == generation {
            snapshot = old
        } else {
            guard old.map({ $0.generation < generation }) ?? true else { throw InstallationFileReadError.unsafeFile }
            snapshot = try capture(in: root, generation: generation, preferences: preferences)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try publish(try encoder.encode(snapshot), to: current) { stage in
                guard try readSnapshot(stage) == snapshot else { throw InstallationFileReadError.sourceChanged }
                if old != nil {
                    _ = try readSnapshot(previous) // Never replace an unexpected entry.
                    guard rename(current.path, previous.path) == 0 else { throw posixError() }
                    try CatalogPublication.synchronize(folder)
                }
            }
        }
        // Also synchronize a checkpoint visible after an interrupted publication before allowing live writes.
        try CatalogPublication.synchronize(folder)
        try CatalogPublication.synchronize(root)
        guard snapshot.needsWarning else { return true }
        let token = Data(snapshot.id.uuidString.utf8)
        if try read(acknowledged, limit: token.count)?.data == token { return true }
        guard acceptingWarning else { return false }
        try publish(token, to: acknowledged) { _ in }
        return true
    }

    private static func capture(in root: URL, generation: Int,
                                preferences: () throws -> [String: Any]) throws -> Snapshot {
        let values = try preferences().filter { preferenceKeys.contains($0.key) }
        let plist = try values.isEmpty ? nil : PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        var remaining = maximumBytes - (plist?.count ?? 0)
        var files: [String: Item] = [:]
        let names = try fileNames(under: root)
        var observations: [InstallationFileObservation] = []
        for name in names {
            let path = root.appendingPathComponent(name)
            guard let bytes = try read(path, limit: remaining) else { throw InstallationFileReadError.sourceChanged }
            files[name] = Item(bytes.data)
            remaining -= bytes.data.count
            observations.append(bytes.observation)
        }
        guard try fileNames(under: root) == names, try NSDictionary(dictionary: preferences().filter {
            preferenceKeys.contains($0.key)
        }).isEqual(to: values) else { throw InstallationFileReadError.sourceChanged }
        for observation in observations { try observation.verifyUnchanged() }
        return Snapshot(generation: generation, files: files, preferences: plist.map(Item.init))
    }

    private static func fileNames(under root: URL) throws -> [String] {
        let fm = FileManager.default
        func present(_ name: String) throws -> URL? {
            let parts = name.split(separator: "/")
            var path = root
            for (index, part) in parts.enumerated() {
                path.appendPathComponent(String(part))
                guard try kind(path) != nil else { return nil }
                if index < parts.count - 1 { try requireDirectory(path) }
            }
            return path
        }
        func children(_ name: String) throws -> [String] {
            guard let url = try present(name) else { return [] }
            try requireDirectory(url)
            return try fm.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }
        }
        var names = try fixedFiles.filter { try present($0) != nil }
        let artNames = Set(ArtworkSlot.allCases.flatMap { slot in ["\(slot.kind.rawValue).png", "\(slot.kind.rawValue).jpg"] })
        for picks in ["artwork-picks", "integrations/steam/artwork-picks"] {
            for title in try children(picks) {
                let folder = "\(picks)/\(title)"
                names += try children(folder).filter(artNames.contains).map { "\(folder)/\($0)" }
            }
        }
        let steamAssets = "integrations/steam/personal/assets"
        names += try children(steamAssets).filter {
            $0.hasSuffix(".png") && UUID(uuidString: String($0.dropLast(4))) != nil
        }.map { "\(steamAssets)/\($0)" }
        for pack in try children("SoundPacks") where pack.hasSuffix(".oortsound") {
            let folder = "SoundPacks/\(pack)"
            names += try children(folder).filter { $0 == "manifest.json" || $0.hasSuffix(".wav") }.map { "\(folder)/\($0)" }
        }
        guard names.count <= maximumEntries else { throw InstallationFileReadError.tooLarge }
        return names.sorted()
    }

    private static func readSnapshot(_ url: URL) throws -> Snapshot? {
        guard let bytes = try read(url, limit: maximumBytes) else { return nil }
        let snapshot = try PropertyListDecoder().decode(Snapshot.self, from: bytes.data)
        guard snapshot.files.count <= maximumEntries, snapshot.files.values.allSatisfy(\.verified),
              snapshot.preferences?.verified != false else { throw InstallationFileReadError.sourceChanged }
        return snapshot
    }

    private static func read(_ url: URL, limit: Int) throws -> InstallationFileSnapshot? {
        do { return try InstallationFileSnapshot.read(at: url, maximumBytes: limit) }
        catch let error as POSIXError where error.code == .ENOENT { return nil }
    }

    private static func publish(_ data: Data, to destination: URL, verify: (URL) throws -> Void) throws {
        guard data.count <= maximumBytes else { throw InstallationFileReadError.tooLarge }
        let folder = destination.deletingLastPathComponent()
        let stage = folder.appendingPathComponent(".staging")
        // This fixed slot bounds the space left by a process killed during staging.
        if let type = try kind(stage) {
            guard type == S_IFREG, unlink(stage.path) == 0 else { throw InstallationFileReadError.unsafeFile }
        }
        let fd = open(stage.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { _ = unlink(stage.path) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        try verify(stage)
        guard rename(stage.path, destination.path) == 0 else { throw posixError() }
        try CatalogPublication.synchronize(folder)
    }

    private static func requireDirectory(_ url: URL) throws {
        guard try kind(url) == S_IFDIR else { throw InstallationFileReadError.unsafeFile }
    }

    private static func kind(_ url: URL) throws -> mode_t? {
        var status = stat()
        if lstat(url.path, &status) == 0 { return status.st_mode & mode_t(S_IFMT) }
        if errno == ENOENT { return nil }
        throw posixError()
    }

    private static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
