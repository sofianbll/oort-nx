import XCTest
import NXLibraryCore

final class AppSettingsDraftTests: XCTestCase {
    private let fields: [AppSettingsDraft.Field] = [
        .init("sound", \.soundVolume, previews: true, describe: { String($0) }),
        .init("language", \.appLanguage, previews: true, describe: { $0.rawValue }),
        .init("look", \.colorThemeID, previews: true, describe: { $0 }),
        .init("network", \.multiplayerDefault, important: true, describe: { $0.rawValue }),
    ]

    private func withStore(_ run: (AppSettingsStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        XCTAssertTrue(store.save())
        store.beginDraft(fields: fields)
        try run(store)
    }

    func testDraftPreviewsWithoutPublishingOrWritingStagedChanges() throws {
        try withStore { store in
            let before = try Data(contentsOf: store.fileURL)
            store.editingSettings.soundVolume = 0.3
            store.editingSettings.appLanguage = .french
            store.editingSettings.colorThemeID = "selene"
            store.editingSettings.multiplayerDefault = .online
            XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
            XCTAssertEqual(store.presentation.soundVolume, 0.3)
            XCTAssertEqual(store.presentation.appLanguage, .french)
            XCTAssertEqual(store.presentation.colorThemeID, "selene")
            XCTAssertEqual(store.presentation.multiplayerDefault, .offline)
            XCTAssertEqual(store.editingSettings.multiplayerDefault, .online)
            XCTAssertEqual(store.draft?.changes.map(\.id), ["network", "sound", "language", "look"])
            XCTAssertEqual(store.settings, AppSettings())

            let reopened = AppSettingsStore(fileURL: store.fileURL)
            XCTAssertEqual(reopened.settings, AppSettings(), "A process interrupted before Save leaves no edits")
            store.endDraft()
            XCTAssertEqual(store.presentation, reopened.settings)
            XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
        }
    }

    func testCommitPreservesAnotherWriterUnrelatedEditAndClearsDraft() throws {
        try withStore { store in
            let other = AppSettingsStore(fileURL: store.fileURL)
            other.settings.showClock = false
            store.editingSettings.soundVolume = 0.3
            store.editingSettings.appLanguage = .french
            store.editingSettings.multiplayerDefault = .online

            try store.commitDraft()
            XCTAssertFalse(store.draft!.hasChanges)
            XCTAssertEqual(store.settings, AppSettingsStore(fileURL: store.fileURL).settings)
            XCTAssertEqual(store.settings.soundVolume, 0.3)
            XCTAssertEqual(store.settings.appLanguage, .french)
            XCTAssertEqual(store.settings.multiplayerDefault, .online)
            XCTAssertFalse(store.settings.showClock)
        }
    }

    func testConflictDoesNotOverwriteAnyFieldAndLeavesDraftOpen() throws {
        try withStore { store in
            store.editingSettings.multiplayerDefault = .online
            store.editingSettings.soundVolume = 0.3
            let other = AppSettingsStore(fileURL: store.fileURL)
            other.settings.multiplayerDefault = .local
            let before = try Data(contentsOf: store.fileURL)
            XCTAssertThrowsError(try store.commitDraft()) {
                XCTAssertEqual($0 as? AppSettingsDraft.Failure, .changedElsewhere)
            }
            XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
            XCTAssertEqual(store.editingSettings.multiplayerDefault, .online)
            XCTAssertEqual(store.settings.soundVolume, 0.6)
            XCTAssertFalse(store.save(), "An ordinary write cannot trample the other writer either")
        }
    }

    func testRevertFieldAndUnreadableReplacement() throws {
        try withStore { store in
            store.editingSettings.soundVolume = 0.3
            store.editingSettings.soundVolume = store.settings.soundVolume
            XCTAssertFalse(store.draft!.hasChanges)
            store.editingSettings.multiplayerDefault = .online
            let bytes = Data("damaged external settings".utf8)
            try bytes.write(to: store.fileURL, options: .atomic)
            XCTAssertThrowsError(try store.commitDraft())
            XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
            XCTAssertTrue(store.draft!.hasChanges)
        }
    }
}
