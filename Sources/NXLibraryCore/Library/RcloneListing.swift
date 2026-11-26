import Foundation

/// One read of a Drive library, for what a screen shows. The account and the folders are proved before the first
/// listing and again by `confirm()` after the last one; in between each folder is read by its ID and asked once.
/// A write never reads here: it keeps proving its own folder, command by command.
package actor RcloneListing {
    /// nil when this rclone cannot answer, so the caller falls back to single commands.
    package typealias Call = @Sendable (_ operation: String, _ parameters: Data) async throws -> String?

    /// This rclone cannot answer. Not a failure of Drive.
    package struct Unavailable: Error {}

    package struct Connection: Sendable {
        let remote: String
        let account: String
        let call: Call
        /// Drive said a search left something out since rclone started.
        let incomplete: @Sendable () -> Bool

        package init(remote: String, account: String, call: @escaping Call, incomplete: @escaping @Sendable () -> Bool) {
            self.remote = remote
            self.account = account
            self.call = call
            self.incomplete = incomplete
        }
    }

    package struct Entry: Sendable {
        package let name: String
        package let id: String?
        package let isDirectory: Bool
        package let size: Int64
        package let md5: String?
        package var hashes: [String: String] { md5.map { ["md5": $0] } ?? [:] }
    }

    /// Drive accepts about this many parents in a search; rclone groups by the same number.
    static let groupSize = 50
    private static let folderType = "application/vnd.google-apps.folder"

    private let connection: Connection
    private var folders: [String: Task<[Entry], Error>] = [:]
    private var groupsFolders = true
    private var cancelled = false
    /// Answers taken since the scope was last proved.
    private var unconfirmed = 0
    /// What `verify` found: a folder's name in its parent, and its ID.
    private var proved: [(parent: String, name: String, id: String)] = []

    package init(_ connection: Connection) { self.connection = connection }

    package nonisolated var account: String { connection.account }

    package func cancel() {
        cancelled = true
        folders.values.forEach { $0.cancel() }
        folders = [:]
    }

    // MARK: - Scope

    package func verify(_ scope: CloudDriveScope) async throws {
        guard scope.remote == connection.remote, scope.account == connection.account else { throw CloudLibraryFailure.scopeChanged }
        var found = try await prove(scope.library)
        if let sources = scope.sources, sources != scope.library { found += try await prove(sources) }
        proved = found
    }

    /// After the last read, before anything read is used. Costs nothing when nothing was asked since the last time.
    package func confirm() async throws {
        guard !proved.isEmpty else { throw CloudLibraryFailure.scopeChanged }
        try check()
        guard unconfirmed > 0 else { return }
        let taken = unconfirmed
        try await withThrowingTaskGroup(of: (String, [Entry]).self) { group in
            for parent in Set(proved.map(\.parent)) { group.addTask { (parent, try await self.fetch(parent, proving: true)) } }
            for try await (parent, entries) in group {
                for step in proved where step.parent == parent {
                    guard Self.folder(named: step.name, in: entries)?.id == step.id else { throw CloudLibraryFailure.scopeChanged }
                }
            }
        }
        if connection.incomplete() { throw StorageBackendError.invalidResponse }
        unconfirmed -= taken
    }

    /// The folder's ID in the account, nil when it is not there. A name that could mean two folders is refused.
    package func identity(of path: String) async throws -> String? {
        guard CloudLibraryPreference.validSourcesRoot(path) else { throw StorageBackendError.invalidKey }
        return try await steps(to: path)?.last?.id
    }

    private func prove(_ folder: CloudDriveScope.Folder) async throws -> [(parent: String, name: String, id: String)] {
        guard let steps = try await steps(to: folder.path), steps.last?.id == folder.id else { throw CloudLibraryFailure.scopeChanged }
        return steps
    }

    private func steps(to path: String) async throws -> [(parent: String, name: String, id: String)]? {
        var result: [(parent: String, name: String, id: String)] = []
        for part in path.split(separator: "/").map(String.init) {
            let parent = result.last?.id ?? ""
            let entries = try await children(of: parent)
            guard Self.matching(part, in: entries).isEmpty == false else { return nil }
            guard let id = Self.folder(named: part, in: entries)?.id else { throw CloudLibraryFailure.scopeChanged }
            result.append((parent, part, id))
        }
        return result
    }

    private static func matching(_ name: String, in entries: [Entry]) -> [Entry] {
        entries.filter { $0.name.precomposedStringWithCanonicalMapping == name.precomposedStringWithCanonicalMapping }
    }

    /// nil unless the name means exactly one folder, spelled the same.
    private static func folder(named name: String, in entries: [Entry]) -> (id: String, entry: Entry)? {
        let matches = matching(name, in: entries)
        guard matches.count == 1, matches[0].isDirectory, matches[0].name.utf8.elementsEqual(name.utf8),
              let id = matches[0].id, CloudDriveScope.validID(id) else { return nil }
        return (id, matches[0])
    }

    // MARK: - Reading

    /// The folder at `path` below the folder with that ID; duplicate names are kept for the caller to refuse.
    package func entries(in path: String, under root: String) async throws -> [Entry] {
        try await children(of: folderID(path, under: root))
    }

    /// Reads these folders with as few requests as possible. Whatever fails here is asked again, and reported, by its reader.
    package func warm(_ paths: [String], under root: String) async {
        var ids: [String] = []
        for path in paths {
            guard let id = try? await folderID(path, under: root), folders[id] == nil, !ids.contains(id) else { continue }
            ids.append(id)
        }
        guard groupsFolders, !cancelled, ids.count > 1 else { return }
        for start in stride(from: 0, to: ids.count, by: Self.groupSize) {
            let group = Array(ids[start..<min(start + Self.groupSize, ids.count)])
            let read = Task { try await self.fetch(group) }
            for id in group {
                folders[id] = Task {
                    let found = try await withTaskCancellationHandler { try await read.value } onCancel: { read.cancel() }
                    if let entries = found[id] { return entries }
                    return try await self.fetch(id)
                }
            }
        }
    }

    /// Only a file the listing shows, from the folder it was listed in.
    package func download(_ path: String, under root: String, to file: URL) async throws {
        let parts = path.components(separatedBy: "/")
        guard let name = parts.last, file.isFileURL else { throw StorageBackendError.invalidKey }
        let parent = try await folderID(parts.dropLast().joined(separator: "/"), under: root)
        let matches = Self.matching(name, in: try await children(of: parent))
        guard !matches.isEmpty else { throw StorageBackendError.notFound }
        guard matches.count == 1, !matches[0].isDirectory, matches[0].name.utf8.elementsEqual(name.utf8) else {
            throw CloudLibraryFailure.incomplete
        }
        unconfirmed += 1
        _ = try await ask("operations/copyfile", ["srcFs": remote(parent), "srcRemote": name,
                                                  "dstFs": ":local:" + file.deletingLastPathComponent().path,
                                                  "dstRemote": file.lastPathComponent])
    }

    private func folderID(_ path: String, under root: String) async throws -> String {
        var id = root
        for part in path.split(separator: "/").map(String.init) {
            let entries = try await children(of: id)
            guard !Self.matching(part, in: entries).isEmpty else { throw CloudLibraryFailure.folderMissing }
            guard let next = Self.folder(named: part, in: entries)?.id else { throw CloudLibraryFailure.incomplete }
            id = next
        }
        return id
    }

    private func children(of id: String) async throws -> [Entry] {
        try check()
        let read = folders[id] ?? Task { try await self.fetch(id) }
        folders[id] = read
        do {
            let entries = try await read.value
            try check()
            return entries
        } catch {
            if folders[id] == read { folders[id] = nil }
            try check()
            throw error
        }
    }

    private func check() throws {
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
    }

    private func fetch(_ id: String, proving: Bool = false) async throws -> [Entry] {
        if !proving { unconfirmed += 1 }
        struct Item: Decodable {
            let Name: String, IsDir: Bool, Size: Int64
            let ID: String?
            let Hashes: [String: String]?
        }
        struct Listed: Decodable { let list: [Item] }
        let output = try await ask("operations/list", ["fs": remote(id), "remote": "", "opt": [
            "noModTime": true, "noMimeType": true, "showHash": true, "hashTypes": ["md5"]] as [String: Any]])
        return try decode(Listed.self, output).list.map {
            Entry(name: $0.Name, id: $0.ID, isDirectory: $0.IsDir, size: $0.Size, md5: $0.Hashes?["md5"])
        }
    }

    /// The children of several folders, from one search. A folder left out of the answer is read on its own.
    private func fetch(_ ids: [String]) async throws -> [String: [Entry]] {
        guard groupsFolders, ids.allSatisfy(CloudDriveScope.validID), let anchor = ids.first else { return [:] }
        struct Item: Decodable {
            let id: String, name: String, mimeType: String
            let parents: [String]?
            let size: String?
            let md5Checksum: String?
        }
        struct Found: Decodable { let result: [Item]? }
        unconfirmed += 1
        let parents = ids.map { "'\($0)' in parents" }.joined(separator: " or ")
        let output: String
        do {
            output = try await ask("backend/command", ["command": "query", "fs": remote(anchor), "arg": [
                "(\(parents)) and trashed=false and mimeType!='application/vnd.google-apps.shortcut'"]])
        } catch is Unavailable {
            groupsFolders = false // rclone before 1.69 has no such command.
            return [:]
        }
        var result = Dictionary(uniqueKeysWithValues: ids.map { ($0, [Entry]()) })
        var apart = Set<String>()
        for item in try decode(Found.self, output).result ?? [] {
            let owners = (item.parents ?? []).filter { result[$0] != nil }
            guard !owners.isEmpty else { return [:] }
            let folder = item.mimeType == Self.folderType
            guard folder || !item.mimeType.hasPrefix("application/vnd.google-apps.") else { continue }
            // rclone spells these names its own way.
            if item.name.unicodeScalars.contains(where: { "/／‛".unicodeScalars.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
                apart.formUnion(owners)
            }
            for owner in owners {
                result[owner]?.append(Entry(name: item.name, id: item.id, isDirectory: folder,
                                            size: folder ? -1 : item.size.flatMap(Int64.init) ?? -1, md5: item.md5Checksum))
            }
        }
        for id in apart { result[id] = nil }
        return result
    }

    private nonisolated func remote(_ id: String) -> String {
        connection.remote + (id.isEmpty ? ":" : ",root_folder_id=\(id):")
    }

    private func ask(_ operation: String, _ parameters: [String: Any]) async throws -> String {
        try check()
        guard let output = try await connection.call(operation, JSONSerialization.data(withJSONObject: parameters)) else {
            throw Unavailable()
        }
        return output
    }

    private nonisolated func decode<T: Decodable>(_ type: T.Type, _ output: String) throws -> T {
        do { return try JSONDecoder().decode(type, from: Data(output.utf8)) }
        catch { throw StorageBackendError.invalidResponse }
    }
}

/// The proved connection a listing reads from: one private copy of the configuration, one account, one rclone.
/// Asked again only when the player's configuration or rclone changed.
package actor RcloneReader {
    private struct Opened {
        let key: [String]
        let contents: Data
        let connection: RcloneListing.Connection
    }

    private let control: RcloneRemoteControl
    private var opened: Opened?
    private var opening: (id: UUID, task: Task<RcloneListing.Connection, Error>)?

    init(control: RcloneRemoteControl) { self.control = control }

    func close() { opened = nil }

    package func connection(remote: String, executable: URL, config: URL?) async throws -> RcloneListing.Connection {
        let id: UUID, task: Task<RcloneListing.Connection, Error>
        if let opening { (id, task) = opening } else {
            id = UUID()
            task = Task { try await self.open(remote: remote, executable: executable, config: config) }
            opening = (id, task)
        }
        defer { if opening?.id == id { opening = nil } }
        return try await task.value
    }

    private func open(remote: String, executable: URL, config: URL?) async throws -> RcloneListing.Connection {
        let run: RcloneConfiguration.Run = { try await RcloneDownload.runCancellable($0, $1, environment: $2) }
        let snapshot = try await RcloneConfigSnapshot.capture(executable: executable, config: config, run: run)
        let contents = try Data(contentsOf: snapshot.config)
        let key = [remote, executable.path, RcloneDownload.identity(of: executable) ?? ""]
        if let opened, opened.key == key, opened.contents == contents { return opened.connection }
        let environment = RcloneConfiguration.driveEnvironment(remote)
        let configuration = RcloneConfiguration.flags(config: snapshot.config, environment: environment)
        let flags = RcloneStorageBackend.flags + RcloneListing.limits + configuration
        let control = control
        // The server starts while the account is proved; it reads nothing of Drive until then.
        async let started = control.read("rc/noop", Data("{}".utf8), executable: executable, environment: environment, flags: flags)
        let remotes = try await run(executable, ["listremotes", "--json"] + configuration, environment)
        guard remotes.status == 0 else { throw CloudLibraryFailure.rclone(remotes.stderr, status: remotes.status) ?? .requiresDrive }
        try RcloneConfiguration.requireDrive(remote, in: remotes.stdout)
        let about = try await run(executable, ["about", "\(remote),root_folder_id=,team_drive=:", "--json", "--log-level", "DEBUG"]
            + RcloneStorageBackend.flags + RcloneListing.limits + configuration, environment)
        guard about.status == 0 else { throw CloudLibraryFailure.rclone(about.stderr, status: about.status) ?? .unavailable }
        guard let account = CloudDriveScope.accountID(in: about.stderr) else { throw CloudLibraryFailure.scopeChanged }
        _ = try await started
        let connection = RcloneListing.Connection(remote: remote, account: account, call: { operation, parameters in
            defer { withExtendedLifetime(snapshot) {} }
            return try await control.read(operation, parameters, executable: executable, environment: environment, flags: flags)
        }, incomplete: { control.sawIncompleteSearch })
        opened = .init(key: key, contents: contents, connection: connection)
        return connection
    }
}

extension RcloneListing {
    /// A screen waits for these reads: a connection that does not answer is reported, not retried for minutes.
    static let limits = ["--retries", "1", "--low-level-retries", "2", "--contimeout", "5s", "--timeout", "20s"]
}
