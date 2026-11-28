import Foundation

/// A game's introduction from Wikipedia in the player's language, shown in About this game when the store has no
/// text in that language. Licensed CC BY-SA: the page link travels with the text and is shown beside it.
public struct WikipediaDescription: Codable, Equatable, Sendable {
    public let text: String
    public let pageURL: URL
}

/// Narrow contract: the same Wikidata identity as critic ratings (`WikidataRatings.entity`), its sitelink to the
/// player's Wikipedia, and that article's plain-text introduction.
public enum WikipediaDescriptions {
    /// Shorter texts are too uncertain to name a language.
    static let minimumLength = 40

    /// The Wikipedia edition for `language`, and the script variant its text is converted to.
    public static func edition(for language: AppLanguage) -> (code: String, variant: String?)? {
        switch language {
        case .automatic: return nil
        case .chineseSimplified: return ("zh", "zh-cn")
        case .portugueseBrazil: return ("pt", nil)
        default: return (language.rawValue, nil)
        }
    }

    /// The article title on `code`.wikipedia for the game the query names, or nil when it has none.
    public static func sitelink(in data: Data, ids: [String], query: CriticRatingQuery, requireSteamID: Bool,
                                edition code: String) throws -> String? {
        guard let (_, entity) = try WikidataRatings.entity(in: data, ids: ids, query: query,
                                                           requireSteamID: requireSteamID, disambiguateSwitchPlatform: true),
              let links = entity["sitelinks"] as? [String: [String: Any]],
              let title = links[code + "wiki"]?["title"] as? String, !title.isEmpty, title.count <= 300 else { return nil }
        return title
    }

    public static func introURL(edition code: String, title: String, variant: String?) -> URL? {
        guard allowedEditions.contains(code), !title.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = code + ".wikipedia.org"
        components.path = "/w/api.php"
        var items = ["action": "query", "prop": "extracts|info", "exintro": "1", "explaintext": "1",
                     "inprop": "url", "redirects": "1", "format": "json", "formatversion": "2", "titles": title]
        if let variant { items["variant"] = variant }
        components.queryItems = items.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        return components.url
    }

    /// The introduction as plain text, with its page; nil for a missing page or an empty introduction.
    public static func description(in data: Data, edition code: String) throws -> WikipediaDescription? {
        let root = try WikidataRatings.object(data)
        guard let query = root["query"] as? [String: Any], let pages = query["pages"] as? [[String: Any]]
        else { throw URLError(.cannotParseResponse) }
        guard let page = pages.first, page["missing"] == nil,
              let raw = page["extract"] as? String,
              let link = (page["fullurl"] as? String).flatMap(URL.init(string:)),
              link.scheme == "https", link.host == code + ".wikipedia.org" else { return nil }
        let text = raw.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard text.count >= minimumLength else { return nil }
        return WikipediaDescription(text: text, pageURL: link)
    }

    static let allowedEditions: Set<String> = ["en", "it", "fr", "de", "es", "pt", "zh"]
}

