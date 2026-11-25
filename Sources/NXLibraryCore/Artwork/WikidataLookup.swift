import Foundation

/// Narrow Wikidata contract: exact video-game identity. Critic aggregates are in WikidataRatings.swift; this part
/// imports nothing from Apple, so Windows and Linux build it too.
public enum WikidataRatings {
    package static func isItemID(_ value: String) -> Bool {
        value.first == "Q" && value.count > 1 && value.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }
    private static func normalized(_ value: String) -> String {
        String(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
    public static func searchURL(name: String) -> URL? {
        guard !name.isEmpty, name.count <= 300 else { return nil }
        // Store trademarks prevent wbsearchentities from finding an otherwise exact title.
        // Keep edition/sequel words: those carry identity, unlike the trademark marks.
        let clean = ["™", "®", "©"].reduce(name) { $0.replacingOccurrences(of: $1, with: "") }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty else { return nil }
        return url(["action": "wbsearchentities", "search": clean, "language": "en", "type": "item", "limit": "5"])
    }
    public static func steamSearchURL(appID: UInt32) -> URL? {
        guard appID > 0 else { return nil }
        return url(["action": "query", "list": "search", "srsearch": "haswbstatement:P1733=\(appID)",
                    "srnamespace": "0", "srlimit": "5", "srprop": ""])
    }
    public static func steamIDs(in data: Data) throws -> [String] {
        let root = try object(data)
        guard let query = root["query"] as? [String: Any], let search = query["search"] as? [[String: Any]]
        else { throw CocoaError(.coderReadCorrupt) }
        return Array(Set(search.compactMap { item -> String? in
            guard let id = item["title"] as? String, isItemID(id), item["ns"] as? Int == 0 else { return nil }
            return id
        })).sorted()
    }
    public static func entitiesURL(ids: [String], props: String = "claims") -> URL? {
        guard !ids.isEmpty, ids.count <= 5, ids.allSatisfy(isItemID) else { return nil }
        return url(["action": "wbgetentities", "ids": ids.joined(separator: "|"), "props": props])
    }
    private static func url(_ values: [String: String]) -> URL? {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = (values.merging(["format": "json", "maxlag": "5"], uniquingKeysWith: { _, b in b }))
            .sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        return components.url
    }
    public static func ids(in data: Data, name: String) throws -> [String] {
        let root = try object(data)
        guard let search = root["search"] as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
        let target = normalized(name)
        guard !target.isEmpty else { return [] }
        return Array(Set(search.compactMap { item -> String? in
            guard let id = item["id"] as? String, isItemID(id) else { return nil }
            var names = [item["label"] as? String].compactMap { $0 } + (item["aliases"] as? [String] ?? [])
            if let match = item["match"] as? [String: String], match["type"] == "alias", let text = match["text"] {
                names.append(text)
            }
            return names.contains { normalized($0) == target } ? id : nil
        })).sorted()
    }
    /// The one video game among `ids` that the query names: P31 video game, and the Steam app ID when either side has
    /// one. Shared by ratings and Wikipedia descriptions, so both name the same game.
    package static func entity(in data: Data, ids: [String], query: CriticRatingQuery,
                       requireSteamID: Bool, disambiguateSwitchPlatform: Bool = false) throws -> (id: String, entity: [String: Any])? {
        let root = try object(data)
        guard let entities = root["entities"] as? [String: [String: Any]],
              ids.allSatisfy({ entities[$0] != nil }) else { throw CocoaError(.coderReadCorrupt) }
        var matched = ids.filter { id in
            guard let claims = entities[id]?["claims"] as? [String: [[String: Any]]],
                  claimItems(claims["P31"] ?? []).contains("Q7889") else { return false }
            let steam = (claims["P1733"] ?? []).filter { ($0["rank"] as? String) != "deprecated" }
                .compactMap { ($0["mainsnak"] as? [String: Any]).flatMap(value) as? String }
            if let expected = query.steamAppID, requireSteamID || !steam.isEmpty { return steam.contains(String(expected)) }
            return true
        }
        if matched.count > 1, disambiguateSwitchPlatform, query.platform != .mac {
            // Use a declared platform to break a tie between the original release and a same-name remake.
            matched = matched.filter { id in
                let claims = entities[id]?["claims"] as? [String: [[String: Any]]]
                return claimItems(claims?["P400"] ?? []).contains(query.platform.wikidataID)
            }
        }
        guard matched.count == 1, let id = matched.first, let entity = entities[id] else { return nil }
        return (id, entity)
    }
    package static func value(_ snak: [String: Any]) -> Any? { (snak["datavalue"] as? [String: Any])?["value"] }
    package static func item(_ snak: [String: Any]) -> String? {
        guard let id = (value(snak) as? [String: Any])?["id"] as? String, isItemID(id) else { return nil }
        return id
    }
    package static func claimItems(_ claims: [[String: Any]]) -> [String] {
        claims.filter { $0["rank"] as? String != "deprecated" }.compactMap { ($0["mainsnak"] as? [String: Any]).flatMap(item) }
    }
    package static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 4_194_304, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error"] == nil else { throw CocoaError(.coderReadCorrupt) }
        return root
    }
}
