import Foundation

public struct CloudLibraryPreference: Equatable, Sendable {
    public static let storageKey = "NXLibrary_CloudStorage"
    public static let sourcesRootKey = "NXLibrary_CloudSourcesRoot"
    package static let sourcesBindingKey = "NXLibrary_CloudSourcesBinding"
    public static let enabledKey = "NXLibrary_CloudStorageEnabled"
    public static let executableKey = "NXLibrary_RclonePath"
    public static let referenceFolderKey = "NXLibrary_CloudReferenceFolder"
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
    let source: String
}
