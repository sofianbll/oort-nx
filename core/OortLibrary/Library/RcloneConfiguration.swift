import Foundation
import Security

package struct CloudDriveScope: Codable, Equatable, Sendable {
    package struct Folder: Codable, Equatable, Sendable {
        package let path: String
        package let id: String

        package init(path: String, id: String) {
            self.path = path
            self.id = id
        }
    }

    /// Where a new folder goes: the account and the parent's own ID, never its path alone.
    package struct CreationParent: Equatable, Sendable {
        package let account: String
        package let id: String

        package init(account: String, id: String) {
            self.account = account
            self.id = id
        }
    }

    package let remote: String
    package let account: String
    package let library: Folder
    package var sources: Folder?
    package var approvedSources: Folder?
    package var sourcesIdentityChanged: Bool?
    package var reference: String?

    package init(remote: String, account: String, library: Folder, sources: Folder? = nil, reference: String? = nil) {
        self.remote = remote
        self.account = account
        self.library = library
        self.sources = sources
        self.reference = reference
    }

    package var availabilityKey: [String] { [remote, account, library.id, sources?.id ?? "", reference ?? ""] }

    package mutating func resolveSources(_ found: Folder?, at path: String, previous: CloudDriveScope?) {
        let prior = previous.flatMap { old -> CloudDriveScope? in
            old.remote == remote && old.account == account && old.library == library ? old : nil
        }
        let previousApproval = (prior?.approvedSources ?? prior?.sources).flatMap { $0.path == path ? $0 : nil }
        approvedSources = previousApproval ?? found
        if let previousApproval, prior?.sourcesIdentityChanged == true || (found != nil && found != previousApproval) {
            sourcesIdentityChanged = true
            sources = nil
        } else {
            sources = found
        }
    }

    package mutating func clearSourcesApproval() {
        sources = nil
        approvedSources = nil
        sourcesIdentityChanged = nil
    }

    // shortcut: rclone does not expose the canonical My Drive ID as structured data.
    package static func accountID(in diagnostic: String) -> String? {
        struct LogLine: Decodable { let msg: String }
        let marker = "'root_folder_id = ", suffix = "' - save this in the config to speed up startup"
        let matches = Set(diagnostic.split(whereSeparator: \.isNewline).compactMap { raw -> String? in
            let line = (try? JSONDecoder().decode(LogLine.self, from: Data(raw.utf8)))?.msg ?? String(raw)
            guard let start = line.range(of: marker, options: .backwards), line.hasSuffix(suffix) else { return nil }
            return String(line[start.upperBound..<line.index(line.endIndex, offsetBy: -suffix.count)])
        })
        guard matches.count == 1, let id = matches.first, validID(id) else { return nil }
        return id
    }

    static func validID(_ id: String) -> Bool {
        id != "root" && id != "appDataFolder" && id.range(of: #"^[A-Za-z0-9_-]{1,256}\z"#, options: .regularExpression) != nil
    }
}

/// Keep one private config for an effect and its checks; never write refreshed credentials back over the user's file.
package final class RcloneConfigSnapshot: Sendable {
    package let config: URL
    private let lease: Int32
    static let prefix = "arcane-rclone-config-"
    private static let sweep = Task.detached(priority: .utility) { removeAbandoned(in: FileManager.default.temporaryDirectory) }

    private init(config: URL) {
        self.config = config
        lease = Self.claim(config.deletingLastPathComponent())
    }

    deinit {
        try? FileManager.default.removeItem(at: config.deletingLastPathComponent())
        if lease >= 0 { close(lease) }
    }

    private static func claim(_ directory: URL) -> Int32 {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return -1 }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
        close(fd)
        return -1
    }

    /// A copy whose owner is gone (a crash, a power cut) must not keep an account on disk. A living copy holds its lease;
    /// the age spares one made by a version without leases.
    static func removeAbandoned(in temporary: URL, olderThan age: TimeInterval = 3_600) {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
            where url.lastPathComponent.hasPrefix(prefix) && UUID(uuidString: String(url.lastPathComponent.dropFirst(prefix.count))) != nil {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
                  Date.now.timeIntervalSince1970 - Double(OortSystem.modified(info).seconds) >= age else { continue }
            let fd = claim(url)
            guard fd >= 0 else { continue }
            try? fm.removeItem(at: url)
            close(fd)
        }
    }

    package static func capture(executable: URL, config: URL?, run: RcloneConfiguration.Run) async throws -> RcloneConfigSnapshot {
        _ = sweep
        let original: URL
        if let config {
            original = config
        } else {
            let environment = RcloneConfiguration.environment()
            let result = try await run(executable, ["config", "file"]
                + RcloneConfiguration.flags(config: nil, environment: environment), environment)
            guard result.status == 0, let path = result.stdout.split(whereSeparator: \.isNewline).last,
                  path.hasPrefix("/") else { throw RcloneConfiguration.Failure.configuration }
            original = URL(fileURLWithPath: String(path))
        }
        return try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let regularFile = original.resolvingSymlinksInPath()
            guard try regularFile.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw RcloneConfiguration.Failure.configuration
            }
            let contents = try Data(contentsOf: regularFile)
            let fm = FileManager.default
            let directory = fm.temporaryDirectory.appendingPathComponent("\(prefix)\(UUID())")
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let snapshot = RcloneConfigSnapshot(config: directory.appendingPathComponent("rclone.conf"))
            guard fm.createFile(atPath: snapshot.config.path, contents: contents, attributes: [.posixPermissions: 0o600])
            else { throw RcloneConfiguration.Failure.configuration }
            return snapshot
        }.value
    }
}

/// A settings toggle is not new consent to use another Drive connection.
public struct CloudLibraryActivation: Codable, Equatable, Sendable {
    public let storage: String
    public let connection: String?
    public let wasEnabled: Bool
    public let enabled: Bool

    public init?(_ base: CloudLibraryPreference, connection: String?, enabled: Bool) {
        guard base.remote != nil, let storage = base.storage else { return nil }
        self.storage = storage
        self.connection = connection
        self.wasEnabled = base.enabled
        self.enabled = enabled
    }

    public func applying(to base: CloudLibraryPreference, connection: String?) -> CloudLibraryPreference {
        guard base.remote != nil, base.storage == storage, self.connection == connection, base.enabled == wasEnabled else { return base }
        return CloudLibraryPreference(storage: base.storage, enabled: enabled, sourcesRoot: base.sourcesRootOverride,
                                      referenceFolder: base.referenceFolder)
    }
}

public struct CloudLibraryPreference: Equatable, Sendable {
    public static let storageKey = "NXLibrary_CloudStorage"
    public static let sourcesRootKey = "NXLibrary_CloudSourcesRoot"
    package static let sourcesBindingKey = "NXLibrary_CloudSourcesBinding"
    public static let enabledKey = "NXLibrary_CloudStorageEnabled"
    public static let executableKey = "NXLibrary_RclonePath"
    public static let referenceFolderKey = "NXLibrary_CloudReferenceFolder"
    /// The name of a connection signed out with its Google client kept; never the client itself.
    public static let keptConnectionKey = "NXLibrary_DriveKeptConnection"
    public static let toolChoiceKey = "NXLibrary_DriveToolChoice"
    public static let toolOfferKey = "NXLibrary_DriveToolOfferSeen"
    public static let defaultRoot = "Games"

    public let remote: String?
    public let root: String
    public let sourcesRootOverride: String?
    public let enabled: Bool
    public let referenceFolder: String?

    public init(storage: String?, enabled: Bool?, sourcesRoot: String? = nil, referenceFolder: String? = nil) {
        let parts = (storage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts.first.map(String.init) ?? ""
        let folder = parts.count == 2 ? String(parts[1]) : Self.defaultRoot
        let valid = Self.validRoot(folder)
        remote = valid && Self.validRemote(name) ? name : nil
        root = valid ? folder : Self.defaultRoot
        sourcesRootOverride = sourcesRoot.flatMap { Self.validSourcesRoot($0) ? $0 : nil }
        self.enabled = enabled ?? (remote != nil)
        self.referenceFolder = referenceFolder.flatMap(Self.referenceFolderID)
    }

    public static func referenceFolderID(_ input: String) -> String? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func valid(_ id: String) -> Bool {
            id != "root" && id != "appDataFolder" && !id.hasPrefix("-")
                && id.range(of: #"^[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil
        }
        if valid(input) { return input }
        guard let url = URLComponents(string: input), url.scheme == "https", url.host == "drive.google.com",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let path = url.percentEncodedPath.components(separatedBy: "/")
        guard path.count == 4 || (path.count == 5 && path[4].isEmpty),
              path[0].isEmpty, path[1] == "drive", path[2] == "folders", valid(path[3]) else { return nil }
        return path[3]
    }

    public var sourcesRoot: String {
        sourcesRootOverride ?? root + (root.hasSuffix("/") ? "" : "/") + "GameFiles"
    }

    public var sourcesStorage: String? { remote.map { "\($0):\(sourcesRoot)" } }

    package struct SourcesBinding: Codable, Equatable, Sendable {
        package let storage: String
        package let sources: String
        package var account: String?
        package var folderID: String?

        package init?(_ preference: CloudLibraryPreference) {
            guard let storage = preference.storage, preference.remote != nil,
                  let sources = preference.sourcesRootOverride else { return nil }
            self.storage = storage
        self.sources = sources
        }

        package func permits(_ scope: CloudDriveScope) -> Bool {
            (account == nil || account == scope.account) && (folderID == nil || folderID == scope.library.id)
        }
    }

    public var storage: String? {
        if let remote { return "\(remote):\(root)" }
        return root == Self.defaultRoot ? nil : ":\(root)"
    }

    public static func validRoot(_ root: String) -> Bool {
        !root.split(separator: "/").isEmpty && safePath(root)
    }

    public static func validSourcesRoot(_ root: String) -> Bool {
        !root.hasPrefix("/") && !root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validRoot(root)
    }

    package static func safePath(_ path: String) -> Bool {
        !path.contains("\\") && !path.contains(":")
            && path.rangeOfCharacter(from: .controlCharacters) == nil
            && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }

    package static func validRemote(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_. -]*\z"#, options: .regularExpression) != nil
    }

    public enum Connection: Equatable {
        case connected(RcloneRemote), notConnected, unknown
    }

    /// An unlocked, locally configured remote is connected; only the test checks network access.
    public func connection(in remotes: [RcloneRemote]?) -> Connection {
        guard let remote else { return .notConnected }
        guard let remotes else { return .unknown }
        return remotes.first { $0.name == remote }.map(Connection.connected) ?? .notConnected
    }
}

public struct RcloneRemote: Equatable, Sendable, Decodable {
    public let name: String
    public let type: String
    fileprivate let source: String
}

/// What rclone keeps for a connection: whether it is there, never its value.
public struct RcloneAccount: Equatable, Sendable {
    public let hasClient: Bool
    public let isSignedIn: Bool

    public init(hasClient: Bool, isSignedIn: Bool) {
        self.hasClient = hasClient
        self.isSignedIn = isSignedIn
    }

    /// Signed out with the Google ID and secret still in rclone's encrypted file: signing in again asks for neither.
    public var keepsClient: Bool { hasClient && !isSignedIn }
}

public struct RcloneConfiguration: Sendable {
    // Keep the parent-ID predicate and include active files owned by other accounts.
    private static let driveFilters = ["shared_with_me", "starred_only", "auth_owner_only", "trashed_only"]
    package static let driveFlags = driveFilters.map {
        "--drive-\($0.replacingOccurrences(of: "_", with: "-"))=false"
    } + ["--drive-skip-shortcuts"]

    package static func driveEnvironment(_ remote: String, base: [String: String] = environment()) -> [String: String] {
        let name = remote.hasSuffix(":") ? String(remote.dropLast()) : remote
        guard CloudLibraryPreference.validRemote(name) else { return base }
        // Older rclone versions ignore a flag set to its default value when a remote overrides it.
        var result = base
        let prefix = "RCLONE_CONFIG_\(name.uppercased())_"
        for filter in driveFilters { result[prefix + filter.uppercased()] = "false" }
        return result
    }

    static let passwordCommand = "/usr/bin/security find-generic-password -a rclone -s rclone-config -w"
    private static let service = "rclone-config"
    private static let account = "rclone"

    package typealias Run = @Sendable (URL, [String], [String: String]) async throws -> CommandResult
    typealias Authorize = @Sendable (URL, URL?, [String: String], String, (id: String, secret: String)?, Bool) async throws -> Void
    private let executable: URL
    private let config: URL?
    private let run: Run
    private let ensurePassword: @Sendable () async throws -> Void
    private let authorize: Authorize
    private let environment: [String: String]

    public init(executable: URL) {
        self.init(executable: executable, config: nil, run: {
            try await RcloneDownload.runCancellable($0, $1, environment: $2)
        }, ensurePassword: {
            try await Task.detached(priority: .utility) { try Self.ensureKeychainPassword() }.value
        }, environment: Self.environment())
    }

    init(executable: URL, config: URL?, run: @escaping Run,
         ensurePassword: @escaping @Sendable () async throws -> Void, environment: [String: String] = [:],
         authorize: @escaping Authorize = RcloneConfiguration.authorizeDrive) {
        self.executable = executable
        self.config = config
        self.run = run
        self.ensurePassword = ensurePassword
        self.environment = environment
        self.authorize = authorize
    }

    package static func environment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter {
            !["ARCANE_GOOGLE_CLIENT_ID", "ARCANE_GOOGLE_CLIENT_SECRET"].contains($0.key)
                && (!$0.key.hasPrefix("RCLONE_") || ["RCLONE_CONFIG", "RCLONE_CONFIG_PASS", "RCLONE_PASSWORD_COMMAND"].contains($0.key))
        }
    }

    package static func flags(config: URL?, environment: [String: String]) -> [String] {
        var flags = ["--ask-password=false"]
        if let config { flags += ["--config", config.path] }
        if environment["RCLONE_CONFIG_PASS"] == nil, environment["RCLONE_PASSWORD_COMMAND"] == nil {
            flags += ["--password-command", passwordCommand]
        }
        return flags
    }

    package static func sharesDefaultConfiguration(_ executable: URL,
                                                   environment: [String: String] = environment()) -> Bool {
        if let path = environment["RCLONE_CONFIG"], !path.isEmpty { return true }
        // rclone prefers a portable config beside the executable to the shared user config.
        return [executable, executable.resolvingSymlinksInPath()].allSatisfy {
            !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().appendingPathComponent("rclone.conf").path)
        }
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case tool, portableConfiguration, configuration, encryption, connect, test, disconnect

        public var errorDescription: String? { L10n.text(key) }

        public var key: String {
            switch self {
            case .tool: return "Arcane could not run rclone. Choose a working rclone executable."
            case .portableConfiguration: return "This rclone uses a separate configuration. Choose a copy that uses your existing Drive settings."
            case .configuration: return "Arcane could not read the rclone configuration. Check access to the login keychain and try again."
            case .encryption: return "Arcane could not encrypt the rclone configuration with the login keychain."
            case .connect: return "Google Drive could not be connected. Check your credentials and try again."
            case .test: return "Arcane could not list the cloud folder. Check the folder name and your access."
            case .disconnect: return "Arcane could not remove the local rclone connection."
            }
        }
    }

    public func version() async throws -> String {
        let output = try await checked(["version"], or: .tool)
        guard let line = output.split(whereSeparator: \.isNewline).first, line.hasPrefix("rclone v") else {
            throw Failure.tool
        }
        return String(line)
    }

    public func remotes() async throws -> [RcloneRemote] {
        try Self.parseRemotes(await checked(["listremotes", "--json"], or: .configuration))
    }

    static func parseRemotes(_ output: String) throws -> [RcloneRemote] {
        guard let remotes = try? JSONDecoder().decode([RcloneRemote].self, from: Data(output.utf8)) else {
            throw Failure.configuration
        }
        return remotes.filter { $0.source == "file" && CloudLibraryPreference.validRemote($0.name) }
    }

    package static func requireDrive(_ name: String, in output: String) throws {
        let matches = try parseRemotes(output).filter { $0.name == name }
        guard matches.count == 1, matches[0].type == "drive" else { throw CloudLibraryFailure.requiresDrive }
    }

    public func connect(clientID: String, secret: String) async throws -> RcloneRemote {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validCredential(clientID), Self.validCredential(secret) else { throw Failure.connect }
        let names = Set(try await remotes().map { $0.name.lowercased() })
        var name = "gdrive"
        var index = 2
        while names.contains(name) {
            name = "gdrive-\(index)"
            index += 1
        }

        let check = ["config", "encryption", "check"]
        let initial = try await command(check, or: .encryption)
        if initial.status != 0 {
            // A locked or unreadable config must never be mistaken for plain text.
            guard initial.stderr.split(whereSeparator: \.isNewline).contains("Error: config file is NOT encrypted"),
                  environment["RCLONE_CONFIG_PASS"] == nil, environment["RCLONE_PASSWORD_COMMAND"] == nil
            else { throw Failure.encryption }
            do { try await ensurePassword() }
            catch is CancellationError { throw CancellationError() }
            catch { throw Failure.encryption }
            _ = try await checked(["config", "encryption", "set"], or: .encryption)
            _ = try await checked(check, or: .encryption)
        }

        try await authorize(executable, config, environment, name, (clientID, secret), false)
        guard let remote = try await remotes().first(where: { $0.name == name && $0.type == "drive" }) else {
            throw Failure.connect
        }
        return remote
    }

    /// Without a client, rclone signs in with the one it kept.
    package static func signInParameters(client: (id: String, secret: String)?, replacing: Bool) -> [String: String] {
        var parameters = ["config_is_local": "true"]
        if let client { parameters["client_id"] = client.id; parameters["client_secret"] = client.secret }
        if replacing { parameters["config_refresh_token"] = "true" } else { parameters["scope"] = "drive" }
        return parameters
    }

    package static func authorizeDrive(executable: URL, config: URL?, environment: [String: String],
                                       name: String, client: (id: String, secret: String)?, replacing: Bool) async throws {
        // Drive's client_secret is not an rclone password field; `obscure` here would change the credential.
        // Send config options via stdin to the private Unix-socket RC session, not via process arguments.
        let control = RcloneRemoteControl()
        defer { control.stop() }
        let body: [String: Any] = [
            "name": name, "type": "drive", "parameters": signInParameters(client: client, replacing: replacing),
            "opt": ["noOutput": true],
        ]
        do {
            guard try await control.call(replacing ? "config/update" : "config/create", body,
                executable: executable, environment: environment,
                flags: driveFlags + flags(config: config, environment: environment), sensitive: true) != nil else {
                throw Failure.connect
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw Failure.connect }
    }

    public func test(_ preference: CloudLibraryPreference) async throws {
        guard let remote = preference.remote else { throw Failure.test }
        try Self.requireDrive(remote, in: await checked(["listremotes", "--json"], or: .configuration))
        let path = "\(remote):\(preference.root)"
        let flags = Self.driveFlags + ["--retries", "1", "--low-level-retries", "1",
                     "--contimeout", "5s", "--timeout", "10s"]
        func checkFolder(_ arguments: [String]) async throws -> String {
            let result = try await command(arguments + flags, or: .test, driveRemote: remote)
            guard result.status == 0 else {
                if let failure = CloudLibraryFailure.rclone(result.stderr, status: result.status, listingFolder: true) {
                    throw failure
                }
                throw Failure.test
            }
            guard !result.stderr.contains("search result INCOMPLETE") else { throw CloudLibraryFailure.incomplete }
            return result.stdout
        }
        let output = try await checkFolder(["lsjson", path, "--stat"])
        if output.trimmingCharacters(in: .whitespacesAndNewlines) == "null" { throw CloudLibraryFailure.folderMissing }
        guard let item = try? JSONDecoder().decode(Item.self, from: Data(output.utf8)), item.isDirectory else {
            throw Failure.test
        }
        _ = try await checkFolder(["lsf", path, "--max-depth", "1"])
    }

    private struct Item: Decodable {
        let isDirectory: Bool
        enum CodingKeys: String, CodingKey { case isDirectory = "IsDir" }
    }

    /// `config redacted` replaces every private value before it leaves rclone; only its presence is read here.
    public func account(_ remote: String) async throws -> RcloneAccount {
        guard CloudLibraryPreference.validRemote(remote) else { throw Failure.configuration }
        let present = Set(try await checked(["config", "redacted", remote], or: .configuration)
            .split(whereSeparator: \.isNewline).compactMap { line -> String? in
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.count == 2 && !parts[1].isEmpty ? parts[0] : nil
            })
        return RcloneAccount(hasClient: present.isSuperset(of: ["client_id", "client_secret"]),
                             isSignedIn: present.contains("token"))
    }

    /// Keeping the client empties only the sign-in: the ID and secret stay where they are, in rclone's own file.
    public func disconnect(_ remote: String, keepingClient: Bool = false) async throws {
        guard CloudLibraryPreference.validRemote(remote) else { throw Failure.disconnect }
        let arguments: [String]
        if keepingClient {
            // Check before the write: if verification failed afterwards, the user would already be signed out.
            guard try await account(remote).hasClient else { throw Failure.disconnect }
            arguments = ["config", "update", remote, "token=", "--non-interactive", "--no-output"]
        } else {
            arguments = ["config", "delete", remote]
        }
        let result = try await command(arguments, or: .disconnect)
        // rclone's SaveConfig can log a failed write and still exit zero. Never return that output to the caller.
        guard result.status == 0, !result.stderr.contains("Failed to save config after ") else {
            throw Failure.disconnect
        }
    }

    public static func validCredential(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.utf8.count <= 1024 && text.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private func checked(_ arguments: [String], or failure: Failure) async throws -> String {
        let result = try await command(arguments, or: failure)
        guard result.status == 0 else { throw failure }
        return result.stdout
    }

    private func command(_ arguments: [String], or failure: Failure, driveRemote: String? = nil) async throws -> CommandResult {
        try Task.checkCancellation()
        let environment = driveRemote.map { Self.driveEnvironment($0, base: self.environment) } ?? self.environment
        do { return try await run(executable, arguments + Self.flags(config: config, environment: environment), environment) }
        catch is CancellationError { throw CancellationError() }
        // Never surface subprocess output or launch errors: they can contain OAuth credentials.
        catch { throw failure }
    }

    private static func ensureKeychainPassword() throws {
        // The CLI password command reads the file-based login keychain, not the Data Protection keychain.
        var login: SecKeychain?
        let path = NSHomeDirectory() + "/Library/Keychains/login.keychain-db"
        guard SecKeychainOpen(path, &login) == errSecSuccess, let login else { throw Failure.encryption }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account
        ]
        var search = query
        search[kSecMatchSearchList] = [login]
        let found = SecItemCopyMatching(search as CFDictionary, nil)
        if found == errSecSuccess { return }
        guard found == errSecItemNotFound else { throw Failure.encryption }

        var bytes = Data(count: 32)
        guard bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess
        else { throw Failure.encryption }
        var item = query
        item[kSecUseKeychain] = login
        item[kSecValueData] = bytes.base64EncodedData()
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure.encryption }
    }
}
