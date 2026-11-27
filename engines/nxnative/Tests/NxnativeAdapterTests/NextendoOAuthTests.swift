import XCTest
import Synchronization
@testable import NxnativeAdapter

final class NextendoOAuthTests: XCTestCase {
    func testRFC7636ChallengeAndRandomVerifier() throws {
        XCTAssertEqual(NextendoAuthorization.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let first = try NextendoAuthorization(clientID: "public-client", port: 47823)
        let second = try NextendoAuthorization(clientID: "public-client", port: 47823)
        XCTAssertEqual(first.verifier.count, 43)
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertNotEqual(first.state, second.state)
        let query = try XCTUnwrap(URLComponents(url: first.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(first.url.host, "nextendo.network")
        XCTAssertEqual(first.url.path, "/oauth/authorize")
        XCTAssertEqual(query.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(query.first { $0.name == "scope" }?.value, "identity friends game.matchmaking presence profil")
    }

    func testOnlyMatchingLoopbackCallbackAcceptsCode() throws {
        let attempt = try NextendoAuthorization(clientID: "public-client", port: 47823)
        func callback(_ path: String) throws -> URL { try XCTUnwrap(URL(string: "http://127.0.0.1:47823\(path)")) }
        let valid = "/callback?state=\(attempt.state)&code=a%2Bb"
        XCTAssertEqual(try attempt.code(from: callback(valid)), "a+b")
        XCTAssertNil(try attempt.code(from: callback(valid + "&state=another")))
        XCTAssertNil(try attempt.code(from: callback("/callback?state=wrong&code=a")))
        XCTAssertNil(try attempt.code(from: callback("/other?state=\(attempt.state)&code=a")))
        XCTAssertNil(try attempt.code(from: XCTUnwrap(URL(string: "http://127.0.0.1:1234\(valid)"))))
        XCTAssertThrowsError(try attempt.code(from: callback("/callback?state=\(attempt.state)&error=access_denied")))
    }

    func testClientIDAgreesWithEngineFormat() {
        for value in ["nxc_A-1.2", String(repeating: "a", count: 128)] {
            XCTAssertTrue(NextendoAuthorization.validClientID(value))
        }
        for value in ["", "invalid id", "é", "id\n", "id<script>", String(repeating: "a", count: 129)] {
            XCTAssertFalse(NextendoAuthorization.validClientID(value))
        }
    }

    func testExchangeThenRefreshUsesTheSameClientAndRotatesOnlyRefreshToken() async throws {
        let store = makeStore()
        let attempt = try NextendoAuthorization(clientID: "sample-client", port: 47823)
        let grants = Mutex([[String: String]]())
        let client = NextendoOAuth(store: store) { request in
            XCTAssertEqual(request.url?.host, "nextendo.network")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Nextendo-Client-Id"), "sample-client")
            if request.url?.path == "/api/oauth/userinfo" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer memory-only")
                return self.reply(request, 200, #"{"username":"Test player"}"#)
            }
            XCTAssertEqual(request.url?.path, "/api/oauth/token")
            XCTAssertEqual(request.httpMethod, "POST")
            var form = URLComponents()
            form.percentEncodedQuery = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
            let fields = (form.queryItems ?? []).reduce(into: [String: String]()) { $0[$1.name] = $1.value }
            let count = grants.withLock { $0.append(fields); return $0.count }
            return self.reply(request, 200, #"{"access_token":"memory-only","refresh_token":"rotation-\#(count)"}"#)
        }
        let name = try await client.signIn(attempt, code: "code+=&")
        XCTAssertEqual(name, "Test player")
        XCTAssertEqual(grants.withLock { $0.first }, ["grant_type": "authorization_code", "code": "code+=&",
                                      "client_id": "sample-client", "redirect_uri": "http://127.0.0.1:47823/callback",
                                      "code_verifier": attempt.verifier])
        let checked = try await client.accountName(clientID: "sample-client")
        XCTAssertEqual(checked, "Test player")
        XCTAssertEqual(grants.withLock { $0.last }, ["grant_type": "refresh_token", "client_id": "sample-client", "refresh_token": "rotation-1"])
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("refresh_token")), Data("rotation-2".utf8))
    }

    func testExpiredGrantIsDistinctFromAnUnavailableProvider() async throws {
        let store = makeStore()
        _ = try await store.withLock { try $0.write("fixture") }
        let client = NextendoOAuth(store: store) { self.reply($0, 400, #"{"error":"invalid_grant"}"#) }
        do {
            _ = try await client.accountName(clientID: "sample-client")
            XCTFail("A refused refresh grant is not a signed-in account")
        } catch let error as NextendoError { XCTAssertEqual(error, .expired) }
        XCTAssertTrue(try store.hasToken(), "another front end can own this token; don't remove it without sign-out")
        let unavailable = NextendoOAuth(store: store) { self.reply($0, 503, "{}") }
        do {
            _ = try await unavailable.accountName(clientID: "sample-client")
            XCTFail("A temporary error is not expiry")
        } catch let error as NextendoError {
            XCTAssertEqual(error.checkDiagnostic, .init(route: "/api/oauth/token", code: 503))
        }
    }

    private func makeStore() -> NextendoTokenStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Nextendo-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return NextendoTokenStore(directory: folder)
    }

    private func reply(_ request: URLRequest, _ status: Int, _ json: String) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
