import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OortLibrary

/// Serves a fixed body in several chunks without the network.
private final class ChunkedStub: URLProtocol {
    nonisolated(unsafe) static var chunks: [Data] = []
    nonisolated(unsafe) static var declaredLength: Int?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        var headers: [String: String] = [:]
        if let length = Self.declaredLength { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in Self.chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class BoundedDownloadTests: XCTestCase {
    private let url = URL(string: "https://example.invalid/page")!
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChunkedStub.self]
        return URLSession(configuration: config)
    }
    override func setUp() {
        ChunkedStub.chunks = []; ChunkedStub.declaredLength = nil
    }

    func testCollectsEveryChunkUpToTheLimit() async throws {
        ChunkedStub.chunks = [Data(repeating: 1, count: 4), Data(repeating: 2, count: 4), Data(repeating: 3, count: 2)]
        let (data, response) = try await BoundedDownload.data(for: URLRequest(url: url), session: session(), limit: 10)
        XCTAssertEqual(data, Data([1, 1, 1, 1, 2, 2, 2, 2, 3, 3]))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(response.url, url)
    }

    func testStopsWhenTheBodyGrowsPastTheLimit() async {
        ChunkedStub.chunks = [Data(repeating: 1, count: 6), Data(repeating: 2, count: 6)]
        do {
            _ = try await BoundedDownload.data(for: URLRequest(url: url), session: session(), limit: 10)
            XCTFail("An oversized body must not be returned")
        } catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
    }

    func testRefusesADeclaredLengthPastTheLimit() async {
        ChunkedStub.chunks = [Data(repeating: 1, count: 4)]
        ChunkedStub.declaredLength = 11
        do {
            _ = try await BoundedDownload.data(for: URLRequest(url: url), session: session(), limit: 10)
            XCTFail("A declared oversized body must not be read")
        } catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
    }

    func testNeverFollowsARedirect() async throws {
        // FoundationNetworking cannot simulate redirects through a custom URLProtocol.
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_protocol = Int32(IPPROTO_TCP)
        var addresses: UnsafeMutablePointer<addrinfo>?
        XCTAssertEqual(getaddrinfo("127.0.0.1", "0", &hints, &addresses), 0)
        let address = try XCTUnwrap(addresses)
        defer { freeaddrinfo(address) }
        let server = socket(address.pointee.ai_family, address.pointee.ai_socktype, address.pointee.ai_protocol)
        guard server >= 0 else { return XCTFail("Cannot create loopback socket") }
        defer { _ = shutdown(server, Int32(SHUT_RDWR)); _ = OortSystem.close(server) }
        guard bindLoopback(server, address.pointee) == 0, listen(server, 1) == 0 else {
            return XCTFail("Cannot listen on loopback")
        }
        var length = address.pointee.ai_addrlen
        guard getsockname(server, address.pointee.ai_addr, &length) == 0 else { return XCTFail("No loopback port") }
        let port = address.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            UInt16(bigEndian: $0.pointee.sin_port)
        }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/start"))
        DispatchQueue.global().async {
            let client = accept(server, nil, nil)
            guard client >= 0 else { return }
            defer { _ = OortSystem.close(client) }
            var ready = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 3_000) == 1 else { return }
            var request = [UInt8](repeating: 0, count: 4096)
            guard request.withUnsafeMutableBytes({ OortSystem.read(client, $0.baseAddress!, $0.count) }) > 0 else { return }
            let reply = Array("HTTP/1.1 302 Found\r\nLocation: /elsewhere\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            _ = reply.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await BoundedDownload.data(for: URLRequest(url: url), session: session, limit: 10)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 302)
        XCTAssertEqual(response.url, url)
    }

    func testCancellationStopsTheRead() async {
        ChunkedStub.chunks = [Data(repeating: 1, count: 4)]
        let session = session()
        let task = Task { try await BoundedDownload.data(for: URLRequest(url: self.url), session: session, limit: 10) }
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled read must not return data") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

private func bindLoopback(_ socket: Int32, _ address: addrinfo) -> Int32 {
    bind(socket, address.ai_addr, address.ai_addrlen)
}
