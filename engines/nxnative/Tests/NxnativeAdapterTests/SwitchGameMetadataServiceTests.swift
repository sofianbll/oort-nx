import XCTest
@testable import ArcanePorting
@testable import NXLibraryCore

final class SwitchGameMetadataServiceTests: XCTestCase {
    private static let smash = "01006A800016E000"
    private static let animal = "01006F8002326000"
    private static let za = "0100F43008C44000"
    private static let pokopia = "0400A3A01EE4C000"
    private let en = AppLocale(language: .english, region: "US")
    private let fr = AppLocale(language: .french, region: "FR")
    private let pt = AppLocale(language: .portugueseBrazil, region: "BR")
    private let zh = AppLocale(language: .chineseSimplified, region: "CN")

    private final class Client: NintendoStoreHTTPClient {
        let handler: (URLRequest) throws -> (Int, Data)
        private let lock = NSLock()
        private var seen: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { seen } }

        init(_ handler: @escaping (URLRequest) throws -> (Int, Data)) { self.handler = handler }

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.withLock { seen.append(request) }
            let (status, data) = try handler(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func cache() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func game(_ id: String = SwitchGameMetadataServiceTests.smash) -> PortedGame {
        PortedGame(name: "My local game", url: URL(fileURLWithPath: "/no-game/Fixture.app"),
                   platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: id)
    }

    private static func doc(_ id: String, fs: Int = 17, type: String = "GAME", system: String? = nil,
                            region: String = "en-gb", product: String = "70010000000017") -> [String: Any] {
        ["application_id_s": id.lowercased(), "fs_id": String(fs), "type": type,
         "title": "Fixture \(fs)", "system_names_txt": [system ?? (id.hasPrefix("0400") ? "Nintendo Switch 2" : "Nintendo Switch")],
         "nsuid_txt": [product], "url": "/\(region)/Games/Fixture-\(fs).html",
         "publisher": "European Publisher", "pretty_game_categories_txt": ["Action"],
         "dates_released_dts": ["2027-01-02T00:00:00Z", "2025-03-05T00:00:00Z"],
         "product_catalog_description_s": "Short catalogue description.",
         "image_url_sq_s": "https://www.nintendo.com/eu/media/images/square_image500w.jpg",
         "image_url_h2x1_s": "https://www.nintendo.com/eu/media/images/hero_image500w.jpg",
         "players_to": 4, "players_from": 1, "pretty_agerating_s": "PEGI 7"]
    }

    private static func catalog(_ docs: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["response": ["numFound": docs.count, "docs": docs]])
    }

    private static func nlib(_ id: String, _ description: String, extra: [String: Any] = [:]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["id": id, "name": "Title DB name", "description": description]
            .merging(extra) { $1 })
    }

    func testExactCatalogRequestIsPublicAndUsesNoNameOrRegion() throws {
        let request = try XCTUnwrap(NintendoEuropeCatalog.request(titleID: Self.smash, language: "fr"))
        let url = try XCTUnwrap(request.url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "searching.nintendo-europe.com")
        XCTAssertEqual(url.path, "/fr/select")
        XCTAssertEqual(items.filter { $0.name == "fq" }.compactMap(\.value), ["application_id_s:01006a800016e000", "type:GAME"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.allHTTPHeaderFields?.count, 1)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(NintendoEuropeCatalog.request(titleID: Self.smash, language: "zh"))
        XCTAssertNil(NintendoEuropeCatalog.request(titleID: "0100A OR type:*", language: "en"))
        XCTAssertNotNil(NintendoEuropeCatalog.request(titleID: Self.smash, language: "nl"))
    }

    func testArcaneKeepsItsFieldsAndEuropeFillsLocalizedGaps() async throws {
        let id = Self.smash
        let root = cache()
        let legacyClient = Client { _ in XCTFail("A fresh Arcane answer does not need to search again"); return (500, Data()) }
        let legacy = NintendoStoreMetadataService(client: legacyClient, cacheDirectory: root)
        let cover = URL(string: "https://example.invalid/original-box.png")!
        let hero = URL(string: "https://example.invalid/original-hero.png")!
        let gallery = URL(string: "https://example.invalid/original-gallery.png")!
        var original = NintendoStoreMetadata(titleId: id, name: "Original name", description:
            "Visit an old coastal town, meet its eccentric residents and discover a mystery hidden in the harbour.",
            developers: ["Original studio"], publishers: ["Original publisher"], genres: ["Action", "Indie"],
            releaseDate: "2017-01-02", storeURL: URL(string: "https://www.nintendo.com/us/store/products/fixture/"),
            imageURL: cover, headerImageURL: hero, nsuid: "original", fetchedAt: .now, screenshotURLs: [gallery])
        original.localeKey = fr.cacheKey
        original.descriptionCheckedAt = .now
        let directory = root.appendingPathComponent("localized/\(fr.cacheKey)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(original).write(to: directory.appendingPathComponent(id + ".json"))
        let client = Client { request in
            if request.url?.host == "api.nlib.cc" { return (404, Data()) }
            var doc = Self.doc(id, region: "fr-fr")
            doc["product_catalog_description_s"] = "Explorez une ville côtière et découvrez son secret."
            doc["pretty_game_categories_txt"] = ["Action", "Aventure"]
            return (200, Self.catalog([doc]))
        }
        let service = SwitchGameMetadataService(client: client, cacheDirectory: root.appendingPathComponent("europe"), legacy: legacy)
        let result = try await service.metadata(for: game(), locale: fr)
        XCTAssertEqual(result.developers, original.developers)
        XCTAssertEqual(result.publishers, original.publishers)
        XCTAssertEqual(result.releaseDate, original.releaseDate)
        XCTAssertEqual(result.imageURL, cover)
        XCTAssertEqual(result.headerImageURL, hero)
        XCTAssertEqual(result.screenshotURLs, [gallery])
        XCTAssertEqual(result.genres, ["Action", "Indie", "Aventure"])
        XCTAssertEqual(result.storeURL?.path, "/fr-fr/Games/Fixture-17.html")
        XCTAssertEqual(result.excerpt, "Explorez une ville côtière et découvrez son secret.")
        XCTAssertEqual(result.description, original.description)
        XCTAssertNotNil(result.squareImageURL)
    }

    func testDeterministicBaseProductAcrossRealIDShapes() throws {
        // Synthetic metadata, with the IDs and counts of the public catalogue; no publisher text or assets ship.
        for (id, count, platform) in [(Self.smash, 69, "Nintendo Switch"), (Self.animal, 4, "Nintendo Switch"),
                                      (Self.za, 5, "Nintendo Switch"), (Self.pokopia, 5, "Nintendo Switch 2")] {
            let alternate = platform == "Nintendo Switch" ? "Nintendo Switch 2" : "Nintendo Switch"
            let base = Self.doc(id, fs: 88)
            let offer = Self.doc(id, fs: 1, product: "70070000000001")
            let wrongSystem = Self.doc(id, fs: 2, system: alternate)
            let dlcs = (0..<(count - 3)).map { Self.doc(id, fs: $0 + 100, type: "DLC") }
            let docs = dlcs + [wrongSystem, offer, base]
            for order in [docs, Array(docs.reversed())] {
                let selected = try NintendoEuropeCatalog.document(in: Self.catalog(order), titleID: id)
                XCTAssertEqual(selected?.fs_id, "88")
            }
            XCTAssertNil(try NintendoEuropeCatalog.document(in: Self.catalog(dlcs + [wrongSystem, Self.doc("0100000000000000")]), titleID: id))
        }
    }

    func testLocalizedSourceOrderPromotionRemovalAndPersonalChoice() async throws {
        let directory = cache()
        let id = Self.za
        let client = Client { request in
            let url = request.url!
            if url.host == "searching.nintendo-europe.com" {
                XCTAssertEqual(url.path, "/fr/select")
                var result = Self.doc(id, region: "fr-fr")
                result["product_catalog_description_s"] = "Découvrez une grande aventure dans une ville pleine de vie."
                result["image_url_h16x9_s"] = "https://www.nintendo.com/eu/media/images/preferred_image500w.jpg"
                return (200, Self.catalog([result]))
            }
            XCTAssertTrue(url.absoluteString.contains("lang=fr"))
            return (200, Self.nlib(id, "Un bonus d’achat anticipé pour le premier achat.\n\nVos cadeaux mystère vous attendent.\n\nExplorez une grande ville avec vos amis et partez à la recherche de nouvelles aventures.", extra: [
                "developer": "Studio", "publisher": "Other publisher", "category": ["Other", "Aventure"],
                "screens": ["screenshots": ["http://api.nlib.cc/nx/\(id)/screen/1", "https://malicious.invalid/image"]]
            ]))
        }
        let service = SwitchGameMetadataService(client: client, cacheDirectory: directory)
        let metadata = try await service.metadata(for: game(id), locale: fr)
        XCTAssertEqual(metadata.name, "Fixture 17")
        XCTAssertTrue(metadata.description.hasPrefix("Explorez"))
        XCTAssertTrue(metadata.excerpt?.hasPrefix("Découvrez") == true)
        XCTAssertEqual(metadata.origin(for: .description), .titleDB)
        XCTAssertEqual(metadata.origin(for: .publisher), .europe)
        XCTAssertEqual(metadata.developers, ["Studio"])
        XCTAssertEqual(metadata.publishers, ["European Publisher"])
        XCTAssertEqual(metadata.genres, ["Action", "Aventure"])
        XCTAssertEqual(metadata.releaseDate, "2025-03-05")
        XCTAssertEqual(metadata.storeURL?.path, "/fr-fr/Games/Fixture-17.html")
        XCTAssertEqual(metadata.headerImageURL?.lastPathComponent, "preferred_image500w.jpg")
        XCTAssertNotNil(metadata.squareImageURL)
        XCTAssertEqual(metadata.screenshotURLs.map(\.absoluteString), ["https://api.nlib.cc/nx/\(id)/screen/1"])
        XCTAssertEqual(metadata.systems, ["Nintendo Switch"])
        XCTAssertEqual(metadata.playersTo, 4)
        XCTAssertEqual(metadata.ageRating, "PEGI 7")
        XCTAssertEqual(service.cached(for: id, locale: fr), metadata)
        let picks = MetadataPicks(directory: directory)
        try picks.set("Mon texte", titleID: id, field: .description)
        let own = picks.applied(to: metadata, titleID: id)
        XCTAssertEqual(own.description, "Mon texte")
        XCTAssertEqual(own.origin(for: .description), .player)
        XCTAssertNil(own.excerpt)
        XCTAssertEqual(client.requests.count, 2)
    }

    func testPortugueseKeepsBrazilianTextAndPortugueseProductLink() async throws {
        let id = Self.animal
        let client = Client { request in
            let url = request.url!
            if url.host == "api.nlib.cc" {
                XCTAssertTrue(url.absoluteString.hasSuffix("lang=pt"))
                return (200, Self.nlib(id, "Jogue com seus amigos e descubra uma ilha cheia de oportunidades para você."))
            }
            let region = url.path == "/pt/select" ? "pt-pt" : "en-gb"
            return (200, Self.catalog([Self.doc(id, region: region)]))
        }
        let service = SwitchGameMetadataService(client: client, cacheDirectory: cache())
        let entry = try await service.metadata(for: game(id), locale: pt)
        XCTAssertEqual(entry.descriptionLanguage, "pt")
        XCTAssertTrue(entry.description.contains("você"))
        XCTAssertEqual(entry.origin(for: .description), .titleDB)
        XCTAssertNil(entry.excerpt)
        XCTAssertEqual(entry.storeURL?.path, "/pt-pt/Games/Fixture-17.html")
    }

    func testChineseUsesEnglishWithResolvedLanguageForWikipediaAndCache() async throws {
        let id = Self.pokopia
        let client = Client { request in
            let url = request.url!
            if url.host == "api.nlib.cc" { return (404, Data()) }
            XCTAssertEqual(url.path, "/en/select")
            return (200, Self.catalog([Self.doc(id)]))
        }
        let service = SwitchGameMetadataService(client: client, cacheDirectory: cache())
        let entry = try await service.metadata(for: game(id), locale: zh)
        XCTAssertEqual(entry.descriptionLanguage, "en")
        XCTAssertEqual(entry.descriptionIsExcerpt, true)
        XCTAssertTrue(entry.languageResolved(for: zh))
        XCTAssertTrue(service.isFresh(entry, locale: zh))
        XCTAssertEqual(entry.storeLanguage, "en")
        let again = try await service.metadata(for: game(id), locale: zh)
        XCTAssertEqual(again, entry)
        XCTAssertEqual(client.requests.count, 3)
    }

    func testLanguageSwitchUsesOwnProductAndReadsCacheAcrossRegions() async throws {
        let id = Self.smash
        let client = Client { request in
            let url = request.url!
            if url.host == "api.nlib.cc" { return (404, Data()) }
            let region = url.path == "/fr/select" ? "fr-fr" : "en-gb"
            return (200, Self.catalog([Self.doc(id, region: region)]))
        }
        let service = SwitchGameMetadataService(client: client, cacheDirectory: cache())
        let original = try await service.metadata(for: game(), locale: en)
        XCTAssertEqual(service.cachedForDisplay(for: id, locale: fr), original)
        XCTAssertFalse(service.isFresh(original, locale: fr))
        let local = try await service.metadata(for: game(), locale: fr)
        XCTAssertEqual(local.storeLanguage, "fr")
        XCTAssertEqual(local.descriptionLanguage, "fr")
        XCTAssertEqual(service.cached(for: id, locale: AppLocale(language: .french, region: "CA")), local)
    }

    func testLegacyCacheStaysReadableOfflineAndFailureDoesNotOverwriteIt() async throws {
        let directory = cache()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = Self.smash
        let legacy = """
        {"titleId":"\(id)","name":"Old name","description":"Local offline description",
        "developers":["Old developer"],"publishers":[],"genres":[],"storeURL":"https://www.nintendo.com/us/store/products/fixture-switch/","fetchedAt":0}
        """
        let file = directory.appendingPathComponent(id + ".json")
        try Data(legacy.utf8).write(to: file)
        let client = Client { _ in throw URLError(.notConnectedToInternet) }
        let service = SwitchGameMetadataService(client: client, cacheDirectory: directory)
        let old = try XCTUnwrap(service.cached(for: id))
        XCTAssertFalse(service.isFresh(old, locale: en))
        let result = try await service.metadata(for: game(), locale: en)
        XCTAssertEqual(result, old)
        XCTAssertEqual(result.screenshotURLs, [])
        XCTAssertEqual(result.developers, ["Old developer"])
        XCTAssertEqual(try Data(contentsOf: file), Data(legacy.utf8))
        XCTAssertGreaterThan(service.cacheSize(), 0)
        var discarded: URL?
        service.clearCache { discarded = $0 }
        XCTAssertEqual(discarded, directory)
    }

    func testMissingAndOfflineWithoutCacheLeaveUsableLocalDetails() async throws {
        let offline = Client { _ in throw URLError(.notConnectedToInternet) }
        let directory = cache()
        let service = SwitchGameMetadataService(client: offline, cacheDirectory: directory)
        let entry = try await service.metadata(for: game(), locale: fr)
        XCTAssertEqual(entry.name, "My local game")
        XCTAssertNil(entry.storeURL)
        XCTAssertNil(service.cached(for: Self.smash, locale: fr))
        XCTAssertFalse(entry.languageResolved(for: fr))
        do {
            _ = try await service.metadata(for: game("not-a-title-id"), locale: fr)
            XCTFail("Invalid ID sent to a provider")
        } catch let error as NintendoStoreError { XCTAssertEqual(error, .notFound) }
        XCTAssertEqual(offline.requests.count, 3)
    }

    func testLaunchBoxKeepsADeveloperAndLongTextWithoutReplacingTheLocalizedExcerpt() async throws {
        let directory = cache()
        let id = Self.pokopia
        let overview = "Create a peaceful town and meet new friends as you explore a countryside full of surprises."
        let graph: [Any] = ["Nintendo Switch 2", ["name": 0], "Fixture 17", 10, overview,
                            "Studio", ["name": 5], [6],
                            ["platform": 1, "name": 2, "gameKey": 3, "overview": 4, "gameDevelopers": 7]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: graph), as: UTF8.self)
        let launchBox = DatabaseMetadataService(database: .launchBox, directory: directory, transport: { request in
            let url = request.url!
            let html = if url.path.contains("/results/") {
                "<a href=\"/games/details/10-fixture\"><h3>Fixture 17</h3><p>Nintendo Switch 2</p></a>"
            } else {
                "<script id=\"__NUXT_DATA__\">\(json)</script>"
            }
            return (Data(html.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let client = Client { request in
            guard request.url?.host == "searching.nintendo-europe.com" else { return (404, Data()) }
            var doc = Self.doc(id, region: "fr-fr")
            doc["product_catalog_description_s"] = "Construisez votre village avec vos amis dans ce jeu."
            return (200, Self.catalog([doc]))
        }
        let service = SwitchGameMetadataService(client: client, cacheDirectory: directory, launchBox: launchBox)
        let title = PortedGame(name: "Fixture 17", url: URL(fileURLWithPath: "/no-game/Fixture.app"),
                               platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: id)
        let result = try await service.metadata(for: title, locale: fr)
        XCTAssertEqual(result.excerpt, "Construisez votre village avec vos amis dans ce jeu.")
        XCTAssertEqual(result.description, overview)
        XCTAssertEqual(result.descriptionLanguage, "en")
        XCTAssertEqual(result.origin(for: .description), .launchBox)
        XCTAssertEqual(result.developers, ["Studio"])
        XCTAssertEqual(result.origin(for: .developer), .launchBox)
        XCTAssertEqual(result.publishers, ["European Publisher"])
    }
}
