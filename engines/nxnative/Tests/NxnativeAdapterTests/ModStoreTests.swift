import XCTest
import os
@testable import OortLibrary
@testable import NxnativeAdapter

final class CodeModStoreTests: XCTestCase {
    func testSyncKeepsMissingModRecordUntilOverlayCanBeWritten() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let store = ModStore(supportFolder: root, recordsFile: root.appendingPathComponent("mods.json"),
                             titleID: "0100000000010000", canWrite: { true }, trash: { _ in XCTFail() })
        let mod = store.modsFolder.appendingPathComponent("Pack")
        try fm.createDirectory(at: mod.appendingPathComponent("romfs"), withIntermediateDirectories: true)
        try store.setOn(true, folderName: "Pack")
        let savedEnv = root.appendingPathComponent("old-env")
        let movedMod = root.appendingPathComponent("missing-mod")
        try fm.moveItem(at: mod, to: movedMod)
        try fm.moveItem(at: store.envFile, to: savedEnv)
        try fm.createDirectory(at: store.envFile, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.sync())
        try fm.removeItem(at: store.envFile)
        try fm.moveItem(at: savedEnv, to: store.envFile)
        try store.sync()
        try fm.moveItem(at: movedMod, to: mod)
        XCTAssertEqual(store.mods().first?.isOn, false)
        XCTAssertFalse(try String(contentsOf: store.envFile, encoding: .utf8).contains("DM_ROMFS_OVERLAY="))
    }

    func testNameCollisionRefusesTogglesAndBuildStaging() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let store = ModStore(supportFolder: root, recordsFile: root.appendingPathComponent("mods.json"),
                             titleID: "0100000000010000", canWrite: { true }, trash: { _ in XCTFail() })
        try fm.createDirectory(at: store.modsFolder.appendingPathComponent("Pack/romfs"), withIntermediateDirectories: true)
        try store.setOn(true, folderName: "Pack")
        let tree = store.codeModsFolder.appendingPathComponent("Pack/exefs")
        try fm.createDirectory(at: tree, withIntermediateDirectories: true)
        try Data("synthetic patch".utf8).write(to: tree.appendingPathComponent("fixture.pchtxt"))
        XCTAssertThrowsError(try BuildService.stageCodeMods(store, in: root.appendingPathComponent("build"), engineSupportsMods: true))
        XCTAssertThrowsError(try store.setOn(false, folderName: "Pack"))
        XCTAssertThrowsError(try store.setOn(true, folderName: "Pack"))
        try fm.moveItem(at: tree.deletingLastPathComponent(), to: store.codeModsFolder.appendingPathComponent("CodePack"))
        XCTAssertTrue(store.mods().first { $0.folderName == "Pack" }?.isOn == true)
        XCTAssertNil(try BuildService.stageCodeMods(store, in: root.appendingPathComponent("build"), engineSupportsMods: true))
        try store.setOn(true, folderName: "CodePack")
        XCTAssertNotNil(try BuildService.stageCodeMods(store, in: root.appendingPathComponent("build"), engineSupportsMods: true))
    }

    func testAmbiguousLocalModsKeepTheAlreadyBuiltCodeDisabledOffline() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let store = ModStore(supportFolder: root, recordsFile: root.appendingPathComponent("mods.json"),
                             titleID: "0100000000010000", canWrite: { true }, trash: { _ in XCTFail() })
        try fm.createDirectory(at: store.codeModsFolder.appendingPathComponent("Pack/exefs"), withIntermediateDirectories: true)
        try store.setOn(false, folderName: "Pack")
        let app = root.appendingPathComponent("Game.app")
        let built = app.appendingPathComponent("Contents/Resources/dm/mods/BuiltPack")
        try fm.createDirectory(at: built, withIntermediateDirectories: true)
        try Data().write(to: built.appendingPathComponent("dm_code.tsv"))
        XCTAssertEqual(store.codeModsLaunchEnvironment(app: app), ["DM_MODS_OFF": "BuiltPack"])

        let romfs = store.modsFolder.appendingPathComponent("Pack/romfs")
        try fm.createDirectory(at: romfs, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.sync(automatic: false))
        XCTAssertTrue(store.codeModsNeedRebuild(app: app))
        XCTAssertEqual(store.codeModsLaunchEnvironment(app: app, online: false), ["DM_MODS_OFF": "BuiltPack"])
        try fm.moveItem(at: store.modsFolder, to: root.appendingPathComponent("old-romfs"))
        try Data().write(to: store.modsFolder)
        XCTAssertThrowsError(try store.sync(automatic: false))
        XCTAssertEqual(store.codeModsLaunchEnvironment(app: app, online: false), ["DM_MODS_OFF": "BuiltPack"])
    }

    func testDisablingOnlineRiskKeepsTexturesAndAllowsReenabling() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("OnlineMods-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let store = ModStore(supportFolder: root.appendingPathComponent("game"),
                             recordsFile: root.appendingPathComponent("mods.json"),
                             titleID: "0100000000010000", canWrite: { true }, trash: { _ in XCTFail() })
        for (mod, file) in [("Colors", "textures/sky.bntx"), ("Rules", "rules.byml"),
                            ("Mixed", "model.bfres"), ("Mixed", "stage.json"), ("Unknown", "archive.pack")] {
            let url = store.modsFolder.appendingPathComponent("\(mod)/romfs/\(file)")
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
            try store.setOn(true, folderName: mod)
        }
        XCTAssertEqual(store.onlineRiskMods(), ["Mixed": .data, "Rules": .data, "Unknown": .uncertain])
        try store.disableOnlineRiskMods()
        XCTAssertEqual(store.mods().filter(\.isOn).map(\.folderName), ["Colors"])
        XCTAssertTrue(store.onlineRiskMods().isEmpty)
        XCTAssertEqual(store.mods().count, 4)
        try store.setOn(true, folderName: "Rules")
        XCTAssertEqual(store.onlineRiskMods(), ["Rules": .data])
    }

    func testTransferredBundleLeavesIncludedCodeModsActiveWithoutLocalPatches() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("CodeModStore-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let store = ModStore(supportFolder: root.appendingPathComponent("game"), recordsFile: root.appendingPathComponent("mods.json"),
                             titleID: "0100000000010000", canWrite: { true }, trash: { _ in XCTFail() })
        let app = root.appendingPathComponent("Game.app")
        let names = ["First", "Second", "Third"]
        for name in names {
            let marker = app.appendingPathComponent("Contents/Resources/dm/mods/\(name)/dm_code.tsv")
            try fm.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: marker)
        }
        XCTAssertFalse(store.codeModsNeedRebuild(app: app))
        XCTAssertEqual(store.codeModsLaunchEnvironment(app: app), [:])
        XCTAssertEqual(store.codeModsLaunchEnvironment(app: app, online: true), ["DM_MODS_OFF": "First"])
        let build = BuildRecord(outputPath: app.path, builtCodeMods: names)
        XCTAssertEqual(store.codeModsLaunchEnvironment(app: app, build: build), ["DM_MODS_OFF": "First"])
        try fm.createDirectory(at: store.codeModsFolder.appendingPathComponent("First/exefs"), withIntermediateDirectories: true)
        try store.setOn(false, folderName: "First")
        XCTAssertFalse(store.codeModsNeedRebuild(app: app))
        XCTAssertEqual(store.codeModsLaunchEnvironment(app: app), ["DM_MODS_OFF": "First"])
    }

    func testMovesStayInTheirSectionAndTogglesAreIndependent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodeModStore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ModStore(supportFolder: root.appendingPathComponent("game"), recordsFile: root.appendingPathComponent("mods.json"),
                             titleID: "0100000000010000", canWrite: { true }, trash: { _ in XCTFail() })
        for (folder, tree) in [(store.modsFolder, "A/romfs"), (store.codeModsFolder, "B/exefs"),
                               (store.modsFolder, "C/romfs"), (store.codeModsFolder, "D/exefs"),
                               (store.codeModsFolder, "D/romfs")] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(tree), withIntermediateDirectories: true)
        }
        for romfs in [store.modsFolder.appendingPathComponent("A/romfs"),
                      store.codeModsFolder.appendingPathComponent("D/romfs")] {
            try Data().write(to: romfs.appendingPathComponent("shared.bin"))
        }
        try store.setOn(true, folderName: "A")
        try store.setOn(true, folderName: "D")
        let overlay = try XCTUnwrap(store.overlayValue())
        XCTAssertEqual(store.conflicts(), [ModConflict(upper: "A", lower: "D")])
        try store.move(folderName: "B", by: -1)
        try store.move(folderName: "C", by: 1)
        XCTAssertEqual(store.mods().map(\.folderName), ["A", "B", "C", "D"])
        XCTAssertEqual(store.overlayValue(), overlay)

        try store.move(folderName: "C", by: -1)
        XCTAssertEqual(store.mods().map(\.folderName), ["C", "B", "A", "D"])
        try store.move(folderName: "B", by: 1)
        XCTAssertEqual(store.mods().map(\.folderName), ["C", "D", "A", "B"])
        XCTAssertEqual(store.mods().filter(\.isOn).map(\.folderName), ["D", "A"])
        XCTAssertEqual(store.conflicts().first?.message, "D and A change the same files: D takes priority.")
        try store.setOn(false, folderName: "D")
        XCTAssertEqual(store.mods().filter(\.isOn).map(\.folderName), ["A"])
    }

    func testCopiesAndPersistsSelectionAndOnlyStagesEnabledModsInOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodeModStore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("game")
        let records = root.appendingPathComponent("records.json")
        func store() -> ModStore {
            ModStore(supportFolder: support, recordsFile: records, titleID: "0100000000010000",
                     canWrite: { true }, trash: { try FileManager.default.removeItem(at: $0) },
                     allowsAutomaticMaintenance: false)
        }
        for name in ["First", "Second", "Third"] {
            let source = root.appendingPathComponent(name)
            let patch = source.appendingPathComponent("exefs/version.pchtxt")
            try FileManager.default.createDirectory(at: patch.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: patch)
            try store().importCodeMod(from: source)
            XCTAssertTrue(FileManager.default.fileExists(atPath: patch.path), "Import copies; the original stays put")
        }
        let existingEnv = "DM_LANG=en\nDM_ROMFS_OVERLAY=/manual\n"
        try Data(existingEnv.utf8).write(to: store().envFile)
        try store().setOn(false, folderName: "Third")
        try store().move(folderName: "Second", by: -1)
        try store().sync(automatic: false)
        XCTAssertEqual(store().mods().map(\.folderName), ["Second", "First", "Third"])
        XCTAssertEqual(store().mods().map(\.isOn), [true, true, false])
        XCTAssertEqual(try String(contentsOf: store().envFile, encoding: .utf8), existingEnv)

        let app = root.appendingPathComponent("Game.app")
        XCTAssertTrue(store().codeModsNeedRebuild(app: app))
        XCTAssertEqual(store().codeModsLaunchEnvironment(app: app), [:])
        let build = root.appendingPathComponent("Build")
        let unsupported = root.appendingPathComponent("Other build")
        XCTAssertThrowsError(try BuildService.stageCodeMods(store(), in: unsupported, engineSupportsMods: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unsupported.path))
        let staged = try XCTUnwrap(BuildService.stageCodeMods(store(), in: build, engineSupportsMods: true))
        let names = try FileManager.default.contentsOfDirectory(atPath: staged.path).sorted()
        XCTAssertEqual(names.count, 2)
        for (index, source) in zip(names, ["Second", "First"]) {
            let copied = staged.appendingPathComponent("\(index)/exefs/version.pchtxt")
            XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), source)
            let marker = app.appendingPathComponent("Contents/Resources/dm/mods/\(index)/dm_code.tsv")
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# applied patches\r\nversion.pchtxt\r\nother.ips\r\n".utf8).write(to: marker)
        }
        let metadata = app.appendingPathComponent("Contents/Resources/dm/mods")
        for ignored in [".hidden/dm_code.tsv", "stray/another.tsv"] {
            let file = metadata.appendingPathComponent(ignored)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        XCTAssertEqual(ModStore.bundledCodeMods(in: app), names, "Switch names come from marker folders, not TSV rows")
        let built = BuildRecord(outputPath: app.path, builtCodeMods: names)
        let stale = BuildRecord(outputPath: app.path, builtCodeMods: ["Old"])
        XCTAssertFalse(store().codeModsNeedRebuild(app: app, build: stale), "Bundle metadata wins over the build record")
        XCTAssertEqual(store().codeModsLaunchEnvironment(app: app), ["DM_MODS_OFF": ""])
        try store().move(folderName: "First", by: -1)
        XCTAssertFalse(store().codeModsNeedRebuild(app: app), "An unchanged set in another order needs no rebuild")
        try store().setOn(false, folderName: "First")
        XCTAssertTrue(store().codeModsNeedRebuild(app: app), "A strict subset needs a rebuild")
        XCTAssertEqual(store().codeModsLaunchEnvironment(app: app), [:])
        try store().setOn(false, folderName: "Second")
        XCTAssertFalse(store().codeModsNeedRebuild(app: app), "The engine can switch its whole code-mod copy off")
        XCTAssertEqual(store().codeModsLaunchEnvironment(app: app, build: stale), ["DM_MODS_OFF": names[0]])
        try store().setOn(true, folderName: "Third")
        XCTAssertTrue(store().codeModsNeedRebuild(app: app), "A mod not in the app needs a rebuild")
        try store().setOn(false, folderName: "Third")
        try store().setOn(true, folderName: "First")
        try store().setOn(true, folderName: "Second")
        XCTAssertFalse(store().codeModsNeedRebuild(app: app), "Turning the whole built set back on needs no rebuild")
        XCTAssertEqual(store().codeModsLaunchEnvironment(app: app), ["DM_MODS_OFF": ""])
        let variant = app.appendingPathComponent("Contents/Resources/dm/codemods")
        try FileManager.default.createDirectory(at: variant, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: metadata)
        XCTAssertTrue(store().codeModsNeedRebuild(app: app, build: BuildRecord(builtCodeMods: names)))
        let decoded = try JSONDecoder().decode(BuildRecord.self, from: JSONEncoder().encode(built))
        XCTAssertFalse(store().codeModsNeedRebuild(app: app, build: decoded), "Fall back to the snapshot for this app")
        try Data("changed".utf8).write(to: store().codeModsFolder.appendingPathComponent("Second/exefs/version.pchtxt"))
        XCTAssertTrue(store().codeModsNeedRebuild(app: app, build: decoded))
        try store().setOn(false, folderName: "First")
        try store().remove(folderName: "Second")
        XCTAssertNil(try BuildService.stageCodeMods(store(), in: root.appendingPathComponent("Empty"), engineSupportsMods: false))
        XCTAssertFalse(store().codeModsNeedRebuild(app: app, build: decoded), "Removing the final enabled code mod also switches the copy off")
        XCTAssertEqual(store().codeModsLaunchEnvironment(app: app, build: decoded), ["DM_MODS_OFF": names[0]])
        try FileManager.default.removeItem(at: variant)
        XCTAssertEqual(store().codeModsLaunchEnvironment(app: app, build: decoded), [:], "No override without a built copy")
        XCTAssertEqual(try String(contentsOf: store().envFile, encoding: .utf8), existingEnv)
    }

    func testLocalImportRejectsLinksAndReplacementPrograms() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodeModStore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source")
        let exefs = source.appendingPathComponent("exefs")
        try FileManager.default.createDirectory(at: exefs, withIntermediateDirectories: true)
        let store = ModStore(supportFolder: root.appendingPathComponent("game"), recordsFile: root.appendingPathComponent("mods.json"),
                             titleID: "0100000000010000", canWrite: { true }, trash: { _ in XCTFail() })
        let patch = exefs.appendingPathComponent("patch.pchtxt")
        try Data("patch".utf8).write(to: patch)
        let descriptor = exefs.appendingPathComponent("main.npdm")
        try Data("not a patch".utf8).write(to: descriptor)
        XCTAssertThrowsError(try store.importCodeMod(from: source))
        try FileManager.default.removeItem(at: descriptor)
        try FileManager.default.createSymbolicLink(at: exefs.appendingPathComponent("linked.ips"), withDestinationURL: patch)
        XCTAssertThrowsError(try store.importCodeMod(from: source))
        XCTAssertTrue(store.mods().isEmpty)
    }
}

final class ModStoreConflictTests: XCTestCase {
    private final class GitFixture: CommandRunning, Sendable {
        private let received = OSAllocatedUnfairLock(initialState: [[String]]())
        var calls: [[String]] { received.withLock { $0 } }

        func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            received.withLock { $0.append(arguments) }
            let object = arguments.last ?? ""
            let status: Int32 = object == "4a2a3426" || object == "deadbee" || object.contains(":") ? 0 : 1
            let profile = object.hasPrefix("deadbee:") ? "off" : "on"
            return CommandResult(status: status, stdout: "title_id\t0100F43008C44000\r\ntrpfd_merge\t\(profile)\r\n", stderr: "")
        }
    }

    func testInstalledRevisionAndProfileGateDescriptorMerge() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModCapability-\(UUID())")
        let app = root.appendingPathComponent("Fixture.app")
        let plist = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func metadata(_ commit: String, _ title: String = "0100F43008C44000") throws {
            let data = try PropertyListSerialization.data(fromPropertyList: ["DMCommit": commit, "DMTitleID": title],
                                                          format: .xml, options: 0)
            try data.write(to: plist)
        }
        let git = GitFixture()
        let capabilities = InstalledEngineCapabilities(runner: git)
        func merges(_ environment: [String: String] = [:]) async -> Bool {
            await capabilities.mergesTrpfd(in: app, engineFolder: root.path, gameData: root, environment: environment)
        }

        try metadata("4a2a3426")
        let enabled = await merges()
        let cached = await merges()
        XCTAssertTrue(enabled)
        XCTAssertTrue(cached)
        XCTAssertEqual(git.calls.count, 2)
        XCTAssertEqual(git.calls[0].suffix(4), ["merge-base", "--is-ancestor", "2aaaa33b5969815bd8692b4a1af42e78b06869d4", "4a2a3426"])
        XCTAssertEqual(git.calls[1].last, "4a2a3426:dm/games/0100F43008C44000/game.tsv")

        try Data("# options\r\nDM_TRPFD_MERGE=0\r\n".utf8).write(to: root.appendingPathComponent("env.txt"))
        let disabled = await merges()
        let overridden = await merges(["DM_TRPFD_MERGE": "1"])
        XCTAssertFalse(disabled)
        XCTAssertTrue(overridden)

        try metadata("e4fddb32")
        let olderBuild = await merges()
        XCTAssertFalse(olderBuild)
        try metadata("deadbee")
        let disabledProfile = await merges(["DM_TRPFD_MERGE": "1"])
        XCTAssertFalse(disabledProfile)
        try metadata("4a2a3426", "0100000000000000")
        let otherGame = await merges()
        XCTAssertFalse(otherGame)
        try metadata("4a2a3426+dirty")
        let unknownBuild = await merges()
        XCTAssertFalse(unknownBuild)
    }

    func testMergedDescriptorIsIgnoredOnlyForZAAndRealConflictsRemain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModStore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support")
        let records = root.appendingPathComponent("records.json")
        let store = ModStore(supportFolder: support, recordsFile: records, titleID: "0100f43008c44000",
                             canWrite: { true }, trash: { _ in XCTFail("Unexpected trash") })
        let first = "Exclusive Mega Stones in Shop"
        let second = "Added Café and Bench Animations"
        for name in [first, second] {
            let arc = store.modsFolder.appendingPathComponent("\(name)/romfs/arc")
            try FileManager.default.createDirectory(at: arc, withIntermediateDirectories: true)
            try Data().write(to: arc.appendingPathComponent("data.trpfd"))
            try store.setOn(true, folderName: name)
        }
        let conflict = ModConflict(upper: first, lower: second)
        XCTAssertEqual(store.conflicts(), [conflict])
        XCTAssertEqual(store.conflicts(mergesTrpfd: true), [])

        let other = ModStore(supportFolder: support, recordsFile: records, titleID: "0100000000000000",
                             canWrite: { true }, trash: { _ in XCTFail("Unexpected trash") })
        XCTAssertEqual(other.conflicts(mergesTrpfd: true), [conflict])

        for name in [first, second] {
            try Data().write(to: store.modsFolder.appendingPathComponent("\(name)/romfs/arc/shared.bin"))
        }
        XCTAssertEqual(store.conflicts(mergesTrpfd: true), [conflict])
        try store.setOn(false, folderName: second)
        XCTAssertEqual(store.conflicts(mergesTrpfd: true), [])
        XCTAssertFalse(try XCTUnwrap(store.overlayValue()).contains("/\(second)/"))
    }
}

final class ModStoreLayoutTests: XCTestCase {
    private func mod(_ id: Int, downloads: Int = 0, likes: Int = 0, added: TimeInterval = 0, updated: TimeInterval = 0,
                     category: String = "Skins", image: Bool = true) -> AvailableMod {
        AvailableMod(id: id, rank: id, name: "Mod \(id)", author: "A", avatarURL: nil,
                     images: image ? [URL(string: "https://images.gamebanana.com/img/ss/mods/\(id).jpg")!] : [],
                     thumbnailURL: image ? URL(string: "https://images.gamebanana.com/img/ss/mods/220-90_\(id).jpg")! : nil,
                     version: "", updated: Date(timeIntervalSince1970: updated),
                     pageURL: URL(string: "https://gamebanana.com/mods/\(id)")!, description: "", likes: likes,
                     downloads: downloads, files: [], category: category,
                     added: Date(timeIntervalSince1970: added))
    }

    func testGameBananaCategoriesGroupIntoOurs() {
        XCTAssertEqual(ModCategory.of("Skins"), .characters)
        XCTAssertEqual(ModCategory.of("Playable Characters"), .characters)
        XCTAssertEqual(ModCategory.of("Models"), .characters)
        XCTAssertEqual(ModCategory.of("Maps"), .worlds)
        XCTAssertEqual(ModCategory.of("Stages"), .worlds)
        XCTAssertEqual(ModCategory.of("Textures"), .graphics)
        XCTAssertEqual(ModCategory.of("Visual Overhaul"), .graphics)
        XCTAssertEqual(ModCategory.of("Effects"), .graphics)
        XCTAssertEqual(ModCategory.of("Music Packs"), .sound)
        XCTAssertEqual(ModCategory.of("Sounds"), .sound)
        XCTAssertEqual(ModCategory.of("GUIs"), .interface)
        XCTAssertEqual(ModCategory.of("UI"), .interface)
        XCTAssertEqual(ModCategory.of("Translations"), .interface)
        XCTAssertEqual(ModCategory.of("Gameplay"), .gameplay)
        XCTAssertEqual(ModCategory.of("Item"), .gameplay)
        XCTAssertEqual(ModCategory.of("Other/Misc"), .more)
        XCTAssertEqual(ModCategory.of("Game files"), .more)
        XCTAssertEqual(ModCategory.of(""), .more)
    }

    func testSortingIsLocalAndStable() {
        let a = mod(1, downloads: 10, likes: 5, added: 300, updated: 100)
        let b = mod(2, downloads: 30, likes: 1, added: 100, updated: 300)
        let c = mod(3, downloads: 20, likes: 9, added: 200, updated: 200)
        let entries = [a, b, c].map { ModCatalogEntry(mod: $0, titleID: "T", gameName: "G") }
        XCTAssertEqual(ModStoreLayout.sorted(entries, by: .popular).map(\.id), [2, 3, 1])
        XCTAssertEqual(ModStoreLayout.sorted(entries, by: .liked).map(\.id), [3, 1, 2])
        XCTAssertEqual(ModStoreLayout.sorted(entries, by: .newest).map(\.id), [1, 3, 2])
        XCTAssertEqual(ModStoreLayout.sorted(entries, by: .updated).map(\.id), [2, 3, 1])
    }

    /// The Mods card's face: the Featured mods' art by popularity, whatever the store's sort and the order the games
    /// come in, so the cover read from disk at launch is the one the open store finds, and it never changes under
    /// the player when the store opens. A mod shared by two games counts for the first by title ID.
    func testCoverArtIsTheSameWhateverTheSortOrTheGamesOrder() {
        let shared = mod(1, downloads: 50)
        let zelda = ModCatalogGame(titleID: "Z", name: "Zelda", mods: [shared, mod(2, downloads: 40), mod(3, downloads: 30)])
        let mario = ModCatalogGame(titleID: "M", name: "Mario", mods: [shared, mod(4, downloads: 45),
                                                                       mod(5, downloads: 99, image: false)])
        let art = { (ids: [Int]) in ids.map { URL(string: "https://images.gamebanana.com/img/ss/mods/\($0).jpg")! } }
        let cover = ModStoreLayout.coverArt(games: [zelda, mario])
        XCTAssertEqual(cover, art([1, 2, 4, 3]), "each game's best first (mod 1 counts for M), only mods with art")
        XCTAssertEqual(ModStoreLayout.coverArt(games: [mario, zelda]), cover)
    }

    func testSectionsRunDownSortFeaturedPopularCategoriesThenEachGame() {
        let zelda = ModCatalogGame(titleID: "Z", name: "Zelda", mods: [
            mod(1, downloads: 50, category: "Skins"), mod(2, downloads: 40, category: "Music Packs"),
            mod(3, downloads: 5, category: "Other/Misc", image: false)])
        let mario = ModCatalogGame(titleID: "M", name: "Mario", mods: [mod(4, downloads: 45, category: "Models")])
        let empty = ModCatalogGame(titleID: "E", name: "Empty", mods: [])
        let sections = ModStoreLayout.sections(games: [mario, zelda, empty], sort: .popular)
        XCTAssertEqual(sections.map(\.kind), [
            .sort, .featured, .popular,
            .category(.characters), .category(.sound), .category(.more),
            .game("M"), .game("Z")])
        XCTAssertEqual(sections[0].count, ModStoreSort.allCases.count)
        // Featured needs art, and takes each game's best first.
        XCTAssertEqual(sections[1].entries.map(\.id), [1, 4, 2])
        XCTAssertEqual(sections[2].entries.map(\.id), [1, 4, 2, 3])
        XCTAssertEqual(sections[3].entries.map(\.id), [1, 4])
        XCTAssertEqual(sections[6].title, "Mario")
        XCTAssertEqual(sections[7].entries.map(\.id), [1, 2, 3])
    }

    func testNoModsMeansOnlyTheSortBar() {
        XCTAssertEqual(ModStoreLayout.sections(games: [], sort: .popular).map(\.kind), [.sort])
    }

    func testRowsHoldAtMostTwelve() {
        let many = ModCatalogGame(titleID: "Z", name: "Zelda", mods: (1...20).map { mod($0, downloads: $0) })
        let sections = ModStoreLayout.sections(games: [many], sort: .popular)
        XCTAssertEqual(sections.first { $0.kind == .popular }?.entries.count, ModStoreLayout.rowLimit)
        XCTAssertEqual(sections.first { $0.kind == .featured }?.entries.count, ModStoreLayout.featuredCount)
        XCTAssertEqual(sections.first { $0.kind == .game("Z") }?.entries.count, ModStoreLayout.rowLimit)
    }

    func testSectionTopsAddUpFixedHeights() {
        let kinds: [ModStoreSectionKind] = [.sort, .featured, .popular, .game("Z")]
        XCTAssertEqual(ModStoreLayout.top(of: 0, in: kinds), 0)
        XCTAssertEqual(ModStoreLayout.top(of: 1, in: kinds), ModStoreLayout.height(.sort))
        XCTAssertEqual(ModStoreLayout.top(of: 3, in: kinds),
                       ModStoreLayout.height(.sort) + ModStoreLayout.height(.featured) + ModStoreLayout.height(.popular))
    }

    /// A row is its title (about 32), its tiles and a 68 gap to the next row's title: room for the focused tile's
    /// grow and ring, no more (it was 104, and the rows read as far apart).
    func testRowsLeaveAShortGapToTheNextRow() {
        for kind: ModStoreSectionKind in [.popular, .category(.graphics), .game("Z")] {
            XCTAssertEqual(ModStoreLayout.height(kind), ModStoreLayout.tileHeight + 100)
        }
    }

    func testRowSlidesOnlyOnceTheFocusedTileReachesTheEdge() {
        let w = ModStoreLayout.tileWidth, g = ModStoreLayout.gap
        XCTAssertEqual(ModStoreLayout.rowScroll(index: nil), 0)
        XCTAssertEqual(ModStoreLayout.rowScroll(index: 4), 0)
        XCTAssertEqual(ModStoreLayout.rowScroll(index: 5), 5 * (w + g) + w + 28 - ModStoreLayout.clipWidth)
    }

    /// A row says there are more tiles past its right edge while some are hidden there: five fit, the sixth is
    /// past the edge until the row has slid to the last.
    func testARowShowsMoreToTheRightOnlyWhileTilesAreHiddenThere() {
        XCTAssertFalse(ModStoreLayout.moreToTheRight(count: 0, index: nil))
        XCTAssertFalse(ModStoreLayout.moreToTheRight(count: 5, index: nil))
        XCTAssertTrue(ModStoreLayout.moreToTheRight(count: 6, index: nil))
        XCTAssertTrue(ModStoreLayout.moreToTheRight(count: 12, index: 5))
        XCTAssertTrue(ModStoreLayout.moreToTheRight(count: 12, index: 10))
        XCTAssertFalse(ModStoreLayout.moreToTheRight(count: 12, index: 11))
        XCTAssertFalse(ModStoreLayout.moreToTheRight(count: 6, index: 5))
    }
}

final class ModStoreFocusTests: XCTestCase {
    private let counts: [(ModStoreSectionKind, Int)] = [(.sort, 4), (.featured, 3), (.popular, 8), (.game("Z"), 2)]
    private var sections: [ModStoreFocus.Section] { counts.map { ModStoreFocus.Section(kind: $0.0, count: $0.1) } }

    func testDownWalksTheSectionsAndUpLeavesAtTheTop() {
        var focus = ModStoreFocus()
        XCTAssertEqual(focus.kind, .sort)
        XCTAssertTrue(focus.down(in: sections))
        XCTAssertEqual(focus.kind, .featured)
        XCTAssertTrue(focus.down(in: sections))
        XCTAssertTrue(focus.down(in: sections))
        XCTAssertEqual(focus.kind, .game("Z"))
        XCTAssertFalse(focus.down(in: sections), "the last section holds")
        for _ in 0..<3 { XCTAssertTrue(focus.up(in: sections)) }
        XCTAssertFalse(focus.up(in: sections), "Up from the top leaves the store")
    }

    func testEachSectionRemembersItsTile() {
        var focus = ModStoreFocus()
        focus.down(in: sections)
        focus.down(in: sections)
        for _ in 0..<5 { XCTAssertTrue(focus.right(in: sections)) }
        XCTAssertEqual(focus.index, 5)
        focus.up(in: sections)
        XCTAssertEqual(focus.index, 0)
        focus.down(in: sections)
        XCTAssertEqual(focus.index, 5)
        for _ in 0..<5 { focus.right(in: sections) }
        XCTAssertEqual(focus.index, 7)
        XCTAssertFalse(focus.right(in: sections))
        XCTAssertTrue(focus.left(in: sections))
    }

    func testFeaturedWrapsAroundLikeACarousel() {
        var focus = ModStoreFocus()
        focus.down(in: sections)
        XCTAssertTrue(focus.left(in: sections))
        XCTAssertEqual(focus.index, 2)
        XCTAssertTrue(focus.right(in: sections))
        XCTAssertEqual(focus.index, 0)
    }

    func testFocusStaysOnItsSectionWhenRowsArriveAbove() {
        var focus = ModStoreFocus()
        focus.down(in: sections)
        focus.down(in: sections)
        focus.down(in: sections)
        XCTAssertEqual(focus.position(in: sections), 3)
        var more = sections
        more.insert(ModStoreFocus.Section(kind: .category(.characters), count: 4), at: 3)
        focus.settle(in: more)
        XCTAssertEqual(focus.kind, .game("Z"))
        XCTAssertEqual(focus.position(in: more), 4)
    }

    func testAVanishedSectionGivesWayToTheOneAbove() {
        var focus = ModStoreFocus()
        for _ in 0..<3 { focus.down(in: sections) }
        focus.settle(in: Array(sections.prefix(2)))
        XCTAssertEqual(focus.kind, .featured)
        focus.settle(in: [ModStoreFocus.Section(kind: .sort, count: 4), ModStoreFocus.Section(kind: .featured, count: 1)])
        XCTAssertEqual(focus.index, 0, "indexes are clamped to what a section holds")
    }
}

final class ModCatalogSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsAndDropsUntrustedLinks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshots = ModCatalogSnapshots(folder: dir)
        let file = GameBananaFile(id: 9, name: "f.zip", size: 10, downloadURL: URL(string: "https://gamebanana.com/dl/9"),
                                  md5: "x", dateAdded: Date(timeIntervalSince1970: 5))
        let good = AvailableMod(id: 1, rank: 0, name: "One", author: "A", avatarURL: URL(string: "https://evil.example/a.png"),
                                images: [URL(string: "https://images.gamebanana.com/1.jpg")!, URL(string: "http://images.gamebanana.com/2.jpg")!],
                                thumbnailURL: URL(string: "https://images.gamebanana.com/t.jpg"), version: "1",
                                updated: Date(timeIntervalSince1970: 7), pageURL: URL(string: "https://gamebanana.com/mods/1")!,
                                description: "d", likes: 2, downloads: 3, files: [file], category: "Skins",
                                added: Date(timeIntervalSince1970: 4),
                                requirements: [GameBananaRequirement(name: "SMO v1.3", isOptional: true)])
        try snapshots.save([good], gameName: "Zelda", titleID: "0100ABC", gameBananaID: 42, at: Date(timeIntervalSince1970: 100))
        let loaded = try XCTUnwrap(snapshots.load(titleID: "0100abc"))
        XCTAssertEqual(loaded.titleID, "0100ABC", "the cover is matched to your games by title ID")
        XCTAssertEqual(loaded.savedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(loaded.gameName, "Zelda")
        XCTAssertEqual(loaded.gameBananaID, 42)
        let mod = try XCTUnwrap(loaded.mods.first)
        XCTAssertEqual(mod.files, [file])
        XCTAssertEqual(mod.category, "Skins")
        XCTAssertEqual(mod.added, Date(timeIntervalSince1970: 4))
        XCTAssertEqual(mod.requirements, [GameBananaRequirement(name: "SMO v1.3", isOptional: true)])
        XCTAssertNil(mod.avatarURL, "only GameBanana links survive the disk")
        XCTAssertEqual(mod.images, [URL(string: "https://images.gamebanana.com/1.jpg")!])
        XCTAssertNil(snapshots.load(titleID: "0100FFF"))
    }

    func testAModWithoutATrustedPageOrFileIsDropped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshots = ModCatalogSnapshots(folder: dir)
        let badFile = GameBananaFile(id: 9, name: "f.zip", size: 10, downloadURL: URL(string: "https://evil.example/f.zip"), md5: "x")
        let mod = AvailableMod(id: 1, rank: 0, name: "One", author: "A", avatarURL: nil, images: [], thumbnailURL: nil,
                               version: "", updated: Date(), pageURL: URL(string: "https://gamebanana.com/mods/1")!,
                               description: "", likes: 0, downloads: 0, files: [badFile])
        try snapshots.save([mod], gameName: "Z", titleID: "T", gameBananaID: 1, at: Date())
        XCTAssertEqual(snapshots.load(titleID: "T")?.mods, [])
    }
}

final class ModCatalogSnapshotsAllTests: XCTestCase {
    func testLoadAllLeavesOutGamesWhosePageChanged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshots = ModCatalogSnapshots(folder: dir.appendingPathComponent("store"))
        let matches = GameBananaMatchStore(file: dir.appendingPathComponent("matches.json"))
        let page = URL(string: "https://gamebanana.com/games/1")!
        let file = GameBananaFile(id: 1, name: "f.zip", size: 1, downloadURL: URL(string: "https://gamebanana.com/dl/1"), md5: "x")
        let mod = AvailableMod(id: 1, rank: 0, name: "M", author: "A", avatarURL: nil, images: [], thumbnailURL: nil,
                               version: "", updated: Date(), pageURL: URL(string: "https://gamebanana.com/mods/1")!,
                               description: "", likes: 0, downloads: 0, files: [file])
        try matches.set(.game(id: 1, name: "A", profileURL: page), titleID: "AAAA")
        try matches.set(.game(id: 3, name: "B", profileURL: page), titleID: "BBBB")
        try matches.set(.noPage, titleID: "CCCC")
        try snapshots.save([mod], gameName: "A", titleID: "AAAA", gameBananaID: 1)
        try snapshots.save([mod], gameName: "B", titleID: "BBBB", gameBananaID: 2)
        try snapshots.save([mod], gameName: "C", titleID: "CCCC", gameBananaID: 4)
        XCTAssertEqual(snapshots.loadAll(matches: matches).map(\.gameName), ["A"])
    }
}
