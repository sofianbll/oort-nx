import Crypto
import Foundation

/// The first writer of a new data generation must leave the old launcher data readable elsewhere.
package enum DowngradeCheckpoint {
    private static let maximumBytes = 128 * 1024 * 1024
    private static let maximumEntries = 8_192
    package enum Omission: String, Codable, CaseIterable, Sendable {
        case sessions, catalog, settings, profiles, queue, preferences, artwork, sound
    }

    package enum Result: Equatable, Sendable {
        case ready, warning([Omission])
    }

    /// New copies hold this directory lease through the notice and the shell.
    /// No lock file has to be created on a full volume with an existing library.
    package final class ProfileLease: Sendable {
        private let descriptor: Int32

        package init(in root: URL) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw posixError() }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                let error = posixError()
                close(fd)
                throw error
            }
            descriptor = fd
        }

        deinit { close(descriptor) }
    }

    package static func savedPalette(in root: URL) -> String {
        guard let bytes = try? read(root.appendingPathComponent("settings.json"), limit: 1_048_576),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: bytes.data)
        else { return SelenePaletteCatalog.defaultID }
        return settings.colorThemeID
    }

    private static let essential: [(Omission, [String])] = [
        (.sessions, ["play-sessions.json", "play-sessions-totals.json", SessionHistoryState.filename,
                     "integrations/steam/playtime-baselines.json"]),
        (.catalog, ["catalog.json", "catalog.json.bak", "catalog-removal-pending.json", "library.json", "library.json.bak"]),
        (.settings, ["settings.json"]),
        (.profiles, ["profiles.json", "profiles-active"]),
        (.queue, ["cloud-transfer-queue.json", "cloud-library-move.json", "activity-results.json", "build-queue.json"]),
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
        var omitted: [Omission]?
        var needsWarning: Bool { !files.isEmpty || preferences != nil || omitted?.isEmpty == false }
    }

    /// A retry never replaces a verified checkpoint of this generation.
    package static func prepare(in root: URL, generation: Int = 1, acceptingWarning: Bool = false,
                                replaceCheckpoint: (URL, URL) throws -> Void = replace,
                                preferences: () throws -> [String: Any]) throws -> Result {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try requireDirectory(root)
        let folder = root.appendingPathComponent("DowngradeProtection", isDirectory: true)
        guard mkdir(folder.path, 0o700) == 0 || errno == EEXIST else { throw posixError() }
        try makePrivate(folder)
        let fd = open(folder.appendingPathComponent(".lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }
        defer { close(fd) }
        _ = try InstallationFileObservation.capture(fileDescriptor: fd, url: folder.appendingPathComponent(".lock"))
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw posixError() }

        let current = folder.appendingPathComponent("checkpoint.plist")
        let previous = folder.appendingPathComponent("previous.plist")
        let retained = folder.appendingPathComponent(".previous-pending")
        let acknowledged = folder.appendingPathComponent("acknowledged")
        let old = try readSnapshot(current)
        if let pending = try readSnapshot(retained) {
            guard let old, pending.generation <= old.generation else { throw InstallationFileReadError.sourceChanged }
            if pending.generation < old.generation {
                try CatalogPublication.synchronize(folder)
                try finishRotation(retained, previous: previous, in: folder)
            } else if pending.id != old.id {
                throw InstallationFileReadError.sourceChanged
            }
        }
        let snapshot: Snapshot
        if let old, old.generation == generation {
            snapshot = old
        } else {
            guard old.map({ $0.generation < generation }) ?? true else { throw InstallationFileReadError.unsafeFile }
            snapshot = try capture(in: root, generation: generation, preferences: preferences)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try publish(try encoder.encode(snapshot), to: current, replacing: replaceCheckpoint) { stage in
                guard try readSnapshot(stage) == snapshot else { throw InstallationFileReadError.sourceChanged }
                if old != nil {
                    _ = try readSnapshot(previous)
                    // Pin the verified current copy without touching either public path before publication.
                    if try kind(retained) == nil {
                        guard link(current.path, retained.path) == 0 else { throw posixError() }
                    }
                    try CatalogPublication.synchronize(folder)
                }
            }
            if old != nil { try finishRotation(retained, previous: previous, in: folder) }
        }
        // Also synchronize a checkpoint visible after an interrupted publication before allowing live writes.
        try CatalogPublication.synchronize(folder)
        try CatalogPublication.synchronize(root)
        guard snapshot.needsWarning else { return .ready }
        let token = Data(snapshot.id.uuidString.utf8)
        if try read(acknowledged, limit: token.count)?.data == token { return .ready }
        guard acceptingWarning else { return .warning(snapshot.omitted ?? []) }
        try publish(token, to: acknowledged) { _ in }
        return .ready
    }

    private static func finishRotation(_ retained: URL, previous: URL, in folder: URL) throws {
        _ = try readSnapshot(previous)
        try replace(retained, previous)
        try CatalogPublication.synchronize(folder)
    }

    private static func capture(in root: URL, generation: Int,
                                preferences: () throws -> [String: Any]) throws -> Snapshot {
        let values = try preferences().filter { preferenceKeys.contains($0.key) }
        var plist = try values.isEmpty ? nil : PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        var remaining = maximumBytes - 4096 // Manifest header, checkpoint ID and top-level keys.
        var omitted = Set<Omission>()
        if let bytes = plist {
            if bytes.count <= remaining { remaining -= bytes.count }
            else { plist = nil; omitted.insert(.preferences) }
        }
        var files: [String: Item] = [:]
        let names = try fileNames(under: root)
        var observations: [InstallationFileObservation] = []
        for (group, name) in names {
            let path = root.appendingPathComponent(name)
            // Leave room for the path, digest and binary-plist object table.
            let overhead = 2 * name.utf8.count + 128
            guard files.count < maximumEntries, remaining >= overhead else { omitted.insert(group); continue }
            do {
                guard let bytes = try read(path, limit: remaining - overhead) else { throw InstallationFileReadError.sourceChanged }
                files[name] = Item(bytes.data)
                remaining -= overhead + bytes.data.count
                observations.append(bytes.observation)
            } catch InstallationFileReadError.tooLarge {
                omitted.insert(group)
            }
        }
        guard try fileNames(under: root).elementsEqual(names, by: ==), try NSDictionary(dictionary: preferences().filter {
            preferenceKeys.contains($0.key)
        }).isEqual(to: values) else { throw InstallationFileReadError.sourceChanged }
        for observation in observations { try observation.verifyUnchanged() }
        let omissions = Omission.allCases.filter(omitted.contains)
        return Snapshot(generation: generation, files: files, preferences: plist.map(Item.init),
                        omitted: omissions.isEmpty ? nil : omissions)
    }

    private static func fileNames(under root: URL) throws -> [(Omission, String)] {
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
        var names: [(Omission, String)] = []
        for (group, paths) in essential {
            names += try paths.filter { try present($0) != nil }.map { (group, $0) }
        }
        var art = try ["metadata-picks.json", "integrations/steam/metadata-picks.json",
                       "integrations/steam/personal/personal.json"].filter { try present($0) != nil }
        let artNames = Set(ArtworkSlot.allCases.flatMap { slot in ["\(slot.kind.rawValue).png", "\(slot.kind.rawValue).jpg"] })
        for picks in ["artwork-picks", "integrations/steam/artwork-picks"] {
            for title in try children(picks) {
                let folder = "\(picks)/\(title)"
                guard try kind(root.appendingPathComponent(folder)) == S_IFDIR else { continue }
                art += try children(folder).filter(artNames.contains).map { "\(folder)/\($0)" }.filter {
                    try kind(root.appendingPathComponent($0)) == S_IFREG
                }
            }
        }
        let steamAssets = "integrations/steam/personal/assets"
        art += try children(steamAssets).filter {
            $0.hasSuffix(".png") && UUID(uuidString: String($0.dropLast(4))) != nil
        }.map { "\(steamAssets)/\($0)" }.filter { try kind(root.appendingPathComponent($0)) == S_IFREG }
        names += art.sorted().map { (.artwork, $0) }
        var audio: [String] = []
        for pack in try children("SoundPacks") where pack.lowercased().hasSuffix(".oortsound") {
            let folder = "SoundPacks/\(pack)"
            switch try kind(root.appendingPathComponent(folder)) {
            case S_IFREG: audio.append(folder)
            case S_IFDIR:
                audio += try children(folder).filter { $0 == "manifest.json" || $0.hasSuffix(".wav") }
                    .map { "\(folder)/\($0)" }.filter { try kind(root.appendingPathComponent($0)) == S_IFREG }
            default: break
            }
        }
        return names + audio.sorted().map { (.sound, $0) }
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

    private static func publish(_ data: Data, to destination: URL, replacing: (URL, URL) throws -> Void = replace,
                                verify: (URL) throws -> Void) throws {
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
        try replacing(stage, destination)
        try CatalogPublication.synchronize(folder)
    }

    package static func replace(_ source: URL, _ destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else { throw posixError() }
    }

    private static func requireDirectory(_ url: URL) throws {
        guard try kind(url) == S_IFDIR else { throw InstallationFileReadError.unsafeFile }
    }

    private static func makePrivate(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw posixError() }
        defer { close(fd) }
        var status = stat()
        guard fstat(fd, &status) == 0 else { throw posixError() }
        guard status.st_uid == geteuid() else { throw InstallationFileReadError.unsafeFile }
        if status.st_mode & 0o7777 != 0o700, fchmod(fd, 0o700) != 0 { throw posixError() }
    }

    private static func kind(_ url: URL) throws -> mode_t? {
        var status = stat()
        if lstat(url.path, &status) == 0 { return status.st_mode & mode_t(S_IFMT) }
        if errno == ENOENT { return nil }
        throw posixError()
    }

    private static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
