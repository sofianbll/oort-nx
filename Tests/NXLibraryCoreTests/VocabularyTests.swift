import XCTest
@testable import NXLibraryCore

/// The experience contract's words, in the catalog every screen reads.
final class VocabularyTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func strings(_ language: String) throws -> [String: String] {
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/NXLibraryCore/Resources/Localizable.xcstrings"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let all = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        return all.compactMapValues { entry in
            ((entry["localizations"] as? [String: Any])?[language] as? [String: Any]).flatMap {
                ($0["stringUnit"] as? [String: Any])?["value"] as? String
            }
        }
    }

    /// Remove leaves the list and erases nothing; Delete erases, or goes to the Trash.
    func testRemoveAndDeleteAreTwoWords() throws {
        for language in ["fr", "de", "es", "it", "pt-BR", "zh-Hans"] {
            let words = try strings(language)
            XCTAssertNotEqual(words["Remove"], words["Delete"], language)
        }
        XCTAssertEqual(try strings("fr")["Remove"], "Retirer")
        // What goes to the Trash is deleted on its button too.
        for path in ["Sources/NXLibrary/Views/GameOptions/GameOptionsView+Confirmation.swift", "Sources/ArcanePorting/Cheats/CheatCopy.swift",
                     "Sources/NXLibrary/Views/Settings/SettingsSoundSection.swift", "Sources/NXLibrary/Views/Theme/ThemePickerView+OwnWallpapers.swift",
                     "Sources/NXLibrary/Views/GameOptions/ModsPanel.swift", "Sources/NXLibrary/Views/Settings/SettingsAPISection.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(text.contains("\"Remove\""), path)
        }
    }
}
