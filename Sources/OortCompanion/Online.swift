import Foundation
@preconcurrency import NXLibraryCore

/// What public services said about one game, kept on this computer.
struct OnlineRecord: Codable, Equatable {
    var found = false
    /// The player chose it, or chose none: never asked again by itself.
    var picked: Bool?
    var source: String?
    var title: String?
    var appID: UInt32?
    /// Its Wikidata item, when it was found there.
    var item: String?
    var about: String?
    var page: String?
    var year: String?
    var genres: [String]?
    var developers: [String]?
    var publishers: [String]?
    var query = ""
    var language = ""
    var fetchedAt = Date.distantPast

    /// What was found is good for a month; what was not is asked again after a week.
    func isFresh(_ now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age < (found ? 30 : 7) * 86_400
    }
}

/// One lookup, a question at a time: this says which address to read, the host reads it (Rust), and the answer comes
/// back here. Only the Steam store and Wikipedia's services are ever named, without any key or account. What goes out
/// is the game's name, or its Steam number, and the language of the texts.
struct OnlineLookup {
    enum Want: Equatable { case info, choices }
    enum Step: Equatable {
        /// A text to read, or a picture to keep at `save` (without its extension).
        case get(url: String, save: String?, limit: Int)
        case done
    }
    private enum Stage: Equatable {
        case search, details, cover, smallCover, hero, smallHero, logo, wikidataSteam, wikidata, entity, article, genres, finished
    }

    let name: String
    let folder: String
    let language: AppLanguage
    let want: Want
    private var stage: Stage = .search
    private var appID: UInt32?
    private var byID = false
    private var ids: [String] = []
    private var article: (code: String, title: String)?
    private var genreIDs: [String] = []
    private(set) var record = OnlineRecord()
    private(set) var choices: [(title: String, appID: UInt32?, item: String?)] = []

    static let textLimit = 4 << 20, pictureLimit = 12 << 20

    init(name: String, steam: UInt32?, item: String? = nil, folder: String, language: AppLanguage, want: Want = .info) {
        (self.name, self.folder, self.language, self.want) = (Self.plain(name), folder, language, want)
        (appID, byID) = (steam, steam != nil)
        record.query = self.name
        record.language = language.rawValue
        if let item { (ids, stage) = ([item], .entity) } else if steam != nil { stage = .details }
    }

    /// A file's marks are not part of a game's name: "Sunken City (USA) [v1.1]" is "Sunken City".
    static func plain(_ name: String) -> String {
        let text = name.replacingOccurrences(of: "[(\\[{][^)\\]}]*[)\\]}]", with: " ", options: .regularExpression)
        return String(SteamStoreArt.plain(text.replacingOccurrences(of: "_", with: " ")).prefix(120))
    }

    /// The addresses the host may read; it checks them again itself.
    static func allowed(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme == "https", url.user == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "store.steampowered.com" || host == "www.wikidata.org" || SteamMetadata.safeImage(url) != nil
            || WikipediaDescriptions.allowedHosts.contains(host)
    }

    func step() -> Step {
        func text(_ url: URL?) -> Step { url.map { .get(url: $0.absoluteString, save: nil, limit: Self.textLimit) } ?? .done }
        func picture(_ file: String, _ name: String) -> Step {
            guard let appID else { return .done }
            return .get(url: SteamStoreArt.url(Int(appID), file).absoluteString, save: Paths.join(folder, name), limit: Self.pictureLimit)
        }
        switch stage {
        case .search: return text(SteamStoreArt.searchURL(for: name))
        case .details:
            guard let appID else { return .done }
            return text(URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=\(SteamMetadata.language(language))"))
        case .cover: return picture("library_600x900_2x.jpg", "cover")
        case .smallCover: return picture("library_600x900.jpg", "cover")
        case .hero: return picture("library_hero_2x.jpg", "hero")
        case .smallHero: return picture("library_hero.jpg", "hero")
        case .logo: return picture("logo.png", "logo")
        case .wikidataSteam: return text(appID.flatMap { WikidataRatings.steamSearchURL(appID: $0) })
        case .wikidata: return text(WikidataRatings.searchURL(name: name))
        case .entity: return text(WikidataRatings.entitiesURL(ids: ids, props: "claims|sitelinks|labels"))
        case .article:
            guard let article else { return .done }
            return text(WikipediaDescriptions.introURL(edition: article.code, title: article.title, variant: WikipediaDescriptions.edition(for: language)?.variant))
        case .genres: return text(WikidataRatings.entitiesURL(ids: genreIDs, props: "labels"))
        case .finished: return .done
        }
    }

    /// The answer to the last step. `status` is 0 when there was none. Throws when the lookup cannot go on: nothing is
    /// kept then, and it is tried again later.
    mutating func answer(status: Int, text: String?, saved: Bool) throws {
        switch stage {
        // A picture that is not there, or is none, is left out.
        case .cover: return stage = saved ? .hero : .smallCover
        case .smallCover: return stage = .hero
        case .hero: return stage = saved ? .logo : .smallHero
        case .smallHero: return stage = .logo
        case .logo: return stage = (record.about ?? "").isEmpty ? .wikidataSteam : .finished
        default: break
        }
        guard status == 200, let text else {
            // The store has no page for some games; a game found by its name there always has one.
            throw Manifest.Failure(code: status == 429 || status == 403 ? "online-slow" : "online")
        }
        let data = Data(text.utf8)
        switch stage {
        case .search:
            let items = Self.items(data)
            choices += items.prefix(8).map { ($0.name, UInt32(exactly: $0.id), nil) }
            if want == .choices { stage = .wikidata; return }
            if let id = SteamStoreArt.appID(in: data, matching: [name]).flatMap(UInt32.init(exactly:)) { (appID, stage) = (id, .details) } else { stage = .wikidata }
        case .details:
            guard let appID else { throw Manifest.Failure(code: "online") }
            guard let details = try? SteamMetadata.decode(data, appID: appID, language: SteamMetadata.language(language)) else {
                // Gone from the store: what Wikipedia knows of it, else nothing.
                stage = byID ? .wikidataSteam : .wikidata
                self.appID = byID ? appID : nil
                return
            }
            record.found = true
            record.source = "Steam"
            record.appID = appID
            record.title = Self.title(data, appID)
            record.about = details.description.nonEmpty
            record.page = "https://store.steampowered.com/app/\(appID)"
            record.year = details.releaseDate.flatMap(Self.year)
            record.genres = Array(details.genres.prefix(6))
            record.developers = details.developers
            record.publishers = details.publishers
            stage = .cover
        case .wikidataSteam:
            ids = (try? WikidataRatings.steamIDs(in: data)) ?? []
            stage = ids.isEmpty ? (record.found ? .finished : .wikidata) : .entity
        case .wikidata:
            ids = (try? WikidataRatings.ids(in: data, name: name)).map { Array($0.prefix(5)) } ?? []
            if want == .choices {
                choices += ids.isEmpty ? [] : [(name, nil, ids[0])]
                stage = .finished
            } else { stage = ids.isEmpty ? .finished : .entity }
        case .entity:
            let query = CriticRatingQuery(name: name, platform: .mac, steamAppID: byID ? appID : nil)
            guard let (id, entity) = try? WikidataRatings.entity(in: data, ids: ids, query: query, requireSteamID: false) else { stage = .finished; return }
            take(id, entity)
        case .article:
            if let article, let said = try? WikipediaDescriptions.description(in: data, edition: article.code) {
                record.about = said.text
                record.page = said.pageURL.absoluteString
                record.source = record.source == nil ? "Wikipedia" : record.source == "Steam" ? "Steam, Wikipedia" : record.source
            }
            stage = genreIDs.isEmpty ? .finished : .genres
        case .genres:
            let entities = (try? WikidataRatings.object(data))?["entities"] as? [String: [String: Any]] ?? [:]
            let code = WikipediaDescriptions.edition(for: language)?.code ?? "en"
            record.genres = genreIDs.compactMap { id in
                let labels = entities[id]?["labels"] as? [String: [String: Any]]
                return (labels?[code]?["value"] ?? labels?["en"]?["value"]) as? String
            }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            stage = .finished
        default: stage = .finished
        }
    }

    private mutating func take(_ id: String, _ entity: [String: Any]) {
        let claims = entity["claims"] as? [String: [[String: Any]]] ?? [:]
        if !record.found {
            record.found = true
            record.source = "Wikipedia"
            record.item = id
            record.title = ((entity["labels"] as? [String: [String: Any]])?["en"]?["value"] as? String) ?? name
            record.page = "https://www.wikidata.org/wiki/\(id)"
            let dates = (claims["P577"] ?? []).compactMap { ($0["mainsnak"] as? [String: Any]).flatMap(WikidataRatings.value) as? [String: Any] }.compactMap { $0["time"] as? String }
            record.year = dates.compactMap(Self.year).min()
            genreIDs = Array(WikidataRatings.claimItems(claims["P136"] ?? []).prefix(5))
        }
        let links = entity["sitelinks"] as? [String: [String: Any]] ?? [:]
        let code = WikipediaDescriptions.edition(for: language)?.code ?? "en"
        for edition in [code, "en"] {
            guard let title = links[edition + "wiki"]?["title"] as? String, !title.isEmpty, title.count <= 300 else { continue }
            article = (edition, title)
            stage = .article
            return
        }
        stage = genreIDs.isEmpty ? .finished : .genres
    }

    private struct Item: Decodable { var type: String?; var name: String; var id: Int }
    private static func items(_ data: Data) -> [Item] {
        struct Wire: Decodable { var items: [Item]? }
        return ((try? JSONDecoder().decode(Wire.self, from: data))?.items ?? []).filter { ($0.type ?? "app") == "app" }
    }

    private static func title(_ data: Data, _ id: UInt32) -> String? {
        let root = try? JSONDecoder().decode(CatalogJSON.self, from: data)
        return root?[String(id)]?["data"]?["name"]?.stringValue
    }

    /// Four digits that are a year, wherever the language puts them.
    static func year(_ text: String) -> String? {
        var digits = ""
        for c in text + " " {
            if c.isASCII, c.isNumber { digits.append(c); continue }
            if digits.count == 4, let n = Int(digits), (1950...2100).contains(n) { return digits }
            digits = ""
        }
        return nil
    }
}
