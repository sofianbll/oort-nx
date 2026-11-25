import Foundation
@preconcurrency import NXLibraryCore

/// A game installed by Steam on this computer.
struct SteamGame: Equatable, Sendable {
    var appID: UInt32
    var name: String
    var folder: String
    var manifest: String
    /// Pictures Steam already keeps on this computer, by kind.
    var art: [String: String] = [:]
    /// The programs Steam itself would start, from the game's folder.
    var programs: [String] = []
}

/// Steam's own files, read and never written: the libraries, what is installed, the pictures. No account, no key, no
/// connection. The text format is the Mac app's reader (`KeyValuesDocument`).
struct SteamShelf {
    struct Found { var games: [SteamGame] = []; var libraries: [String] = []; var downloading = 0; var others = 0 }

    let root: String

    /// Where Steam is: the folder the system names, else its usual places on Linux. `named` comes from the registry.
    static func root(named: String?, home: String, system: String) -> String? {
        var places: [String] = []
        if let named, !named.isEmpty { places.append(named.replacingOccurrences(of: "\\", with: "/")) }
        if system == "linux" {
            places += [".local/share/Steam", ".steam/steam", ".steam/root", ".var/app/com.valvesoftware.Steam/.local/share/Steam",
                       "snap/steam/common/.local/share/Steam"].map { Paths.join(home, $0) }
        }
        return places.first { folderExists(Paths.join($0, "steamapps")) }.map(Paths.real)
    }

    static func folderExists(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
    }

    private static func document(_ path: String, limit: Int = 4 << 20) -> KeyValuesDocument? {
        guard let file = Window(path), file.size <= limit, let bytes = file.bytes(0, file.size) else { return nil }
        return try? KeyValuesDocument(text: String(decoding: bytes.all, as: UTF8.self))
    }

    /// Steam's own folder, and every other one it lists, on any drive.
    func libraries() -> [String] {
        var out = [root]
        for file in ["steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"] {
            guard let document = Self.document(Paths.join(root, file)), let entries = document.entries.firstObject(for: "libraryfolders") else { continue }
            for entry in entries where entry.key.allSatisfy(\.isNumber) {
                let path: String?
                switch entry.value {
                case .string(let value): path = value
                case .object(let children): path = children.firstString(for: "path")
                }
                guard let path = path?.replacingOccurrences(of: "\\", with: "/"), Paths.isAbsolute(path), !path.contains("\0"), out.count < 64 else { continue }
                let real = Paths.real(path)
                if !out.contains(where: { Self.same($0, real) }), Self.folderExists(Paths.join(real, "steamapps")) { out.append(real) }
            }
            break
        }
        return out
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        #if os(Windows)
        return Paths.parts(a.lowercased()) == Paths.parts(b.lowercased())
        #else
        return Paths.parts(a) == Paths.parts(b)
        #endif
    }

    /// Steam marks a game fully installed with this bit; a game that updates keeps it.
    static let installed: UInt64 = 4

    private struct State { var id: UInt32; var name: String; var folder: String; var flags: UInt64? }

    private static func state(_ path: String) -> State? {
        guard let fields = document(path, limit: 1 << 20)?.entries.firstObject(for: "AppState"),
              let id = fields.firstString(for: "appid").flatMap(UInt32.init), id > 0,
              let name = fields.firstString(for: "name")?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
              let folder = fields.firstString(for: "installdir"), !folder.isEmpty else { return nil }
        let parts = folder.split(whereSeparator: { $0 == "/" || $0 == "\\" }, omitting: false)
        // One of Steam's own folders, with no way out of it.
        guard !Paths.isAbsolute(folder), !folder.contains(":"), !folder.contains("\0"), !parts.contains(where: { [".", "..", ""].contains($0) }) else { return nil }
        return State(id: id, name: name, folder: parts.joined(separator: "/"), flags: fields.firstString(for: "StateFlags").flatMap(UInt64.init))
    }

    /// appinfo.vdf can be large: read again only when it changed.
    struct Known { var stamp = "", wanted = Set<UInt32>(), infos: [UInt32: AppInfo.Info] = [:] }

    func scan() -> Found {
        var known = Known()
        return scan(&known)
    }

    func scan(_ known: inout Known) -> Found {
        var found = Found(), seen = Set<UInt32>(), all: [SteamGame] = []
        found.libraries = libraries()
        for library in found.libraries {
            let steamapps = Paths.join(library, "steamapps")
            for file in Library.names(steamapps).prefix(20_000) where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
                let path = Paths.join(steamapps, file)
                guard let state = Self.state(path), file == "appmanifest_\(state.id).acf", !seen.contains(state.id) else { continue }
                if let flags = state.flags, flags & Self.installed == 0 { found.downloading += 1; continue }
                let common = Paths.join(steamapps, "common"), folder = Paths.join(common, state.folder)
                guard Self.folderExists(folder), Paths.isInside(Paths.real(folder), Paths.real(common)) else { continue }
                seen.insert(state.id)
                all.append(SteamGame(appID: state.id, name: state.name, folder: folder, manifest: path))
            }
        }
        let file = Paths.join(root, "appcache/appinfo.vdf"), attributes = try? FileManager.default.attributesOfItem(atPath: file)
        let stamp = "\(file)|\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\((attributes?[.size] as? NSNumber)?.intValue ?? 0)"
        if known.stamp != stamp || known.wanted != seen { known = Known(stamp: stamp, wanted: seen, infos: AppInfo.read(file, wanted: seen)) }
        let infos = known.infos
        let cache = Paths.join(root, "appcache/librarycache"), cached = Set(Library.names(cache))
        for var game in all {
            let info = infos[game.appID]
            guard Self.isGame(game.name, id: game.appID, type: info?.type) else { found.others += 1; continue }
            game.programs = info?.programs ?? []
            game.art = Self.art(game.appID, cache, cached)
            found.games.append(game)
        }
        return found
    }

    /// Steam's own word for what it is when it can be read, else its name: tools, soundtracks and shared parts are no games.
    static func isGame(_ name: String, id: UInt32, type: String?) -> Bool {
        if id == 228980 { return false }
        if let type = type?.lowercased() { return ["game", "demo", "application", "beta", "mod", "episode"].contains(type) }
        let n = name.lowercased()
        return !(n.hasPrefix("steamworks ") || n.hasPrefix("proton ") || n.hasPrefix("steam linux runtime") || n.hasPrefix("steamvr")
            || n.contains("redistributable") || n.contains("soundtrack") || n.hasSuffix(" ost") || n.contains("dedicated server")
            || n.hasSuffix(" sdk") || n.contains("authoring tools") || n.contains("digital artbook"))
    }

    private static let pictures: [String: [String]] = [
        "cover": ["library_600x900_2x.jpg", "library_600x900.jpg", "library_capsule_2x.jpg", "library_capsule.jpg"],
        "hero": ["library_hero_2x.jpg", "library_hero.jpg"], "logo": ["logo_2x.png", "logo.png"],
    ]

    /// `<id>/<name>`, `<id>/<hash>/<name>` in newer Steams, `<id>_<name>` in older ones.
    private static func art(_ id: UInt32, _ cache: String, _ cached: Set<String>) -> [String: String] {
        var out: [String: String] = [:], folders: [(String, Set<String>)] = []
        if cached.contains(String(id)) {
            let own = Paths.join(cache, String(id)), names = Library.names(own)
            folders.append((own, Set(names)))
            for name in names.prefix(32) where !name.contains(".") { folders.append((Paths.join(own, name), Set(Library.names(Paths.join(own, name))))) }
        }
        for (kind, names) in pictures {
            for name in names where out[kind] == nil {
                if let folder = folders.first(where: { $0.1.contains(name) }) { out[kind] = Paths.join(folder.0, name) }
                else if cached.contains("\(id)_\(name)") { out[kind] = Paths.join(cache, "\(id)_\(name)") }
            }
        }
        return out.filter { Picture.check($0.value) != nil }
    }

    /// Whether Steam is changing the game's files now; nil when it is no longer installed.
    static func isUpdating(_ game: SteamGame) -> Bool? {
        guard let state = state(game.manifest), state.id == game.appID else { return nil }
        return state.flags.map { $0 != installed } ?? false
    }

    /// The game's program, for its icon: the one Steam starts, else the largest at the top of its folder.
    static func program(_ game: SteamGame) -> String? {
        for name in game.programs {
            let path = Paths.join(game.folder, name)
            if name.lowercased().hasSuffix(".exe"), FileManager.default.fileExists(atPath: path), Paths.isInside(Paths.real(path), Paths.real(game.folder)) { return path }
        }
        let helpers = ["crash", "setup", "redist", "install", "unins", "report", "anticheat", "eac", "dotnet", "server"]
        return Library.names(game.folder).filter { name in
            let n = name.lowercased()
            return n.hasSuffix(".exe") && !helpers.contains { n.contains($0) }
        }.map { name -> (String, Int) in
            let path = Paths.join(game.folder, name)
            return (path, ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.intValue ?? 0)
        }.max { $0.1 < $1.1 }?.0
    }
}

private extension String {
    func split(whereSeparator isSeparator: (Character) -> Bool, omitting: Bool) -> [String] {
        split(omittingEmptySubsequences: omitting, whereSeparator: isSeparator).map(String.init)
    }
}

/// appcache/appinfo.vdf: what Steam knows about each app. Only two things are read, for the apps that are installed:
/// what it is (game, tool, music…) and its programs. An unknown version of the file gives nothing.
enum AppInfo {
    struct Info: Equatable { var type: String?; var programs: [String] }

    static func read(_ path: String, wanted: Set<UInt32>) -> [UInt32: Info] {
        guard !wanted.isEmpty, let file = Window(path), let head = file.bytes(0, 16), let magic = head.u32(0), [0x0756_4427, 0x0756_4428, 0x0756_4429].contains(magic) else { return [:] }
        var names: [String]? = nil, at = 8, end = file.size
        if magic == 0x0756_4429 {
            guard let low = head.u32(8), let high = head.u32(12), high == 0, low < file.size, let bytes = file.bytes(low, file.size - low), let count = bytes.u32(0), count <= 1 << 20 else { return [:] }
            var list: [String] = [], start = 4
            for i in 4..<bytes.count where bytes.all[i] == 0 {
                list.append(String(decoding: bytes.all[start..<i], as: UTF8.self))
                start = i + 1
                if list.count == count { break }
            }
            (names, at, end) = (list, 16, low)
        }
        // Before the data: state, date, token, two digests, change number.
        let skip = magic == 0x0756_4427 ? 4 + 4 + 8 + 20 + 4 : 4 + 4 + 8 + 20 + 4 + 20
        var out: [UInt32: Info] = [:]
        while at + 8 <= end, let entry = file.bytes(at, 8), let id = entry.u32(0), id != 0, let size = entry.u32(4) {
            if let app = UInt32(exactly: id), wanted.contains(app), size > skip, size <= 4 << 20, let body = file.bytes(at + 8 + skip, size - skip) {
                var reader = Reader(bytes: body, names: names)
                if let tree = reader.object(0) { out[app] = info(tree) }
                if out.count == wanted.count { break }
            }
            at += 8 + size
        }
        return out
    }

    private indirect enum Node { case text(String), object([(String, Node)]) }

    private static func info(_ tree: [(String, Node)]) -> Info {
        func object(_ list: [(String, Node)], _ key: String) -> [(String, Node)] {
            for (name, node) in list where name.lowercased() == key { if case .object(let inside) = node { return inside } }
            return []
        }
        func text(_ list: [(String, Node)], _ key: String) -> String? {
            for (name, node) in list where name.lowercased() == key { if case .text(let value) = node { return value } }
            return nil
        }
        let app = object(tree, "appinfo")
        let launch = object(object(app, "config"), "launch").compactMap { _, node -> String? in
            guard case .object(let one) = node else { return nil }
            let systems = text(object(one, "config"), "oslist") ?? ""
            guard systems.isEmpty || systems.contains("windows") else { return nil }
            return text(one, "executable")?.replacingOccurrences(of: "\\", with: "/")
        }
        return Info(type: text(object(app, "common"), "type"), programs: launch.filter { !$0.contains("..") && !Paths.isAbsolute($0) })
    }

    private struct Reader {
        let bytes: Bytes
        let names: [String]?
        var at = 0, count = 0

        init(bytes: Bytes, names: [String]?) { (self.bytes, self.names) = (bytes, names) }

        mutating func word() -> String? {
            let start = at
            while let c = bytes.u8(at) {
                at += 1
                if c == 0 { return String(decoding: bytes.all[start..<(at - 1)], as: UTF8.self) }
            }
            return nil
        }

        mutating func object(_ depth: Int) -> [(String, Node)]? {
            var out: [(String, Node)] = []
            while let type = bytes.u8(at) {
                at += 1
                if type == 8 { return out }
                count += 1
                guard depth < 32, count < 100_000 else { return nil }
                var key = ""
                if let names {
                    guard let index = bytes.u32(at), names.indices.contains(index) else { return nil }
                    key = names[index]
                    at += 4
                } else {
                    guard let text = word() else { return nil }
                    key = text
                }
                switch type {
                case 0:
                    guard let inside = object(depth + 1) else { return nil }
                    out.append((key, .object(inside)))
                case 1:
                    guard let value = word() else { return nil }
                    out.append((key, .text(value)))
                case 2, 3, 4, 6: at += 4
                case 7, 10: at += 8
                default: return nil
                }
            }
            // The last level of some files ends with the data.
            return depth == 0 ? out : nil
        }
    }
}
