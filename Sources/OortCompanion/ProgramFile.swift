import Foundation

/// What a program says about itself: its name, who made it, its version and its icon, read in its own file.
/// Nothing is run. A file that lies about its sizes gives less, never a crash.
struct ProgramFile {
    var name: String?
    var about: String?
    var publisher: String?
    var version: String?
    /// The largest icon, as a PNG.
    var icon: Data?

    /// A Windows program, whatever system reads it; nil for anything else.
    init?(_ path: String) {
        guard let file = Window(path), let exe = Executable(file) else { return nil }
        let words = exe.version()
        func word(_ key: String) -> String? {
            words[key]?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).nonEmpty
        }
        about = word("FileDescription").flatMap { Self.isGeneric($0) ? nil : $0 }
        name = word("ProductName").flatMap { Self.isGeneric($0) ? nil : $0 } ?? about
        publisher = word("CompanyName").flatMap { Self.isGeneric($0) ? nil : $0 }
        version = [word("ProductVersion"), word("FileVersion")].compactMap(\.self).first { $0.contains { $0.isNumber && $0 != "0" } }
        icon = exe.icon()
    }

    /// Names a tool left in place, which say nothing about the program.
    static func isGeneric(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["operating system", "bootstrappackagedgame", "todo:", "unityplayer", "unity playback engine", "electron", "microsoft visual", "windowsapplication",
                "consoleapplication", "setup/uninstall"].contains { t.contains($0) } || ["unity", "unreal engine", "product", "game", "application", "launcher", "default company", "defaultcompany"].contains(t)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Parts of a file, read where they are: a game's program can be large.
struct Window {
    private let handle: FileHandle
    let size: Int

    init?(_ path: String) {
        guard let handle = FileHandle(forReadingAtPath: path), let end = try? handle.seekToEnd(), end < UInt64(Int.max) else { return nil }
        (self.handle, size) = (handle, Int(end))
    }

    func bytes(_ at: Int, _ count: Int) -> Bytes? {
        guard at >= 0, count >= 0, count <= size, at <= size - count else { return nil }
        guard (try? handle.seek(toOffset: UInt64(at))) != nil, let data = try? handle.read(upToCount: count), data.count == count else { return count == 0 ? Bytes([]) : nil }
        return Bytes([UInt8](data))
    }
}

/// Little-endian numbers out of bytes, nil past the end.
struct Bytes {
    let all: [UInt8]
    init(_ all: [UInt8]) { self.all = all }
    var count: Int { all.count }
    func u8(_ at: Int) -> Int? { all.indices.contains(at) ? Int(all[at]) : nil }
    func u16(_ at: Int) -> Int? { at >= 0 && at <= count - 2 ? Int(all[at]) | Int(all[at + 1]) << 8 : nil }
    func u32(_ at: Int) -> Int? { at >= 0 && at <= count - 4 ? (0..<4).reduce(0) { $0 | Int(all[at + $1]) << (8 * $1) } : nil }
    func slice(_ at: Int, _ length: Int) -> Bytes? { at >= 0 && length >= 0 && length <= count && at <= count - length ? Bytes(Array(all[at..<(at + length)])) : nil }
}

/// A Windows program's resources (PE32 and PE32+).
private struct Executable {
    let file: Window
    private let sections: [(address: Int, length: Int, at: Int)]
    private let root: Int

    init?(_ file: Window) {
        guard let dos = file.bytes(0, 64), dos.u16(0) == 0x5a4d, let at = dos.u32(0x3c), let head = file.bytes(at, 24), head.u32(0) == 0x4550,
              let count = head.u16(6), count <= 96, let optionalSize = head.u16(20), let optional = file.bytes(at + 24, optionalSize),
              let magic = optional.u16(0), magic == 0x10b || magic == 0x20b else { return nil }
        let tables = magic == 0x10b ? 96 : 112
        guard let many = optional.u32(tables - 4), many > 2, let address = optional.u32(tables + 16), address > 0,
              let table = file.bytes(at + 24 + optionalSize, count * 40) else { return nil }
        var sections: [(address: Int, length: Int, at: Int)] = []
        for i in 0..<count {
            guard let virtual = table.u32(i * 40 + 8), let address = table.u32(i * 40 + 12), let raw = table.u32(i * 40 + 16), let at = table.u32(i * 40 + 20) else { return nil }
            sections.append((address, max(virtual, raw), at))
        }
        (self.file, self.sections) = (file, sections)
        guard let root = Self.offset(address, sections) else { return nil }
        self.root = root
    }

    private static func offset(_ address: Int, _ sections: [(address: Int, length: Int, at: Int)]) -> Int? {
        sections.first { address >= $0.address && address - $0.address < $0.length }.map { $0.at + address - $0.address }
    }

    private struct Entry { var id: Int?; var at: Int; var isFolder: Bool }

    private func entries(_ at: Int) -> [Entry] {
        guard let head = file.bytes(root + at, 16), let named = head.u16(12), let numbered = head.u16(14), named + numbered <= 4096,
              let list = file.bytes(root + at + 16, (named + numbered) * 8) else { return [] }
        return (0..<(named + numbered)).compactMap { i in
            guard let name = list.u32(i * 8), let to = list.u32(i * 8 + 4) else { return nil }
            return Entry(id: name & 0x8000_0000 == 0 ? name : nil, at: to & 0x7fff_ffff, isFolder: to & 0x8000_0000 != 0)
        }
    }

    /// The resources of one kind: their number and their bytes, the first language of each.
    private func resources(_ kind: Int) -> [(id: Int?, entry: Int)] {
        guard let type = entries(0).first(where: { $0.id == kind && $0.isFolder }) else { return [] }
        return entries(type.at).compactMap { item in
            if !item.isFolder { return (item.id, item.at) }
            return entries(item.at).first { !$0.isFolder }.map { (item.id, $0.at) }
        }
    }

    private func data(_ entry: Int, limit: Int) -> Bytes? {
        guard let head = file.bytes(root + entry, 16), let address = head.u32(0), let size = head.u32(4), size <= limit,
              let at = Self.offset(address, sections) else { return nil }
        return file.bytes(at, size)
    }

    func icon() -> Data? {
        guard let first = resources(14).first, let group = data(first.entry, limit: 1 << 16), group.u16(2) == 1, let count = group.u16(4) else { return nil }
        var all: [(side: Int, bits: Int, id: Int)] = []
        for i in 0..<min(count, 256) {
            guard let width = group.u8(6 + i * 14), let bits = group.u16(6 + i * 14 + 6), let id = group.u16(6 + i * 14 + 12) else { break }
            all.append((width == 0 ? 256 : width, bits, id))
        }
        let icons = resources(3)
        for one in all.sorted(by: { ($0.side, $0.bits) > ($1.side, $1.bits) }) {
            if let entry = icons.first(where: { $0.id == one.id })?.entry, let bytes = data(entry, limit: 8 << 20), let png = Picture.png(icon: bytes) { return png }
        }
        return nil
    }

    /// The words of the version resource, the first language of it.
    func version() -> [String: String] {
        guard let first = resources(16).first, let bytes = data(first.entry, limit: 1 << 18) else { return [:] }
        var out: [String: String] = [:]
        func block(_ at: Int, _ end: Int, _ depth: Int) -> Int? {
            guard depth < 5, let length = bytes.u16(at), length >= 6, at + length <= end, let valueLength = bytes.u16(at + 2) else { return nil }
            var p = at + 6, key: [UInt16] = []
            while let c = bytes.u16(p), p < at + length, c != 0 { key.append(UInt16(c)); p += 2 }
            p = (p + 2 + 3) & ~3
            let name = String(decoding: key, as: UTF16.self)
            if depth == 3 {
                var value: [UInt16] = []
                // Some tools count the value in bytes, some in letters: it ends at its zero or with its block.
                while let c = bytes.u16(p), p + 1 < at + length, c != 0 { value.append(UInt16(c)); p += 2 }
                if out[name] == nil { out[name] = String(decoding: value, as: UTF16.self) }
            } else {
                if depth == 0 { p = (p + valueLength + 3) & ~3 }
                if depth != 1 || name == "StringFileInfo" {
                    while p < at + length, let next = block(p, at + length, depth + 1) { p = next }
                }
            }
            return (at + length + 3) & ~3
        }
        _ = block(0, bytes.count, 0)
        return out
    }
}

/// Pictures the app makes or checks.
enum Picture {
    /// The kind of picture a file is, and its size, from its first bytes; nil for anything else.
    static func kind(_ b: Bytes) -> (ext: String, width: Int, height: Int)? {
        func big(_ at: Int) -> Int? { b.u16(at).map { ($0 & 0xff) << 8 | $0 >> 8 } }
        if b.all.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), let w = big(18), let h = big(22), big(16) == 0, big(20) == 0 { return ("png", w, h) }
        if b.all.starts(with: [0xff, 0xd8, 0xff]) {
            var at = 2
            while let mark = b.u8(at), mark == 0xff, let code = b.u8(at + 1) {
                if code == 0xff { at += 1; continue }
                if (0xc0...0xcf).contains(code), ![0xc4, 0xc8, 0xcc].contains(code), let h = big(at + 5), let w = big(at + 7) { return ("jpg", w, h) }
                guard let length = big(at + 2), length >= 2 else { return nil }
                at += 2 + length
            }
            return nil
        }
        if b.all.starts(with: Array("RIFF".utf8)), b.slice(8, 4)?.all == Array("WEBP".utf8) {
            switch b.slice(12, 4)?.all {
            case Array("VP8X".utf8)?:
                guard let w = b.u32(24), let h = b.u32(27) else { return nil }
                return ("webp", (w & 0xff_ffff) + 1, (h & 0xff_ffff) + 1)
            case Array("VP8L".utf8)?:
                guard let v = b.u32(21) else { return nil }
                return ("webp", (v & 0x3fff) + 1, (v >> 14 & 0x3fff) + 1)
            case Array("VP8 ".utf8)?:
                guard let w = b.u16(26), let h = b.u16(28) else { return nil }
                return ("webp", w & 0x3fff, h & 0x3fff)
            default: return nil
            }
        }
        return nil
    }

    /// A picture file of this computer that the app may show: its kind and size are what they say.
    static func check(_ path: String, limit: Int = 24 << 20) -> (ext: String, width: Int, height: Int)? {
        guard let file = Window(path), file.size <= limit, let head = file.bytes(0, min(file.size, 1 << 19)), let kind = kind(head),
              (8...12_000).contains(kind.width), (8...12_000).contains(kind.height) else { return nil }
        return kind
    }

    /// One picture of a Windows icon as a PNG: it is one already, or a bitmap with its mask.
    static func png(icon b: Bytes) -> Data? {
        if let kind = kind(b) { return kind.ext == "png" && kind.width <= 1024 && kind.height <= 1024 ? Data(b.all) : nil }
        guard let head = b.u32(0), head >= 40, let width = b.u32(4), let double = b.u32(8), let bits = b.u16(14), b.u32(16) == 0,
              (1...512).contains(width), double == width * 2 || double == width, [1, 4, 8, 24, 32].contains(bits) else { return nil }
        let height = width
        let colors = bits <= 8 ? (b.u32(32).flatMap { $0 == 0 ? nil : $0 } ?? 1 << bits) : 0
        guard colors <= 256 else { return nil }
        let pixels = head + colors * 4, stride = (width * bits + 31) / 32 * 4, masks = (width + 31) / 32 * 4
        guard pixels + stride * height <= b.count else { return nil }
        let hasMask = pixels + stride * height + masks * height <= b.count
        var out = [UInt8](repeating: 0, count: width * height * 4), seen = false
        for y in 0..<height {
            let row = pixels + (height - 1 - y) * stride, mask = pixels + stride * height + (height - 1 - y) * masks
            for x in 0..<width {
                let to = (y * width + x) * 4
                let from: Int
                switch bits {
                case 32: from = row + x * 4
                case 24: from = row + x * 3
                default:
                    let index = Int(b.all[row + x * bits / 8]) >> (8 - bits - x * bits % 8) & (1 << bits - 1)
                    guard index < colors else { return nil }
                    from = head + index * 4
                }
                (out[to], out[to + 1], out[to + 2]) = (b.all[from + 2], b.all[from + 1], b.all[from])
                let hidden = hasMask && b.all[mask + x / 8] >> (7 - x % 8) & 1 == 1
                out[to + 3] = bits == 32 ? b.all[from + 3] : hidden ? 0 : 255
                if bits == 32, out[to + 3] != 0 { seen = true }
            }
        }
        // An old 32-bit icon has its shape in the mask alone.
        if bits == 32, !seen {
            for y in 0..<height { for x in 0..<width {
                let mask = pixels + stride * height + (height - 1 - y) * masks
                out[(y * width + x) * 4 + 3] = hasMask && b.all[mask + x / 8] >> (7 - x % 8) & 1 == 1 ? 0 : 255
            } }
        }
        return png(width, height, out)
    }

    /// RGBA as a PNG, stored without compression: icons are small.
    static func png(_ width: Int, _ height: Int, _ rgba: [UInt8]) -> Data {
        func big(_ n: UInt32) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: n >> $0) } }
        var raw: [UInt8] = []
        raw.reserveCapacity((width * 4 + 1) * height)
        for y in 0..<height {
            raw.append(0)
            raw += rgba[(y * width * 4)..<((y + 1) * width * 4)]
        }
        var z: [UInt8] = [0x78, 0x01], at = 0
        repeat {
            let n = min(65_535, raw.count - at), last = at + n == raw.count
            z += [last ? 1 : 0, UInt8(n & 255), UInt8(n >> 8), UInt8(~n & 255), UInt8(~n >> 8 & 255)]
            z += raw[at..<(at + n)]
            at += n
        } while at < raw.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw { a = (a + UInt32(byte)) % 65_521; b = (b + a) % 65_521 }
        z += big(b << 16 | a)
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let all = Array(type.utf8) + body
            return big(UInt32(body.count)) + all + big(crc(all))
        }
        return Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] + chunk("IHDR", big(UInt32(width)) + big(UInt32(height)) + [8, 6, 0, 0, 0])
            + chunk("IDAT", z) + chunk("IEND", []))
    }

    private static let table: [UInt32] = (0..<256).map { n in (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xedb8_8320 ^ c >> 1 : c >> 1 } }
    private static func crc(_ bytes: [UInt8]) -> UInt32 { ~bytes.reduce(~0) { table[Int(($0 ^ UInt32($1)) & 255)] ^ $0 >> 8 } }
}

/// A program's entry in a Linux menu (freedesktop.org Desktop Entry).
struct DesktopEntry {
    let name: String?
    let program: String
    let args: [String]
    let icon: String?

    init?(_ path: String, languages: [String], folders: [String]) {
        guard let file = Window(path), file.size <= 1 << 18, let bytes = file.bytes(0, file.size) else { return nil }
        var values: [String: String] = [:], inside = false
        for line in String(decoding: bytes.all, as: UTF8.self).split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") { inside = line == "[Desktop Entry]"; continue }
            guard inside, !line.hasPrefix("#"), let equal = line.firstIndex(of: "=") else { continue }
            let key = line[..<equal].trimmingCharacters(in: .whitespaces)
            if values[key] == nil { values[key] = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces) }
        }
        guard values["Type"] == nil || values["Type"] == "Application", let exec = values["Exec"] else { return nil }
        var words = Arguments.split(exec.replacingOccurrences(of: "%%", with: "\u{0}")).filter { !($0.count == 2 && $0.hasPrefix("%")) }
            .map { $0.replacingOccurrences(of: "\u{0}", with: "%") }
        guard !words.isEmpty else { return nil }
        let first = words.removeFirst()
        guard let program = first.hasPrefix("/") ? first : folders.map({ Paths.join($0, first) }).first(where: FileManager.default.isExecutableFile) else { return nil }
        (self.program, args) = (program, words)
        name = languages.compactMap { l in values["Name[\(l.prefix(2))]"] }.first ?? values["Name"]
        icon = values["Icon"]
    }

    /// The largest PNG of a named icon in the system's folders.
    static func icon(_ name: String, data: [String]) -> String? {
        if name.hasPrefix("/") { return Picture.check(name) != nil ? name : nil }
        guard !name.contains("/"), !name.hasPrefix(".") else { return nil }
        var places: [String] = []
        for folder in data {
            for side in [512, 256, 192, 128, 96, 64, 48] { places.append("\(folder)/icons/hicolor/\(side)x\(side)/apps/\(name).png") }
            places.append("\(folder)/pixmaps/\(name).png")
        }
        return places.first { Picture.check($0) != nil }
    }

    /// The menu entry that starts `program`.
    static func entry(for program: String, languages: [String], folders: [String], data: [String]) -> DesktopEntry? {
        let real = Paths.real(program), base = (program as NSString).lastPathComponent
        for folder in data.map({ $0 + "/applications" }) {
            for file in Library.names(folder) where file.hasSuffix(".desktop") {
                let path = Paths.join(folder, file)
                // Only entries that name the program are read whole.
                guard let text = try? String(contentsOfFile: path, encoding: .utf8), text.contains(base),
                      let entry = DesktopEntry(path, languages: languages, folders: folders) else { continue }
                if Paths.real(entry.program) == real { return entry }
            }
        }
        return nil
    }
}
