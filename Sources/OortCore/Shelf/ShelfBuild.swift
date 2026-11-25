import Foundation

/// A build of one game for one kind of device, as `targets/<platform>/<stamp>-<sha256>.json` describes it beside the Mac's archive.
/// The Mac's own app stays in its own manifests (`ShelfMacBuild`).
public struct ShelfBuild: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let path: String
        public let size: Int64
        public let sha256: String

        public init(path: String, size: Int64, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    public let titleID: String
    public let name: String
    public let platform: ShelfPlatform
    public let gameVersion: String
    public let engineCommit: String
    /// The oldest system that runs it.
    public let minimumSystem: String
    public let architecture: String
    /// What the graphics unit must offer, such as `apple7` or `bc`. A device that does not know a word does not have it.
    public let features: [String]
    /// The launcher-side contract it was built for.
    public let host: Int
    /// The framework folder or the APK inside the build.
    public let package: String
    /// Android: the package it installs as, its version code and its signer.
    public let packageID: String?
    public let packageVersion: Int64?
    public let packageSigner: String?
    public let bytes: Int64
    public let entries: [Entry]
    /// SHA-256 of the entries: the name of the folder that holds them.
    public let digest: String
    /// Publication time in milliseconds: the newest build wins.
    public let stamp: Int64
    /// The source's identifier of that folder, nil when it is not there.
    public internal(set) var folder: String?
}

public enum ShelfPlatform: String, CaseIterable, Sendable {
    case ios, android
}

/// The device that asks. `features` and `host` are what it really has.
public struct ShelfDevice: Equatable, Sendable {
    public let platform: ShelfPlatform
    public let system: String
    public let architecture: String
    public let features: Set<String>
    public let host: Int

    public init(platform: ShelfPlatform, system: String, architecture: String = "arm64", features: Set<String>, host: Int) {
        self.platform = platform
        self.system = system
        self.architecture = architecture
        self.features = features
        self.host = host
    }

    /// Why a build would not run here, nil when it runs.
    public func refusal(of build: ShelfBuild) -> ShelfHidden.Reason? {
        guard build.platform == platform, build.architecture == architecture else { return .notPrepared }
        guard let order = ShelfNames.compareVersions(build.minimumSystem, system), order <= 0 else { return .system }
        guard Set(build.features).isSubset(of: features) else { return .graphics }
        return build.host == host ? nil : .launcher
    }
}

extension ShelfBuild {
    public static let manifestLimit: Int64 = 16 * 1024 * 1024
    public static let maximumEntries = 50_000
    static let signedPrefix = "oort-target-1\n"

    private struct File: Decodable {
        struct Engine: Decodable { let commit: String }
        struct Requires: Decodable { let os: String, arch: String, features: [String], host: Int }
        struct Package: Decodable { let path: String, id: String?, version_code: Int64?, certificate_sha256: String? }
        struct Item: Decodable { let path: String, size: Int64, sha256: String }
        let format: String, version: Int, title_id: String, game_name: String, game_version: String, platform: String
        let engine: Engine, requires: Requires, package: Package
        let unpacked_size: Int64, entry_count: Int, inventory_sha256: String, entries: [Item]
    }

    /// Checks everything before anything is shown: the name, the content's hash, the signature, the paths and the sizes.
    static func read(_ data: Data, signature: Data, stamp: Int64, sha256: String, titleID: String, platform: ShelfPlatform,
                     crypto: ShelfCrypto) throws -> Self {
        guard Int64(data.count) <= manifestLimit, crypto.digest(data) == sha256 else { throw ShelfError.invalidManifest }
        guard crypto.isSigned(Data(signedPrefix.utf8) + data, signature) else { throw ShelfError.unsigned }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.format == "oort-target", file.version == 1,
              file.title_id == titleID, file.platform == platform.rawValue, file.entry_count == file.entries.count,
              (1...maximumEntries).contains(file.entries.count), ShelfNames.isHex(file.engine.commit, count: 40),
              (1...40).contains(file.game_version.utf8.count), ShelfNames.isPlain(file.game_version),
              ShelfNames.compareVersions(file.requires.os, "0") != nil, file.requires.host >= 0,
              file.requires.features.count <= 32 else { throw ShelfError.invalidManifest }
        let entries = file.entries.map { Entry(path: $0.path, size: $0.size, sha256: $0.sha256) }
        let bytes = try total(entries)
        guard bytes == file.unpacked_size, digest(entries, crypto: crypto) == file.inventory_sha256
        else { throw ShelfError.invalidManifest }
        let package = file.package
        switch platform {
        case .ios:
            guard package.path.hasSuffix(".framework"), !package.path.contains("/"),
                  entries.contains(where: { $0.path.hasPrefix(package.path + "/") }) else { throw ShelfError.invalidManifest }
        case .android:
            guard package.path.hasSuffix(".apk"), !package.path.contains("/"), entries.contains(where: { $0.path == package.path }),
                  package.id?.range(of: #"^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+\z"#, options: .regularExpression) != nil,
                  let code = package.version_code, code > 0, ShelfNames.isHex(package.certificate_sha256 ?? "", count: 64)
            else { throw ShelfError.invalidManifest }
        }
        return Self(titleID: titleID, name: ShelfNames.displayName(file.game_name, titleID: titleID), platform: platform,
                    gameVersion: file.game_version, engineCommit: file.engine.commit, minimumSystem: file.requires.os,
                    architecture: file.requires.arch, features: file.requires.features, host: file.requires.host,
                    package: package.path, packageID: package.id, packageVersion: package.version_code,
                    packageSigner: package.certificate_sha256, bytes: bytes, entries: entries,
                    digest: file.inventory_sha256, stamp: stamp, folder: nil)
    }

    /// The same bytes as the Mac's encoder: sorted keys, no spaces, slashes as they are.
    static func digest(_ entries: [Entry], crypto: ShelfCrypto) -> String {
        let items = entries.map { "{\"path\":\(ShelfNames.quoted($0.path)),\"sha256\":\"\($0.sha256)\",\"size\":\($0.size)}" }
        return crypto.digest(Data(("[" + items.joined(separator: ",") + "]").utf8))
    }

    private static func total(_ entries: [Entry]) throws -> Int64 {
        var bytes: Int64 = 0
        var seen: [String: (name: String, isFolder: Bool)] = [:]
        for entry in entries {
            guard ShelfNames.isSafePath(entry.path) else { throw ShelfError.unsafeName }
            guard entry.size >= 0, entry.size <= Int64.max - bytes, ShelfNames.isHex(entry.sha256, count: 64)
            else { throw ShelfError.invalidManifest }
            bytes += entry.size
            // One spelling per name, and a name is a file or a folder, never both.
            var prefix = ""
            let parts = entry.path.components(separatedBy: "/")
            for (index, part) in parts.enumerated() {
                prefix += (prefix.isEmpty ? "" : "/") + part
                let isFolder = index < parts.count - 1
                if let old = seen[ShelfNames.folded(prefix)] {
                    guard isFolder, old.isFolder, old.name.utf8.elementsEqual(prefix.utf8) else { throw ShelfError.unsafeName }
                } else {
                    seen[ShelfNames.folded(prefix)] = (prefix, isFolder)
                }
            }
        }
        return bytes
    }
}

/// What the Mac's own manifest (version 1 or 2) says of its app. The phone shows it as "on your Mac"; it never downloads it.
public struct ShelfMacBuild: Equatable, Sendable {
    public let titleID: String
    public let name: String?
    public let gameVersion: String?
    public let engineCommit: String?
    public let bytes: Int64
    public let stamp: Int64

    static let manifestLimit: Int64 = 32 * 1024 * 1024
    private static let legacyLimit = 64 * 1024

    private struct File: Decodable {
        struct Artifact: Decodable {
            struct Tree: Decodable { let folder: String, entries: [Item] }
            struct Item: Decodable { let path: String, size: Int64, md5: String }
            let kind: String, size: Int64?, sha256: String?, md5: String?, unpacked_size: Int64, entry_count: Int
            let inventory_sha256: String, engine_commit: String?, options: [String: String], files: Tree?
            let published_at: Date?, revision: Int64?
        }
        let version: Int, title_id: String, created_at: Date, artifacts: [Artifact], game_name: String?
    }

    /// Nil when this snapshot holds no app. The checks are the Mac's own (`CloudGameArchive.readManifest`).
    static func read(_ data: Data, name: (stamp: Int64, sha256: String), titleID: String, crypto: ShelfCrypto) throws -> Self? {
        guard Int64(data.count) <= manifestLimit, crypto.digest(data) == name.sha256 else { throw ShelfError.invalidManifest }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), [1, 2].contains(file.version), file.title_id == titleID,
              [["app"], ["app", "cache"], [], ["cache"]].contains(file.artifacts.map(\.kind)),
              file.version == 2 || data.count <= legacyLimit else { throw ShelfError.invalidManifest }
        for artifact in file.artifacts {
            guard artifact.unpacked_size >= 0, ShelfNames.isHex(artifact.inventory_sha256, count: 64)
            else { throw ShelfError.invalidManifest }
            if let revision = artifact.revision {
                guard revision > 0, revision <= name.stamp,
                      artifact.published_at == Date(timeIntervalSince1970: Double(revision / 1000)) else { throw ShelfError.invalidManifest }
            }
            if let tree = artifact.files {
                let parts = tree.folder.components(separatedBy: "/")
                guard file.version == 2, artifact.size == nil, artifact.sha256 == nil, artifact.md5 == nil,
                      artifact.entry_count == tree.entries.count, parts.count == (artifact.kind == "app" ? 4 : 3),
                      parts.allSatisfy(ShelfNames.isPlain), parts[0].hasSuffix(" [\(titleID)]"), parts[1] == artifact.kind,
                      parts[2] == artifact.inventory_sha256,
                      tree.entries.allSatisfy({ $0.size >= 0 && ShelfNames.isHex($0.md5, count: 32) }),
                      digest(tree.entries, crypto: crypto) == artifact.inventory_sha256 else { throw ShelfError.invalidManifest }
                var bytes: Int64 = 0
                for entry in tree.entries {
                    guard entry.size <= Int64.max - bytes else { throw ShelfError.invalidManifest }
                    bytes += entry.size
                }
                guard bytes == artifact.unpacked_size else { throw ShelfError.invalidManifest }
            } else {
                guard let size = artifact.size, size > 0, ShelfNames.isHex(artifact.sha256 ?? "", count: 64),
                      ShelfNames.isHex(artifact.md5 ?? "", count: 32) else { throw ShelfError.invalidManifest }
            }
        }
        guard let app = file.artifacts.first(where: { $0.kind == "app" }) else { return nil }
        let published = app.published_at ?? file.created_at
        return Self(titleID: titleID, name: file.game_name.map { ShelfNames.displayName($0, titleID: titleID) },
                    gameVersion: app.options["CFBundleShortVersionString"], engineCommit: app.engine_commit,
                    bytes: app.unpacked_size, stamp: app.revision ?? Int64(published.timeIntervalSince1970 * 1000))
    }

    private static func digest(_ entries: [File.Artifact.Item], crypto: ShelfCrypto) -> String {
        let items = entries.map { "{\"md5\":\"\($0.md5)\",\"path\":\(ShelfNames.quoted($0.path)),\"size\":\($0.size)}" }
        return crypto.digest(Data(("[" + items.joined(separator: ",") + "]").utf8))
    }
}
