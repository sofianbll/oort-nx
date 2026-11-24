import Foundation
import NXLibraryCore

public enum NintendoMetadataOrigin: String, Codable {
    case europe = "Nintendo Europe"
    case titleDB = "Title DB"
    case europeAndTitleDB = "Nintendo Europe + Title DB"
    case legacy = "Nintendo store"
    case player = "Your choice"
}

public struct NintendoStoreMetadata: Codable, Equatable {
    public var titleId: String
    public var name: String
    public var description: String
    public var developers: [String]
    public var publishers: [String]
    public var genres: [String]
    public var releaseDate: String?
    public var storeURL: URL?
    public var imageURL: URL?
    public var headerImageURL: URL?
    public var logoURL: URL?
    public var nsuid: String?
    public var fetchedAt: Date
    public var screenshotURLs: [URL] = []
    /// Fallback gallery credit ("LaunchBox"); its own cache stores the URLs.
    public var screenshotSource: String?
    public var descriptionLanguage = "en"
    public var localeKey: String? = nil
    /// The last successful response for the requested description language, including an empty translation.
    public var descriptionCheckedAt: Date?
    public var excerpt: String?
    public var descriptionIsExcerpt: Bool?
    public var squareImageURL: URL?
    public var systems: [String]?
    public var playersFrom: Int?
    public var playersTo: Int?
    public var ageRating: String?
    public var storeLanguage: String?
    public var origins: [String: NintendoMetadataOrigin]?
    var catalogCheckedAt: Date?

    public func origin(for field: MetadataField) -> NintendoMetadataOrigin {
        origins?[field.rawValue] ?? .legacy
    }

    /// Saved for the app language of `locale` (any region), not shown from another language's cache.
    public func isInLanguage(_ locale: AppLocale) -> Bool {
        (localeKey ?? "en_US").hasPrefix(locale.language.rawValue + "_")
    }

    /// Whether the store's answer for `locale`'s language is final: found, confirmed missing (Nlib 404, the
    /// daily check), or English. False while that language is still on its way or after an outage.
    public func languageResolved(for locale: AppLocale) -> Bool {
        guard isInLanguage(locale) else { return false }
        return locale.metadataLanguage == "en" || descriptionLanguage == locale.metadataLanguage
            || descriptionCheckedAt != nil
    }

    public init(titleId: String, name: String, description: String, developers: [String],
                publishers: [String], genres: [String], releaseDate: String?, storeURL: URL?,
                imageURL: URL?, headerImageURL: URL?, logoURL: URL? = nil,
                nsuid: String?, fetchedAt: Date, screenshotURLs: [URL] = []) {
        self.titleId = titleId
        self.name = name
        self.description = description
        self.developers = developers
        self.publishers = publishers
        self.genres = genres
        self.releaseDate = releaseDate
        self.storeURL = storeURL
        self.imageURL = imageURL
        self.headerImageURL = headerImageURL
        self.logoURL = logoURL
        self.nsuid = nsuid
        self.fetchedAt = fetchedAt
        self.screenshotURLs = screenshotURLs
    }

    private enum CodingKeys: String, CodingKey {
        case titleId, name, description, developers, publishers, genres, releaseDate
        case descriptionLanguage, localeKey, descriptionCheckedAt
        case storeURL, imageURL, headerImageURL, logoURL, nsuid, fetchedAt, screenshotURLs
        case excerpt, descriptionIsExcerpt, squareImageURL, systems, playersFrom, playersTo, ageRating, storeLanguage
        case origins, catalogCheckedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        descriptionLanguage = try c.decodeIfPresent(String.self, forKey: .descriptionLanguage) ?? "en"
        localeKey = try c.decodeIfPresent(String.self, forKey: .localeKey)
        descriptionCheckedAt = try c.decodeIfPresent(Date.self, forKey: .descriptionCheckedAt)
        titleId = try c.decode(String.self, forKey: .titleId)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        developers = try c.decode([String].self, forKey: .developers)
        publishers = try c.decode([String].self, forKey: .publishers)
        genres = try c.decode([String].self, forKey: .genres)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        storeURL = try c.decodeIfPresent(URL.self, forKey: .storeURL)
        imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        headerImageURL = try c.decodeIfPresent(URL.self, forKey: .headerImageURL)
        logoURL = try c.decodeIfPresent(URL.self, forKey: .logoURL)
        nsuid = try c.decodeIfPresent(String.self, forKey: .nsuid)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        screenshotURLs = try c.decodeIfPresent([URL].self, forKey: .screenshotURLs) ?? []
        excerpt = try c.decodeIfPresent(String.self, forKey: .excerpt)
        descriptionIsExcerpt = try c.decodeIfPresent(Bool.self, forKey: .descriptionIsExcerpt)
        squareImageURL = try c.decodeIfPresent(URL.self, forKey: .squareImageURL)
        systems = try c.decodeIfPresent([String].self, forKey: .systems)
        playersFrom = try c.decodeIfPresent(Int.self, forKey: .playersFrom)
        playersTo = try c.decodeIfPresent(Int.self, forKey: .playersTo)
        ageRating = try c.decodeIfPresent(String.self, forKey: .ageRating)
        storeLanguage = try c.decodeIfPresent(String.self, forKey: .storeLanguage)
        origins = try c.decodeIfPresent([String: NintendoMetadataOrigin].self, forKey: .origins)
        catalogCheckedAt = try c.decodeIfPresent(Date.self, forKey: .catalogCheckedAt)
    }

    public var releaseYear: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        let year = String(releaseDate.prefix(4))
        return Int(year) == nil ? nil : year
    }
}

public enum NintendoStoreError: Error, Equatable, LocalizedError {
    case notFound
    case invalidURL
    case http(Int)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .notFound: return L10n.text("No Nintendo Store entry was found for this game.")
        case .invalidURL: return L10n.text("The Nintendo Store URL is invalid.")
        case .http(let status): return L10n.format("Nintendo Store returned status %@.", [String(describing: status)])
        case .decoding: return L10n.text("Nintendo Store returned a response this app could not read.")
        }
    }
}

public protocol NintendoStoreHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionNintendoStoreClient: NintendoStoreHTTPClient {
    private static let publicSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private let session: URLSession

    public init() {
        session = Self.publicSession
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await BoundedDownload.data(for: request, session: session, limit: 2 * 1024 * 1024)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Resolves Switch metadata by title ID and keeps the last usable per-language answer on disk.
public final class NintendoStoreMetadataService: @unchecked Sendable {
    private static let ttl: TimeInterval = 7 * 24 * 60 * 60
    private static let missTTL: TimeInterval = 24 * 3600
    private static let cadence = Cadence()

    private let client: NintendoStoreHTTPClient
    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let refreshLock = NSLock()
    private var descriptionRetryAfter: [String: Date] = [:]

    private actor Cadence {
        var next = ContinuousClock.now

        func wait() async throws {
            let start = max(.now, next)
            next = start.advanced(by: .milliseconds(250))
            try await Task.sleep(until: start, clock: .continuous)
        }
    }

    public init(
        client: NintendoStoreHTTPClient = URLSessionNintendoStoreClient(),
        cacheDirectory: URL = AppData.supportRoot.appendingPathComponent("metadata"),
        fileManager: FileManager = .default
    ) {
        self.client = client
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
    }

    public func cached(for titleId: String, locale: AppLocale = AppLocale(language: .english, region: "US")) -> NintendoStoreMetadata? {
        if let exact = read(cacheURL(for: titleId, locale: locale), titleId: titleId) { return exact }
        // The provider localizes descriptions by language, not by formatting region.
        var alternatives: [NintendoStoreMetadata] = []
        if locale.language == .english,
           let legacy = read(cacheURL(for: titleId, locale: AppLocale(language: .english, region: "US")), titleId: titleId) {
            alternatives.append(legacy)
        }
        let root = cacheDirectory.appendingPathComponent("localized")
        for folder in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where folder.lastPathComponent.hasPrefix(locale.language.rawValue + "_") {
            if let entry = read(folder.appendingPathComponent(Self.safeFileName(titleId) + ".json"), titleId: titleId) { alternatives.append(entry) }
        }
        return alternatives.max { $0.fetchedAt < $1.fetchedAt }
    }

    /// What a page shows before the network answers: the entry for `locale`, else the newest one cached in any
    /// language, so a new app language shows the last text read (with its language note) instead of an empty page.
    /// That entry is never fresh for `locale` (`isFresh`), so the text in the new language is still asked for.
    public func cachedForDisplay(for titleId: String, locale: AppLocale) -> NintendoStoreMetadata? {
        if let entry = cached(for: titleId, locale: locale) { return entry }
        let name = Self.safeFileName(titleId) + ".json"
        let root = cacheDirectory.appendingPathComponent("localized")
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let entries = ([cacheDirectory] + folders).compactMap { read($0.appendingPathComponent(name), titleId: titleId) }
        return entries.max { $0.fetchedAt < $1.fetchedAt }
    }

    private func read(_ url: URL, titleId: String) -> NintendoStoreMetadata? {
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(NintendoStoreMetadata.self, from: data),
              metadata.titleId == titleId else { return nil }
        return metadata
    }

    /// A legacy entry remains displayable but is refreshed on use. A transient failure never extends its disk TTL.
    public func isFresh(_ metadata: NintendoStoreMetadata, now: Date = Date(), locale: AppLocale = AppLocale(language: .english, region: "US")) -> Bool {
        guard isInLanguage(metadata, locale: locale) else { return false }
        let retryKey = metadata.titleId + "/" + locale.metadataLanguage
        if refreshLock.withLock({ descriptionRetryAfter[retryKey].map { now < $0 } == true }) { return true }
        let ttl = metadata.storeLanguage == nil || metadata.descriptionLanguage != locale.metadataLanguage
            ? Self.missTTL : Self.ttl
        return metadata.catalogCheckedAt.map { now.timeIntervalSince($0) < ttl } == true
            && metadata.descriptionCheckedAt.map { now.timeIntervalSince($0) < ttl } == true
    }

    /// Whether `metadata` was saved for the app language of `locale` (any region), not shown from another language.
    public func isInLanguage(_ metadata: NintendoStoreMetadata, locale: AppLocale) -> Bool {
        metadata.isInLanguage(locale)
    }

    /// Whether the app language's description was settled for `metadata`: found, confirmed missing (Nlib 404, the
    /// daily check), or English. False after an outage, so a background pass asks again later.
    public func languageResolved(_ metadata: NintendoStoreMetadata, locale: AppLocale) -> Bool {
        metadata.languageResolved(for: locale)
    }

    /// Forgets the one-minute waits after network failures, when the connection returns.
    public func forgetDescriptionRetries() {
        refreshLock.lock()
        descriptionRetryAfter.removeAll()
        refreshLock.unlock()
    }

    static func validTitleID(_ id: String) -> Bool {
        id.utf8.count == 16 && (id.hasPrefix("0100") || id.hasPrefix("0400"))
            && id.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    public func metadata(for game: PortedGame, locale: AppLocale = AppLocale(language: .english, region: "US")) async throws -> NintendoStoreMetadata {
        let key = game.titleId ?? game.uniqueKey
        let previous = cached(for: key, locale: locale)
        if let previous, isFresh(previous, locale: locale) { return previous }
        let saved = previous ?? cachedForDisplay(for: key, locale: locale)
        guard Self.validTitleID(key) else {
            if let saved { return saved }
            throw NintendoStoreError.notFound
        }

        let language = locale.metadataLanguage
        let european = NintendoEuropeCatalog.locale(for: language)
        let preferred = european ?? "en"
        async let catalog = fetchCatalog(titleID: key, language: preferred)
        async let nlib = fetchTitleDBLookup(titleId: key, language: language)
        let (catalogResult, localNlib) = await (catalog, nlib)
        try Task.checkCancellation()
        let local = catalogResult.item
        let englishResult: Lookup<NintendoEuropeCatalog.Document> =
            preferred != "en" && catalogResult.complete && (
                local == nil || local?.publisher == nil || local?.releaseDate == nil ||
                local?.pretty_game_categories_txt?.isEmpty != false || local?.image_url_sq_s == nil ||
                (local?.image_url_h16x9_s == nil && local?.image_url_h2x1_s == nil) ||
                local?.product_catalog_description_s == nil || local?.players_to == nil || local?.pretty_agerating_s == nil ||
                locale.language == .portugueseBrazil
            ) ? await fetchCatalog(titleID: key, language: "en") : .missing
        let english = preferred == "en" ? local : englishResult.item
        let localizedExcerpt = language != "pt" && european != nil
            ? Self.sourceText(local?.product_catalog_description_s) : nil
        let localLong = Self.localizedLongText(localNlib.item?.description, language: locale.language)
        let savedLong = saved.flatMap { entry in
            entry.descriptionLanguage == language && entry.descriptionIsExcerpt != true
                ? Self.localizedLongText(entry.description, language: locale.language) : nil
        }
        let shouldGetEnglishNlib = language != "en" && localLong == nil && savedLong == nil && localizedExcerpt == nil
        let englishNlib = shouldGetEnglishNlib ? await fetchTitleDBLookup(titleId: key, language: "en") : .missing
        try Task.checkCancellation()
        let nlibItem = localNlib.item ?? englishNlib.item
        let complete = catalogResult.complete && englishResult.complete && localNlib.complete && englishNlib.complete
        if !complete {
            refreshLock.withLock { descriptionRetryAfter[key + "/" + language] = Date().addingTimeInterval(60) }
            // Do not rewrite the saved language with another language or stamp a partial update as settled.
            if let previous, !catalogResult.complete && !localNlib.complete { return previous }
            if local == nil, english == nil, nlibItem == nil, let saved { return saved }
        }

        let docs = [local, english].compactMap { $0 }
        let date = Date()
        var metadata = NintendoStoreMetadata(
            titleId: key, name: game.name, description: "", developers: [], publishers: [], genres: [],
            releaseDate: nil, storeURL: local?.productURL ?? english?.productURL ?? saved?.storeURL.flatMap {
                $0.pathComponents.count > 1 ? $0 : nil
            },
            imageURL: docs.lazy.compactMap { NintendoEuropeCatalog.Document.image($0.image_url) }.first ?? saved?.imageURL,
            headerImageURL: docs.lazy.compactMap {
                NintendoEuropeCatalog.Document.image($0.image_url_h16x9_s)
                    ?? NintendoEuropeCatalog.Document.image($0.image_url_h2x1_s)
            }.first ?? nlibItem?.banner.flatMap(Self.nlibImage) ?? saved?.headerImageURL,
            logoURL: saved?.logoURL, nsuid: local?.baseProductID ?? english?.baseProductID ?? saved?.nsuid,
            fetchedAt: date, screenshotURLs: nlibItem?.screenshotURLs.nonEmpty ?? saved?.screenshotURLs ?? [])
        metadata.localeKey = locale.cacheKey
        metadata.storeLanguage = local != nil ? preferred : english != nil ? "en" : saved?.storeLanguage
        metadata.excerpt = localizedExcerpt
        metadata.squareImageURL = docs.lazy.compactMap { NintendoEuropeCatalog.Document.image($0.image_url_sq_s) }.first
            ?? nlibItem?.icon.flatMap(Self.nlibImage) ?? saved?.squareImageURL
        metadata.systems = docs.lazy.compactMap { $0.system_names_txt?.nonEmpty }.first ?? saved?.systems
        metadata.playersFrom = docs.lazy.compactMap(\.players_from).first ?? saved?.playersFrom
        metadata.playersTo = docs.lazy.compactMap(\.players_to).first ?? saved?.playersTo
        metadata.ageRating = docs.lazy.compactMap { Self.sourceText($0.pretty_agerating_s) }.first ?? saved?.ageRating
        metadata.name = docs.lazy.compactMap { Self.sourceText($0.title) }.first
            ?? Self.sourceText(nlibItem?.name) ?? saved?.name ?? game.name
        metadata.origins = [:]

        // Optionals preserve provenance through cache migration and when only one provider has the field.
        func select<T>(_ field: MetadataField, _ europe: T?, _ nlib: T?, _ old: T?) -> T? {
            if let europe { metadata.origins?[field.rawValue] = .europe; return europe }
            if let nlib { metadata.origins?[field.rawValue] = .titleDB; return nlib }
            if let old { metadata.origins?[field.rawValue] = saved?.origin(for: field); return old }
            return nil
        }
        let catalogPublisher = docs.lazy.compactMap { Self.sourceText($0.publisher) }.first.map { [$0] }
        metadata.publishers = select(.publisher, catalogPublisher, Self.sourceText(nlibItem?.publisher).map { [$0] },
                                     saved?.publishers.nonEmpty) ?? []
        metadata.developers = select(.developer, nil, Self.sourceText(nlibItem?.developer).map { [$0] },
                                     saved?.developers.nonEmpty) ?? []
        let catalogGenres = docs.lazy.compactMap { $0.pretty_game_categories_txt?.nonEmpty }.first
        metadata.genres = select(.genres, catalogGenres, nlibItem?.genres.nonEmpty, saved?.genres.nonEmpty) ?? []
        if catalogGenres != nil, let extra = nlibItem?.genres.nonEmpty {
            let current = Set(metadata.genres.map { GameGenre.title($0, context: locale).lowercased() })
            // The catalog omits some tags that Title DB offers, e.g. multiplayer.
            let additions = extra.filter { !current.contains(GameGenre.title($0, context: locale).lowercased()) }
            if !additions.isEmpty {
                metadata.genres += additions
                metadata.origins?[MetadataField.genres.rawValue] = .europeAndTitleDB
            }
        }
        metadata.releaseDate = select(.releaseDate, docs.lazy.compactMap(\.releaseDate).first,
                                      nlibItem?.releaseDateString, saved?.releaseDate)

        let englishLong = Self.localizedLongText(englishNlib.item?.description, language: .english)
        let englishExcerpt = Self.sourceText(english?.product_catalog_description_s)
        let savedEnglish = saved.flatMap { $0.descriptionLanguage == "en" ? Self.sourceText($0.description) : nil }
        let descriptions: [(String?, String, NintendoMetadataOrigin, Bool)] = [
            (localLong, language, .titleDB, false),
            (savedLong, language, saved?.origin(for: .description) ?? .legacy, false),
            (localizedExcerpt, language, .europe, true),
            (englishLong, "en", .titleDB, false),
            (savedEnglish, "en", saved?.origin(for: .description) ?? .legacy, saved?.descriptionIsExcerpt == true),
            (englishExcerpt, "en", .europe, true)
        ]
        if let (text, language, source, short) = descriptions.first(where: { $0.0 != nil }) {
            metadata.description = text ?? ""
            metadata.descriptionLanguage = language
            metadata.descriptionIsExcerpt = short
            metadata.origins?[MetadataField.description.rawValue] = source
        }
        if complete {
            metadata.descriptionCheckedAt = date
            metadata.catalogCheckedAt = date
        }
        // Cache partial hits only when there is no previous version in this language to protect.
        if complete || previous == nil && (local != nil || english != nil || nlibItem != nil) {
            try? cache(metadata, for: key, locale: locale)
        }
        return metadata
    }

    private enum Lookup<Item> {
        case found(Item), missing, unavailable
        var item: Item? { if case .found(let item) = self { return item }; return nil }
        var complete: Bool { if case .unavailable = self { return false }; return true }
    }

    private func fetchCatalog(titleID: String, language: String) async -> Lookup<NintendoEuropeCatalog.Document> {
        guard let request = NintendoEuropeCatalog.request(titleID: titleID, language: language) else { return .missing }
        do {
            let (data, http) = try await publicData(for: request)
            guard http.statusCode == 200 else { return .unavailable }
            guard let doc = try NintendoEuropeCatalog.document(in: data, titleID: titleID) else { return .missing }
            return .found(doc)
        } catch { return .unavailable }
    }

    private func publicData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Self.cadence.wait()
        do {
            let reply = try await client.data(for: request)
            guard (500...599).contains(reply.1.statusCode) else { return reply }
        } catch let error as URLError where error.code == .timedOut {
            // One spaced retry for a timeout or 5xx; no retry on 429 or offline.
        }
        try await Task.sleep(for: .milliseconds(500))
        try await Self.cadence.wait()
        return try await client.data(for: request)
    }

    static func sourceText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = plainText(raw)
        return text.isEmpty ? nil : text
    }

    static func localizedLongText(_ raw: String?, language: AppLanguage) -> String? {
        guard let text = sourceText(raw) else { return nil }
        // Nlib can prefix a dated digital-purchase notice. Cut that prefix, not the gameplay paragraphs after it.
        let promo = #"pre.order|early purchase|achat anticipé|frühkauf|regalo misterioso|bonus per l.acquisto|dono segreto"#
        let paragraphs = text.components(separatedBy: "\n\n")
        let kept = paragraphs.drop(while: {
            $0.range(of: promo, options: [.regularExpression, .caseInsensitive]) != nil
                || $0.range(of: #"cadeaux mystère|geheimgeschenk|recibirás un código"#,
                            options: [.regularExpression, .caseInsensitive]) != nil
        }).joined(separator: "\n\n")
        guard !kept.isEmpty, !WikipediaDescriptions.wanted(description: kept, descriptionLanguage: nil, language: language) else { return nil }
        return kept
    }

    private static func nlibImage(_ raw: String) -> URL? {
        let text = raw.hasPrefix("http://api.nlib.cc/") ? "https://" + raw.dropFirst(7) : raw
        guard let url = URL(string: text), url.scheme == "https", url.host == "api.nlib.cc",
              url.port == nil, url.user == nil else { return nil }
        return url
    }

    private struct TitleDBItem: Decodable {
        struct Screens: Decodable {
            let count: Int?
            let screenshots: [String]?
        }
        let id: String?
        let name: String?
        let publisher: String?
        let description: String?
        let banner: String?
        let icon: String?
        let screens: Screens?
        let releaseDate: String?
        let developer: String?
        let category: [String]?

        private enum CodingKeys: String, CodingKey {
            case id, name, publisher, description, banner, icon, screens, releaseDate, developer, category
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decodeIfPresent(String.self, forKey: .id)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            publisher = try? c.decodeIfPresent(String.self, forKey: .publisher)
            description = try? c.decodeIfPresent(String.self, forKey: .description)
            banner = try? c.decodeIfPresent(String.self, forKey: .banner)
            icon = try? c.decodeIfPresent(String.self, forKey: .icon)
            screens = try? c.decodeIfPresent(Screens.self, forKey: .screens)
            developer = try? c.decodeIfPresent(String.self, forKey: .developer)
            category = try? c.decodeIfPresent([String].self, forKey: .category)
            // titledb sends either "2017-03-03" or an integer like 20170303.
            if let text = try? c.decodeIfPresent(String.self, forKey: .releaseDate) {
                releaseDate = text
            } else if let number = try? c.decodeIfPresent(Int.self, forKey: .releaseDate) {
                releaseDate = String(number)
            } else {
                releaseDate = nil
            }
        }

        var screenshotURLs: [URL] {
            (screens?.screenshots ?? []).compactMap(NintendoStoreMetadataService.nlibImage)
        }

        var genres: [String] { (category ?? []).filter { $0 != "Other" } }

        /// "yyyy-MM-dd" as stored; compact 8-digit integers are reformatted.
        var releaseDateString: String? {
            guard let raw = releaseDate?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
                return nil
            }
            let parse = DateFormatter()
            parse.locale = Locale(identifier: "en_US_POSIX")
            parse.timeZone = TimeZone(identifier: "UTC")
            parse.dateFormat = raw.count == 8 && Int(raw) != nil ? "yyyyMMdd" : "yyyy-MM-dd"
            guard let date = parse.date(from: String(raw.prefix(raw.count == 8 ? 8 : 10))) else {
                return nil
            }
            parse.dateFormat = "yyyy-MM-dd"
            return parse.string(from: date)
        }
    }

    private func fetchTitleDBLookup(titleId: String, language: String) async -> Lookup<TitleDBItem> {
        guard Self.validTitleID(titleId),
              let url = URL(string: "https://api.nlib.cc/nx/\(titleId.uppercased())?fields=id,name,publisher,description,banner,icon,screens,releaseDate,developer,category&lang=\(language)") else {
            return .missing
        }
        do {
            let (data, response) = try await publicData(for: NintendoEuropeCatalog.publicRequest(url))
            if response.statusCode == 404 { return .missing }
            guard (200..<300).contains(response.statusCode) else { return .unavailable }
            let item = try JSONDecoder().decode(TitleDBItem.self, from: data)
            guard item.id?.uppercased() == titleId.uppercased() else { return .unavailable }
            return .found(item)
        } catch {
            return .unavailable
        }
    }

    public func cacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard values?.isDirectory != true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    public func clearCache() {
        clearCache { try fileManager.trashItem(at: $0, resultingItemURL: nil) }
    }
    internal func clearCache(discard: (URL) throws -> Void) {
        try? discard(cacheDirectory)
    }

    private func cacheURL(for titleId: String, locale: AppLocale) -> URL {
        let folder = locale.cacheKey == "en_US" ? cacheDirectory
            : cacheDirectory.appendingPathComponent("localized/\(locale.cacheKey)")
        return folder.appendingPathComponent(Self.safeFileName(titleId) + ".json")
    }

    private func cache(_ metadata: NintendoStoreMetadata, for titleId: String, locale: AppLocale) throws {
        let url = cacheURL(for: titleId, locale: locale)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    private static func safeFileName(_ value: String) -> String {
        value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
    }

    static func plainText(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
            "&lt;": "<", "&gt;": ">"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
