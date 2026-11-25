import Foundation
import OortCore

/// Where a manifest's placeholders point for one game, and what it may start and write.
struct Places: Sendable {
    var install: String
    var documents = "", local = "", config = "", home = ""
    var pad = "xbox"
    /// Every input of the manifest, and the files picked for them.
    var inputs: Set<String> = []
    var picked: [String: String] = [:]

    var data: String { Paths.join(install, "recompdata") }

    /// Fills a path, an argument or a value, once: what a placeholder gives is never filled again.
    /// nil when it names a file that was not picked, so the whole text is left out. `native` is for what a program is
    /// given: the paths put in take the system's own form, the manifest's own text stays as written.
    func fill(_ text: String, native: Bool = false) throws -> String? {
        var out = "", rest = Substring(text)
        func path(_ value: String) -> String { native ? Paths.native(value) : value }
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            rest = rest[open...]
            guard let close = rest.firstIndex(of: "}") else { break }
            let name = rest[rest.index(after: open)..<close]
            switch name {
            case "install": out += path(install)
            case "data": out += path(data)
            case "documents": out += path(documents)
            case "local": out += path(local)
            case "config": out += path(config)
            case "home": out += path(home)
            case "pad": out += pad
            default:
                guard name == "game" || name.hasPrefix("input:") else {
                    out += rest[...close]
                    break
                }
                let id = name == "game" ? "game" : String(name.dropFirst("input:".count))
                guard inputs.contains(id) else { throw Manifest.Failure(code: "unknown-input") }
                guard let file = picked[id] else { return nil }
                out += path(file)
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    /// Arguments, as a program gets them.
    func fill(_ list: [String]) throws -> [String] { try list.compactMap { try fill($0, native: true) } }

    /// The first place whose `if` exists, else the first without one.
    func place(_ places: [Manifest.Place]) throws -> String? {
        for place in places {
            if let when = place.when {
                guard let path = try fill(when), FileManager.default.fileExists(atPath: path) else { continue }
            }
            return try fill(place.path)
        }
        return nil
    }

    /// One of the format's own places, with no way out of it.
    func mayWrite(_ path: String) -> Bool {
        let parts = Paths.parts(path)
        guard Paths.isAbsolute(path), !parts.contains(".."), !parts.contains(".") else { return false }
        return [install, documents, local, config, home].contains { !Paths.parts($0).isEmpty && Paths.isInside(path, $0) }
    }

    /// The first of `programs` that is a file inside the game's folder.
    func program(_ programs: [String]) -> String? {
        let root = Paths.real(install)
        for name in programs {
            let parts = Paths.parts(name)
            guard !parts.isEmpty, !Paths.isAbsolute(name), !parts.contains(".."), !parts.contains(where: { $0.contains(":") }) else { continue }
            var path = Paths.join(install, parts.joined(separator: "/"))
            if path.hasSuffix(".app") {
                // shortcut: the only program in the bundle; read Info.plist when Macs are a target of this app.
                let inside = Paths.join(path, "Contents/MacOS")
                guard let file = try? FileManager.default.contentsOfDirectory(atPath: inside).sorted().first else { continue }
                path = Paths.join(inside, file)
            }
            var isFolder: ObjCBool = false
            let real = Paths.real(path)
            if FileManager.default.fileExists(atPath: real, isDirectory: &isFolder), !isFolder.boolValue, Paths.isInside(real, root) {
                return path
            }
        }
        return nil
    }

    /// Names a manifest may set for the program it starts.
    static func mayName(_ name: String) -> Bool {
        let up = name.uppercased()
        let system: Set<String> = ["PATH", "PATHEXT", "COMSPEC", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "TMPDIR", "HOME",
                                   "USERPROFILE", "APPDATA", "LOCALAPPDATA", "SHELL", "USER", "USERNAME", "IFS"]
        return (1...64).contains(name.utf8.count) && !("0"..."9").contains(name.first!)
            && name.utf8.allSatisfy { $0 == 95 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
            && !system.contains(up) && !["RECOMPLAUNCHER", "LD_", "DYLD_", "OORT_"].contains { up.hasPrefix($0) }
    }
}

/// Paths as text, with `/` inside the app on every system and the system's own form outside.
enum Paths {
    static func join(_ base: String, _ tail: String) -> String { base.hasSuffix("/") ? base + tail : base + "/" + tail }

    static func parts(_ path: String) -> [String] {
        path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
    }

    static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") { return true }
        let units = Array(path.utf8.prefix(3))
        return path.hasPrefix("\\") || (units.count == 3 && units[1] == 58 && (units[2] == 47 || units[2] == 92))
    }

    /// `path` is strictly inside `folder`.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        #if os(Windows)
        let (a, b) = (parts(path.lowercased()), parts(folder.lowercased()))
        #else
        let (a, b) = (parts(path), parts(folder))
        #endif
        return a.count > b.count && Array(a.prefix(b.count)) == b
    }

    static func real(_ path: String) -> String { rooted(URL(fileURLWithPath: path).resolvingSymlinksInPath().path) }

    /// `C:` alone is whatever folder the program is in on that drive; the drive itself is `C:/`.
    static func rooted(_ path: String) -> String { isDrive(path) ? path + "/" : path }

    private static func isDrive(_ path: String) -> Bool {
        let units = Array(path.utf8)
        return units.count == 2 && units[1] == 58 && ((65...90).contains(units[0]) || (97...122).contains(units[0]))
    }

    /// The folder above; nil at the top (`/`, a drive).
    static func parent(_ path: String) -> String? {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !isDrive(trimmed), let slash = trimmed.lastIndex(of: "/"), trimmed != "/" else { return nil }
        return slash == trimmed.startIndex ? "/" : rooted(String(trimmed[..<slash]))
    }

    /// The form a program on this system expects.
    static func native(_ path: String) -> String {
        #if os(Windows)
        return path.replacingOccurrences(of: "/", with: "\\")
        #else
        return path
        #endif
    }

    /// A stable identity for a game: the same text gives the same UUID on every system.
    static func uuid(_ text: String) -> UUID {
        let b = [UInt8](PortableSHA256.hash(Data(text.utf8)).prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], (b[6] & 0x0f) | 0x80, b[7], (b[8] & 0x3f) | 0x80, b[9], b[10], b[11],
                           b[12], b[13], b[14], b[15]))
    }
}
