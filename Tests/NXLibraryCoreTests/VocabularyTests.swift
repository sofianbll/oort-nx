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

    /// The names the player chose for the two views, in the languages that have their own.
    func testSpotlightKeepsItsChosenNames() throws {
        for (language, name) in ["fr": "À la une", "es": "Destacados", "pt-BR": "Destaques"] {
            XCTAssertEqual(try strings(language)["Spotlight"], name, language)
        }
    }

    /// Making a game's app is « Compiler », never « porter » or « créer l'app Mac ».
    func testMakingAGamesAppHasOneWord() throws {
        let other = "\\bportage\\b|\\bport(é|ée|és|ées)\\b(?!\\s+par)|création d[’'](apps?|une app) Mac|création de l[’']app Mac|cré\\w+ (à nouveau )?l[’']app Mac"
        for (key, value) in try strings("fr") {
            XCTAssertNil(value.range(of: other, options: [.regularExpression, .caseInsensitive]), "\(key): \(value)")
        }
        XCTAssertEqual(try strings("fr")["Porting"], "Compilation")
    }
}
