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
    public var gamepadLayout: String? = "oort"
    public var createdAt: Date? = nil
    public var pageCards: ProfilePageCards? = nil
    public internal(set) var spotlightPlatform: CatalogIntegration? = nil
    public var appearsOnline: Bool? = nil
    public var showsCurrentGame: Bool? = nil
    public var sharesPresence: Bool { appearsOnline == true }
    public var sharesCurrentGame: Bool { sharesPresence && showsCurrentGame == true }
    private var pinDigest: Data? = nil
    public var isLocked: Bool { pinDigest != nil }
    public package(set) var favorites: Set<UUID> = []

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

    private func digest(_ pin: String) -> Data { PortableSHA256.hash(Data((id.uuidString + pin).utf8)) }

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
