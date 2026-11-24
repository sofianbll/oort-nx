import Foundation
import XCTest
@testable import ArcanePorting
@testable import NXLibraryCore

final class PersonalAppReceiptTests: XCTestCase {
    private let title = "0100000000001000"
    private let firstDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testVerifiedPublicationSurvivesReopeningOnlyInTheSameScope() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("profile")
        let app = try makeApp(in: root)
        let game = CloudArchiveGame(titleID: title, locations: [.app: app])
        let manifest = try publication("900150983cd24fb0d6963f7d28e17f72", date: firstDate)
        try PersonalAppReceipt.Store(in: profile).record(manifest, for: game, scope: scope())

        let reopened = PersonalAppReceipt.Store(in: profile)
        let receipt = try XCTUnwrap(reopened.receipt(titleID: title, scope: scope()))
        XCTAssertEqual(receipt.inventorySHA256, manifest.artifacts.first?.inventorySHA256)
        XCTAssertEqual(receipt.publishedAt, firstDate, "A later cache publication must not date the app")
        XCTAssertNil(reopened.receipt(titleID: title, scope: scope(account: "account-b")))
        XCTAssertNil(reopened.receipt(titleID: title, scope: scope(folder: "folder-b")))
        XCTAssertNil(reopened.receipt(titleID: "0100000000002000", scope: scope()))
        XCTAssertNil(reopened.receipt(titleID: title, scope: nil))
        XCTAssertNil(PersonalAppReceipt.Store(in: root.appendingPathComponent("other-profile"))
            .receipt(titleID: title, scope: scope()))
    }

    func testUnverifiedOrUnreadablePublicationProvidesNoReceipt() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("profile")
        let app = try makeApp(in: root)
        let game = CloudArchiveGame(titleID: title, locations: [.app: app])
        let good = try publication("900150983cd24fb0d6963f7d28e17f72", date: firstDate)
        let wrongBytes = try publication("4ed9407630eb1000c0f6b63842defa7d", date: firstDate)
        let store = PersonalAppReceipt.Store(in: profile)
        try store.record(good, for: game, scope: nil)
        try store.record(good, for: game, scope: scope(account: "root"))
        try store.record(wrongBytes, for: game, scope: scope())
        XCTAssertNil(store.receipt(titleID: title, scope: scope()))

        try store.record(good, for: game, scope: scope())
        let dir = profile.appendingPathComponent("personal-app-receipts")
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        try Data("not a receipt".utf8).write(to: file)
        XCTAssertNil(store.receipt(titleID: title, scope: scope()))
    }

    private func scope(account: String = "account-a", folder: String = "folder-a") -> CloudDriveScope {
        .init(remote: "fixture", account: account, library: .init(path: "Games", id: folder))
    }

    private func publication(_ md5: String, date: Date) throws -> CloudGameManifest {
        let entries = [CloudArtifactFiles.Entry(path: "Contents/payload", size: 3, md5: md5)]
        let digest = try CloudArtifactFiles.digest(entries)
        return .init(version: 2, titleID: title, createdAt: date.addingTimeInterval(60), artifacts: [
            .init(kind: .app, unpackedSize: 3, entryCount: entries.count, inventorySHA256: digest, engineCommit: nil,
                  shaderChain: nil, options: [:], files: .init(folder: "Fixture [\(title)]/app/\(digest)/Fixture.app",
                                                             entries: entries), publishedAt: date)
        ])
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func makeApp(in root: URL) throws -> URL {
        let app = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: contents.appendingPathComponent("payload"))
        return app
    }
}
