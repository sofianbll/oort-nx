import XCTest
@testable import OortLibrary

/// The core reads `Localizable.xcstrings` itself, on every system. On a Mac it must give what Apple's compiled
/// catalogue gave through `Bundle`: every key, in the seven languages, and for a plural every count tried.
final class L10nAgainstBundleTests: XCTestCase {
    private let regions: [AppLanguage: String] = [.english: "US", .italian: "IT", .french: "FR", .german: "DE",
                                                  .spanish: "ES", .portugueseBrazil: "BR", .chineseSimplified: "CN"]

    func testEveryKeyAndCountIsWhatTheCompiledCatalogueGives() throws {
        let catalogue = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../core/OortLibrary/Resources/Localizable.xcstrings").standardized
        let compiled = FileManager.default.temporaryDirectory.appendingPathComponent("oort-l10n-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: compiled) }
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        tool.arguments = ["xcstringstool", "compile", catalogue.path, "--output-directory", compiled.path]
        try tool.run()
        tool.waitUntilExit()
        XCTAssertEqual(tool.terminationStatus, 0, "xcstringstool compile")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: catalogue)) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        var checked = 0, differences: [String] = []
        for (language, region) in regions {
            let bundle = try XCTUnwrap(Bundle(path: compiled.appendingPathComponent("\(language.rawValue).lproj").path),
                                       language.rawValue)
            let locale = AppLocale(language: language, region: region).formatLocale
            for (key, node) in strings {
                let apple = bundle.localizedString(forKey: key, value: key, table: "Localizable")
                let localizations = node["localizations"] as? [String: [String: Any]]
                guard localizations?[language.rawValue]?["variations"] != nil else {
                    checked += 1
                    let ours = L10n.value(key, language: language)
                    if ours != apple { differences.append("\(language.rawValue) \(key): \(ours) ≠ \(apple)") }
                    continue
                }
                for count in [0, 1, 2, 5, 21, 1_000_000, -1] {
                    checked += 1
                    let expected = String(format: apple, locale: locale, count, "X")
                    let ours = String(format: L10n.value(key, language: language, count: count), locale: locale, count, "X")
                    if ours != expected { differences.append("\(language.rawValue) \(key) [\(count)]: \(ours) ≠ \(expected)") }
                }
            }
        }
        XCTAssertGreaterThan(checked, 7 * 3_000)
        XCTAssertEqual(differences.count, 0, differences.prefix(20).joined(separator: "\n"))
    }
}
