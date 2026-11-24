import Combine
import CryptoKit
import Foundation

public enum ProfileStartup: Codable, Equatable {
    case ask, last, profile(UUID)

    public func available(in profiles: [LocalProfile]) -> Self {
        if case .profile(let id) = self, !profiles.contains(where: { $0.id == id }) { return .ask }
        return self
    }
}

public struct LocalProfile: Codable, Equatable, Identifiable {
    public static let avatarCount = 28
    public let id: UUID
    public var name: String
    private var initialName: String? = nil
    public var defaultName: String { initialName ?? name }
    public var avatar: Int
    public var portrait: Data?
    public var look: Look
    public var createdAt: Date? = nil
    public var pageCards: ProfilePageCards? = nil
    public fileprivate(set) var spotlightPlatform: CatalogIntegration? = nil
    public var appearsOnline: Bool? = nil
    public var showsCurrentGame: Bool? = nil
    public var sharesPresence: Bool { appearsOnline == true }
    public var sharesCurrentGame: Bool { sharesPresence && showsCurrentGame == true }
    private var pinDigest: Data? = nil
    public var isLocked: Bool { pinDigest != nil }
    public fileprivate(set) var favorites: Set<UUID> = []

    public init(id: UUID = UUID(), name: String, avatar: Int = 0, portrait: Data? = nil, look: Look) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.portrait = portrait
        self.look = look
        self.createdAt = .now
    }

    public static let pinLength = 4

    public mutating func rename(to name: String) {
        if initialName == nil { initialName = self.name }
        self.name = name
    }

    public mutating func setPIN(_ pin: String?) -> Bool {
        if let pin, pin.utf8.count != Self.pinLength || !pin.utf8.allSatisfy({ (48...57).contains($0) }) { return false }
        pinDigest = pin.map(digest)
        return true
    }

    public func matchesPIN(_ pin: String) -> Bool { pinDigest == digest(pin) }

    private func digest(_ pin: String) -> Data { Data(SHA256.hash(data: Data((id.uuidString + pin).utf8))) }

    public struct Look: Codable, Equatable {
        public var theme: String
        public var wallpaper: String?
        public var settingsWallpaper: String?
        public var sizing: BackgroundSizing
        public var order: [String]

        public init(_ settings: AppSettings) {
            theme = settings.colorThemeID
            wallpaper = settings.wallpaperID
            settingsWallpaper = settings.settingsWallpaperID
            sizing = settings.backgroundSizing
            order = settings.spotlightOrder
        }

        public func apply(to settings: inout AppSettings) {
            settings.colorThemeID = theme
            settings.wallpaperID = wallpaper
            settings.settingsWallpaperID = settingsWallpaper
            settings.backgroundSizing = sizing
            settings.spotlightOrder = order
        }
    }
}

/// The first profile inherits the existing catalog favorites and play history without rewriting either file.
public final class LocalProfileStore: ObservableObject {
    public static let maximumPortraitBytes = 4_000_000
    private struct Document: Codable {
        let originalID: UUID
        var activeID: UUID
        var profiles: [LocalProfile]
    }

    @Published private var document: Document?
    @Published public private(set) var guest: LocalProfile?
    @Published public private(set) var failed = false
    private let url: URL
    private let selectionURL: URL

    public var profiles: [LocalProfile] { document?.profiles ?? [] }
    public var active: LocalProfile? { guest ?? profiles.first { $0.id == document?.activeID } }
    public var originalID: UUID? { document?.originalID }

    /// Resolve before applying the active profile's appearance and play history.
    public func startupSelection(_ preference: ProfileStartup) -> UUID? {
        if case .profile(let id) = preference.available(in: profiles) { return id }
        return active?.id
    }

    public func needsStartupPicker(_ preference: ProfileStartup) -> Bool {
        guard active != nil else { return false }
        switch preference.available(in: profiles) {
        case .ask: return true
        case .last: return active?.isLocked == true
        case .profile(let id):
            return profiles.first { $0.id == id }?.isLocked == true || !choose(id)
        }
    }

    public init(directory: URL = AppData.supportRoot, settings: AppSettings, name: String) {
        url = directory.appendingPathComponent("profiles.json")
        selectionURL = directory.appendingPathComponent("profiles-active")
        do { try Self.backup(in: directory) }
        catch { failed = true; return }
        do {
            var saved = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            guard Set(saved.profiles.map(\.id)).count == saved.profiles.count,
                  saved.profiles.contains(where: { $0.id == saved.activeID }) else {
                failed = true
                return
            }
            if let text = try? String(contentsOf: selectionURL, encoding: .utf8), let id = UUID(uuidString: text),
               saved.profiles.contains(where: { $0.id == id }) {
                saved.activeID = id
            }
            document = saved
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            let initial = LocalProfile(name: name, look: .init(settings))
            _ = save(Document(originalID: initial.id, activeID: initial.id, profiles: [initial]))
        } catch {
            failed = true
        }
    }

    @discardableResult public func choose(_ id: UUID) -> Bool {
        guard var next = document, next.profiles.contains(where: { $0.id == id }) else { return false }
        if next.activeID == id { guest = nil; return true }
        do {
            try Data(id.uuidString.utf8).write(to: selectionURL, options: .atomic)
            next.activeID = id
            document = next
            guest = nil
            failed = false
            return true
        } catch {
            failed = true
            return false
        }
    }

    @discardableResult public func beginGuest(_ profile: LocalProfile) -> Bool {
        guard document != nil, !failed, guest == nil, !profiles.contains(where: { $0.id == profile.id }) else { return false }
        guest = profile
        return true
    }

    /// The picker may have lost its input or its profile while its preview was open.
    @discardableResult public func rememberSpotlightPlatform(_ integration: CatalogIntegration?, for profile: PlayProfile) -> Bool {
        guard !profile.blocksPlay, var active, profile.id == active.id, profile.isGuest == (guest != nil) else { return false }
        guard active.spotlightPlatform != integration else { return true }
        active.spotlightPlatform = integration
        return update(active)
    }

    @discardableResult public func update(_ value: LocalProfile) -> Bool {
        guard var next = document else { return false }
        var profile = value
        profile.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.name.isEmpty, profile.name.count <= 32,
              (0..<LocalProfile.avatarCount).contains(profile.avatar), (profile.portrait?.count ?? 0) <= Self.maximumPortraitBytes else { return false }
        if guest?.id == profile.id {
            profile.favorites = guest?.favorites ?? []
            guest = profile
            return true
        }
        if let index = next.profiles.firstIndex(where: { $0.id == value.id }) {
            profile.favorites = next.profiles[index].favorites
            guard next.profiles[index] != profile else { return true }
            next.profiles[index] = profile
        } else {
            next.profiles.append(profile)
        }
        return save(next)
    }

    @discardableResult public func remove(_ id: UUID) -> Bool {
        guard var next = document, id != next.originalID, next.profiles.count > 1,
              let index = next.profiles.firstIndex(where: { $0.id == id }) else { return false }
        next.profiles.remove(at: index)
        if next.activeID == id { next.activeID = next.profiles[min(index, next.profiles.count - 1)].id }
        return save(next)
    }

    @discardableResult public func toggleFavorite(_ gameID: UUID) -> Bool {
        if var guest {
            if guest.favorites.remove(gameID) == nil { guest.favorites.insert(gameID) }
            self.guest = guest
            return true
        }
        guard var next = document, let index = next.profiles.firstIndex(where: { $0.id == next.activeID }) else { return false }
        if next.profiles[index].favorites.remove(gameID) == nil { next.profiles[index].favorites.insert(gameID) }
        return save(next)
    }

    private func save(_ next: Document) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            document = next
            failed = false
            return true
        } catch {
            failed = true
            return false
        }
    }

    /// Publish the original files together, once, without touching the credential store.
    private static func backup(in directory: URL) throws {
        let manager = FileManager.default
        let backup = directory.appendingPathComponent("profiles-migration-backup")
        guard !manager.fileExists(atPath: backup.path) else { return }
        let stage = directory.appendingPathComponent(".profiles-backup-\(UUID().uuidString)")
        try manager.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: stage) }
        for name in ["profiles.json", "profiles-active", "settings.json", "catalog.json", "catalog.json.bak",
                     "library.json", "library.json.bak", "play-sessions.json", "play-sessions-totals.json", SessionHistoryState.filename] {
            let source = directory.appendingPathComponent(name)
            if manager.fileExists(atPath: source.path) {
                try manager.copyItem(at: source, to: stage.appendingPathComponent(name))
            }
        }
        try manager.moveItem(at: stage, to: backup)
    }
}
