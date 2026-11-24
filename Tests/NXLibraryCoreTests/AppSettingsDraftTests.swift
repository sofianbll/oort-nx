import XCTest
import NXLibraryCore

final class AppSettingsDraftTests: XCTestCase {
    private let fields: [AppSettingsDraft.Field] = [
        .init("sound", \.soundVolume, previews: true, describe: { String($0) }),
        .init("language", \.appLanguage, previews: true, describe: { $0.rawValue }),
        .init("look", \.colorThemeID, previews: true, describe: { $0 }),
        .init("network", \.multiplayerDefault, important: true, describe: { $0.rawValue }),
        .init("deadzone", \.launcherChoices.controllerDeadzone, describe: { String($0 ?? 0.35) }),
        .init("dockIcon", \.launcherChoices.dockIconAppearance, previews: true, describe: { $0 ?? "Auto" }),
        .init("gameSources", \.launcherChoices.gameSourcesPath, describe: { $0 ?? "Legacy" }),
        .init("players", \.launcherChoices.players, describe: { $0?.mode.rawValue ?? "Default" }),
    ]

    private func withStore(fileManager: FileManager = .default, _ run: (AppSettingsStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppSettingsStore(fileURL: directory.appendingPathComponent("settings.json"), fileManager: fileManager)
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

    func testInterruptionAfterTemporaryWriteKeepsThePreviousCompleteFile() throws {
        let files = InterruptBeforeReplacement()
        try withStore(fileManager: files) { store in
            store.editingSettings.multiplayerDefault = .online
            store.editingSettings.soundVolume = 0.3
            let previous = try Data(contentsOf: store.fileURL)
            files.interrupt = true
            XCTAssertThrowsError(try store.commitDraft())
            XCTAssertEqual(try Data(contentsOf: store.fileURL), previous)
            XCTAssertEqual(AppSettingsStore(fileURL: store.fileURL).settings, AppSettings())
            XCTAssertTrue(store.draft!.hasChanges)
        }
    }

    func testLauncherChoicesShareTheDraftAndDoNotChangeLegacyDefaults() throws {
        try withStore { store in
            XCTAssertNil(store.settings.launcherChoices.controllerDeadzone)
            store.editingSettings.launcherChoices.controllerDeadzone = 0.6
            store.editingSettings.launcherChoices.dockIconAppearance = "Monochrome"
            XCTAssertNil(store.presentation.launcherChoices.controllerDeadzone)
            XCTAssertEqual(store.presentation.launcherChoices.dockIconAppearance, "Monochrome")
            store.discardDraft()
            XCTAssertNil(store.presentation.launcherChoices.dockIconAppearance)
            store.editingSettings.launcherChoices.controllerDeadzone = 0.6
            store.editingSettings.launcherChoices.dockIconAppearance = "Monochrome"
            try store.commitDraft()
            XCTAssertEqual(AppSettingsStore(fileURL: store.fileURL).settings.launcherChoices, store.settings.launcherChoices)
            XCTAssertEqual(store.settings.launcherChoices.controllerDeadzone, 0.6)
        }
    }

    func testClearingSourcesRemembersTheExplicitEmptyChoice() throws {
        try withStore { store in
            XCTAssertNil(store.settings.launcherChoices.gameSourcesPath)
            store.editingSettings.launcherChoices.gameSourcesPath = ""
            XCTAssertNil(store.presentation.launcherChoices.gameSourcesPath)
            try store.commitDraft()
            XCTAssertEqual(AppSettingsStore(fileURL: store.fileURL).settings.launcherChoices.gameSourcesPath, "")
        }
    }

    func testPlayersAndSoundAreSavedTogetherOrDiscardedTogether() throws {
        try withStore { store in
            var plan = PlayerPlan(mode: .merge)
            try plan.setMergePlayer(2)
            try plan.set(.init(profileID: UUID()), at: 2)
            store.editingSettings.launcherChoices.players = plan
            store.editingSettings.soundVolume = 0.3
            XCTAssertNil(AppSettingsStore(fileURL: store.fileURL).settings.launcherChoices.players)
            store.discardDraft()
            XCTAssertNil(store.editingSettings.launcherChoices.players)
            XCTAssertEqual(store.editingSettings.soundVolume, 0.6)
            store.editingSettings.launcherChoices.players = plan
            store.editingSettings.soundVolume = 0.3
            try store.commitDraft()
            let saved = AppSettingsStore(fileURL: store.fileURL).settings
            XCTAssertEqual(saved.launcherChoices.players, plan)
            XCTAssertEqual(saved.soundVolume, 0.3)
        }
    }
}

private final class InterruptBeforeReplacement: FileManager, @unchecked Sendable {
    var interrupt = false

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        if interrupt { throw CocoaError(.fileWriteNoPermission) }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }
}
