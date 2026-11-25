import Foundation
@preconcurrency import NXLibraryCore
import OortCore

/// A game found on this computer, from either connector.
struct Game: LibraryQueryRecord {
    enum Source: Sendable {
        case recompilation(Manifest, sub: Manifest.SubGame?)
        /// The manifest is there but cannot be used.
        case broken(String)
        case program(Program)
        /// Installed by Steam, which starts it.
        case steam(SteamGame)
    }

    let key: String
    let id: UUID
    let name: String
    let folder: String
    let source: Source
    var isFavorite = false
    let isHidden = false
    var isInstalledForLibrary: Bool { if case .broken = source { false } else { true } }
    var librarySearchTerms: [String] {
        switch source {
        case .recompilation(let m, let sub): [m.name, m.repo, sub == nil ? nil : (folder as NSString).lastPathComponent].compactMap(\.self)
        case .program(let p): [(p.program as NSString).lastPathComponent]
        case .steam: ["Steam"]
        case .broken: []
        }
    }
    let libraryModificationDate: Date?

    var manifest: Manifest? { if case .recompilation(let m, _) = source { m } else { nil } }
    var sub: Manifest.SubGame? { if case .recompilation(_, let s) = source { s } else { nil } }
}

/// The two connectors: folders of recompilations, and programs with arguments.
enum Library {
    static let depth = 2

    /// `names` are what programs call themselves, for the ones the player did not name.
    static func scan(_ shelf: Shelf, favorites: Set<UUID>, steam: [SteamGame] = [], names: [String: String] = [:]) -> [Game] {
        var games: [Game] = [], keys = Set<String>(), folders = Set<String>()
        func add(_ key: String, _ name: String, _ folder: String, _ source: Game.Source, _ date: Date?) {
            // Two copies of one project stay two games.
            let key = keys.contains(key) ? key + "@" + folder : key
            guard keys.insert(key).inserted else { return }
            let id = Paths.uuid(key)
            games.append(Game(key: key, id: id, name: name, folder: folder, source: source, isFavorite: favorites.contains(id),
                              libraryModificationDate: date))
        }
        for root in shelf.folders {
            for folder in manifests(in: root, depth: depth) where folders.insert(Paths.real(folder)).inserted {
                let url = URL(fileURLWithPath: folder), base = url.lastPathComponent
                let date = try? FileManager.default.attributesOfItem(atPath: Paths.join(folder, Manifest.fileName))[.modificationDate] as? Date
                do {
                    let m = try Manifest(folder: url)
                    let key = "recompilation:" + (m.repo ?? base).lowercased()
                    if m.games.isEmpty { add(key, m.name ?? base, folder, .recompilation(m, sub: nil), date) }
                    for sub in m.games { add(key + "--" + sub.id, sub.name, folder, .recompilation(m, sub: sub), date) }
                } catch {
                    add("recompilation:" + base.lowercased(), base, folder, .broken((error as? Manifest.Failure)?.code ?? "manifest-unreadable"), date)
                }
            }
        }
        for program in shelf.programs {
            let date = try? FileManager.default.attributesOfItem(atPath: program.program)[.modificationDate] as? Date
            let name = program.name == program.stem ? names["program:" + program.key] ?? program.name : program.name
            add("program:" + program.key, name, (program.program as NSString).deletingLastPathComponent, .program(program), date)
        }
        for game in steam {
            let date = try? FileManager.default.attributesOfItem(atPath: game.manifest)[.modificationDate] as? Date
            add("steam:\(game.appID)", game.name, game.folder, .steam(game), date)
        }
        return games
    }

    private static func manifests(in folder: String, depth: Int) -> [String] {
        if FileManager.default.fileExists(atPath: Paths.join(folder, Manifest.fileName)) { return [folder] }
        guard depth > 0 else { return [] }
        return names(folder).filter { !$0.hasPrefix(".") }.flatMap { name -> [String] in
            let child = Paths.join(folder, name)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: child, isDirectory: &isFolder), isFolder.boolValue else { return [] }
            return manifests(in: child, depth: depth - 1)
        }
    }

    static func names(_ folder: String) -> [String] { (try? read(folder)) ?? [] }

    static func read(_ folder: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The pictures a game has, in order: the one the player chose, the game's own, Steam's on this computer, the ones
    /// found online, and last its program's icon (`mark`). Each folder is read once: asking the disk for every name it
    /// could have is slow where files are scanned as they are opened.
    struct Art {
        static let kinds = ["cover", "icon", "hero", "logo", "mark"]
        private static let names: [String: [String]] = ["cover": ["cover", "box", "boxart"], "icon": ["icon", "square", "cover"],
                                                        "hero": ["hero", "background", "banner"], "logo": ["logo"]]
        private let folders: [(path: String, files: Set<String>)]
        private let online: (path: String, files: Set<String>)?
        private let steam: [String: String]
        private var beside: String?
        private let mark: String?

        init(of game: Game, data: String, mark: String?) {
            func read(_ path: String) -> (path: String, files: Set<String>) { (path, Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])) }
            let id = game.id.uuidString.lowercased()
            var own = [Paths.join(data, "art/" + id)], steam: [String: String] = [:]
            switch game.source {
            case .program(let p):
                // "Sunken City.png" beside "Sunken City.rom".
                if let target = p.args.last?.replacingOccurrences(of: "\\", with: "/"), Paths.isAbsolute(target) {
                    let stem = (target as NSString).deletingPathExtension
                    beside = ["png", "jpg", "jpeg", "webp"].map { stem + "." + $0 }.first { Picture.check($0) != nil }
                }
            case .steam(let s): steam = s.art
            default: own += [game.folder, Paths.join(game.folder, "art")]
            }
            (folders, online, self.steam, self.mark) = (own.map(read), read(Paths.join(data, "online/" + id)), steam, mark)
        }

        func path(_ kind: String) -> String? {
            if kind == "mark" { return mark }
            for (folder, files) in folders where !files.isEmpty {
                for name in Self.names[kind] ?? [] {
                    if let path = Self.file(name, folder, files) { return path }
                }
            }
            if let path = steam[kind] ?? (kind == "cover" ? beside : nil) { return path }
            // A cover found elsewhere is never cut into a square.
            return online.flatMap { Self.file(kind, $0.path, $0.files) }
        }

        private static func file(_ name: String, _ folder: String, _ files: Set<String>) -> String? {
            for ext in ["png", "jpg", "jpeg", "webp"] where files.contains(name + "." + ext) {
                let path = Paths.join(folder, name + "." + ext)
                if Paths.isInside(Paths.real(path), Paths.real(folder)) { return path }
            }
            return nil
        }
    }
}

/// Text arguments as typed, with quotes around the ones that hold spaces.
enum Arguments {
    static func split(_ text: String) -> [String] {
        var out: [String] = [], word = "", quote: Character?, open = false
        for c in text {
            if let q = quote { if c == q { quote = nil } else { word.append(c) } }
            else if c == "\"" || c == "'" { (quote, open) = (c, true) }
            else if c.isWhitespace {
                if open || !word.isEmpty { out.append(word) }
                (word, open) = ("", false)
            } else { word.append(c) }
        }
        if open || !word.isEmpty { out.append(word) }
        return out
    }
}

/// Play history for one profile, from the sessions on disk.
struct History: PlayHistory {
    let last: [UUID: Date], total: [UUID: TimeInterval]

    init(_ sessions: [PlaySession], profile: UUID?) {
        var last: [UUID: Date] = [:], total: [UUID: TimeInterval] = [:]
        for s in sessions where s.profileID == profile {
            last[s.gameID] = max(last[s.gameID] ?? .distantPast, s.startedAt)
            total[s.gameID, default: 0] += s.duration ?? max(0, s.lastHeartbeatAt.timeIntervalSince(s.startedAt))
        }
        (self.last, self.total) = (last, total)
    }

    func lastPlayed(for gameID: UUID) -> Date? { last[gameID] }
    func totalDuration(for gameID: UUID) -> TimeInterval { total[gameID] ?? 0 }
}
