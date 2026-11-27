import Foundation
import os
import XCTest
import OortLibrary
@testable import ArcanePorting

private final class OnlineCountsStub: URLProtocol {
    static let requests = OSAllocatedUnfairLock(initialState: 0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0 += 1 }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"counts":{"01000000000000ab":4}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NextendoOnlineCountsTests: XCTestCase {
    func testNoRequestWithoutLinkedAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("online-counts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NextendoTokenStore(directory: directory)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OnlineCountsStub.self]
        OnlineCountsStub.requests.withLock { $0 = 0 }
        let counts = NextendoOnlineCounts(session: URLSession(configuration: config))

        let withoutToken = try await counts.read(tokenStore: store)
        XCTAssertTrue(withoutToken.isEmpty)
        XCTAssertEqual(OnlineCountsStub.requests.withLock { $0 }, 0)

        _ = try await store.withLock { try $0.write("synthetic-token") }
        let linked = try await counts.read(tokenStore: store)
        XCTAssertEqual(linked, ["01000000000000ab": 4])
        XCTAssertEqual(OnlineCountsStub.requests.withLock { $0 }, 1)

        _ = try await store.withLock { try $0.write(nil) }
        let signedOut = try await counts.read(tokenStore: store)
        XCTAssertTrue(signedOut.isEmpty)
        XCTAssertEqual(OnlineCountsStub.requests.withLock { $0 }, 1)
    }

    func testNoRequestWithAllFourPlacesOff() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("online-counts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NextendoTokenStore(directory: directory)
        _ = try await store.withLock { try $0.write("synthetic-token") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OnlineCountsStub.self]
        OnlineCountsStub.requests.withLock { $0 = 0 }
        let counts = NextendoOnlineCounts(session: URLSession(configuration: config))

        let never = try await counts.read(tokenStore: store, display: .init([]))
        XCTAssertTrue(never.isEmpty)
        XCTAssertEqual(OnlineCountsStub.requests.withLock { $0 }, 0)

        let shown = try await counts.read(tokenStore: store, display: .init([.gamePage]))
        XCTAssertEqual(shown, ["01000000000000ab": 4])
        // A cached answer is not handed out either.
        let after = try await counts.read(tokenStore: store, display: .init([]))
        XCTAssertTrue(after.isEmpty)
        XCTAssertEqual(OnlineCountsStub.requests.withLock { $0 }, 1)
    }

    func testCountsIgnoreUnknownIDsAndZeroAndNormalizeCase() throws {
        let data = Data(#"{"counts":{"01000000000000AB":4,"01000000000000ab":2,"01000000000000bb":0,"+000000000000000":99,"other":42}}"#.utf8)
        XCTAssertEqual(try NextendoOnlineCounts.decode(data), ["01000000000000ab": 4])
        XCTAssertThrowsError(try NextendoOnlineCounts.decode(Data(#"{"counts":[]}"#.utf8)))
    }
}
