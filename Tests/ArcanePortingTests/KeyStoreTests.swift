import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class KeyStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXKeys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func fakeKeys(header: Bool = true) -> String {
        var lines = ["key_area_key_application_00 = " + String(repeating: "00", count: 16)]
        if header { lines.append("header_key = " + String(repeating: "11", count: 32)) }
        return lines.joined(separator: "\n") + "\n"
    }

    func testImportSets0600AndKeepsOnlySummary() throws {
        let source = dir.appendingPathComponent("prod.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        let store = KeyStore(directory: dir.appendingPathComponent("keys"))
        XCTAssertEqual(try store.importKey(from: source), 1)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.keyURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let parent = try FileManager.default.attributesOfItem(atPath: store.keyURL.deletingLastPathComponent().path)
        XCTAssertEqual((parent[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testMissingHeaderKeyThrows() throws {
        let source = dir.appendingPathComponent("bad.keys")
        try fakeKeys(header: false).write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try KeyStore(directory: dir.appendingPathComponent("k2")).importKey(from: source))
    }

    func testWorkshopDistinguishesMissingAndInvalidKeys() throws {
        let store = KeyStore(directory: dir)
        let engine = MacNXNative(place: Place(UUID()), checkout: "", prescribed: "a123456", expected: "a123456", keys: dir)
        XCTAssertEqual(engine.workshop().localKeys, .required)
        try fakeKeys(header: false).write(to: store.keyURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(engine.workshop().localKeys, .invalid(.missingHeaderKey))
        try (fakeKeys() + "malformed\n").write(to: store.keyURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(engine.workshop().localKeys, .invalid(.invalidLine(3)))
        try Data(repeating: 0, count: 1_048_577).write(to: store.keyURL)
        XCTAssertEqual(engine.workshop().localKeys, .invalid(.unreadable))
    }

    func testMalformedHeaderDoesNotReplaceManagedKey() throws {
        let source = dir.appendingPathComponent("source.keys")
        let store = KeyStore(directory: dir.appendingPathComponent("managed"))
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        try store.importKey(from: source)
        let before = try Data(contentsOf: store.keyURL)
        try "header_key = 11\n".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.importKey(from: source))
        XCTAssertTrue(try Data(contentsOf: store.keyURL) == before)
    }

    func testReadingManagedKeysDoesNotChangePermissionsOrContents() async throws {
        let source = dir.appendingPathComponent("source.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        let store = KeyStore(directory: dir.appendingPathComponent("managed"))
        try store.importKey(from: source)
        let before = try Data(contentsOf: store.keyURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.keyURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.keyURL.deletingLastPathComponent().path)
        let place = Place(UUID())
        let engine: any EngineAdapter = MacNXNative(place: place, checkout: "", prescribed: "a123456",
            expected: "a123456", keys: store.keyURL.deletingLastPathComponent())
        let workshop = try await engine.workshop(place)
        XCTAssertEqual(workshop.localKeys, .available(applicationGenerations: 1, needsPrivatePermissions: true))
        let mode = try FileManager.default.attributesOfItem(atPath: store.keyURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o644)
        XCTAssertEqual(try Data(contentsOf: store.keyURL), before)
        for _ in 0..<2 {
            try store.secureManagedCopy()
            let repaired = try await engine.workshop(place)
            XCTAssertEqual(repaired.localKeys, .available(applicationGenerations: 1))
            let fm = FileManager.default
            for (url, mode) in [(store.keyURL, 0o600), (store.keyURL.deletingLastPathComponent(), 0o700)] {
                XCTAssertEqual((try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, mode)
            }
            XCTAssertEqual(try Data(contentsOf: store.keyURL), before)
        }
    }

    func testImportDoesNotChangeTheOriginalFilesPermissions() throws {
        let source = dir.appendingPathComponent("source.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path)
        _ = try KeyStore(directory: dir.appendingPathComponent("managed")).importKey(from: source)
        let mode = try FileManager.default.attributesOfItem(atPath: source.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o644)
    }

    func testManagedSymlinkIsRejectedWithoutChangingItsTarget() throws {
        let source = dir.appendingPathComponent("source.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path)
        let store = KeyStore(directory: dir)
        try FileManager.default.createSymbolicLink(at: store.keyURL, withDestinationURL: source)
        XCTAssertEqual(store.readStatus(), .invalid(.unreadable))
        let mode = try FileManager.default.attributesOfItem(atPath: source.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o644)
    }

    func testFailedReplacementKeepsTheManagedKeyAndTheSource() throws {
        let source = dir.appendingPathComponent("source.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        let managed = dir.appendingPathComponent("managed")
        let original = KeyStore(directory: managed)
        try original.importKey(from: source)
        let before = try Data(contentsOf: original.keyURL)
        let store = KeyStore(directory: managed)
        store.publish = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try store.importKey(from: source))
        XCTAssertEqual(try Data(contentsOf: store.keyURL), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: managed.path), ["prod.keys"])
    }

    func testSuccessfulReplacementPublishesTheNewKeyWithPrivatePermissions() throws {
        let source = dir.appendingPathComponent("source.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        let store = KeyStore(directory: dir.appendingPathComponent("managed"))
        try store.importKey(from: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.keyURL.path)
        let updated = fakeKeys() + "key_area_key_application_01 = " + String(repeating: "22", count: 16) + "\n"
        try updated.write(to: source, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.importKey(from: source), 2)
        XCTAssertEqual(try Data(contentsOf: store.keyURL), try Data(contentsOf: source))
        let permissions = try FileManager.default.attributesOfItem(atPath: store.keyURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testMalformedLineDoesNotLeakContent() throws {
        let source = dir.appendingPathComponent("malformed.keys")
        try (fakeKeys() + "TOP_SECRET_KEY_MATERIAL\n")
            .write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try KeyStore(directory: dir.appendingPathComponent("k3")).importKey(from: source)) { error in
            XCTAssertEqual(error as? KeyIssue, .invalidLine(3))
        }
    }

    func testCRLFLineNumber() throws {
        let source = dir.appendingPathComponent("crlf.keys")
        try (fakeKeys().replacingOccurrences(of: "\n", with: "\r\n") + "BAD\r\n")
            .write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try KeyStore(directory: dir.appendingPathComponent("k4")).importKey(from: source)) { error in
            XCTAssertEqual(error as? KeyIssue, .invalidLine(3))
        }
    }
}
