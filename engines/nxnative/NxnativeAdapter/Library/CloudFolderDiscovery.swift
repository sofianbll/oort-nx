import Foundation
import OortLibrary

/// What the folders of a Drive hold, from one bounded listing of names. It opens no file.
public struct CloudFolderIndex: Equatable, Sendable {
    package struct Entry: Equatable, Sendable {
        let path: String
        let isDirectory: Bool
    }

    /// What a player finds in a folder. Names are the games' own, without their IDs.
    public enum Kind: Equatable, Sendable {
        case roms(count: Int, names: [String])
        case compiled(count: Int, names: [String])
        case oneGame
        /// No game right here, but in folders further in, the fullest first.
        case further([String])
        case nothing
        /// Never read.
        case unknown
    }

    /// Why a folder is the wrong answer, and the one to take instead.
    public struct Advice: Equatable, Sendable {
        public enum Reason: Equatable, Sendable { case compiledHere, romsHere, oneGame, further, nothingHere, sameFolder }
        public let reason: Reason
        public let instead: String?
        /// Each of the two folders is the answer to the other question.
        public let swaps: Bool
    }

    static let limit = 20_000
    private(set) var titled: [String: [String: String]] = [:]
    private(set) var compiled: [String: [String: String]] = [:]
    private(set) var directories = Set<String>()
    /// Folders with anything in them.
    private var occupied = Set<String>()
    private let root: String
    private let depth: Int

    /// `entries` carry paths from the root of My Drive, read `depth` levels below `root`. Names Oort would refuse are left out.
    package init(entries: [Entry], root: String = CloudFolderDiscovery.searchRoot, depth: Int = CloudFolderDiscovery.depth) throws {
        guard entries.count <= Self.limit else { throw StorageBackendError.invalidResponse }
        self.root = root
        self.depth = depth
        for entry in entries {
            let parts = entry.path.components(separatedBy: "/")
            guard parts.allSatisfy(CloudDriveFolders.validName),
                  !parts.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") }) else { continue }
            if entry.isDirectory { directories.insert(entry.path) }
            for depth in parts.indices.dropFirst() { occupied.insert(parts.prefix(depth).joined(separator: "/")) }
            if parts.count >= 3, entry.isDirectory, parts.last == "manifests" {
                add(parts.dropLast(), to: &compiled)
            } else if parts.count >= 4, parts[parts.count - 2] == "manifests", entry.path.hasSuffix(".json") {
                add(parts.dropLast(2), to: &compiled)
            } else if parts.count >= 3, !entry.isDirectory, Self.isPackage(entry.path), parts[parts.count - 2].hasSuffix("]") {
                add(parts.dropLast(), to: &titled)
            }
        }
    }

    /// What a glance at one more folder says: the names in it, and what the first game's folder holds.
    public mutating func note(_ path: String, folders: [String], firstGame: (names: [String], isCompiled: Bool)?) {
        directories.insert(path)
        if !folders.isEmpty { occupied.insert(path) }
        let games = folders.reduce(into: [String: String]()) { games, name in
            if let title = CloudDriveFolders.titleID(in: name) { games[title] = Self.gameName(name) }
        }
        guard !games.isEmpty, let firstGame else { return }
        if firstGame.isCompiled { compiled[path] = games }
        else if firstGame.names.contains(where: Self.isPackage) { titled[path] = games }
    }

    /// The first of these folders that holds nothing yet, so that a new library never lands among other files.
    public func firstFree(of paths: [String]) -> String? { paths.first { !occupied.contains($0) } }

    /// Games whose files are there and that Oort has not compiled yet.
    public func gamesToCompile(sources: String, library: String) -> Int? {
        titled[sources].map { roms in roms.keys.filter { compiled[library]?[$0] == nil }.count }
    }

    private func add(_ folder: ArraySlice<String>, to found: inout [String: [String: String]]) {
        guard let name = folder.last, let title = CloudDriveFolders.titleID(in: name) else { return }
        found[folder.dropLast().joined(separator: "/"), default: [:]][title] = Self.gameName(name)
    }

    static func isPackage(_ path: String) -> Bool {
        CloudGameSources.fileExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Empty for a folder named by its ID alone.
    static func gameName(_ folder: String) -> String {
        guard folder.hasSuffix("]"), CloudDriveFolders.titleID(in: folder) != nil else { return "" }
        return folder.dropLast(18).trimmingCharacters(in: .whitespaces)
    }

    static func names(_ games: [String: String]) -> [String] {
        games.values.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func kind(of path: String) -> Kind {
        if let games = compiled[path] { return .compiled(count: games.count, names: Self.names(games)) }
        if let games = titled[path] { return .roms(count: games.count, names: Self.names(games)) }
        let name = path.components(separatedBy: "/").last ?? ""
        if name.hasSuffix("]"), CloudDriveFolders.titleID(in: name) != nil { return .oneGame }
        let below = further(in: path)
        if !below.isEmpty { return .further(below) }
        let prefix = root.isEmpty ? "" : root + "/"
        guard path == root || path.hasPrefix(prefix) else { return .unknown }
        // A game's files are two levels below its folder's parent: deeper than that, nothing was read.
        let level = path == root ? 0 : path.dropFirst(prefix.count).split(separator: "/").count
        return level + 2 <= depth ? .nothing : .unknown
    }

    private func further(in path: String) -> [String] {
        let prefix = path.isEmpty ? "" : path + "/"
        let folders = titled.map { ($0.key, $0.value.count) } + compiled.filter { titled[$0.key] == nil }.map { ($0.key, $0.value.count) }
        return folders.filter { $0.0.hasPrefix(prefix) && $0.0 != path }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }.map(\.0)
    }

    /// nil when the folder answers the question. `other` is the answer to the other one.
    public func advice(_ folder: CloudSetupAssistantFocus.Folder, choosing path: String, other: String?) -> Advice? {
        let roms = best(titled.filter { compiled[$0.key] == nil }), library = best(compiled)
        let proposed = (folder == .sources ? roms : library).flatMap { $0 == path ? nil : $0 }
        func advice(_ reason: Advice.Reason, _ instead: String?) -> Advice {
            Advice(reason: reason, instead: instead,
                   swaps: instead != nil && instead == other && (folder == .sources ? compiled[path] != nil : titled[path] != nil))
        }
        switch (kind(of: path), folder) {
        case (.compiled, .library), (.roms, .sources), (.nothing, .library), (.unknown, _):
            return other == path ? advice(.sameFolder, proposed) : nil
        case (.compiled, .sources): return advice(.compiledHere, proposed)
        case (.roms, .library): return advice(.romsHere, proposed)
        case (.oneGame, _):
            return advice(.oneGame, path.components(separatedBy: "/").dropLast().joined(separator: "/"))
        case (.further(let below), .sources):
            return advice(.further, below.first { titled[$0] != nil && compiled[$0] == nil } ?? proposed)
        case (.further(let below), .library):
            // Beside the ROMs is a good place for Oort's own folder; above a library that exists is not.
            return below.first { compiled[$0] != nil }.map { advice(.further, $0) }
        case (.nothing, .sources): return advice(.nothingHere, proposed)
        }
    }

    func best(_ candidates: [String: [String: String]]) -> String? {
        candidates.min {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            let depth = [$0, $1].map { $0.key.components(separatedBy: "/").count }
            return depth[0] == depth[1] ? $0.key < $1.key : depth[0] < depth[1]
        }?.key
    }
}

/// Where the player's two Drive folders probably are. Only a proposal: nothing is kept, written or moved
/// until the player chooses it.
public struct CloudFolderDiscovery: Equatable, Sendable {
    public struct Folder: Equatable, Sendable {
        public let path: String
        /// nil when packages lie loose in the folder: an update and its game are not two games.
        public let games: Int?
        public let names: [String]
        /// The folder used before with this account, not a new find.
        public let kept: Bool

        package init(path: String, games: Int?, names: [String] = [], kept: Bool) {
            self.path = path
            self.games = games
            self.names = names
            self.kept = kept
        }
    }

    package typealias Entry = CloudFolderIndex.Entry

    public static let searchRoot = CloudLibraryPreference.defaultRoot
    /// The one system Oort compiles today; its folders are Games/<system>/Jeux and Games/<system>/ROM.
    static let system = "Switch"
    /// Games/Switch/Oort-nx/<game>/manifests/<file>, and Games/Switch/Jeux/<game>/<file>.
    static let depth = 5

    /// Where a first library goes. A folder of that name that holds something, such as ROMs, is never proposed.
    public var newLibrary: String? {
        index.firstFree(of: ["Jeux", "Oort-nx"].map { "\(Self.searchRoot)/\(Self.system)/\($0)" })
    }
    /// Where a first ROM folder goes, when none is found.
    public var newSources: String? { index.firstFree(of: ["\(Self.searchRoot)/\(Self.system)/ROM"]) }

    public let index: CloudFolderIndex
    public let library: Folder?
    public let sources: Folder?

    package init(entries: [Entry], kept: CloudKeptFolders?) throws {
        let index = try CloudFolderIndex(entries: entries)
        func folder(_ path: String, _ games: [String: String]?, kept: Bool = false) -> Folder {
            .init(path: path, games: games?.count ?? 0, names: CloudFolderIndex.names(games ?? [:]), kept: kept)
        }
        func present(_ path: String) -> Bool { index.directories.contains(path) || path == Self.searchRoot && !entries.isEmpty }
        if let path = kept?.library, index.compiled[path] != nil || kept?.account != nil && present(path) {
            library = folder(path, index.compiled[path], kept: true)
        } else {
            library = index.best(index.compiled).map { folder($0, index.compiled[$0]) }
        }
        if let path = kept?.sources, index.titled[path] != nil || kept?.account != nil && present(path) {
            sources = folder(path, index.titled[path], kept: true)
        } else {
            // A library holds what Oort uploads: the same folder is the player's own only when they said so.
            let own = index.titled.filter { index.compiled[$0.key] == nil }
            sources = index.best(own).map { folder($0, own[$0]) } ?? library.flatMap { Self.conventional(under: $0.path, entries: entries) }
        }
        self.index = index
    }

    /// Folders named without a title ID are read only where a library keeps its own game files.
    private static func conventional(under library: String, entries: [Entry]) -> Folder? {
        for path in ["GameFiles", "Switch/Jeux", "Switch/Games"].map({ CloudDriveFolders.joining(library, $0) }) {
            var groups = Set<String>()
            var loose = false
            for entry in entries where !entry.isDirectory && entry.path.hasPrefix(path + "/") {
                let parts = entry.path.dropFirst(path.count + 1).components(separatedBy: "/")
                guard parts.count <= 2, parts.allSatisfy(CloudDriveFolders.validName),
                      !parts.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") }),
                      CloudFolderIndex.isPackage(entry.path) else { continue }
                if parts.count == 1 { loose = true } else { groups.insert(CloudGameSources.title(in: parts[0])) }
            }
            if loose || !groups.isEmpty {
                return Folder(path: path, games: loose ? nil : groups.count, names: loose ? [] : groups.sorted(), kept: false)
            }
        }
        return nil
    }
}
