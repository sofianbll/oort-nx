import Foundation
import NXLibraryCore

/// Where each engine setting goes on a game's settings page. The build says which settings it has (`launcher.json`)
/// and what each accepts; this only sorts them. A setting the catalog does not list stays reachable under Other, so
/// a newer engine needs no change here: adding its name to `game-settings-<engine>.json` moves it to a category.
public struct GameSettingCatalog: Decodable, Equatable {
    public static let otherID = "other"

    public struct Category: Decodable, Equatable {
        public let id: String
        /// Localization key.
        public let title: String
        public let settings: [String]
    }

    /// A line of the game's env.txt that no setting of the build covers: shown as it is, never changed.
    public struct FileLine: Equatable, Identifiable {
        public let key: String
        public let value: String
        public var id: String { key }
    }

    public struct Group: Equatable, Identifiable {
        public let id: String
        public let title: String
        public let settings: [LauncherSetting]
        public let fileLines: [FileLine]
    }

    public let categories: [Category]

    public init(categories: [Category]) { self.categories = categories }

    /// The catalog shipped for an engine; an unreadable one sorts everything under Other.
    public static func load(engine: String = "nxnative") -> GameSettingCatalog {
        guard let url = L10n.resources()?.url(forResource: "game-settings-\(engine)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(GameSettingCatalog.self, from: data)
        else { return GameSettingCatalog(categories: []) }
        return catalog
    }

    /// Non-empty groups in the catalog's order, Other last. Within a group the catalog's order, then the build's.
    public func groups(for settings: [LauncherSetting], envText: String? = nil) -> [Group] {
        let offered = Dictionary(settings.map { ($0.env, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(categories.flatMap(\.settings))
        var groups = categories.compactMap { category -> Group? in
            let found = category.settings.compactMap { offered[$0] }
            return found.isEmpty ? nil : Group(id: category.id, title: category.title, settings: found, fileLines: [])
        }
        var seen = Set<String>()
        let unknown = settings.filter { !known.contains($0.env) && seen.insert($0.env).inserted }
        let lines = Self.lines(of: envText).filter { offered[$0.key] == nil }
        if !unknown.isEmpty || !lines.isEmpty {
            groups.append(Group(id: Self.otherID, title: "Other", settings: unknown, fileLines: lines))
        }
        return groups
    }

    /// First line wins, as the launcher reads them.
    private static func lines(of text: String?) -> [FileLine] {
        guard let text else { return [] }
        var seen = Set<String>()
        return text.components(separatedBy: .newlines).compactMap { line in
            guard let (key, value) = NXNativeGameSettings.pair(line), seen.insert(key).inserted else { return nil }
            return FileLine(key: key, value: value)
        }
    }
}
