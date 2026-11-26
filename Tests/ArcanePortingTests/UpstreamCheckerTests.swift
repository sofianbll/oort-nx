import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class UpstreamCheckerTests: XCTestCase {
    private actor CompareResponse: UpstreamHTTPClient {
        let body: Data
        let status: Int
        private(set) var requests = 0
        init(_ body: String, status: Int = 200) { self.body = Data(body.utf8); self.status = status }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests += 1
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testAdapterKeepsReviewedFactsAndRefusesWithoutLeakingRequestDetails() async throws {
        let pin = "a123456"
        let place = Place(UUID())
        func workshop(_ response: CompareResponse) async throws -> Workshop {
            let engine: any EngineAdapter = MacNXNative(place: place, checkout: "", prescribed: pin,
                                                         expected: "b123456", client: response)
            return try await engine.workshop(place)
        }
        for behind in [0, 1] {
            let response = CompareResponse("""
                {"ahead_by":0,"behind_by":\(behind),"base_commit":{"sha":"a123456"},"commits":[]}
                """)
            let snapshot = try await workshop(response)
            let before = await response.requests
            XCTAssertEqual(before, 0)
            let review = try await snapshot.checkUpstream.run(Confirmed(UUID()), request: RequestID(UUID()))
            XCTAssertEqual(review.isUpToDate, behind == 0)
            XCTAssertEqual(review.targetSHA, pin)
            XCTAssertEqual(review.newCommitsCount, 0)
            XCTAssertEqual(review.commits, [])
            let after = await response.requests
            XCTAssertEqual(after, 1)
        }
        let response = CompareResponse(#"{"message":"Temporary error /Volumes/Private/prod.keys opaque_fixture https://private.invalid/secret"}"#,
                                       status: 503)
        let offer = try await workshop(response).checkUpstream
        do {
            _ = try await offer.run(Confirmed(UUID()), request: RequestID(UUID()))
            XCTFail("The review must refuse a 503")
        } catch {
            guard case .upstream(.http(let code, let message)) = error else { return XCTFail("Unexpected refusal: \(error)") }
            XCTAssertEqual(code, 503)
            XCTAssertNil(message, "Unrecognised server text is not safe to relay")
        }
    }

    final class FakeClient: UpstreamHTTPClient {
        var request: URLRequest?
        var result: Result<(Data, HTTPURLResponse), Error> = .failure(URLError(.notConnectedToInternet))

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            self.request = request
            return try result.get()
        }
    }

    private func response(_ code: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.github.com")!,
                        statusCode: code, httpVersion: nil, headerFields: headers)!
    }

    private func fixture() -> Data {
        Data("""
        {
          "status": "ahead",
          "ahead_by": 2,
          "behind_by": 0,
          "total_commits": 2,
          "base_commit": {"sha": "06b7b3e56303bc67213a98cae61925f9253bdf89"},
          "commits": [
            {
              "sha": "40b643b1234567890",
              "commit": {
                "author": {"name": "seedds", "date": "2026-10-26T16:41:11Z"},
                "message": "Keep Mac audio buffers near 5 ms across output changes\\n\\nBody"
              }
            },
            {
              "sha": "57080541234567890",
              "commit": {
                "author": {"name": "seedds", "date": "2026-10-26T23:12:02Z"},
                "message": "Port Mario + Rabbids Sparks of Hope\\n\\nBody"
              }
            }
          ]
        }
        """.utf8)
    }

    func testDecodesCompareAndOrdersNewestFirst() async throws {
        let client = FakeClient()
        client.result = .success((fixture(), response(200)))
        let checker = UpstreamChecker(client: client)
        let base = "06b7b3e56303bc67213a98cae61925f9253bdf89"

        let status = try await checker.check(from: base)

        XCTAssertEqual(status.repository, "seedds/nxnative")
        XCTAssertEqual(status.status, "ahead")
        XCTAssertEqual(status.aheadBy, 2)
        XCTAssertEqual(status.behindBy, 0)
        XCTAssertEqual(status.totalCommits, 2)
        XCTAssertEqual(status.upstreamCommit, "57080541234567890")
        XCTAssertEqual(status.commits.count, 2)
        XCTAssertEqual(status.commits.first?.subject, "Port Mario + Rabbids Sparks of Hope")
        XCTAssertEqual(status.commits.first?.author, "seedds")
        XCTAssertEqual(status.commits.first?.shortSha, "5708054")
        XCTAssertEqual(status.compareURL.absoluteString,
                       "https://github.com/seedds/nxnative/compare/\(base)...main")
        XCTAssertEqual(client.request?.url?.absoluteString,
                       "https://api.github.com/repos/seedds/nxnative/compare/\(base)...main")
        XCTAssertEqual(client.request?.value(forHTTPHeaderField: "Accept"),
                       "application/vnd.github+json")
    }

    func testAdapterReturnsTheInspectedCommitListWithoutAnotherRequest() async throws {
        let pin = "06b7b3e56303bc67213a98cae61925f9253bdf89"
        let place = Place(UUID())
        let response = CompareResponse(String(decoding: fixture(), as: UTF8.self))
        let engine: any EngineAdapter = MacNXNative(place: place, checkout: "", prescribed: pin,
                                                     expected: pin, client: response)
        let workshop = try await engine.workshop(place)
        let review = try await workshop.checkUpstream.run(Confirmed(UUID()), request: RequestID(UUID()))
        XCTAssertEqual(review.targetSHA, "57080541234567890")
        XCTAssertEqual(review.newCommitsCount, 2)
        XCTAssertEqual(review.commits.map(\.sha), ["57080541234567890", "40b643b1234567890"])
        let requests = await response.requests
        XCTAssertEqual(requests, 1)
    }

    func testIdenticalRepository() async throws {
        let client = FakeClient()
        let json = """
        {"status":"identical","ahead_by":0,"behind_by":0,"total_commits":0,
         "base_commit":{"sha":"06b7b3e"},"commits":[]}
        """
        client.result = .success((Data(json.utf8), response(200)))
        let status = try await UpstreamChecker(client: client).check(from: "06b7b3e")
        XCTAssertTrue(status.isUpToDate)
        XCTAssertEqual(status.upstreamCommit, "06b7b3e")
        XCTAssertTrue(status.commits.isEmpty)
    }

    func testRateLimitError() async throws {
        let client = FakeClient()
        client.result = .success((Data("{}".utf8), response(403, headers: [
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": "1793056000",
        ])))
        do {
            _ = try await UpstreamChecker(client: client).check(from: "06b7b3e")
            XCTFail("expected rate limit")
        } catch let UpstreamCheckerError.rateLimited(reset) {
            XCTAssertNotNil(reset)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testHTTPErrorMessage() async throws {
        let client = FakeClient()
        client.result = .success((Data(#"{"message":"Not Found"}"#.utf8), response(404)))
        do {
            _ = try await UpstreamChecker(client: client).check(from: "06b7b3e")
            XCTFail("expected HTTP error")
        } catch let UpstreamCheckerError.http(status, message) {
            XCTAssertEqual(status, 404)
            XCTAssertEqual(message, "Not Found")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
