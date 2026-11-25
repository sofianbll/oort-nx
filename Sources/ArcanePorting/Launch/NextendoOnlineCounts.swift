import Foundation
import NXLibraryCore

/// The public count per title, not the total for a group of titles in `jeux`.
public actor NextendoOnlineCounts {
    private struct Response: Decodable { let counts: [String: Int] }
    private static let endpoint = URL(string: "https://nextendo.network/api/online-counts")!
    private let session: URLSession
    private var cached: [String: Int] = [:]
    private var expires = Date.distantPast
    private var isLoading = false

    public init() { session = URLSession(configuration: .ephemeral) }
    package init(session: URLSession) { self.session = session }

    /// Nothing is read or sent, cached answer included, when the player never wants these counts.
    public func read(tokenStore: NextendoTokenStore, display: OnlinePlayersDisplay = .dot) async throws -> [String: Int] {
        guard display.asksService, try tokenStore.hasToken() else { return [:] }
        guard Date() >= expires, !isLoading else { return cached }
        isLoading = true
        defer { isLoading = false }
        let request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await BoundedDownload.data(for: request, session: session, limit: 512_000)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == Self.endpoint else {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()
        cached = try Self.decode(data)
        expires = Date().addingTimeInterval(180)
        return cached
    }

    package static func decode(_ data: Data) throws -> [String: Int] {
        let counts = try JSONDecoder().decode(Response.self, from: data).counts
        return counts.reduce(into: [:]) { result, entry in
            guard entry.value > 0, entry.key.utf8.count == 16,
                  entry.key.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return }
            let title = entry.key.lowercased()
            result[title] = max(result[title, default: 0], entry.value)
        }
    }
}
