import AppKit
import NXLibraryCore

public struct GameDisplay: Equatable {
    public static let key = "DM_SCREEN"
    public static let likeArcane = "Like Arcane"
    public static let useGlobal = "Use global setting"
    public static let disconnected = "Display not connected"
    public static let title = "Game display"

    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    public init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let id = UUID(uuidString: CFUUIDCreateString(nil, uuid) as String) else { return nil }
        self.init(id: id, name: screen.localizedName)
    }

    /// A missing choice follows Arcane, not another preferred display. Keep the stored UUID for reconnection.
    public static func resolve(_ choice: String, connected: [GameDisplay], arcane: UUID?) -> (id: UUID?, missing: Bool) {
        guard let id = UUID(uuidString: choice) else { return (arcane, false) }
        return connected.contains { $0.id == id } ? (id, false) : (arcane, true)
    }

    /// The bundled launcher would otherwise give the process environment priority over the player's file.
    public static func fileOverride(for game: PortedGame,
                                    support: URL = FileManager.default.homeDirectoryForCurrentUser
                                        .appendingPathComponent("Library/Application Support/nxnative")) -> String? {
        let files = [game.titleId.map { support.appendingPathComponent($0).appendingPathComponent("env.txt") },
                     game.url.appendingPathComponent("Contents/Resources/dm/env.txt")]
        for file in files.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: file) else { continue }
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                if let (key, value) = NXNativeGameSettings.pair(String(line)), key == Self.key { return value }
            }
        }
        return nil
    }
}
