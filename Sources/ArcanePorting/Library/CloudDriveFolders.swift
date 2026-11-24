import Foundation
import Darwin
import NXLibraryCore

public struct CloudDriveFolders: Sendable {
    public struct Listing: Sendable {
        public let ticket: UUID
        public let names: [String]
    }

    public struct Library: Sendable, Equatable {
        public let path: String
        public let games: Int
    }

    public struct Sources: Sendable, Equatable {
        public let path: String
        public let games: Int?
    }

    public struct MovePlan: Equatable, Codable, Sendable {
        public let source: String
        public let games: Int
        public let bytes: Int64
        package let remote: String
        fileprivate let entries: [MoveEntry]
        // Optional for decoding old activity results, never for an actual remote move.
        fileprivate var binding: MoveBinding?
    }

    package struct MoveBinding: Equatable, Codable, Sendable {
        let account: String
        let sourceID: String
        let destinationID: String
        let destination: String
    }

    package enum MoveFailure: LocalizedError {
        case missingIdentity, accountChanged, foldersChanged, sourceNotEmpty, destinationChanged
        case sourceResidue(String)

        package var errorDescription: String? {
            switch self {
            case .missingIdentity:
                return L10n.text("The account and folders for this move could not be verified. No new files were moved. Keep the recovery record.")
            case .accountChanged:
                return L10n.text("This move belongs to another Drive account. Reconnect the original account before retrying.")
            case .foldersChanged:
                return L10n.text("A library folder was replaced, renamed or cannot be read. Restore the original folders at their original paths before retrying.")
            case .sourceNotEmpty:
                return L10n.text("Archives still exist in the old folder. Pause uploads from other Macs and reconcile those archives before retrying. The library folder was not switched.")
            case .sourceResidue(let path):
                return L10n.format("Unplanned archive in the old folder: %@. Pause uploads from other Macs and move this file outside the old folder without deleting it before retrying.", [path])
            case .destinationChanged:
                return L10n.text("The destination no longer matches the confirmed archives. Restore the missing or changed files before retrying.")
            }
        }
    }

    fileprivate struct MoveEntry: Equatable, Codable, Sendable {
        let file: StorageObject
        let dependencies: [StorageObject]
    }

    private let remote: String
    private let executable: URL
    private let localRoot: URL?
    private let config: URL?
    private let run: RcloneConfiguration.Run

    public init(remote: String, executable: URL, config: URL? = nil) {
        self.init(remote: remote, executable: executable, config: config, run: Self.runCommand)
    }

    init(remote: String, executable: URL, localRoot: URL? = nil, config: URL? = nil,
         run: @escaping RcloneConfiguration.Run = Self.runCommand) {
        self.remote = remote
        self.executable = executable
        self.localRoot = localRoot
        self.config = config
        self.run = run
    }

    public static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.contains("/") && name.lowercased() != ".arcane-upload"
            && CloudLibraryPreference.safePath(name)
    }

    public static func joining(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : "\(folder)/\(name)"
    }

    static func titleID(in folder: String) -> String? {
        guard validName(folder) else { return nil }
        let title = folder.hasSuffix("]") ? String(folder.dropLast().suffix(16)) : folder
        guard SaveLocation.validID(title), title == title.uppercased(),
              folder == title || folder.hasSuffix(" [\(title)]") else { return nil }
        return title
    }

    public func list(_ folder: String, ticket: UUID) async throws -> Listing {
        let output = try await checked(["lsjson", try target(folder), "--dirs-only", "--max-depth", "1",
                                        "--no-modtime", "--no-mimetype"])
        guard let items = try? JSONDecoder().decode([Item].self, from: Data(output.utf8)) else {
            throw StorageBackendError.invalidResponse
        }
        let names = Set(items.filter(\.IsDir).map(\.Name).filter(Self.validName))
        return Listing(ticket: ticket, names: names.sorted {
            let order = $0.localizedStandardCompare($1)
            return order == .orderedSame ? $0 < $1 : order == .orderedAscending
        })
    }

    public func verifyAccess(to folder: String) async throws {
        let output = try await checked(["lsjson", try target(folder), "--stat"])
        guard (try? JSONDecoder().decode(Item.self, from: Data(output.utf8)))?.IsDir == true else {
            throw RcloneConfiguration.Failure.test
        }
        _ = try await list(folder, ticket: UUID())
    }

    /// Only an explicit confirmation calls this. A lost reply is followed by a read, never another write.
    public func create(_ name: String, in folder: String) async throws {
        guard Self.validName(name) else { throw StorageBackendError.invalidKey }
        let destination = try target(Self.joining(folder, name))
        if try await list(folder, ticket: UUID()).names.contains(name) { return }
        do {
            _ = try await checked(["mkdir", destination])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if try await list(folder, ticket: UUID()).names.contains(name) { return }
            throw error
        }
    }

    public func libraryCount(in folder: String, folders: [String]) async throws -> Int {
        let backend = try backend(in: folder)
        defer { backend.stopRemoteControl() }
        return try await CloudGameArchive(backend: backend).latestManifests().count
    }

    public func discoverLibrary() async throws -> Library? {
        try await Self.discoverLibrary(directories: {
            try await list($0, ticket: UUID()).names
        }, count: { folder, names in
            try await libraryCount(in: folder, folders: names)
        })
    }

    static func discoverLibrary(directories: (String) async throws -> [String],
                                count: (String, [String]) async throws -> Int) async throws -> Library? {
        let root = CloudLibraryPreference.defaultRoot
        guard let names = try await listingIfPresent(root, list: directories) else { return nil }
        let games = try await count(root, names)
        try Task.checkCancellation()
        if games > 0 { return Library(path: root, games: games) }
        let children = names.filter { validName($0) && titleID(in: $0) == nil }
        guard children.count <= 64 else { throw StorageBackendError.invalidResponse }
        for child in children {
            let path = joining(root, child)
            guard let names = try await listingIfPresent(path, list: directories) else {
                // The folder was listed, but disappeared before we could inspect it.
                throw StorageBackendError.invalidResponse
            }
            let games = try await count(path, names)
            try Task.checkCancellation()
            if games > 0 { return Library(path: path, games: games) }
        }
        return nil
    }

    public func discoverSources(library: String) async throws -> Sources? {
        try await Self.discoverSources(library: library) { folder in
            let output = try await checked(["lsjson", try target(folder), "--recursive", "--max-depth", "2",
                                            "--files-only", "--no-modtime", "--no-mimetype"])
            guard let items = try? JSONDecoder().decode([Item].self, from: Data(output.utf8)) else {
                throw StorageBackendError.invalidResponse
            }
            return items.filter { !$0.IsDir }.map(\.Path)
        }
    }

    static func discoverSources(library: String, files: (String) async throws -> [String]) async throws -> Sources? {
        guard library.components(separatedBy: "/").allSatisfy(validName) else { throw StorageBackendError.invalidKey }
        for path in ["GameFiles", "Switch/Jeux", "Switch/Games"].map({ joining(library, $0) }) {
            guard let names = try await listingIfPresent(path, list: files) else { continue }
            guard names.count <= 10_000 else { throw StorageBackendError.invalidResponse }
            var groups = Set<String>()
            var loose = false
            for name in names {
                try Task.checkCancellation()
                let parts = name.components(separatedBy: "/")
                guard parts.count <= 2, parts.allSatisfy(validName),
                    !parts.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") }),
                    CloudGameSources.fileExtensions.contains((name as NSString).pathExtension.lowercased())
                else { continue }
                if parts.count == 1 { loose = true }
                else { groups.insert(CloudGameSources.title(in: parts[0])) }
            }
            try Task.checkCancellation()
            // Loose packages may be updates or DLC for the same title; don't guess a count.
            if loose || !groups.isEmpty { return Sources(path: path, games: loose ? nil : groups.count) }
        }
        return nil
    }

    private static func listingIfPresent(_ folder: String,
                                         list: (String) async throws -> [String]) async throws -> [String]? {
        try Task.checkCancellation()
        let result: [String]?
        do { result = try await list(folder) }
        catch StorageBackendError.notFound { result = nil }
        try Task.checkCancellation()
        return result
    }

    static func libraryCount(_ backend: any StorageBackend, folders: [String]) async throws -> Int {
        try await CloudGameArchive(backend: backend).latestManifests(in: folders).count
    }

    public static func canMove(from source: String, to destination: String) -> Bool {
        let old = source.lowercased(), new = destination.lowercased()
        guard CloudLibraryPreference.validRoot(old), CloudLibraryPreference.validRoot(new), old != new else { return false }
        for (parent, child) in [(old, new), (new, old)] where child.hasPrefix(parent + "/") {
            guard let subtree = child.dropFirst(parent.count + 1).split(separator: "/").first,
                  titleID(in: subtree.uppercased()) == nil else { return false }
        }
        return true
    }

    public func movePlan(from source: String, to destination: String? = nil) async throws -> MovePlan {
        let binding: MoveBinding?
        if let destination, remote != ":local:" {
            binding = try await moveBinding(from: source, to: destination)
        } else {
            guard remote == ":local:" else { throw MoveFailure.missingIdentity }
            _ = try await folderID(source)
            binding = nil
        }
        let sourceID = binding?.sourceID
        let sourceRoot = sourceID == nil ? source : ""
        let items = try await contents(sourceRoot, recursive: true, rootID: sourceID, allowMissing: false)
        let paths = Dictionary(grouping: items, by: \.Path)
        let backend = try backend(in: source)
        defer { backend.stopRemoteControl() }
        let archive = CloudGameArchive(backend: backend)
        var archiveTitles = Set<String>()
        var objects: [MoveEntry] = [], manifests: [MoveEntry] = []
        for item in items.sorted(by: { $0.Path < $1.Path }) where !item.IsDir {
            let path = item.Path
            let parts = path.components(separatedBy: "/")
            guard parts.allSatisfy(Self.validName) else { continue }
            if parts.count == 3, let title = Self.titleID(in: parts[0]),
               parts[1] == "manifests", path.hasSuffix(".json") {
                guard Self.uniquePath(path, in: paths) else { throw StorageBackendError.alreadyExists }
                let manifest: CloudGameManifest
                do { manifest = try await archive.readManifest(item.object, titleID: title) }
                catch CloudArchiveError.invalidManifest, CloudArchiveError.unsafePath { continue }
                archiveTitles.insert(manifest.titleID)
                let dependencies = manifest.artifacts.flatMap { $0.objects(titleID: manifest.titleID) }
                manifests.append(.init(file: item.object, dependencies: dependencies))
                objects += manifest.artifacts.compactMap(\.files).flatMap(\.objects).map { .init(file: $0, dependencies: []) }
            }
        }
        for item in items where !item.IsDir {
            let parts = item.Path.components(separatedBy: "/")
            if parts.count == 3, archiveTitles.contains(parts[0]), CloudArtifactKind(rawValue: parts[1]) != nil,
               parts[2].range(of: #"^[0-9a-f]{64}\.aar\z"#, options: .regularExpression) != nil {
                objects.append(.init(file: item.object, dependencies: []))
            }
        }
        // Keep each key once even when Drive lists several objects with that name. The mover reports the conflict.
        var seen = Set<StorageObjectKey>()
        let entries = (objects.sorted { $0.file.key.value < $1.file.key.value } + manifests)
            .filter { seen.insert($0.file.key).inserted }
        var bytes: Int64 = 0
        for entry in entries {
            let (total, overflow) = bytes.addingReportingOverflow(entry.file.size)
            guard !overflow, entry.file.size >= 0 else { throw StorageBackendError.invalidResponse }
            bytes = total
        }
        let plan = MovePlan(source: source, games: archiveTitles.count, bytes: bytes, remote: remote,
                            entries: entries, binding: binding)
        try await verifySourceArchives(sourceRoot, id: sourceID, allowing: entries)
        if remote != ":local:", let destination { try await verifyBinding(plan, to: destination) }
        return plan
    }

    package func preflightMove(_ plan: MovePlan, to destination: String) async throws {
        guard remote == plan.remote, Self.validMove(plan, to: destination) else {
            throw StorageBackendError.invalidKey
        }
        try await verifyBinding(plan, to: destination)
        let id = plan.binding?.sourceID
        try await verifySourceArchives(id == nil ? plan.source : "", id: id, allowing: plan.entries)
    }

    /// Run only after confirmation; a skipped key (or manifest with missing dependencies) prevents activation.
    public func move(_ plan: MovePlan, to destination: String,
                     progress: (Int, Int) async throws -> Void) async throws -> [String] {
        try await preflightMove(plan, to: destination)
        let sourceID = plan.binding?.sourceID, destinationID = plan.binding?.destinationID
        let folders = Set(plan.entries.compactMap { Self.treeFolder($0.file.key.value) })
        func paths(at root: String, id: String?) async throws -> [String: [Item]] {
            var result = Dictionary(grouping: try await contents(root, recursive: true, rootID: id, allowMissing: false), by: \.Path)
            for folder in folders.sorted() {
                for item in try await contents(Self.joining(root, folder), recursive: true, deep: true, rootID: id) {
                    result[Self.joining(folder, item.Path), default: []].append(item)
                }
            }
            return result
        }
        let sourcePaths = try await paths(at: sourceID == nil ? plan.source : "", id: sourceID)
        let destinationRoot = destinationID == nil ? destination : ""
        let destinationPaths = try await paths(at: destinationRoot, id: destinationID)
        var conflicts: [String] = []
        var blockedTitles = Set<String>()
        try await progress(0, plan.entries.count)
        for (index, entry) in plan.entries.enumerated() {
            try Task.checkCancellation()
            let path = entry.file.key.value
            let folder = String(path.prefix { $0 != "/" })
            let title = Self.titleID(in: folder) ?? folder
            let dependenciesReady = blockedTitles.contains(title) ? false
                : try await dependenciesMatch(entry.dependencies, at: destinationRoot, id: destinationID)
            if !(Self.uniquePath(path, in: sourcePaths) && Self.uniquePath(path, in: destinationPaths)
                 && dependenciesReady) {
                conflicts.append(path)
                blockedTitles.insert(title)
            } else if try await !moveFile(entry.file, from: plan.source, to: destination,
                                          binding: plan.binding) {
                conflicts.append(path)
                blockedTitles.insert(title)
            }
            try await progress(index + 1, plan.entries.count)
        }
        guard conflicts.isEmpty else { return conflicts }
        let actual = try await paths(at: destinationRoot, id: destinationID)
        let expected = plan.entries.flatMap { [$0.file] + $0.dependencies }
        guard expected.allSatisfy({
            Self.uniquePath($0.key.value, in: actual) && Self.matches($0, actual[$0.key.value] ?? [])
        }) else { throw MoveFailure.destinationChanged }
        try await verifyBinding(plan, to: destination)
        try await verifySourceArchives(sourceID == nil ? plan.source : "", id: sourceID)
        try await verifyBinding(plan, to: destination)
        return conflicts
    }

    private func dependenciesMatch(_ dependencies: [StorageObject], at root: String, id: String?) async throws -> Bool {
        let byParent = Dictionary(grouping: dependencies) { $0.key.value.components(separatedBy: "/").dropLast().joined(separator: "/") }
        for (parent, files) in byParent {
            let items = try await contents(Self.joining(root, parent), recursive: false, rootID: id)
            guard files.allSatisfy({ file in
                let name = file.key.value.components(separatedBy: "/").last
                return Self.matches(file, items.filter { $0.Name == name })
            }) else { return false }
        }
        return true
    }

    private func verifySourceArchives(_ root: String, id: String?, allowing entries: [MoveEntry]? = nil) async throws {
        // Swift String equality folds NFC/NFD; Drive can list both spellings.
        var allowed = Set((entries ?? []).map { Array($0.file.key.value.utf8) })
        let children = try await contents(root, recursive: false, hashes: false, rootID: id, allowMissing: false)
        let titles = children.filter { $0.IsDir && Self.titleID(in: $0.Name) != nil }
        guard Set(titles.map(\.Name)).count == titles.count else { throw MoveFailure.foldersChanged }
        for child in titles {
            let items = try await contents(Self.joining(root, child.Name), recursive: true, hashes: false,
                                           deep: true, rootID: id, allowMissing: false)
            for item in items where !item.IsDir {
                let key = Self.joining(child.Name, item.Path)
                let parts = item.Path.lowercased().components(separatedBy: "/")
                if Self.treeFolder(key) != nil || (parts.count == 2 && (
                    (parts[0] == "manifests" && parts[1].hasSuffix(".json")) ||
                    (CloudArtifactKind(rawValue: parts[0]) != nil && parts[1].hasSuffix(".aar"))
                )), allowed.remove(Array(key.utf8)) == nil {
                    if entries != nil { throw MoveFailure.sourceResidue(key) }
                    throw MoveFailure.sourceNotEmpty
                }
            }
        }
    }

    package static func validMove(_ plan: MovePlan, to destination: String) -> Bool {
        canMove(from: plan.source, to: destination)
            && [plan.source, destination].allSatisfy { $0.components(separatedBy: "/").allSatisfy(validName) }
            && !plan.entries.isEmpty && plan.entries.allSatisfy(validMoveEntry)
            && Set(plan.entries.map(\.file.key)).count == plan.entries.count
    }

    package static func isBound(_ plan: MovePlan, to destination: String) -> Bool {
        guard let binding = plan.binding else { return false }
        return binding.destination.utf8.elementsEqual(destination.utf8)
            && [binding.account, binding.sourceID, binding.destinationID].allSatisfy(validID)
            && binding.sourceID != binding.destinationID
    }

    package func originalSourcesRoot(_ plan: MovePlan, to destination: String) async throws -> String? {
        try await verifyBinding(plan, to: destination)
        let items = try await contents("", recursive: false, hashes: false, rootID: plan.binding?.sourceID, allowMissing: false)
        let defaults = items.filter { $0.Name == "GameFiles" }
        guard defaults.count <= 1, defaults.first?.IsDir != false else { throw MoveFailure.foldersChanged }
        return defaults.isEmpty ? nil : Self.joining(plan.source, "GameFiles")
    }

    private static func validMoveEntry(_ entry: MoveEntry) -> Bool {
        func parts(_ object: StorageObject) -> [String]? {
            let path = object.key.value.components(separatedBy: "/")
            guard path.count == 3, path.allSatisfy(validName), object.size >= 0 else { return nil }
            return path
        }
        func isArchive(_ path: [String]) -> Bool {
            CloudArtifactKind(rawValue: path[1]) != nil
                && path[2].range(of: #"^[0-9a-f]{64}\.aar\z"#, options: .regularExpression) != nil
        }
        if treeFolder(entry.file.key.value) != nil {
            return entry.dependencies.isEmpty && entry.file.size >= 0 && entry.file.md5 != nil
        }
        guard let path = parts(entry.file), let title = titleID(in: path[0]) else { return false }
        if isArchive(path) { return path[0] == title && entry.dependencies.isEmpty }
        guard path[1] == "manifests",
              path[2].range(of: #"^[0-9]{16}-[0-9a-f]{64}\.json\z"#, options: .regularExpression) != nil else { return false }
        return !entry.dependencies.isEmpty && entry.dependencies.allSatisfy { object in
            if let folder = treeFolder(object.key.value) {
                return titleID(in: folder.components(separatedBy: "/")[0]) == title
                    && object.size >= 0 && object.md5 != nil
            }
            return parts(object).map { $0[0] == title && isArchive($0) } == true
        }
    }

    private static func treeFolder(_ path: String) -> String? {
        let parts = path.components(separatedBy: "/")
        guard parts.count >= 4, parts.allSatisfy(validName),
              let kind = CloudArtifactKind(rawValue: parts[1]),
              parts[2].range(of: #"^[0-9a-f]{64}\z"#, options: .regularExpression) != nil else { return nil }
        guard let title = titleID(in: parts[0]), parts[0] != title else { return nil }
        let count = kind == .app ? 4 : 3
        guard parts.count > count, kind != .app || (parts[3] as NSString).pathExtension.lowercased() == "app" else { return nil }
        let relative = parts.dropFirst(count).joined(separator: "/")
        let logical = relative.hasSuffix(CloudArtifactFiles.linkSuffix)
            ? String(relative.dropLast(CloudArtifactFiles.linkSuffix.count)) : relative
        guard !logical.isEmpty, SaveFiles.validRelative(logical), !CloudArchiveInventory.isExcluded(logical, kind)
        else { return nil }
        return parts.prefix(count).joined(separator: "/")
    }

    private func moveFile(_ file: StorageObject, from source: String, to destination: String,
                          binding: MoveBinding?) async throws -> Bool {
        let key = file.key.value
        let old = try target(Self.joining(source, key))
        let new = try target(Self.joining(binding == nil ? destination : "", key), rootID: binding?.destinationID)
        let parts = key.components(separatedBy: "/")
        let parent = parts.dropLast().joined(separator: "/")
        let name = parts.last
        func siblings(_ root: String, id: String?) async throws -> [Item] {
            try await contents(Self.joining(id == nil ? root : "", parent), recursive: false, rootID: id)
                .filter { $0.Name == name }
        }
        let current = try await siblings(source, id: binding?.sourceID)
        let existing = try await siblings(destination, id: binding?.destinationID)
        if current.isEmpty { return Self.matches(file, existing) }
        // A path-based delete can trash a replacement uploaded after the comparison.
        guard Self.matches(file, current), existing.isEmpty else { return false }
        if remote == ":local:" {
            // The local rclone Move uses a replacing rename.
            let path = String(new.dropFirst(remote.count))
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Task.checkCancellation()
            guard renamex_np(String(old.dropFirst(remote.count)), path, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { return false }
                throw CloudArchiveError.installFailed
            }
        } else if let binding, let id = current[0].ID, Self.validID(id) {
            guard current[0].Name.utf8.elementsEqual(name?.utf8 ?? "".utf8) else { return false }
            guard try await accountID() == binding.account else { throw MoveFailure.accountChanged }
            _ = try await checked(["backend", "moveid", try target("", rootID: binding.sourceID), id, new,
                                   "--drive-server-side-across-configs", "--drive-use-trash=true",
                                   "--disable", "Copy", "--max-transfer", "0"])
        } else { return false }
        let final = try await siblings(destination, id: binding?.destinationID)
        let remaining = try await siblings(source, id: binding?.sourceID)
        return Self.matches(file, final) && remaining.isEmpty
            && (binding == nil || final.first?.ID == current[0].ID)
    }

    private static func validID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9_-]{1,256}\z"#, options: .regularExpression) != nil && id != "root"
    }

    private func accountID() async throws -> String {
        guard CloudLibraryPreference.validRemote(remote) else { throw MoveFailure.missingIdentity }
        // Clear remote overrides so a shared folder ID cannot stand in for the account ID.
        let result = try await checkedResult(["about", "\(remote),root_folder_id=,team_drive=:", "--json", "--log-level", "DEBUG"])
        guard let id = CloudDriveScope.accountID(in: result.stderr) else { throw MoveFailure.missingIdentity }
        return id
    }

    private func moveBinding(from source: String, to destination: String) async throws -> MoveBinding {
        let account = try await accountID()
        let sourceID = try await folderID(source)
        let destinationID = try await folderID(destination)
        guard sourceID != destinationID else { throw MoveFailure.foldersChanged }
        return .init(account: account, sourceID: sourceID, destinationID: destinationID, destination: destination)
    }

    private func verifyBinding(_ plan: MovePlan, to destination: String) async throws {
        if remote == ":local:" {
            _ = try await folderID(plan.source)
            _ = try await folderID(destination)
            return
        }
        guard Self.isBound(plan, to: destination), let binding = plan.binding else { throw MoveFailure.missingIdentity }
        guard try await accountID() == binding.account else { throw MoveFailure.accountChanged }
        let sourceID = try await folderID(plan.source)
        let destinationID = try await folderID(destination)
        guard sourceID == binding.sourceID, destinationID == binding.destinationID else { throw MoveFailure.foldersChanged }
    }

    private static func matches(_ file: StorageObject, _ items: [Item]) -> Bool {
        items.count == 1 && !items[0].IsDir && file.size == items[0].Size
            && file.md5 != nil && file.md5 == items[0].object.md5
    }

    private static func uniquePath(_ path: String, in listing: [String: [Item]]) -> Bool {
        var prefix = ""
        let parts = path.components(separatedBy: "/")
        for (index, part) in parts.enumerated() {
            prefix = joining(prefix, part)
            guard let items = listing[prefix] else { continue }
            if items.count != 1 || items[0].IsDir != (index < parts.count - 1) { return false }
        }
        return true
    }

    private func folderID(_ folder: String) async throws -> String {
        _ = try target(folder)
        guard !folder.isEmpty else { throw StorageBackendError.invalidKey }
        var parent = ""
        var id: String?
        for name in folder.components(separatedBy: "/") {
            let matches = try await contents(parent, recursive: false, hashes: false).filter { $0.Name == name }
            guard matches.count == 1, matches[0].IsDir, matches[0].Name.utf8.elementsEqual(name.utf8)
            else { throw MoveFailure.foldersChanged }
            id = matches[0].ID
            parent = Self.joining(parent, matches[0].Name)
        }
        if remote == ":local:" { return parent }
        guard let id, Self.validID(id) else { throw MoveFailure.missingIdentity }
        return id
    }

    private func contents(_ folder: String, recursive: Bool, hashes: Bool = true, deep: Bool = false,
                          rootID: String? = nil, allowMissing: Bool = true) async throws -> [Item] {
        let scope = recursive ? ["--recursive", "--exclude", "/.arcane-upload/**"] + (deep ? [] : ["--max-depth", "3"]) : []
        let hashing = hashes ? ["--hash-type", "MD5"] : []
        do {
            let output = try await checked(["lsjson", try target(folder, rootID: rootID), "--no-modtime", "--no-mimetype"] + scope + hashing)
            return try JSONDecoder().decode([Item].self, from: Data(output.utf8))
        } catch StorageBackendError.notFound where allowMissing { return [] }
    }

    private func backend(in folder: String) throws -> RcloneStorageBackend {
        let path = try target(folder)
        let prefix = remote == ":local:" ? remote : remote + ":"
        return RcloneStorageBackend(remote: remote, root: String(path.dropFirst(prefix.count)),
                                    executable: executable, config: config)
    }

    private struct Item: Decodable {
        let Name: String
        let IsDir: Bool
        let path: String?
        let size: Int64?
        let Hashes: [String: String]?
        let ID: String?

        enum CodingKeys: String, CodingKey { case Name, IsDir, Hashes, ID, path = "Path", size = "Size" }
        var Path: String { path ?? Name }
        var Size: Int64 { size ?? -1 }
        var object: StorageObject {
            StorageObject(key: StorageObjectKey(Path), size: Size,
                          hashes: (Hashes ?? [:]).reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value })
        }
    }

    private func target(_ folder: String, rootID: String? = nil) throws -> String {
        guard folder.isEmpty || folder.components(separatedBy: "/").allSatisfy(Self.validName) else {
            throw StorageBackendError.invalidKey
        }
        if remote == ":local:", let localRoot, localRoot.isFileURL {
            var location = localRoot
            for component in folder.split(separator: "/") {
                location.appendPathComponent(String(component))
                guard (try? FileManager.default.destinationOfSymbolicLink(atPath: location.path)) == nil else {
                    throw StorageBackendError.invalidKey
                }
            }
            return remote + location.path
        }
        guard CloudLibraryPreference.validRemote(remote) else { throw StorageBackendError.invalidConfiguration }
        if let rootID {
            guard Self.validID(rootID) else { throw MoveFailure.missingIdentity }
            return "\(remote),root_folder_id=\(rootID):\(folder)"
        }
        return "\(remote):\(folder)"
    }

    private func checked(_ arguments: [String]) async throws -> String {
        try await checkedResult(arguments).stdout
    }

    private func checkedResult(_ arguments: [String]) async throws -> CommandResult {
        let environment = RcloneConfiguration.environment()
        let flags = RcloneConfiguration.driveFlags + ["--local-links=false", "--copy-links=false",
                     "--retries", "1", "--low-level-retries", "1", "--contimeout", "5s", "--timeout", "10s"]
        let configFlags = RcloneConfiguration.flags(config: config, environment: environment)
        do {
            try Task.checkCancellation()
            if remote != ":local:" {
                let configured = try await run(executable, ["listremotes", "--json"] + configFlags, environment)
                guard configured.status == 0 else { throw RcloneConfiguration.Failure.configuration }
                try RcloneConfiguration.requireDrive(remote, in: configured.stdout)
            }
            try Task.checkCancellation()
            let result = try await run(executable, arguments + flags + configFlags, environment)
            try Task.checkCancellation()
            if result.status != 0, let failure = CloudLibraryFailure.rclone(result.stderr, status: result.status) {
                throw failure
            }
            if result.status == 3 && arguments.first == "lsjson" { throw StorageBackendError.notFound }
            guard result.status == 0 else { throw RcloneConfiguration.Failure.test }
            if result.stderr.contains("search result INCOMPLETE") { throw StorageBackendError.invalidResponse }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch StorageBackendError.notFound {
            throw StorageBackendError.notFound
        } catch let failure as CloudLibraryFailure {
            throw failure
        } catch {
            throw RcloneConfiguration.Failure.test
        }
    }

    private static let runCommand: RcloneConfiguration.Run = { executable, arguments, environment in
        try await SystemCommandRunner().runCancellable(executable, arguments, environment: environment)
    }
}

/// rclone saves update options before OAuth completes. Stage the encrypted file so cancellation or a failed
/// access check cannot break the account Arcane is currently using.
public final class CloudDriveCredentialChange: Sendable {
    public let config: URL
    private let original: URL
    private let baseline: Data

    private init(config: URL, original: URL, baseline: Data) {
        self.config = config
        self.original = original
        self.baseline = baseline
    }

    deinit { try? FileManager.default.removeItem(at: config.deletingLastPathComponent()) }

    public static func prepare(remote: String, executable: URL, clientID: String,
                               secret: String) async throws -> CloudDriveCredentialChange {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CloudSetupAssistantDraft.validGoogleClientID(id), RcloneConfiguration.validCredential(password),
              CloudLibraryPreference.validRemote(remote) else { throw RcloneConfiguration.Failure.connect }
        let environment = RcloneConfiguration.environment()
        @Sendable func run(_ args: [String], config: URL? = nil) async throws -> String {
            do {
                let result = try await SystemCommandRunner().runCancellable(executable,
                    args + RcloneConfiguration.flags(config: config, environment: environment), environment: environment)
                guard result.status == 0 else { throw RcloneConfiguration.Failure.connect }
                return result.stdout
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw RcloneConfiguration.Failure.connect
            }
        }
        let location = try await run(["config", "file"])
        guard let path = location.split(separator: "\n").last, path.hasPrefix("/") else {
            throw RcloneConfiguration.Failure.configuration
        }
        let original = URL(fileURLWithPath: String(path))
        let staged = try await Task.detached(priority: .utility) { try stage(original) }.value
        _ = try await run(["config", "encryption", "check"], config: staged.config)
        try Task.checkCancellation()
        try await RcloneConfiguration.authorizeDrive(executable: executable, config: staged.config,
            environment: environment, name: remote, clientID: id, secret: password, replacing: true)
        return staged
    }

    static func stage(_ original: URL) throws -> CloudDriveCredentialChange {
        let properties = try original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink == false else {
            throw RcloneConfiguration.Failure.configuration
        }
        let baseline = try Data(contentsOf: original)
        guard baseline.starts(with: "# Encrypted rclone configuration File".utf8)
            || baseline.starts(with: "RCLONE_ENCRYPT_V0:".utf8) else { throw RcloneConfiguration.Failure.encryption }
        let directory = original.deletingLastPathComponent().appendingPathComponent(".arcane-rclone-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        let staged = CloudDriveCredentialChange(config: directory.appendingPathComponent("rclone.conf"),
                                                original: original, baseline: baseline)
        guard fm.createFile(atPath: staged.config.path, contents: baseline, attributes: [.posixPermissions: 0o600])
        else { throw RcloneConfiguration.Failure.configuration }
        return staged
    }

    /// Reject a file that rclone or another application changed during the wizard.
    public func apply() throws {
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        let properties = try original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink == false,
              try Data(contentsOf: original) == baseline,
              rename(config.path, original.path) == 0 else {
            throw RcloneConfiguration.Failure.configuration
        }
    }
}
