import Foundation
import zlib

extension SoundPackEvent {
    public var legacyCue: SoundCue? {
        switch self {
        case .move: return .move
        case .select: return .select
        case .confirm: return .key
        case .back, .close: return .back
        case .deny, .notification: return .alert
        case .open: return .openPanel
        case .play: return .gameStarting
        case .success: return .success
        case .boot: return .boot
        case .resume, .ambience: return nil
        }
    }
}

public struct SoundPackManifest: Decodable, Sendable {
    public let id, name, author, license, version: String
    public let format: Int
    public let events: [String: [String]]
}

public enum SoundPackError: Error, LocalizedError {
    case layout, metadata, audio, archive, size, unavailable, duplicate, capacity

    public var errorDescription: String? {
        switch self {
        case .layout: return L10n.text("Put manifest.json and the listed WAV files at the root of the sound pack. Links and other files are not allowed.")
        case .metadata: return L10n.text("The sound pack manifest is invalid. Check its format, details and event names.")
        case .audio: return L10n.text("A sound is too loud, too long or not a supported WAV. Use 24 kHz, 16-bit mono PCM.")
        case .archive: return L10n.text("This sound pack ZIP is invalid or uses an unsupported ZIP option.")
        case .size: return L10n.text("This sound pack is too large. Use up to 40 files and 4 MB.")
        case .unavailable: return L10n.text("This sound pack is unavailable.")
        case .duplicate: return L10n.text("A sound pack with this ID is already installed. Remove the old copy before importing another.")
        case .capacity: return L10n.text("Remove an imported sound pack before adding another. The limit is 12.")
        }
    }
}

/// A validated, bounded snapshot; confirmation can copy it without re-reading the source.
public struct SoundPack: Sendable {
    static let limit = 4 * 1024 * 1024
    static let maxFiles = 40
    static let manifestLimit = 16 * 1024
    public let manifest: SoundPackManifest
    fileprivate let files: [String: Data]

    public func audio(for event: SoundPackEvent) -> Data? {
        manifest.events[event.rawValue]?.randomElement().flatMap { files[$0] }
    }

    public static func read(_ url: URL) throws -> SoundPack {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SoundPackError.unavailable }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw SoundPackError.unavailable }
        let files: [String: Data]
        if info.st_mode & S_IFMT == S_IFDIR {
            files = try readFolder(fd)
        } else {
            guard url.pathExtension.lowercased() == "oortsound" else { throw SoundPackError.layout }
            files = try SoundPackZIP.read(readFile(fd, maximum: limit))
        }
        guard let json = files["manifest.json"] else { throw SoundPackError.layout }
        let allowed: Set<String> = ["format", "id", "name", "author", "license", "version", "events"]
        guard String(data: json, encoding: .utf8) != nil,
              let keys = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              Set(keys.keys) == allowed,
              let manifest = try? JSONDecoder().decode(SoundPackManifest.self, from: json),
              manifest.format == 1, isID(manifest.id),
              [manifest.name, manifest.author, manifest.license].allSatisfy(isLabel),
              manifest.version.range(of: #"^[0-9]{1,8}\.[0-9]{1,8}\.[0-9]{1,8}$"#, options: .regularExpression) != nil,
              !manifest.events.isEmpty else { throw SoundPackError.metadata }
        var expected: Set<String> = ["manifest.json"]
        for (key, variants) in manifest.events {
            guard let event = SoundPackEvent(rawValue: key), (1...3).contains(variants.count),
                  Set(variants).count == variants.count else { throw SoundPackError.metadata }
            for name in variants {
                guard name != "manifest.json", validFile(name), let bytes = files[name] else { throw SoundPackError.layout }
                try validateWAV(bytes, event: event)
                expected.insert(name)
            }
        }
        guard expected == Set(files.keys) else { throw SoundPackError.layout }
        return SoundPack(manifest: manifest, files: files)
    }

    static func isID(_ value: String) -> Bool {
        (1...48).contains(value.utf8.count) &&
        value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }

    private static func isLabel(_ value: String) -> Bool {
        (1...80).contains(value.count) && value.utf8.count <= 320 &&
        value == value.trimmingCharacters(in: .whitespacesAndNewlines) &&
        value.unicodeScalars.allSatisfy {
            switch $0.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return false
            default: return true
            }
        }
    }

    static func validFile(_ name: String) -> Bool {
        if name == "manifest.json" { return true }
        return (5...64).contains(name.utf8.count) && name.hasSuffix(".wav") &&
        name.utf8.dropLast(4).allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }

    static func maxBytes(_ name: String) -> Int {
        name == "manifest.json" ? manifestLimit : 44 + 30 * 24_000 * 2
    }

    private static func readFolder(_ fd: Int32) throws -> [String: Data] {
        let copy = dup(fd)
        guard copy >= 0 else { throw SoundPackError.unavailable }
        guard let directory = fdopendir(copy) else {
            Darwin.close(copy)
            throw SoundPackError.unavailable
        }
        defer { closedir(directory) }
        var files: [String: Data] = [:], remaining = limit
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw SoundPackError.unavailable }
                break
            }
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: &entry.pointee.d_name) {
                String(decoding: $0.prefix(length), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            guard validFile(name), files[name] == nil else { throw SoundPackError.layout }
            guard files.count < maxFiles else { throw SoundPackError.size }
            var info = stat()
            guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0, info.st_mode & S_IFMT == S_IFREG else {
                throw SoundPackError.layout
            }
            let item = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard item >= 0 else { throw SoundPackError.layout }
            defer { Darwin.close(item) }
            let data = try readFile(item, maximum: min(remaining, maxBytes(name)), singleLink: true)
            remaining -= data.count
            files[name] = data
        }
        return files
    }

    private static func readFile(_ fd: Int32, maximum: Int, singleLink: Bool = false) throws -> Data {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              !singleLink || info.st_nlink == 1 else { throw SoundPackError.layout }
        guard (0...Int64(maximum)).contains(info.st_size) else { throw SoundPackError.size }
        var bytes = Data(count: Int(info.st_size) + 1)
        let count = try bytes.withUnsafeMutableBytes { buffer in
            var used = 0
            while used < buffer.count {
                let step = Darwin.read(fd, buffer.baseAddress!.advanced(by: used), buffer.count - used)
                if step < 0, errno == EINTR { continue }
                guard step >= 0 else { throw SoundPackError.unavailable }
                if step == 0 { break }
                used += step
            }
            return used
        }
        guard count == info.st_size else { throw SoundPackError.size }
        bytes.removeLast()
        return bytes
    }

    private static func validateWAV(_ data: Data, event: SoundPackEvent) throws {
        guard data.count >= 44, data.count % 2 == 0,
              data.u32(0) == 0x46464952, data.u32(4) == data.count - 8, data.u32(8) == 0x45564157,
              data.u32(12) == 0x20746d66, data.u32(16) == 16, data.u16(20) == 1, data.u16(22) == 1,
              data.u32(24) == 24_000, data.u32(28) == 48_000, data.u16(32) == 2, data.u16(34) == 16,
              data.u32(36) == 0x61746164, data.u32(40) == data.count - 44 else { throw SoundPackError.audio }
        let count = (data.count - 44) / 2
        guard (240...(event == .ambience ? 720_000 : 18_000)).contains(count) else { throw SoundPackError.audio }
        let power: Double = try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var sum = 0.0
            for index in stride(from: 44, to: bytes.count, by: 2) {
                let sample = Double(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index, as: Int16.self))) / 32768
                guard abs(sample) <= 0.50118724 else { throw SoundPackError.audio }
                sum += sample * sample
            }
            return sum / Double(count)
        }
        guard power <= 0.025118865 else { throw SoundPackError.audio }
    }
}

public struct SoundPackLibrary: Sendable {
    private static let builtIn = ["oort", "pollen", "umbra", "impulsion"]
    private static let importLimit = 12
    private let root: URL
    private let bundled: URL?

    public init(root: URL = AppData.supportRoot.appendingPathComponent("SoundPacks", isDirectory: true),
                bundled: URL? = Bundle.main.resourceURL?.appendingPathComponent("SoundPacks", isDirectory: true)) {
        self.root = root
        self.bundled = bundled
    }

    public func choices() -> [(key: String, name: String)] {
        let originals = Self.builtIn.compactMap { key -> (String, String)? in
            guard let value = try? load(key) else { return nil }
            return (key, value.manifest.name)
        }
        let customs = customIDs().prefix(Self.importLimit).map { id in
            let key = "custom." + id
            return (key, (try? load(key))?.manifest.name ?? id)
        }
        return [("selene", "Selene")] + originals + customs
    }

    private func customIDs() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return contents.compactMap { name in
            let id = String(name.dropLast(".oortsound".count))
            return name.hasSuffix(".oortsound") && SoundPack.isID(id) ? id : nil
        }.sorted()
    }

    public func load(_ key: String) throws -> SoundPack? {
        if key == "selene" { return nil }
        let id: String, source: URL
        if key.hasPrefix("custom.") {
            id = String(key.dropFirst(7))
            source = try customURL(id)
        } else {
            guard Self.builtIn.contains(key), let bundled else { throw SoundPackError.unavailable }
            id = key
            source = bundled.appendingPathComponent(id + ".oortsound", isDirectory: true)
        }
        let pack = try SoundPack.read(source)
        guard pack.manifest.id == id else { throw SoundPackError.metadata }
        return pack
    }

    public func install(_ pack: SoundPack) throws {
        let fm = FileManager.default
        let destination = try customURL(pack.manifest.id)
        guard !fm.fileExists(atPath: destination.path) else { throw SoundPackError.duplicate }
        guard customIDs().count < Self.importLimit else { throw SoundPackError.capacity }
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stage = root.appendingPathComponent("." + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        for (name, data) in pack.files { try data.write(to: stage.appendingPathComponent(name), options: .withoutOverwriting) }
        // One exclusive move publishes a complete copy; another import cannot overwrite it.
        let result = renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, destination.path, UInt32(RENAME_EXCL))
        if result != 0 {
            if errno == EEXIST { throw SoundPackError.duplicate }
            throw SoundPackError.unavailable
        }
    }

    public func remove(_ key: String) throws {
        guard key.hasPrefix("custom.") else { throw SoundPackError.unavailable }
        let url = try customURL(String(key.dropFirst(7)))
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private func customURL(_ id: String) throws -> URL {
        guard SoundPack.isID(id) else { throw SoundPackError.unavailable }
        return root.appendingPathComponent(id + ".oortsound", isDirectory: true)
    }
}

extension Data {
    fileprivate func u16(_ index: Int) -> Int { Int(self[index]) | Int(self[index + 1]) << 8 }
    fileprivate func u32(_ index: Int) -> Int { u16(index) | u16(index + 2) << 16 }
}

private enum SoundPackZIP {
    static func read(_ zip: Data) throws -> [String: Data] {
        let end = zip.count - 22
        guard end >= 0, zip.u32(end) == 0x06054b50, zip.u32(end + 4) == 0, zip.u16(end + 20) == 0,
              zip.u16(end + 8) == zip.u16(end + 10) else { throw SoundPackError.archive }
        let count = zip.u16(end + 10), start = zip.u32(end + 16)
        guard (1...SoundPack.maxFiles).contains(count), start + zip.u32(end + 12) == end else { throw SoundPackError.size }
        var remaining = SoundPack.limit, central = start, ranges: [Range<Int>] = [], files: [String: Data] = [:]
        for _ in 0..<count {
            guard central + 46 <= end, zip.u32(central) == 0x02014b50, zip.u16(central + 34) == 0 else {
                throw SoundPackError.archive
            }
            let flags = zip.u16(central + 8), method = zip.u16(central + 10), crc = zip.u32(central + 16)
            let compressed = zip.u32(central + 20), size = zip.u32(central + 24), nameLength = zip.u16(central + 28)
            let local = zip.u32(central + 42), type = mode_t(zip.u32(central + 38) >> 16) & S_IFMT
            let next = central + 46 + nameLength + zip.u16(central + 30) + zip.u16(central + 32)
            guard next <= end, local + 30 <= start, flags & ~0x806 == 0, method == 0 || method == 8,
                  type == 0 || type == S_IFREG, zip.u32(local) == 0x04034b50,
                  zip.u16(local + 6) == flags, zip.u16(local + 8) == method,
                  zip.u32(local + 14) == crc, zip.u32(local + 18) == compressed, zip.u32(local + 22) == size,
                  zip.u16(local + 26) == nameLength else { throw SoundPackError.archive }
            let payload = local + 30 + nameLength + zip.u16(local + 28)
            let range = local..<(payload + compressed)
            guard range.upperBound <= start, !ranges.contains(where: { $0.overlaps(range) }) else { throw SoundPackError.archive }
            let nameBytes = zip[(central + 46)..<(central + 46 + nameLength)]
            let name = String(decoding: nameBytes, as: UTF8.self)
            guard SoundPack.validFile(name), files[name] == nil,
                  zip[(local + 30)..<(local + 30 + nameLength)] == nameBytes else { throw SoundPackError.layout }
            guard size <= min(remaining, SoundPack.maxBytes(name)) else { throw SoundPackError.size }
            let encoded = zip.subdata(in: payload..<range.upperBound)
            let decoded = method == 0 ? encoded : try inflate(encoded, size: size)
            let actual = decoded.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(decoded.count)) }
            guard decoded.count == size, actual == crc else { throw SoundPackError.archive }
            files[name] = decoded
            remaining -= size
            ranges.append(range)
            central = next
        }
        guard central == end, ranges.reduce(0, { $0 + $1.count }) == start else { throw SoundPackError.archive }
        return files
    }

    private static func inflate(_ bytes: Data, size: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw SoundPackError.archive
        }
        defer { inflateEnd(&stream) }
        var decoded = Data(count: size + 1)
        let status = bytes.withUnsafeBytes { input in
            decoded.withUnsafeMutableBytes { output in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
                stream.avail_in = uInt(bytes.count)
                stream.next_out = output.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = uInt(size + 1)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.avail_in == 0, stream.total_out == size else { throw SoundPackError.archive }
        decoded.removeLast()
        return decoded
    }
}
