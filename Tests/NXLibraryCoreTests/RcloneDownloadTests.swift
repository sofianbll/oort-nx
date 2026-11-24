import CryptoKit
import Foundation
import XCTest
@testable import NXLibraryCore

final class RcloneDownloadTests: XCTestCase {
    private final class FixtureTransport: URLProtocol {
        static let responses = NSLock()
        static var fixtures: [String: (Int, Data)] = [:]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url,
                  let (status, body) = Self.responses.withLock({ Self.fixtures[url.path] }) else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rclone-test-\(UUID())", isDirectory: true)
        var installer: RcloneDownload { .init(supportRoot: root.appendingPathComponent("Support", isDirectory: true)) }
        var transport: URLSessionConfiguration {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FixtureTransport.self]
            return configuration
        }
        func release(_ body: Data?, size: Int? = nil, badHash: Bool = false,
                     status: Int = 200, executableBytes: Int = 1) -> RcloneDownload.Release {
            let url = URL(string: "https://\(RcloneDownload.host)/fixture/\(UUID())")!
            if let body { FixtureTransport.responses.withLock { FixtureTransport.fixtures[url.path] = (status, body) } }
            return .init(url: url, bytes: size ?? body?.count ?? 1,
                         sha256: badHash ? "" : SHA256.hash(data: body ?? Data()).map { String(format: "%02x", $0) }.joined(),
                         member: "fixture", executableBytes: executableBytes)
        }
        func dispose(_ release: RcloneDownload.Release) {
            _ = FixtureTransport.responses.withLock { FixtureTransport.fixtures.removeValue(forKey: release.url.path) }
        }
        func clean() { try? FileManager.default.removeItem(at: root) }
        func nothingInstalled() {
            XCTAssertNil(installer.installedExecutable)
            let parent = installer.directory.deletingLastPathComponent()
            XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [], [])
        }
    }

    func testRefusesWrongHashTruncationOversizeRedirectAndOffline() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        let bytes = Data([1, 2, 3])
        let cases: [(RcloneDownload.Release, RcloneDownload.Failure)] = [
            (fixture.release(bytes, badHash: true), .integrity),
            (fixture.release(bytes, size: 4), .response),
            (fixture.release(bytes, size: 2), .response),
            (fixture.release(Data(), status: 302), .redirect),
            (fixture.release(nil), .network),
        ]
        for (release, expected) in cases {
            defer { fixture.dispose(release) }
            do {
                _ = try await fixture.installer.install(release, transport: fixture.transport)
                XCTFail("Accepted a refused download: \(expected)")
            } catch { XCTAssertEqual(error as? RcloneDownload.Failure, expected) }
            fixture.nothingInstalled()
        }
    }

    func testRedirectDelegateRejectsOtherOriginsWithoutFollowingThem() {
        let origin = RcloneDownload.release.url
        let policy = RcloneDownload.RedirectPolicy(origin: origin)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: origin)
        let response = HTTPURLResponse(url: origin, statusCode: 302, httpVersion: nil, headerFields: nil)!
        for target in [origin, URL(string: "https://elsewhere.invalid/tool")!,
                       URL(string: "http://\(RcloneDownload.host)/tool")!,
                       URL(string: "https://\(RcloneDownload.host):8443/tool")!] {
            let result = expectation(description: "Redirect decision")
            policy.urlSession(session, task: task, willPerformHTTPRedirection: response,
                              newRequest: URLRequest(url: target)) { request in
                XCTAssertEqual(request?.url, target == origin ? origin : nil)
                result.fulfill()
            }
            wait(for: [result], timeout: 1)
        }
    }

    func testNoSpaceStopsBeforeNetworkAndWriteErrorsAreNormalized() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        let release = fixture.release(nil)
        for capacity: (URL) throws -> Int? in [{ _ in 0 }, { _ in throw POSIXError(.ENOSPC) }] {
            do {
                _ = try await fixture.installer.install(release, transport: fixture.transport, available: capacity)
                XCTFail("Installed without space")
            } catch { XCTAssertEqual(error as? RcloneDownload.Failure, .space) }
            fixture.nothingInstalled()
        }
    }

    func testCancellationBeforeCommitLeavesNothingInstalled() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        let release = fixture.release(Data(repeating: 42, count: 1024 * 1024))
        defer { fixture.dispose(release) }
        let downloading = expectation(description: "Received response bytes")
        let task = Task {
            try await fixture.installer.install(release, transport: fixture.transport, progress: { _ in
                downloading.fulfill()
                try? await Task.sleep(for: .seconds(5))
            })
        }
        await fulfillment(of: [downloading], timeout: 8)
        task.cancel()
        do { _ = try await task.value; XCTFail("Published after cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        fixture.nothingInstalled()
    }

    func testVerifiedArchiveIsPublishedOnlyWithSignedMember() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let files = FileManager.default
        try files.createDirectory(at: fixture.root, withIntermediateDirectories: false)
        let member = fixture.root.appendingPathComponent("fixture")
        let archive = fixture.root.appendingPathComponent("fixture.zip")
        func zip() throws -> Data {
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.arguments = ["-qj", archive.path, member.path]
            try zip.run()
            zip.waitUntilExit()
            XCTAssertEqual(zip.terminationStatus, 0)
            let data = try Data(contentsOf: archive)
            try files.removeItem(at: archive)
            return data
        }
        let unsigned = Data("not a signed executable".utf8)
        try unsigned.write(to: member)
        let bad = fixture.release(try zip(), executableBytes: unsigned.count)
        defer { fixture.dispose(bad) }
        do {
            _ = try await fixture.installer.install(bad, transport: fixture.transport)
            XCTFail("Published an unsigned executable")
        } catch { XCTAssertEqual(error as? RcloneDownload.Failure, .integrity) }
        fixture.nothingInstalled()
        try files.removeItem(at: member)
        try files.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: member)
        let signed = fixture.release(try zip(), executableBytes: try Data(contentsOf: member).count)
        defer { fixture.dispose(signed) }
        let installed = try await fixture.installer.install(signed, transport: fixture.transport)
        XCTAssertEqual(fixture.installer.installedExecutable, installed)
        XCTAssertEqual(try Data(contentsOf: installed), try Data(contentsOf: member))
        let extras = try files.contentsOfDirectory(atPath: fixture.installer.directory.deletingLastPathComponent().path)
        XCTAssertEqual(extras, [fixture.installer.directory.lastPathComponent])
        try Data().write(to: fixture.installer.directory.appendingPathComponent("rclone.conf"))
        XCTAssertNil(fixture.installer.installedExecutable)
        XCTAssertThrowsError(try fixture.installer.moveInstalledCopyToTrash())
    }

    func testRemovalDoesNotTouchUnownedOrSymlinkedCopy() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let files = FileManager.default
        try files.createDirectory(at: fixture.installer.directory, withIntermediateDirectories: true)
        let candidate = fixture.installer.directory.appendingPathComponent("rclone")
        try files.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: candidate)
        XCTAssertNil(fixture.installer.installedExecutable)
        XCTAssertThrowsError(try fixture.installer.moveInstalledCopyToTrash())
        XCTAssertTrue(files.fileExists(atPath: candidate.path))

        let parent = fixture.installer.directory.deletingLastPathComponent()
        let elsewhere = fixture.root.appendingPathComponent("external", isDirectory: true)
        try files.moveItem(at: parent, to: elsewhere)
        try files.createSymbolicLink(at: parent, withDestinationURL: elsewhere)
        XCTAssertNil(fixture.installer.installedExecutable)
        XCTAssertThrowsError(try fixture.installer.moveInstalledCopyToTrash())
        XCTAssertTrue(files.fileExists(atPath: candidate.path))
    }

    func testReceiptDoesNotMakeAnUnsignedExecutableAvailable() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let files = FileManager.default
        try files.createDirectory(at: fixture.installer.directory, withIntermediateDirectories: true)
        let candidate = fixture.installer.directory.appendingPathComponent("rclone")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: candidate)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: candidate.path)
        try Data().write(to: fixture.installer.directory.appendingPathComponent("oort-install"))
        XCTAssertNil(fixture.installer.installedExecutable)
    }
}
