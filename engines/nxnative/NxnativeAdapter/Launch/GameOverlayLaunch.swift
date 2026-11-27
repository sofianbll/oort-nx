import Foundation
import ImageIO
import OortLibrary
import UniformTypeIdentifiers

/// Launch-only data. Each exact, NUL-terminated key in dmhost advertises its own reader.
public struct GameOverlayLaunch {
    static let themeKey = "DM_OVERLAY_THEME_V1"
    static let playtimeKey = "DM_OVERLAY_PLAYTIME_MIN"
    static let coverKey = "DM_OVERLAY_COVER"
    static let dataKey = "DM_OVERLAY_DATA"
    static let totalKey = "DM_OVERLAY_PLAY_TIME"
    static let keys = [themeKey, playtimeKey, coverKey, dataKey, totalKey]

    private let supported: Set<String>

    public init(app: URL) {
        let host = try? Data(contentsOf: HomeMenu.hostExecutable(in: app), options: [.mappedIfSafe])
        supported = Set(Self.keys.filter { host?.range(of: Data("\($0)\0".utf8)) != nil })
    }

    public var supportsCover: Bool { supported.contains(Self.coverKey) }

    public func environment(palette: SelenePalette, playtime: TimeInterval?, cover: URL?,
                            profilePlaytime: String? = nil) -> [String: String] {
        var values: [String: String] = [:]
        if supported.contains(Self.themeKey) {
            values[Self.themeKey] = Self.theme(palette)
        }
        if supported.contains(Self.playtimeKey), let playtime, playtime >= 0,
           let minutes = Int(exactly: (playtime / 60).rounded(.down)) {
            values[Self.playtimeKey] = String(minutes)
        }
        if supportsCover, let cover, cover.isFileURL,
           (try? cover.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            values[Self.coverKey] = cover.path
        }
        if supported.contains(Self.dataKey), supported.contains(Self.totalKey) {
            values[Self.totalKey] = profilePlaytime
        }
        return values
    }

    func writeSnapshot(_ snapshot: GameOverlaySnapshot, in root: URL) throws -> URL? {
        guard supported.contains(Self.dataKey), let data = try snapshot.encoded() else { return nil }
        let directory = root.appendingPathComponent("Arcane-overlay-\(UUID())", isDirectory: true)
        let file = directory.appendingPathComponent("overlay.json")
        guard file.path.utf8.count < 4096 else { return nil }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        do {
            let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            // A restrictive umask can remove owner access too.
            guard fchmod(fd, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try handle.close()
            return file
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    static func theme(_ palette: SelenePalette) -> String? {
        let fields = [("ink", palette.ink), ("surface", palette.glass), ("scrim", palette.scrim),
                      ("focus", palette.focus), ("onFocus", palette.onFocus)]
        // Solid surface and text provide a known contrast regardless of the frame behind them.
        guard fields.allSatisfy({ $0.1 <= 0xFFFFFF }),
              contrast(palette.ink, palette.glass) >= 4.5,
              contrast(palette.onFocus, palette.focus) >= 4.5,
              contrast(palette.focus, palette.glass) >= 3 else { return nil }
        return fields.map { key, rgb in "\(key)=#\(String(format: "%06X", rgb))FF" }.joined(separator: ";")
    }

    private static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        func luminance(_ rgb: UInt32) -> Double {
            func component(_ shift: UInt32) -> Double {
                let value = Double((rgb >> shift) & 0xFF) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * component(16) + 0.7152 * component(8) + 0.0722 * component(0)
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Explicit display fields only: never encode the profile or Nextendo account models themselves.
public struct GameOverlaySnapshot: Sendable {
    public var profile: LocalProfile?
    public var color: UInt32?
    public var nextendoName: String?
    public var presence: NextendoAccountSnapshot.Presence?
    public var week: String?
    public var friends: [NextendoAccountSnapshot.Friend]?
    public var friendGameTitles: [String: String] = [:]
    public var achievements: AchievementSummary?

    public init() {}

    func encoded() throws -> Data? {
        var sections: [String: Any] = [:]
        if let profile, let name = Self.text(profile.name) {
            var person = ["name": name]
            if let color, color <= 0xFFFFFF { person["color"] = String(format: "#%06X", color) }
            person["avatar"] = profile.portrait.flatMap(Self.avatar)
            person["nextendo"] = Self.text(nextendoName)
            person["status"] = presence.map(Self.status)
            person["week"] = Self.text(week)
            sections["profile"] = person
        }
        if let friends {
            let items = friends.lazy.compactMap { friend -> [String: String]? in
                guard let name = Self.text(friend.name) else { return nil }
                var item = ["name": name, "status": Self.status(friend.presence)]
                if friend.presence == .playing {
                    let fallback = friend.gameID.flatMap { friendGameTitles[$0.uppercased()] }
                    item["game"] = Self.text(friend.game) ?? Self.text(fallback)
                }
                return item
            }.prefix(100)
            if !items.isEmpty { sections["friends"] = ["shared": true, "items": Array(items)] }
        }
        if let achievements, achievements.total > 0 {
            let total = min(100_000, achievements.total)
            let recent = achievements.rows(.unlocked).lazy.compactMap { Self.text($0.name) }.prefix(4)
            sections["achievements"] = ["total": total, "unlocked": min(total, achievements.unlocked), "recent": Array(recent)]
        }
        guard !sections.isEmpty else { return nil }
        let data = try JSONSerialization.data(withJSONObject: sections)
        return data.count <= 512 * 1024 ? data : nil
    }

    private static func text(_ value: String?) -> String? {
        guard let value else { return nil }
        let words = value.components(separatedBy: .controlCharacters.union(.newlines))
        let clean = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var length = 0
        let prefix = clean.prefix { character in
            length += character.utf16.count
            return length <= 160
        }
        return prefix.isEmpty ? nil : String(prefix)
    }

    private static func status(_ presence: NextendoAccountSnapshot.Presence) -> String {
        switch presence {
        case .offline: return "offline"
        case .online: return "online"
        case .playing: return "playing"
        }
    }

    private static func avatar(_ portrait: Data) -> String? {
        guard portrait.count <= LocalProfileStore.maximumPortraitBytes,
              let source = CGImageSourceCreateWithData(portrait as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 256
              ] as CFDictionary) else { return nil }
        let bytes = NSMutableData()
        guard let jpeg = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(jpeg, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(jpeg), bytes.length <= 98_304 else { return nil }
        return (bytes as Data).base64EncodedString()
    }
}
