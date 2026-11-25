import Foundation

/// Referenced /100 critic aggregates. Source/metric IDs come from the inspected P444/P447/P459 statements, not label
/// guesses.
extension WikidataRatings {
    public static func rating(in data: Data, ids: [String], query: CriticRatingQuery,
                              requireSteamID: Bool = false) throws -> CriticRating? {
        guard let (id, entity) = try entity(in: data, ids: ids, query: query, requireSteamID: requireSteamID),
              let claims = entity["claims"] as? [String: [[String: Any]]] else { return nil }
        let ratings = (claims["P444"] ?? []).compactMap { parse($0, entityID: id, platform: query.platform.wikidataID) }
        return ratings.sorted { a, b in
            if a.platforms.isEmpty != b.platforms.isEmpty { return !a.platforms.isEmpty }
            if a.source.priority != b.source.priority { return a.source.priority < b.source.priority }
            if a.scoreDate != b.scoreDate { return (a.scoreDate ?? "") > (b.scoreDate ?? "") }
            return (a.statementID ?? "") < (b.statementID ?? "")
        }.first
    }
    private static func parse(_ claim: [String: Any], entityID: String, platform: String) -> CriticRating? {
        guard claim["rank"] as? String != "deprecated",
              let raw = (claim["mainsnak"] as? [String: Any]).flatMap(value) as? String,
              let statement = claim["id"] as? String, statement.hasPrefix(entityID + "$"),
              let quals = claim["qualifiers"] as? [String: [[String: Any]]] else { return nil }
        let issuerSnaks = quals["P447"] ?? []
        let issuers = issuerSnaks.compactMap(item)
        guard issuerSnaks.count == 1, issuers.count == 1 else { return nil }
        let source: CriticRating.Source
        let metric: String
        switch issuers[0] {
        case "Q21039459": source = .openCritic; metric = "Q114712322"
        case "Q150248": source = .metacritic; metric = "Q106515043"
        case "Q131917281": source = .criticDB; metric = "Q132178503"
        default: return nil
        }
        let methods = (quals["P459"] ?? []).compactMap(item)
        guard methods.count == (quals["P459"] ?? []).count else { return nil }
        guard methods == [metric] || (methods.isEmpty && source == .metacritic) else { return nil }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let score = Double(parts[0]), Double(parts[1]) == 100,
              score.isFinite, (0...100).contains(score) else { return nil }
        let platforms = (quals["P400"] ?? []).compactMap(item)
        guard platforms.count == (quals["P400"] ?? []).count else { return nil }
        guard platforms.isEmpty || platforms.contains(platform) else { return nil }
        let refs = (claim["references"] as? [[String: Any]] ?? []).compactMap { $0["snaks"] as? [String: [[String: Any]]] }
        let urls = refs.flatMap { $0["P854"] ?? [] }.compactMap { value($0) as? String }.compactMap(URL.init(string:))
            .filter { $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil }
        let items = refs.flatMap { $0["P248"] ?? [] }.compactMap(item)
        guard !urls.isEmpty || !items.isEmpty else { return nil }
        let date = (quals["P585"] ?? []).compactMap { value($0) as? [String: Any] }.compactMap { $0["time"] as? String }.sorted().last
        return CriticRating(score: score, source: source, entityID: entityID, statementID: statement,
                            referenceURLs: urls, referenceItems: items, scoreDate: date, platforms: platforms)
    }
}
