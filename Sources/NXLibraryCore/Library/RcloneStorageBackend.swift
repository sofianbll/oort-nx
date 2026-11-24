import Darwin
import Foundation

public struct RcloneStorageBackend: StorageBackend {
    private static let staging = ".arcane-upload"
    private static let smallDownloadLimit: Int64 = 64 * 1024
    private static let flags = ["--drive-skip-shortcuts", "--local-links=false", "--copy-links=false",
                                "--drive-chunk-size", "64M", "--multi-thread-streams", "4",
                                "--multi-thread-cutoff", "64M"]
    private let remote: String
    private let root: String
    private let executable: URL?
    private let config: URL?
    private let commandOverride: RcloneConfiguration.Run?
    private let referenceID: String?
    package var isReference: Bool { referenceID != nil }
    let control: RcloneRemoteControl
    package let leases: CloudTitleLeases

    /// `remote` is a configured rclone name (e.g. `gdrive`) or `:local:` with an absolute `root`.
    /// Credentials and unlocking stay in rclone's configuration, not the arguments or Arcane preferences.
    public init(remote: String, root: String, executable: URL? = nil, config: URL? = nil) {
        self.init(remote: remote, root: root, executable: executable, config: config,
                  control: RcloneRemoteControl(), leases: CloudTitleLeases(), commandOverride: nil)
    }

    package init(remote: String, root: String, run: @escaping RcloneConfiguration.Run) {
        self.init(remote: remote, root: root, executable: nil, config: nil,
                  control: RcloneRemoteControl(), leases: CloudTitleLeases(), commandOverride: run)
    }

    private init(remote: String, root: String, executable: URL?, config: URL?,
                 control: RcloneRemoteControl, leases: CloudTitleLeases, commandOverride: RcloneConfiguration.Run?,
                 referenceID: String? = nil) {
        self.remote = remote
        self.root = root
        self.executable = executable
        self.config = config
        self.control = control
        self.leases = leases
        self.commandOverride = commandOverride
        self.referenceID = referenceID
    }

    package func atRoot(_ root: String) -> Self {
        Self(remote: remote, root: root, executable: executable, config: config,
             control: control, leases: leases, commandOverride: commandOverride, referenceID: referenceID)
    }

    package func descendant(ofRoot path: String) -> String? {
        let parent = root.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = parent.isEmpty ? "" : parent + "/"
        let child = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard root.hasPrefix("/") == path.hasPrefix("/"), CloudLibraryPreference.safePath(path),
              child.hasPrefix(prefix), child.count > prefix.count else { return nil }
        let relative = String(child.dropFirst(prefix.count))
        return relative.components(separatedBy: "/").contains("") ? nil : relative
    }

    /// One directory, metadata only. Keep duplicate names and directories so the caller can refuse them.
    package func directoryEntries(in prefix: String, withHashes: Bool = false) async throws
        -> [(name: String, isDirectory: Bool, object: StorageObject)] {
        let directory = try prefix.isEmpty ? basePath() : path(for: .init(prefix))
        let items = try decode([Item].self, from: await run([
            "lsjson", directory, "--no-modtime", "--no-mimetype",
        ] + (withHashes ? ["--hash"] : []), listingFolder: true))
        if items.isEmpty { try await checkDirectory(try basePath(), prefix: prefix) }
        return try items.map {
            guard $0.path == $0.name, let isDirectory = $0.isDirectory else { throw StorageBackendError.invalidResponse }
            let key = prefix.isEmpty ? $0.name : prefix + "/" + $0.name
            return ($0.name, isDirectory, .init(key: .init(key), size: $0.size, hashes: $0.hashes ?? [:]))
        }
    }

    package func reference(folderID: String) -> Self? {
        guard remote != ":local:", CloudLibraryPreference.referenceFolderID(folderID) == folderID else { return nil }
        return Self(remote: remote, root: "", executable: executable, config: config,
                    control: control, leases: leases, commandOverride: commandOverride, referenceID: folderID)
    }

    package func referenceName() async throws -> String? {
        guard let referenceID else { throw StorageBackendError.invalidConfiguration }
        struct Folder: Decodable { let ID: String?; let Name: String?; let IsDir: Bool }
        let folder = try decode(Folder?.self, from: await run([
            "lsjson", basePath(), "--stat", "--no-modtime", "--no-mimetype",
        ], listingFolder: true))
        guard let folder, folder.IsDir, folder.ID == nil || folder.ID == referenceID else { return nil }
        return folder.Name.flatMap { $0.isEmpty ? nil : $0 } ?? referenceID
    }

    /// Ends the RC session when the cloud configuration is replaced or the app quits.
    public func stopRemoteControl() { control.stop() }

    public static func findExecutable(preferred: URL? = nil) -> URL? {
        findExecutable(preferred: preferred, bundle: Bundle.main.bundleURL,
                       path: ProcessInfo.processInfo.environment["PATH"] ?? "",
                       systemDirectories: ["/opt/homebrew/bin", "/usr/local/bin"])
    }

    static func findExecutable(preferred: URL?, bundle: URL, path: String, systemDirectories: [String]) -> URL? {
        if let preferred { return isExecutable(preferred) ? preferred : nil }
        let bundled = bundle.appendingPathComponent("Contents/Helpers/rclone")
        if isExecutable(bundled) { return bundled }
        return (systemDirectories + path.split(separator: ":").map(String.init))
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0).appendingPathComponent("rclone") }
            .first(where: isExecutable)
    }

    public static func isExecutable(_ url: URL) -> Bool {
        url.isFileURL && FileManager.default.isExecutableFile(atPath: url.path)
            && (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    public func list() async throws -> [StorageObject] {
        let base = try basePath()
        let exclude = "/\(Self.staging)/**"
        let items: [Item]
        if let output = try await rc("operations/list", [
            "fs": base, "remote": "", "opt": ["recurse": true, "filesOnly": true, "showHash": true],
            "_filter": ["ExcludeRule": [exclude]],
        ]) {
            items = try decode(ListResult.self, from: output).list
        } else {
            let output = try await run(["lsjson", base, "--recursive", "--files-only", "--hash", "--exclude", exclude],
                                       listingFolder: true)
            items = try decode([Item].self, from: output)
        }
        if items.isEmpty { try await checkDirectory(base) }
        return items.map {
            StorageObject(key: StorageObjectKey($0.path), size: $0.size, hashes: $0.hashes ?? [:])
        }
    }

    public func list(in prefix: StorageObjectKey) async throws -> [StorageObject] {
        try await list(in: prefix, withHashes: false)
    }

    public func rootDirectories() async throws -> [String] {
        let base = try basePath()
        let items: [Item]
        if let output = try await rc("operations/list", [
            "fs": base, "remote": "", "opt": ["dirsOnly": true, "noModTime": true, "noMimeType": true],
        ]) {
            items = try decode(ListResult.self, from: output).list
        } else {
            let output = try await run(["lsjson", base, "--dirs-only", "--no-modtime", "--no-mimetype",
                                        "--retries", "1", "--low-level-retries", "1", "--contimeout", "5s", "--timeout", "10s"],
                                       listingFolder: true)
            items = try decode([Item].self, from: output)
        }
        if items.isEmpty { try await checkDirectory(base) }
        return items.map(\.name)
    }

    package func list(in prefix: StorageObjectKey, withHashes: Bool) async throws -> [StorageObject] {
        let directory = try path(for: prefix)
        let items: [Item]
        if let output = try await rc("operations/list", [
            "fs": basePath(), "remote": prefix.value, "opt": ["filesOnly": !withHashes, "showHash": withHashes],
        ]) {
            items = try decode(ListResult.self, from: output).list
        } else {
            let output = try await run(["lsjson", directory, withHashes ? "--hash" : "--files-only"],
                                       listingFolder: true)
            items = try decode([Item].self, from: output)
        }
        if items.isEmpty { try await checkDirectory(try basePath(), prefix: prefix.value) }
        return items.map {
            StorageObject(key: StorageObjectKey(prefix.value + "/" + $0.name), size: $0.size, hashes: $0.hashes ?? [:])
        }
    }

    package func tree(in prefix: StorageObjectKey) async throws -> [StorageObject] {
        let target = try path(for: prefix)
        let items: [Item]
        do {
            items = try decode([Item].self, from: await run([
                "lsjson", target, "--recursive", "--hash-type", "MD5", "--no-modtime", "--no-mimetype",
            ]))
        } catch StorageBackendError.notFound { return [] }
        // Include directories: a duplicate Drive directory makes all child paths ambiguous.
        guard Set(items.map(\.path)).count == items.count else { throw StorageBackendError.invalidResponse }
        return items.filter { $0.isDirectory != true }.map {
            StorageObject(key: StorageObjectKey($0.path), size: $0.size, hashes: $0.hashes ?? [:])
        }
    }

    package func copyFiles(_ paths: [String], from local: URL, to key: StorageObjectKey,
                           reusing previous: StorageObjectKey?,
                           progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        guard !isReference else { throw StorageBackendError.invalidConfiguration }
        let reuse = try previous.map { ["--copy-dest", try path(for: $0)] } ?? []
        // Encode links on the source only. The local fixture must store the same sidecars as Drive.
        try await copyFiles(paths, from: ":local,links=true:" + local.path, to: path(for: key),
                            flags: reuse, progress: progress)
    }

    package func downloadFiles(_ paths: [String], from key: StorageObjectKey, to local: URL,
                               decodeLinks: Bool = false,
                               progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        guard local.isFileURL, local.path.hasPrefix("/") else { throw StorageBackendError.invalidLocalFile }
        // Never ask rclone to create a symlink before Arcane has checked its target.
        guard !decodeLinks || !paths.contains(where: { $0.lowercased().hasSuffix(".rclonelink") }) else {
            throw StorageBackendError.invalidKey
        }
        try await copyFiles(paths, from: path(for: key), to: decodeLinks ? ":local,links=true:" + local.path : local.path,
                            flags: [], progress: progress)
    }

    private func copyFiles(_ paths: [String], from: String, to: String, flags: [String],
                           progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        guard !paths.isEmpty else { return }
        guard paths.allSatisfy({ !$0.hasPrefix("/") && CloudLibraryPreference.safePath($0) }) else {
            throw StorageBackendError.invalidKey
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arcane-rclone-\(UUID())")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { throw CloudLibraryFailure.localWriteFailure(error, at: directory) as Error? ?? error }
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("paths")
        do {
            try Data((paths.joined(separator: "\n") + "\n").utf8).write(to: file)
        } catch { throw CloudLibraryFailure.localWriteFailure(error, at: directory) as Error? ?? error }
        let local = [":local,links=true:", ":local:"].first(where: to.hasPrefix)
            .map { String(to.dropFirst($0.count)) } ?? to
        _ = try await run(["copy", from, to, "--files-from-raw", file.path, "--checksum", "--immutable",
                           "--no-update-modtime", "--transfers", "4", "--checkers", "4",
                           "--buffer-size", "4M"] + flags, progress: progress,
                          localDestination: local.hasPrefix("/") ? URL(fileURLWithPath: local) : nil)
    }

    private func checkDirectory(_ base: String, prefix: String = "") async throws {
        struct Directory: Decodable { let IsDir: Bool }
        let directory: Directory?
        do {
            if let output = try await rc("operations/stat", [
                "fs": base, "remote": prefix, "opt": ["dirsOnly": true, "noModTime": true, "noMimeType": true],
            ]) {
                directory = try decode(StatResult<Directory>.self, from: output).item
            } else {
                let path = prefix.isEmpty ? base : base + (base.hasSuffix("/") || base.hasSuffix(":") ? "" : "/") + prefix
                let output = try await run(["lsjson", path, "--stat", "--no-modtime", "--no-mimetype",
                                            "--retries", "1", "--low-level-retries", "1", "--contimeout", "5s", "--timeout", "10s"],
                                           listingFolder: true)
                directory = try decode(Directory?.self, from: output)
            }
        } catch StorageBackendError.notFound { throw CloudLibraryFailure.folderMissing }
        guard directory?.IsDir == true else { throw CloudLibraryFailure.folderMissing }
    }

    public func put(_ source: URL, as object: StorageObject,
                    progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        try validateFingerprint(object)
        try await put(source, as: object, md5Only: false, progress: progress)
    }

    package func putSource(_ source: URL, as object: StorageObject,
                   progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        guard object.size >= 0, isHex(object.hashes["md5"], length: 32) else {
            throw StorageBackendError.invalidFingerprint
        }
        try await put(source, as: object, md5Only: true, progress: progress)
    }

    private func put(_ source: URL, as object: StorageObject, md5Only: Bool,
                     progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        guard !isReference else { throw StorageBackendError.invalidConfiguration }
        let final = try path(for: object.key)
        guard source.isFileURL, isRegularFile(source) else {
            throw StorageBackendError.invalidLocalFile
        }
        guard try await item(at: final) == nil else { throw StorageBackendError.alreadyExists }

        let temporary = try objectPath("\(Self.staging)/\(UUID().uuidString)")
        var createdFinal = false
        do {
            _ = try await run(["copyto", source.path, temporary], progress: progress)
            progress?(StorageProgress(bytesTransferred: object.size, totalBytes: object.size, isVerifying: true))
            try await verify(object, at: temporary, md5Only: md5Only)
            if md5Only && remote == ":local:" {
                // rclone's local Move uses a replacing rename, so make the local publication exclusive.
                let destination = URL(fileURLWithPath: String(final.dropFirst(remote.count)))
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Task.checkCancellation()
                guard renamex_np(String(temporary.dropFirst(remote.count)), destination.path, UInt32(RENAME_EXCL)) == 0 else {
                    if errno == EEXIST { throw StorageBackendError.alreadyExists }
                    throw StorageBackendError.publicationFailed
                }
                createdFinal = true
            } else {
                // Do not let moveto fall back to streaming data into the final key.
                _ = try await run(["moveto", temporary, final, "--ignore-existing", "--immutable", "--checksum",
                                   "--disable", "Copy", "--max-transfer", "0", "--retries", "1"])
                // A skipped move leaves our unique staging object behind, even for identical content.
                createdFinal = try await Task.detached { try await item(at: temporary) == nil }.value
            }
            guard createdFinal else { throw StorageBackendError.alreadyExists }
            // The sources service verifies the published entry in a fresh directory listing for duplicates.
            if !md5Only { try await verify(object, at: final) }
        } catch {
            let cleanup = createdFinal && !md5Only ? [final, temporary] : [temporary]
            await Task.detached {
                for target in cleanup {
                    _ = try? await run(["deletefile", target, "--retries", "1", "--low-level-retries", "1",
                                        "--contimeout", "5s", "--timeout", "5s"])
                }
            }.value
            throw error
        }
    }

    public func get(_ key: StorageObjectKey, to destination: URL,
                    progress: (@Sendable (StorageProgress) -> Void)?) async throws {
        let source = try path(for: key)
        guard destination.isFileURL else { throw StorageBackendError.invalidLocalFile }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw StorageBackendError.alreadyExists }
        guard let item = try await item(at: source) else { throw StorageBackendError.notFound }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".arcane-download-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: false,
                                   attributes: [.posixPermissions: 0o700])
        } catch { throw CloudLibraryFailure.localWriteFailure(error, at: staging) as Error? ?? StorageBackendError.invalidLocalFile }
        defer { try? fm.removeItem(at: staging) }
        let temporary: URL
        if progress == nil, (1...Self.smallDownloadLimit).contains(item.size),
           try await rc("operations/copyfile", [
               "srcFs": basePath(), "srcRemote": key.value, "dstFs": ":local:" + staging.path, "dstRemote": "rc",
           ]) != nil {
            temporary = staging.appendingPathComponent("rc")
        } else {
            // A lost RC response can leave a partial download; the CLI uses a separate staging file.
            temporary = staging.appendingPathComponent("file")
            _ = try await run(["copyto", source, temporary.path], progress: progress, localDestination: staging)
        }
        try Task.checkCancellation()
        guard isRegularFile(temporary) else { throw StorageBackendError.invalidResponse }
        do { try fm.moveItem(at: temporary, to: destination) }
        catch let error as CocoaError where error.code == .fileWriteFileExists { throw StorageBackendError.alreadyExists }
        catch { throw CloudLibraryFailure.localWriteFailure(error, at: destination) as Error? ?? StorageBackendError.invalidLocalFile }
    }

    public func delete(_ key: StorageObjectKey) async throws {
        _ = try await run(["deletefile", path(for: key)])
    }

    public func verify(_ object: StorageObject) async throws {
        try validateFingerprint(object)
        try await verify(object, at: path(for: object.key))
    }

    private func verify(_ object: StorageObject, at target: String, md5Only: Bool = false) async throws {
        guard let item = try await item(at: target, withHashes: true) else { throw StorageBackendError.notFound }
        guard item.size == object.size else { throw StorageBackendError.hashMismatch }
        if md5Only {
            guard isHex(item.hashes?["md5"], length: 32) else { throw StorageBackendError.hashMismatch }
            guard item.hashes?["md5"]?.lowercased() == object.hashes["md5"]?.lowercased() else {
                throw StorageBackendError.hashMismatch
            }
            return
        }
        let expected = object.hashes["sha256"]?.lowercased()
        if let actual = item.hashes?["sha256"], !actual.isEmpty {
            guard actual.lowercased() == expected else { throw StorageBackendError.hashMismatch }
            return
        }
        let output = try await run(["hashsum", "SHA-256", target, "--download"])
        let lines = output.split(separator: "\n")
        guard lines.count == 1, let digest = lines[0].split(separator: " ", maxSplits: 1).first,
              isHex(String(digest), length: 64) else { throw StorageBackendError.invalidResponse }
        guard digest.lowercased() == expected else {
            throw StorageBackendError.hashMismatch
        }
    }

    private func item(at path: String, withHashes: Bool = false) async throws -> Item? {
        let base = try basePath()
        let relative = String(path.dropFirst(base.count + (base.hasSuffix("/") ? 0 : 1)))
        if let output = try await rc("operations/stat", [
            "fs": base, "remote": relative, "opt": ["filesOnly": true, "showHash": withHashes],
        ]) { return try decode(StatResult<Item>.self, from: output).item }
        let output = try await run(["lsjson", path, "--stat", "--files-only"] + (withHashes ? ["--hash"] : []))
        return try decode(Item?.self, from: output)
    }

    private func rc(_ operation: String, _ parameters: [String: Any]) async throws -> String? {
        if commandOverride != nil || isReference { return nil }
        guard let binary = Self.findExecutable(preferred: executable) else { return nil }
        let environment = RcloneConfiguration.environment()
        do {
            return try await control.call(operation, parameters, executable: binary, environment: environment,
                flags: Self.flags + RcloneConfiguration.flags(config: config, environment: environment))
        } catch StorageBackendError.notFound where operation == "operations/list" {
            throw CloudLibraryFailure.folderMissing
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func validateFingerprint(_ object: StorageObject) throws {
        guard object.size >= 0, isHex(object.hashes["sha256"], length: 64),
              object.hashes["md5"].map({ isHex($0, length: 32) }) ?? true else {
            throw StorageBackendError.invalidFingerprint
        }
    }

    private func isHex(_ value: String?, length: Int) -> Bool {
        guard let value else { return false }
        return value.utf8.count == length && value.utf8.allSatisfy { "0123456789abcdefABCDEF".utf8.contains($0) }
    }

    private func path(for key: StorageObjectKey) throws -> String {
        let components = key.value.components(separatedBy: "/")
        guard !components.contains(""), CloudLibraryPreference.safePath(key.value),
              components.first?.lowercased() != Self.staging else {
            throw StorageBackendError.invalidKey
        }
        return try objectPath(key.value)
    }

    private func objectPath(_ key: String) throws -> String {
        let base = try basePath()
        if remote == ":local:" {
            var candidate = URL(fileURLWithPath: root, isDirectory: true)
            for component in key.split(separator: "/") {
                candidate.appendPathComponent(String(component))
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
                    throw StorageBackendError.invalidKey
                }
            }
        }
        return base + (base.hasSuffix("/") || base.hasSuffix(":") ? "" : "/") + key
    }

    private func basePath() throws -> String {
        let name = remote.hasSuffix(":") ? String(remote.dropLast()) : remote
        guard (isReference && root.isEmpty || CloudLibraryPreference.validRoot(root)), config?.isFileURL != false,
              remote == ":local:" ? root.hasPrefix("/") && root != "/" :
                  CloudLibraryPreference.validRemote(name)
        else { throw StorageBackendError.invalidConfiguration }
        return (remote == ":local:" ? remote : name + ":") + root
    }

    private func binary() throws -> URL {
        guard let binary = Self.findExecutable(preferred: executable) else {
            throw StorageBackendError.backendUnavailable
        }
        return binary
    }

    private func run(_ arguments: [String], progress: (@Sendable (StorageProgress) -> Void)? = nil,
                     listingFolder: Bool = false, localDestination: URL? = nil) async throws -> String {
        try Task.checkCancellation()
        let flags = ["--use-json-log", "--stats", "1s", "--stats-log-level", "NOTICE"] + Self.flags
        let environment = RcloneConfiguration.environment()
        var referenceFlags: [String] = []
        if let referenceID {
            let prefix = (remote.hasSuffix(":") ? remote : remote + ":")
            switch arguments.first {
            case "lsjson":
                guard arguments.count > 1, arguments[1].hasPrefix(prefix) else {
                    throw StorageBackendError.invalidConfiguration
                }
            case "copy", "copyto":
                guard arguments.count > 2, arguments[1].hasPrefix(prefix),
                      arguments[2].hasPrefix("/") || arguments[2].hasPrefix(":local,links=true:/") else {
                    throw StorageBackendError.invalidConfiguration
                }
            default: throw StorageBackendError.invalidConfiguration
            }
            referenceFlags = ["--drive-root-folder-id", referenceID]
        }
        let command = arguments + flags + referenceFlags + RcloneConfiguration.flags(config: config, environment: environment)
        let result: CommandResult
        do {
            if let commandOverride {
                result = try await commandOverride(URL(fileURLWithPath: "/fixture/rclone"), command, [:])
            } else {
                result = try await SystemCommandRunner().runCancellable(binary(), command, environment: environment) { line in
                    if let progress, let update = Self.transferProgress(from: line) { progress(update) }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CloudLibraryFailure.localWriteFailure(error, at: localDestination ?? FileManager.default.temporaryDirectory)
                as Error? ?? StorageBackendError.backendUnavailable
        }
        if result.status != 0, let failure = CloudLibraryFailure.rclone(result.stderr, status: result.status,
                                                                       listingFolder: listingFolder) {
            throw failure == .macFull ? CloudLibraryFailure.diskFull(at: localDestination ?? FileManager.default.temporaryDirectory)
                : failure
        }
        if isReference && result.status != 0,
           result.stderr.lowercased().contains("error 403") || result.stderr.lowercased().contains("error 404") {
            throw CloudLibraryFailure.folderMissing
        }
        switch result.status {
        case 0: return result.stdout
        case 3, 4: throw StorageBackendError.notFound
        default:
            let messages: [String] = result.stderr.split(whereSeparator: \.isNewline).suffix(8).compactMap {
                guard let log = try? JSONDecoder().decode(Log.self, from: Data($0.utf8)) else { return String($0) }
                guard log.stats == nil else { return nil }
                return log.message
            }
            if messages.contains(where: {
                $0.contains("Failed to create file system") || $0.contains("Failed to load config")
            }) { throw StorageBackendError.backendUnavailable }
            // OAuth responses in stderr can contain credentials even outside recognizable keys.
            throw StorageBackendError.processFailed(status: result.status)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        do { return try JSONDecoder().decode(type, from: Data(output.utf8)) }
        catch { throw StorageBackendError.invalidResponse }
    }

    static func transferProgress(from line: String) -> StorageProgress? {
        guard let stats = (try? JSONDecoder().decode(Log.self, from: Data(line.utf8)))?.stats,
              stats.bytes >= 0, stats.totalBytes > 0 else { return nil }
        let speed = [stats.speed, stats.transferring?.first?.speed].compactMap { $0 }.first { $0.isFinite && $0 > 0 }
        let eta = stats.eta ?? speed.map { Double(max(0, stats.totalBytes - stats.bytes)) / $0 }
        return StorageProgress(bytesTransferred: min(stats.bytes, stats.totalBytes), totalBytes: stats.totalBytes,
                               bytesPerSecond: speed, etaSeconds: eta)
    }

    private struct Item: Decodable {
        let path: String
        let name: String
        let size: Int64
        let hashes: [String: String]?
        let isDirectory: Bool?

        enum CodingKeys: String, CodingKey {
            case path = "Path", name = "Name", size = "Size", hashes = "Hashes", isDirectory = "IsDir"
        }
    }

    private struct ListResult: Decodable { let list: [Item] }
    private struct StatResult<Entry: Decodable>: Decodable {
        let item: Entry?
        private enum CodingKeys: CodingKey { case item }
        init(from decoder: Decoder) throws {
            item = try decoder.container(keyedBy: CodingKeys.self).decode(Entry?.self, forKey: .item)
        }
    }

    private struct Log: Decodable {
        struct Stats: Decodable {
            struct Active: Decodable { let speed: Double? }
            let bytes: Int64
            let totalBytes: Int64
            let speed: Double?
            let eta: Double?
            let transferring: [Active]?
        }

        let message: String
        let stats: Stats?

        enum CodingKeys: String, CodingKey { case message = "msg", stats }
    }
}
