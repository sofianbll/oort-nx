import Foundation

/// Steam's own art for a game that is also on Steam: the publisher's logo with a
/// transparent background, the library cover and the library background. Found by
/// the store's public search, and only for a game whose name is the same.
public enum SteamStoreArt {
    package static let assets = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps"

    /// The store search for `name`, without trademark signs.
    public static func searchURL(for name: String) -> URL? {
        let term = plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        components.queryItems = [.init(name: "term", value: term), .init(name: "l", value: "english"),
                                 .init(name: "cc", value: "US")]
        return components.url
    }

    /// The app named like one of `names` (`ArtworkNames`); a DLC or a soundtrack never is.
    public static func appID(in data: Data, matching names: [String]) -> Int? {
        struct Wire: Decodable {
            struct Item: Decodable { var type: String?; var name: String; var id: Int }
            var items: [Item]?
        }
        guard let items = (try? JSONDecoder().decode(Wire.self, from: data))?.items else { return nil }
        return items.first { ($0.type ?? "app") == "app" && ArtworkNames.matches($0.name, names) }?.id
    }

    package static func url(_ appID: Int, _ file: String) -> URL {
        URL(string: "\(assets)/\(appID)/\(file)")!
    }

    package static func plain(_ name: String) -> String {
        var text = name
        for mark in ["™", "®", "©"] { text = text.replacingOccurrences(of: mark, with: "") }
        return text.split(separator: " ").joined(separator: " ")
    }
}
