import Foundation

/// Exact-ID read of Nintendo Europe's public game catalogue, not a title search.
enum NintendoEuropeCatalog {
    static func locale(for language: String) -> String? {
        ["en", "fr", "de", "es", "it", "nl", "pt"].contains(language) ? language : nil
    }

    static func request(titleID: String, language: String) -> URLRequest? {
        guard NintendoStoreMetadataService.validTitleID(titleID), locale(for: language) != nil else { return nil }
        var url = URLComponents(string: "https://searching.nintendo-europe.com/\(language)/select")!
        url.queryItems = [
            .init(name: "q", value: "*"),
            .init(name: "fq", value: "application_id_s:\(titleID.lowercased())"),
            .init(name: "fq", value: "type:GAME"),
            .init(name: "rows", value: "30"),
            .init(name: "wt", value: "json")
        ]
        return url.url.map { publicRequest($0) }
    }

    static func publicRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Game Library", forHTTPHeaderField: "User-Agent")
        return request
    }

    struct Document: Decodable {
        var application_id_s: String?
        var type: String?
        var title: String?
        var fs_id: String?
        var url: String?
        var system_names_txt: [String]?
        var product_catalog_description_s: String?
        var publisher: String?
        var dates_released_dts: [String]?
        var pretty_game_categories_txt: [String]?
        var image_url_sq_s: String?
        var image_url_h16x9_s: String?
        var image_url_h2x1_s: String?
        var image_url: String?
        var nsuid_txt: [String]?
        var players_from: Int?
        var players_to: Int?
        var pretty_agerating_s: String?

        var productURL: URL? {
            guard let url, url.hasPrefix("/"), !url.hasPrefix("//"),
                  let result = URL(string: "https://www.nintendo.com" + url),
                  result.host == "www.nintendo.com", result.path.hasSuffix(".html") else { return nil }
            return result
        }

        var baseProductID: String? {
            nsuid_txt?.filter { $0.hasPrefix("700100") }.sorted().first
        }

        var releaseDate: String? {
            let formatter = ISO8601DateFormatter()
            return dates_released_dts?.compactMap { formatter.date(from: $0) }.min().map {
                String(formatter.string(from: $0).prefix(10))
            }
        }

        static func image(_ raw: String?) -> URL? {
            guard let raw, let url = URL(string: raw), url.scheme == "https",
                  url.host == "www.nintendo.com", url.port == nil, url.user == nil,
                  url.path.hasPrefix("/eu/media/images/") else { return nil }
            return url
        }
    }

    static func document(in data: Data, titleID: String) throws -> Document? {
        struct Envelope: Decodable {
            struct Response: Decodable { let numFound: Int; let docs: [Document] }
            let response: Response
        }
        let response = try JSONDecoder().decode(Envelope.self, from: data).response
        guard response.numFound == response.docs.count else { throw NintendoStoreError.decoding }
        let platform = titleID.hasPrefix("0400") ? "Nintendo Switch 2" : "Nintendo Switch"
        // Never guess from search order or price: base downloads have a 700100 product ID.
        // A physical-only entry can still match; packs, demos and add-ons cannot outrank the base.
        return response.docs.filter { doc in
            guard doc.type == "GAME", doc.application_id_s?.lowercased() == titleID.lowercased(),
                  doc.system_names_txt?.contains(platform) == true, doc.productURL != nil,
                  let title = doc.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let path = doc.productURL?.path.lowercased() ?? ""
            return !path.contains("/dlc/") && !path.contains("/downloadable-content/") &&
                !path.contains("/contenu-telechargeable/") &&
                !(platform == "Nintendo Switch" && path.contains("/nintendo-switch-2-edition/"))
        }.min { lhs, rhs in
            let rank: (Document) -> (Int, Int, Int, String) = {
                let edition = $0.productURL?.path.lowercased().contains("/nintendo-switch-2-edition/") == true
                return (edition ? 1 : 0, $0.baseProductID == nil ? 1 : 0, Int($0.fs_id ?? "") ?? .max, $0.url ?? "")
            }
            return rank(lhs) < rank(rhs)
        }
    }
}
