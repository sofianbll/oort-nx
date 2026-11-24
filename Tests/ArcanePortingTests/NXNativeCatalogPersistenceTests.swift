import Darwin
import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class NXNativeCatalogPersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXLibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRemovalRefusesRepeatedPhysicalSourcesBeforePublication() throws {
        let fm = FileManager.default
        for keeping in [true, false] {
            for names in [("fixture.nsp", "FIXTURE.nsp"), ("café.nsp", "cafe\u{301}.nsp"),
                          ("first.nsp", "hardlink.nsp"), ("same.nsp", "same.nsp")] {
                let root = dir.appendingPathComponent(UUID().uuidString)
                let (repo, trash) = try removalFixture(at: root)
                let first = root.appendingPathComponent(names.0), second = root.appendingPathComponent(names.1)
                let bytes = names.0 == "first.nsp" ? Data() : Data([17])
                try bytes.write(to: first)
                if names.1 == "hardlink.nsp" { try fm.linkItem(at: first, to: second) }
                guard fm.fileExists(atPath: second.path) else { continue } // Case-equivalence depends on the volume.
                let game = removalGame(in: root, sources: [first, second])
                let base = try repo.updateNXNativeGames { $0 = [game] }
                var detached = game
                detached.sources = []
                XCTAssertThrowsError(try repo.removeNXNativeFiles(id: game.id, from: base, files: [first, second],
                                                                 keeping: keeping ? detached : nil) {
                    XCTFail("An ambiguous selection reached the Trash phase")
                    throw CocoaError(.fileWriteNoPermission)
                }) { error in
                    guard case .duplicateFiles? = error as? CatalogRemovalFailure else {
                        return XCTFail("Unexpected error \(error)")
                    }
                }
                XCTAssertEqual(try repo.load(), base)
                XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("catalog-removal-pending.json").path))
                XCTAssertEqual(try fm.contentsOfDirectory(atPath: trash.path), [])
                XCTAssertEqual(try Data(contentsOf: first), bytes)
                XCTAssertEqual(try Data(contentsOf: second), bytes)
            }
        }
    }

    func testRemovalAllowsDistinctCaseVariantsAndZeroByteFilesOnCaseSensitiveAPFS() throws {
        guard let path = ProcessInfo.processInfo.environment["NX_TEST_CASE_SENSITIVE_ROOT"] else {
            throw XCTSkip("Set NX_TEST_CASE_SENSITIVE_ROOT to a disposable case-sensitive APFS mount")
        }
        let root = URL(fileURLWithPath: path).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (repo, trash) = try removalFixture(at: root)
        let first = root.appendingPathComponent("fixture.nsp"), second = root.appendingPathComponent("FIXTURE.nsp")
        try Data().write(to: first, options: .withoutOverwriting)
        try Data([42]).write(to: second, options: .withoutOverwriting)
        var game = removalGame(in: root, sources: [first, second])
        let base = try repo.updateNXNativeGames { $0 = [game] }
        let nfc = root.appendingPathComponent("café.nsp"), nfd = root.appendingPathComponent("cafe\u{301}.nsp")
        try Data([3]).write(to: nfc)
        XCTAssertThrowsError(try repo.removeNXNativeFiles(id: game.id, from: base, files: [nfc, nfd], keeping: game) {
            XCTFail("APFS case sensitivity does not make the two Unicode spellings distinct")
            throw CocoaError(.fileWriteNoPermission)
        }) { error in
            guard case .duplicateFiles? = error as? CatalogRemovalFailure else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        game.sources = []
        _ = try repo.removeNXNativeFiles(id: game.id, from: base, files: [first, second], keeping: game) {}
        let fm = FileManager.default
        XCTAssertEqual(try repo.load().nxnativeGames.first?.sources, [])
        XCTAssertFalse(fm.fileExists(atPath: first.path))
        XCTAssertFalse(fm.fileExists(atPath: second.path))
        let buckets = try fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
        let moved = try buckets.flatMap { try fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
        XCTAssertEqual(moved.count, 2)
        XCTAssertEqual(try moved.map { try Data(contentsOf: $0).count }.sorted(), [0, 1])
    }

    func testReopeningLegacyRemovalRestoresAliasesWithoutOverwritingOrInventingMissingLinks() throws {
        let fm = FileManager.default
        for (firstName, secondName, obstruction) in [
            ("fixture.nsp", "FIXTURE.nsp", "none"),
            ("café.nsp", "cafe\u{301}.nsp", "none"),
            ("café.nsp", "cafe\u{301}.nsp", "replacement"),
            ("first.nsp", "hardlink.nsp", "missing link"),
        ] {
            let root = dir.appendingPathComponent(UUID().uuidString)
            let (repo, trash) = try removalFixture(at: root)
            let first = root.appendingPathComponent(firstName), second = root.appendingPathComponent(secondName)
            let bytes = firstName == "café.nsp" ? Data() : Data([42])
            try bytes.write(to: first)
            if obstruction == "missing link" { try fm.linkItem(at: first, to: second) }
            guard fm.fileExists(atPath: second.path) else { continue }
            let game = removalGame(in: root, sources: [first, second])
            let base = try repo.updateNXNativeGames { $0 = [game] }
            let moved = try repo.removeNXNative(id: game.id)
            let journal = root.appendingPathComponent("catalog-removal-pending.json")
            let targets = [first, second].enumerated().map { index, source in
                trash.appendingPathComponent("bucket-\(index)").appendingPathComponent(source.lastPathComponent)
            }
            let items = try zip([first, second], targets).map { source, target -> [String: Any] in
                ["source": source.absoluteString, "target": target.absoluteString, "identity": try removalIdentity(source),
                 "origin": try removalIdentity(root), "trash": try removalIdentity(trash)]
            }
            let record = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base.games[0]))
            try JSONSerialization.data(withJSONObject: [
                "version": 1, "original": base.revision.uuidString, "moved": moved.revision.uuidString,
                "restored": UUID().uuidString, "record": record, "index": 0, "items": items,
            ]).write(to: journal)
            try fm.createDirectory(at: targets[0].deletingLastPathComponent(), withIntermediateDirectories: false)
            try fm.moveItem(at: first, to: targets[0])
            if obstruction == "replacement" { try Data([99]).write(to: first) }
            if obstruction == "missing link" { try fm.removeItem(at: second) }
            if obstruction == "none" {
                let reopened = try repo.load()
                XCTAssertEqual(reopened.games, base.games)
                XCTAssertEqual(reopened.cloudImportExclusions, base.cloudImportExclusions)
                XCTAssertFalse(fm.fileExists(atPath: journal.path))
                XCTAssertEqual(try Data(contentsOf: first), bytes)
                XCTAssertEqual(try Data(contentsOf: second), bytes)
                XCTAssertEqual(try fm.contentsOfDirectory(atPath: trash.path), [])
            } else {
                XCTAssertThrowsError(try repo.load()) { XCTAssertTrue($0 is CatalogRemovalRecovery) }
                XCTAssertTrue(fm.fileExists(atPath: journal.path))
                XCTAssertEqual(try Data(contentsOf: first), obstruction == "replacement" ? Data([99]) : bytes)
                if obstruction == "replacement" { XCTAssertEqual(try Data(contentsOf: targets[0]), bytes) }
                else { XCTAssertFalse(fm.fileExists(atPath: second.path)) }
            }
        }
    }

    private func removalFixture(at root: URL) throws -> (CatalogRepository, URL) {
        let trash = root.appendingPathComponent("Fixture Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let store = CatalogStore(directory: root, publication: .atomic, kinds: .standard, legacy: nil,
                                 removalTrashDirectory: { _ in trash })
        return (CatalogRepository(store: store), trash)
    }

    private func removalGame(in root: URL, sources: [URL]) -> PortedGame {
        var game = PortedGame(name: "Fixture", url: root.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: .now, titleId: "0100000000000001")
        game.sources = sources.map { .init(url: $0, kind: .base, sizeBytes: 1) }
        return game
    }

    // On-disk version-1 journal fixture, independent of the current writer.
    private func removalIdentity(_ url: URL) throws -> [String: Any] {
        var node = stat()
        guard lstat(url.path, &node) == 0 else { throw CocoaError(.fileReadNoSuchFile) }
        return ["device": node.st_dev, "inode": node.st_ino, "type": node.st_mode & mode_t(S_IFMT),
                "birthSeconds": node.st_birthtimespec.tv_sec, "birthNanoseconds": node.st_birthtimespec.tv_nsec]
    }

    func testExplicitSelectionReplacesExistingSourcesAndSurvivesLaterScans() throws {
        let store = CatalogRepository(store: CatalogStore(directory: dir.appendingPathComponent("catalog")))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        let app = dir.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let oldSource = dir.appendingPathComponent("old.nsp"), newSource = dir.appendingPathComponent("new.nsp")
        try Data("old".utf8).write(to: oldSource)
        try Data("new".utf8).write(to: newSource)
        var old = PortedGame(name: "Game", url: app, platform: .macApp, sizeBytes: 1,
                             modificationDate: Date(), titleId: "0100000000000001")
        old.status = .built
        old.isFavorite = true
        old.settings.language = "it"
        old.sources = [GameFileItem(url: oldSource, kind: .base, sizeBytes: 3)]
        old.workspacePath = dir.appendingPathComponent("old-workspace").path
        old.buildCachePath = dir.appendingPathComponent("old-cache").path
        try store.updateNXNativeGames { $0 = [old] }
        var selected = old
        selected.url = dir.appendingPathComponent("new-workspace")
        selected.sources = [GameFileItem(url: newSource, kind: .base, sizeBytes: 3)]
        selected.workspacePath = selected.url.path
        selected.buildCachePath = dir.appendingPathComponent("new-cache").path
        let result = try XCTUnwrap(try store.mergeNXNative(scanned: [selected], replacingSources: true).nxnativeGames.first)
        XCTAssertEqual(result.sources, selected.sources)
        XCTAssertEqual(result.workspacePath, selected.workspacePath)
        XCTAssertEqual(result.buildCachePath, selected.buildCachePath)
        XCTAssertEqual(result.url, app)
        XCTAssertEqual(result.id, old.id)
        XCTAssertEqual(result.settings, old.settings)
        XCTAssertTrue(result.isFavorite)
        var scanned = selected
        scanned.sources = []
        let refreshed = try XCTUnwrap(try store.mergeNXNative(scanned: [scanned]).nxnativeGames.first)
        XCTAssertEqual(refreshed.sources, selected.sources)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldSource.path), "Replacing a selection never deletes sources")
    }

    func testCatalogSaveLoadAndMergePreservesSettings() throws {
        let store = CatalogRepository(store: CatalogStore(directory: dir))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        var game = PortedGame(
            name: "The Legend of Zelda: Breath of the Wild",
            url: URL(fileURLWithPath: "/tmp/game.app"),
            platform: .macApp,
            sizeBytes: 17,
            modificationDate: Date(timeIntervalSince1970: 1),
            bundleId: "org.nxnative.01007ef00011e000",
            titleId: "01007EF00011E000",
            versionString: "1.9.0"
        )
        game.status = .builtSourcesMissing
        game.settings.metalHUD = true
        try store.updateNXNativeGames { $0 = [game] }
        let loaded = try store.load()
        XCTAssertEqual(loaded.nxnativeGames.first?.status, .builtSourcesMissing)
        XCTAssertEqual(loaded.nxnativeGames.first?.settings.metalHUD, true)

        var scanned = game
        scanned.status = .built
        scanned.settings = GameRuntimeConfig()
        let merged = try store.mergeNXNative(scanned: [scanned])
        XCTAssertEqual(merged.nxnativeGames.first?.status, .built)
        XCTAssertEqual(merged.nxnativeGames.first?.settings.metalHUD, true)
        XCTAssertEqual(merged.nxnativeGames.count, 1)
    }

    func testMergeKeepsFavoriteAndHidden() throws {
        let store = CatalogRepository(store: CatalogStore(directory: dir))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/g.app"),
                              platform: .macApp, sizeBytes: 1,
                              modificationDate: Date(timeIntervalSince1970: 1),
                              titleId: "0100000000000001")
        game.isFavorite = true
        game.isHidden = true
        try store.updateNXNativeGames { $0 = [game] }
        var scanned = game
        scanned.isFavorite = false
        scanned.isHidden = false
        let merged = try store.mergeNXNative(scanned: [scanned])
        XCTAssertEqual(merged.nxnativeGames.first?.isFavorite, true)
        XCTAssertEqual(merged.nxnativeGames.first?.isHidden, true)
    }

    func testRepeatedScansKeepPendingInstallAndFailureDetails() throws {
        let apps = dir.appendingPathComponent("Applications")
        let app = apps.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "org.nxnative.0100000000000001",
                    "DMTitleID": "0100000000000001", "CFBundleName": "Game",
                    "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let importer = ImportService()
        let store = CatalogRepository(store: CatalogStore(directory: dir.appendingPathComponent("store")))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        var game = try XCTUnwrap(importer.scan(directories: [apps]).first.map { importer.makeGame(from: $0) })
        game.isFavorite = true
        game.settings.metalHUD = true
        game.pendingInstall = PendingInstall(tempApp: dir.appendingPathComponent("waiting/Game.app"), finalApp: app,
            record: BuildRecord(startedAt: Date(timeIntervalSince1970: 1), engineCommit: "2716f78"),
            toolchain: ToolchainInfo(engineCommit: "2716f78"))
        game.portingFailure = .failed
        game.portingFailureReason = PortingFailureReason(kind: .diskFull, detail: "Synthetic failure")
        try store.updateNXNativeGames { $0 = [game] }

        for _ in 0..<3 {
            let scanned = importer.scan(directories: [apps]).map { importer.makeGame(from: $0) }
            let merged = try store.mergeNXNative(scanned: scanned)
            let saved = try XCTUnwrap(store.load().nxnativeGames.first)
            XCTAssertEqual(merged.nxnativeGames.count, 1)
            XCTAssertEqual(saved.id, game.id)
            XCTAssertEqual(saved.pendingInstall, game.pendingInstall)
            XCTAssertEqual(saved.portingFailure, game.portingFailure)
            XCTAssertEqual(saved.portingFailureReason, game.portingFailureReason)
            XCTAssertEqual(saved.settings, game.settings)
            XCTAssertTrue(saved.isFavorite)
        }
    }

    func testMergePreservesBuildMetadataAndMarksMissingSources() throws {
        let store = CatalogRepository(store: CatalogStore(directory: dir))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        let sourceFile = dir.appendingPathComponent("Game [0100000000010000].nsp")
        try Data("x".utf8).write(to: sourceFile)
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/G.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                              titleId: "0100000000010000")
        game.status = .built
        game.sources = [GameFileItem(url: sourceFile, kind: .base,
                                     titleId: "0100000000010000", sizeBytes: 1)]
        game.toolchain = ToolchainInfo(engineCommit: "06b7b3e",
                                       metalVersion: "32023.921",
                                       xcodeVersion: "27.1", verified: true)
        game.lastBuild = BuildRecord(endedAt: Date(), exitCode: 0,
                                     outputPath: "/tmp/G.app", toolchainVerified: true)
        try store.updateNXNativeGames { $0 = [game] }

        var imported = game
        imported.status = .builtSourcesMissing
        imported.toolchain = ToolchainInfo(note: "Imported build; build record unavailable")
        imported.lastBuild = nil
        imported.sources = []

        let merged = try store.mergeNXNative(scanned: [imported])
        XCTAssertEqual(merged.nxnativeGames.first?.status, .built)
        XCTAssertEqual(merged.nxnativeGames.first?.toolchain.verified, true)
        XCTAssertEqual(merged.nxnativeGames.first?.lastBuild?.exitCode, 0)

        try FileManager.default.removeItem(at: sourceFile)
        let afterDeletion = try store.mergeNXNative(scanned: [imported])
        XCTAssertEqual(afterDeletion.nxnativeGames.first?.status, .builtSourcesMissing)
        XCTAssertEqual(afterDeletion.nxnativeGames.first?.toolchain.verified, true)
    }

    func testAttachingSourcesKeepsTheImportedAppURL() throws {
        let store = CatalogRepository(store: CatalogStore(directory: dir))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        let app = dir.appendingPathComponent("Old.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let sourceFile = dir.appendingPathComponent("Game [0100000000010000].nsp")
        try Data("x".utf8).write(to: sourceFile)

        var imported = PortedGame(name: "G", url: app, platform: .macApp,
                                  sizeBytes: 17, modificationDate: Date(),
                                  bundleId: "org.nxnative.0100000000010000",
                                  titleId: "0100000000010000",
                                  versionString: "1.9.0")
        imported.status = .builtSourcesMissing
        try store.updateNXNativeGames { $0 = [imported] }

        var added = PortedGame(name: "G", url: dir.appendingPathComponent("workspace"),
                               platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                               titleId: "0100000000010000")
        added.status = .notBuilt
        added.sources = [GameFileItem(url: sourceFile, kind: .base,
                                      titleId: "0100000000010000", sizeBytes: 1)]
        added.bundleId = "org.nxnative.0100000000010000"
        added.versionString = "65536"

        let merged = try store.mergeNXNative(scanned: [added])
        XCTAssertEqual(merged.nxnativeGames.first?.url, app)
        XCTAssertEqual(merged.nxnativeGames.first?.status, .built)
        XCTAssertEqual(merged.nxnativeGames.first?.versionString, "1.9.0")
        XCTAssertEqual(merged.nxnativeGames.first?.bundleId, "org.nxnative.0100000000010000")
    }

    func testLocateSourcesReplacesMissingRecordedSources() throws {
        let store = CatalogRepository(store: CatalogStore(directory: dir))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        let app = dir.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let oldSource = dir.appendingPathComponent("old.nsp")
        let newSource = dir.appendingPathComponent("new.nsp")
        try Data("new".utf8).write(to: newSource)

        var old = PortedGame(name: "G", url: app, platform: .macApp,
                             sizeBytes: 1, modificationDate: Date(),
                             titleId: "0100000000010000")
        old.status = .builtSourcesMissing
        old.sources = [GameFileItem(url: oldSource, kind: .base,
                                    titleId: "0100000000010000", sizeBytes: 1)]
        try store.updateNXNativeGames { $0 = [old] }

        var scanned = PortedGame(name: "G", url: dir.appendingPathComponent("workspace"),
                                 platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                                 titleId: "0100000000010000")
        scanned.status = .notBuilt
        scanned.sources = [GameFileItem(url: newSource, kind: .base,
                                        titleId: "0100000000010000", sizeBytes: 1)]

        let merged = try store.mergeNXNative(scanned: [scanned])
        XCTAssertEqual(merged.nxnativeGames.first?.sources.first?.url, newSource)
        XCTAssertEqual(merged.nxnativeGames.first?.status, .built)
        XCTAssertEqual(merged.nxnativeGames.first?.url, app)
    }

    func testMergeTitleIdsCaseInsensitively() throws {
        let store = CatalogRepository(store: CatalogStore(directory: dir))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        var old = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/G.app"),
                             platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                             titleId: "01007EF00011E000")
        old.status = .builtSourcesMissing
        try store.updateNXNativeGames { $0 = [old] }

        var scanned = old
        scanned.titleId = "01007ef00011e000"
        scanned.status = .builtSourcesMissing
        let merged = try store.mergeNXNative(scanned: [scanned])
        XCTAssertEqual(merged.nxnativeGames.count, 1)
        XCTAssertEqual(merged.nxnativeGames.first?.titleId, "01007ef00011e000")
    }
}
