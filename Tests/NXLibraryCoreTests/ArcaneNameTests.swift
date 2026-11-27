import XCTest
@testable import NXLibraryCore

/// The user-facing brand is separate from the upstream network identity.
final class ArcaneNameTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testCatalogShowsNoOldAppName() throws {
        let url = repository.appendingPathComponent("core/OortLibrary/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        var found: [String] = []
        for (key, entry) in strings {
            if key.contains("NX Library") { found.append(key) }
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (language, value) in localizations {
                let text = ((value as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                if text.contains("NX Library") { found.append("\(language): \(key)") }
            }
        }
        XCTAssertEqual(found.sorted(), [])
    }

    func testUserAgentNamesArcane() {
        XCTAssertEqual(AppIdentity.userAgent(version: "0.2"), "Arcane/0.2 (macOS; +https://github.com/sofianbll/oort-nx)")
    }

    func testProjectDocsOpenTheReadmeOnlineOnEveryMac() {
        XCTAssertEqual(AppIdentity.documentationPage.absoluteString, "https://github.com/sofianbll/oort-nx#readme")
    }

    /// Every module folder of the package, as architecture/names.json declares them.
    private func moduleFolders() throws -> [URL] {
        let data = try Data(contentsOf: repository.appendingPathComponent("architecture/names.json"))
        let names = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let modules = try XCTUnwrap(names["modules"] as? [String: [String: Any]])
        return try modules.values.map { try XCTUnwrap($0["path"] as? String) }.map(repository.appendingPathComponent)
    }

    func testNoSourceSendsTheOldUserAgent() throws {
        let files = try moduleFolders().flatMap { folder in
            FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        }
        XCTAssertFalse(files.isEmpty)
        let offenders = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains("\"NXLibrary/") }
            .map(\.lastPathComponent)
        XCTAssertEqual(offenders, [])
    }
}
