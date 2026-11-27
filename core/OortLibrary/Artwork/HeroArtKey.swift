import Foundation

/// Names the art behind a page. The game's id leads, so the page can tell whose art it holds.
public enum HeroArtKey {
    public static func make(_ id: UUID, _ source: String) -> String { id.uuidString + "|" + source + "|" }
    public static func belongs(_ key: String, to id: UUID) -> Bool { key.hasPrefix(id.uuidString + "|") }
}
