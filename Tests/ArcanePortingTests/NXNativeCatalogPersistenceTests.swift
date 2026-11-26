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

    func testOpeningWithAnInheritedRemovalNeverRecoversIntoTheOldLibrary() throws {
        let fm = FileManager.default
        for alreadyCopied in [false, true] {
            for phase in ["intent", "catalog", "trash"] {
                let profile = AppDataProfile(home: dir.appendingPathComponent(UUID().uuidString), isDevelopment: false)
                let old = profile.legacySupportRoot, new = profile.supportRoot
                let (repo, _) = try removalFixture(at: old)
                let workspace = old.appendingPathComponent("workspace")
                let trash = profile.home.appendingPathComponent("trash")
                let target = trash.appendingPathComponent("bucket/workspace")
                try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
                try fm.createDirectory(at: trash, withIntermediateDirectories: true)
                try Data([17, 29]).write(to: workspace.appendingPathComponent("fixture"))
                let game = removalGame(in: old, sources: [])
                let base = try repo.updateNXNativeGames { $0 = [game] }
                let catalog = phase == "intent" ? base : try repo.removeNXNative(id: game.id)
                let journal = old.appendingPathComponent("catalog-removal-pending.json")
                let record = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base.games[0]))
                let item: [String: Any] = ["source": workspace.absoluteString, "target": target.absoluteString,
                    "identity": try removalIdentity(workspace), "origin": try removalIdentity(old), "trash": try removalIdentity(trash)]
                try JSONSerialization.data(withJSONObject: [
                    "version": 1, "original": base.revision.uuidString, "moved": (phase == "intent" ? UUID() : catalog.revision).uuidString,
                    "restored": UUID().uuidString, "record": record, "index": 0, "items": [item],
                ]).write(to: journal)
                if phase == "trash" {
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: false)
                    try fm.moveItem(at: workspace, to: target)
                }
                if alreadyCopied {
                    try fm.copyItem(at: old, to: new)
                    try Data(#"{"version":1,"ready":true,"files":1}"#.utf8).write(to: new.appendingPathComponent(".moved-library.json"))
                }
                let original = try diskTree(old), trashBefore = try diskTree(trash)
                for _ in 0..<2 {
                    try AppData.adoptLegacyLibrary(profile, checks: DevelopmentProfileImporter.portingChecks,
                        legacyPreferences: { [:] }, preferences: { [:] }, savePreferences: { _ in })
                    XCTAssertEqual(try CatalogStore(directory: new).loadOrMigrate().revision, catalog.revision)
                    XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("catalog-removal-from-previous-library.json")),
                                   try Data(contentsOf: journal))
                    XCTAssertEqual(try diskTree(old), original, "old tree changed; earlier copy \(alreadyCopied), phase \(phase)")
                    XCTAssertEqual(try diskTree(trash), trashBefore)
                }
            }
        }
    }

    func testOpeningDoesNotArmAPendingBuildFromTheOldLibrary() throws {
        let fm = FileManager.default
        for copy in ["fresh", "beta3", "preferences interrupted"] {
            for localDestination in [false, true] {
                let profile = AppDataProfile(home: dir.appendingPathComponent(UUID().uuidString), isDevelopment: false)
                let old = profile.legacySupportRoot, new = profile.supportRoot
                let (repo, _) = try removalFixture(at: old)
                let staging = old.appendingPathComponent("Temp/fixture/Waiting.app")
                let final = (localDestination ? old : profile.home).appendingPathComponent("Existing.app")
                for app in [staging, final] {
                    try fm.createDirectory(at: app, withIntermediateDirectories: true)
                    try Data([42]).write(to: app.appendingPathComponent("fixture"))
                }
                var game = removalGame(in: old, sources: [])
                game.url = final
                game.status = .built
                let record = BuildRecord(logPath: "", outputPath: final.path)
                game.pendingInstall = PendingInstall(tempApp: staging, finalApp: final, record: record, toolchain: .init(),
                    expectedDestination: BuildOutputInstaller.expectedDestination(at: final))
                _ = try repo.updateNXNativeGames { $0 = [game] }
                if copy == "beta3" {
                    try fm.copyItem(at: old, to: new)
                    try fm.removeItem(at: new.appendingPathComponent("Temp"))
                    try Data(#"{"version":1,"ready":true,"files":1}"#.utf8).write(to: new.appendingPathComponent(".moved-library.json"))
                }
                let original = try diskTree(old)
                if copy == "preferences interrupted" {
                    XCTAssertThrowsError(try LibraryMove(from: old, to: new).prepare(preferences: { [:] }, savePreferences: { _ in
                        throw CocoaError(.fileWriteUnknown)
                    }))
                    XCTAssertEqual(try diskTree(old), original)
                }
                for attempt in 0..<2 {
                    try AppData.adoptLegacyLibrary(profile, checks: DevelopmentProfileImporter.portingChecks,
                        legacyPreferences: { [:] }, preferences: { [:] }, savePreferences: { _ in })
                    let prepared = try CatalogStore(directory: new).loadForStartup(previousLibrary: old)
                    XCTAssertEqual(prepared.keptPreviousBuild, attempt == 0)
                    let reopened = try XCTUnwrap(prepared.catalog.games.first?.nxnativeGame)
                    XCTAssertNil(reopened.pendingInstall, "staging should stay with the old version: \(copy), local destination \(localDestination)")
                    XCTAssertEqual(reopened.status, .built)
                    XCTAssertEqual(try diskTree(old), original)
                    XCTAssertEqual(try Data(contentsOf: final.appendingPathComponent("fixture")), Data([42]))
                }
            }
        }
    }

    func testOpeningKeepsExternalStagingWithTheProfileThatBuiltIt() throws {
        let fm = FileManager.default
        for alreadyCopied in [false, true] {
            let profile = AppDataProfile(home: dir.appendingPathComponent(UUID().uuidString), isDevelopment: false)
            let old = profile.legacySupportRoot, new = profile.supportRoot
            let apps = profile.home.appendingPathComponent("external/Game apps")
            let temp = BuildScratch.choose(core: old, appFolder: apps) {
                .init(device: $0 == apps ? 2 : 1, canHoldBuilds: true)
            }.temp
            XCTAssertEqual(temp.path, apps.appendingPathComponent(".nxlibrary-build/Temp").path)
            func pending(_ name: String, logFrom root: URL?) throws -> PendingInstall {
                let stage = temp.appendingPathComponent(UUID().uuidString)
                let final = apps.appendingPathComponent("\(name).app")
                let held = stage.appendingPathComponent(final.lastPathComponent)
                for app in [held, final] {
                    try fm.createDirectory(at: app, withIntermediateDirectories: true)
                    try Data(app == held ? [42] : [23]).write(to: app.appendingPathComponent("fixture"))
                }
                try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: stage.path)
                // Even a missing log still names the profile that produced the build.
                return PendingInstall(tempApp: held, finalApp: final,
                    record: BuildRecord(logPath: root?.appendingPathComponent("Logs/\(name).log").path, outputPath: final.path),
                    toolchain: .init(), expectedDestination: BuildOutputInstaller.expectedDestination(at: final))
            }
            let inherited = try pending("Old", logFrom: alreadyCopied ? nil : old)
            var game = removalGame(in: old, sources: [])
            game.url = inherited.finalApp
            game.status = .built
            game.pendingInstall = inherited
            let (repo, _) = try removalFixture(at: old)
            _ = try repo.updateNXNativeGames { $0 = [game] }
            if alreadyCopied {
                try fm.copyItem(at: old, to: new)
                try Data(#"{"version":1,"ready":true,"files":1}"#.utf8).write(to: new.appendingPathComponent(".moved-library.json"))
            }
            let original = try diskTree(old)
            try AppData.adoptLegacyLibrary(profile, checks: DevelopmentProfileImporter.portingChecks,
                legacyPreferences: { [:] }, preferences: { [:] }, savePreferences: { _ in })

            let current = try pending("New", logFrom: new)
            var other = PortedGame(name: "New", url: current.finalApp, platform: .macApp, sizeBytes: 1,
                                   modificationDate: .now, titleId: "0100000000000002")
            other.status = .built
            other.pendingInstall = current
            let store = CatalogStore(directory: new)
            _ = try CatalogRepository(store: store).updateNXNativeGames { $0.append(other) }
            let external = try diskTree(apps)
            for attempt in 0..<2 {
                let prepared = try store.loadForStartup(previousLibrary: old)
                XCTAssertEqual(prepared.keptPreviousBuild, attempt == 0)
                let games = prepared.catalog.nxnativeGames
                let previous = try XCTUnwrap(games.first { $0.id == game.id })
                XCTAssertNil(previous.pendingInstall)
                XCTAssertEqual(previous.status, .built)
                XCTAssertEqual(games.first { $0.id == other.id }?.pendingInstall, current)
                XCTAssertEqual(profile.automaticStagingFolders(appFolders: [apps]).map(\.path),
                               [new.appendingPathComponent("Temp").path])
                XCTAssertEqual(try diskTree(old), original)
                XCTAssertEqual(try diskTree(apps), external)
            }
        }
    }

    private func diskTree(_ root: URL) throws -> [String: [String]] {
        let fm = FileManager.default
        let names = [""] + (try XCTUnwrap(fm.subpaths(atPath: root.path)))
        return try Dictionary(uniqueKeysWithValues: names.map { name in
            let path = root.appendingPathComponent(name).path
            var node = stat()
            guard lstat(path, &node) == 0 else { throw POSIXError(.ENOENT) }
            func date(_ time: timespec) -> String { "\(time.tv_sec).\(time.tv_nsec)" }
            let bytes = node.st_mode & S_IFMT == S_IFREG ? try Data(contentsOf: URL(fileURLWithPath: path)).base64EncodedString() : ""
            // APFS may update the access timestamp on our own read. Compare all dates that do not measure reads.
            return (name, [String(node.st_ino), String(node.st_mode), date(node.st_birthtimespec),
                           date(node.st_mtimespec), date(node.st_ctimespec), bytes])
        })
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

    func testScanUsesTheRecoveredAppsProvenanceInsteadOfTheMissingAppsBuildRecord() throws {
        let store = CatalogRepository(store: CatalogStore(directory: dir.appendingPathComponent("store")))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        let titleID = "0100000000000001"
        var old = PortedGame(name: "Game", url: dir.appendingPathComponent("Old.app"), platform: .macApp,
                             sizeBytes: 1, modificationDate: Date(), titleId: titleID, versionString: "1.0")
        old.status = .builtSourcesMissing
        old.isFavorite = true
        old.toolchain = ToolchainInfo(engineCommit: "old", verified: true)
        old.lastBuild = BuildRecord(engineCommit: "old", toolchainVerified: true)
        try store.updateNXNativeGames { $0 = [old] }

        let recoveredApp = dir.appendingPathComponent("Recovered.app")
        try FileManager.default.createDirectory(at: recoveredApp, withIntermediateDirectories: true)
        var observed = PortedGame(name: "Game", url: recoveredApp, platform: .macApp,
                                  sizeBytes: 2, modificationDate: Date(), titleId: titleID, versionString: "2.0")
        observed.status = .builtSourcesMissing
        observed.toolchain = ToolchainInfo(engineCommit: "recovered")
        let merged = try XCTUnwrap(try store.mergeNXNative(scanned: [observed]).nxnativeGames.first)
        XCTAssertEqual(merged.id, old.id)
        XCTAssertTrue(merged.isFavorite)
        XCTAssertEqual(merged.url, recoveredApp)
        XCTAssertEqual(merged.versionString, "2.0")
        XCTAssertEqual(merged.toolchain, observed.toolchain)
        XCTAssertNil(merged.lastBuild)
    }

    func testCloudImportDefersSourcesForATitleWithAnActiveLease() async throws {
        let title = "0100000000004000", folder = "Orbit [\(title)]"
        let temp = dir!
        let repo = CatalogRepository(store: .init(directory: temp))
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, _, _ in
            throw StorageBackendError.invalidConfiguration
        }
        let archive = CloudGameArchive(backend: backend)
        let source = GameFileItem(url: URL(fileURLWithPath: "/\(folder)/Orbit.nsp"), kind: .base,
                                  titleId: title, sizeBytes: 4)
        let encoded = try XCTUnwrap(CloudGameSources.ArchivedSelection(folder: folder, files: [source], titleID: title))
        let manifest = CloudGameManifest(version: 2, titleID: title, createdAt: .now, artifacts: [],
                                         gameName: "Orbit", sourceSelection: encoded)
        let lease = try await archive.beginBuild(titleID: title)
        let busy = try repo.importCloudGames([manifest], discovered: [], in: temp, sourceRoot: temp, leases: archive.leases)
        XCTAssertTrue(busy.nxnativeGames.isEmpty, "Import must not mutate a title while a build or transfer holds its lease")
        await archive.endBuild(titleID: title, token: lease)
        let available = try repo.importCloudGames([manifest], discovered: [], in: temp, sourceRoot: temp, leases: archive.leases)
        XCTAssertEqual(available.nxnativeGames.map(\.titleId), [title])
    }

    func testCloudAppRestoreKeepsReferenceSourceProvenanceAfterReload() throws {
        let repository = CatalogRepository(store: CatalogStore(directory: dir))
        let title = "0100000000004000", reference = "1FixtureReference"
        let candidate = cloudSources(title: title, folder: "Original")
        let imported = try repository.importCloudGames([cloudApp(title: title)], discovered: [candidate],
            in: dir, sourceRoot: dir, referenceFolder: reference)
        let game = try XCTUnwrap(imported.nxnativeGames.first)
        XCTAssertEqual(game.sources.count, 1)

        let restoredApp = dir.appendingPathComponent("Restored.app", isDirectory: true)
        try writeCloudAppFixture(at: restoredApp, title: title)
        _ = try repository.recordCloudAppRestore(id: game.id, at: restoredApp)
        let restored = try XCTUnwrap(try repository.load().nxnativeGames.first)
        XCTAssertEqual(restored.id, game.id)
        XCTAssertEqual(restored.url, restoredApp)
        XCTAssertTrue(restored.isPlayableLocally)
        XCTAssertEqual(restored.sources, game.sources)
        XCTAssertEqual(restored.discoveredCloudSourceDirectory, candidate.directory)
        XCTAssertNil(restored.cloudReferenceFolder)
        XCTAssertEqual(restored.cloudSourcesReferenceFolder, reference)

        let updated = cloudSources(title: title, folder: "Original", updated: true)
        let refreshed = try repository.importCloudGames([], discovered: [updated],
            in: dir, sourceRoot: dir, referenceFolder: reference)
        XCTAssertEqual(refreshed.nxnativeGames.first?.url, restoredApp)
        XCTAssertEqual(refreshed.nxnativeGames.first?.sources.map(\.kind), [.base, .update])
    }

    func testCloudSourceRefreshAdoptsUpdateAndRenameWithoutReplacingPersonalization() throws {
        let repository = CatalogRepository(store: CatalogStore(directory: dir))
        let title = "0100000000004000", reference = "1FixtureReference"
        var candidate = cloudSources(title: title, folder: "Original")
        let imported = try repository.importCloudGames([], discovered: [candidate],
            in: dir, sourceRoot: dir, referenceFolder: reference)
        let game = try XCTUnwrap(imported.nxnativeGames.first)
        let customized = try repository.updateNXNative(id: game.id) {
            $0.isFavorite = true
            $0.isHidden = true
            $0.settings.metalHUD = true
        }

        for folder in ["Original", "Renamed"] {
            candidate = cloudSources(title: title, folder: folder, updated: true)
            _ = try repository.importCloudGames([], discovered: [candidate],
                in: dir, sourceRoot: dir, referenceFolder: reference)
            let saved = try repository.load()
            let refreshed = try XCTUnwrap(saved.nxnativeGames.first)
            XCTAssertEqual(saved.nxnativeGames.count, 1)
            XCTAssertEqual(refreshed.id, game.id)
            XCTAssertEqual(refreshed.discoveredCloudSourceDirectory, candidate.directory)
            XCTAssertNil(refreshed.cloudReferenceFolder)
            XCTAssertEqual(refreshed.cloudSourcesReferenceFolder, reference)
            XCTAssertEqual(refreshed.sources.map(\.kind), [.base, .update])
            XCTAssertTrue(candidate.matches(refreshed.sources,
                in: CloudGameSources.importedFolder(for: game.id, in: dir)))
            XCTAssertTrue(refreshed.isFavorite)
            XCTAssertTrue(refreshed.isHidden)
            XCTAssertTrue(refreshed.settings.metalHUD)
            XCTAssertEqual(saved.games.first?.personalizationReference, customized.games.first?.personalizationReference)
        }
    }

    func testManifestOnlySourceRefreshAdoptsRenameWithoutReplacingLocalSelection() throws {
        let repository = CatalogRepository(store: CatalogStore(directory: dir))
        let title = "0400123400000002", folder = "Orbit [\(title)]"
        let program = NUPProgramSelection(programID: 0x0400123400000002, applicationID: 0x0400123400000000,
                                          addOnContentBaseID: 0x0400123400001000)
        func manifest(_ filename: String, at time: TimeInterval) throws -> CloudGameManifest {
            let source = GameFileItem(url: URL(fileURLWithPath: "/fixture/\(filename)"), kind: .base, titleId: title,
                                      sizeBytes: 7, sourceLayout: .container, nupProgram: program)
            let selection = try XCTUnwrap(CloudGameSources.ArchivedSelection(folder: folder, files: [source], titleID: title))
            return .init(version: 2, titleID: title, createdAt: Date(timeIntervalSince1970: time), artifacts: [],
                         gameName: "Orbit", sourceSelection: selection)
        }
        let imported = try repository.importCloudGames([manifest("Original.nup", at: 1)], in: dir, sourceRoot: dir)
        let game = try XCTUnwrap(imported.nxnativeGames.first)
        _ = try repository.updateNXNative(id: game.id) { $0.isFavorite = true }

        let otherProvider = try repository.importCloudGames([manifest("Reference.nup", at: 2)], in: dir,
                                                             sourceRoot: dir, referenceFolder: "1FixtureReference")
        XCTAssertEqual(otherProvider.nxnativeGames.first?.sources, game.sources)
        let refreshed = try repository.importCloudGames([manifest("Renamed.nup", at: 3)], in: dir, sourceRoot: dir)
        let updated = try XCTUnwrap(refreshed.nxnativeGames.first)
        XCTAssertEqual(updated.id, game.id)
        XCTAssertTrue(updated.isFavorite)
        XCTAssertEqual(updated.sources.first?.url.lastPathComponent, "Renamed.nup")
        XCTAssertEqual(updated.sources.first?.nupProgram, program)
        XCTAssertNil(updated.discoveredCloudSourceDirectory)
        let unchanged = try repository.importCloudGames([manifest("Renamed.nup", at: 3)], in: dir, sourceRoot: dir)
        XCTAssertEqual(unchanged.revision, refreshed.revision)

        let local = try XCTUnwrap(updated.sources.first?.url)
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([42]).write(to: local)
        let kept = try repository.importCloudGames([manifest("Next.nup", at: 4)], in: dir, sourceRoot: dir)
        XCTAssertEqual(kept.nxnativeGames.first?.sources, updated.sources)
        XCTAssertEqual(try Data(contentsOf: local), Data([42]))
    }

    func testCloudSourceRefreshKeepsEvenAPartlyDownloadedLocalSelection() throws {
        let repository = CatalogRepository(store: CatalogStore(directory: dir))
        let title = "0100000000004000", reference = "1FixtureReference"
        let original = cloudSources(title: title, folder: "Original", updated: true)
        let imported = try repository.importCloudGames([], discovered: [original],
            in: dir, sourceRoot: dir, referenceFolder: reference)
        let game = try XCTUnwrap(imported.nxnativeGames.first)
        let base = try XCTUnwrap(game.sources.first?.url)
        let update = try XCTUnwrap(game.sources.last?.url)
        let bytes = Data([42])
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: base)
        XCTAssertFalse(FileManager.default.fileExists(atPath: update.path))

        _ = try repository.importCloudGames([], discovered: [cloudSources(title: title, folder: "Changed")],
            in: dir, sourceRoot: dir, referenceFolder: reference)
        XCTAssertEqual(try repository.load().games, imported.games)
        XCTAssertEqual(try Data(contentsOf: base), bytes)
    }

    func testUnfollowKeepsTheMatchingLocalAppBeforeTheNextScan() throws {
        let repository = CatalogRepository(store: CatalogStore(directory: dir))
        let title = "0100000000004000", reference = "1FixtureReference"
        let imported = try repository.importCloudGames([cloudApp(title: title)], in: dir,
            sourceRoot: dir, referenceFolder: reference)
        let game = try XCTUnwrap(imported.nxnativeGames.first)
        let customized = try repository.updateNXNative(id: game.id) { $0.isFavorite = true }
        try writeCloudAppFixture(at: game.url, title: title)

        _ = try repository.forgetCloudReference(reference)
        let saved = try repository.load()
        let kept = try XCTUnwrap(saved.nxnativeGames.first)
        XCTAssertEqual(kept.id, game.id)
        XCTAssertEqual(kept.url, game.url)
        XCTAssertTrue(kept.isFavorite)
        XCTAssertEqual(saved.games.first?.personalizationReference, customized.games.first?.personalizationReference)
        XCTAssertEqual(ImportService.titleID(in: try XCTUnwrap(ImportService.info(at: game.url))), title)
    }

    func testUnfollowDoesNotForgetAnAppWhenLocalAccessIsUncertain() throws {
        let repository = CatalogRepository(store: CatalogStore(directory: dir))
        let title = "0100000000004000", reference = "1FixtureReference"
        let apps = dir.appendingPathComponent("Unavailable", isDirectory: true)
        let imported = try repository.importCloudGames([cloudApp(title: title)], in: apps,
            sourceRoot: dir, referenceFolder: reference)
        let game = try XCTUnwrap(imported.nxnativeGames.first)
        // A loop yields a lookup error even for users who can bypass mode-bit restrictions.
        try FileManager.default.createSymbolicLink(atPath: apps.path, withDestinationPath: apps.path)
        var node = stat()
        let lookup = lstat(game.url.path, &node)
        let lookupError = errno
        XCTAssertEqual(lookup, -1)
        XCTAssertEqual(lookupError, ELOOP)

        _ = try repository.forgetCloudReference(reference)
        XCTAssertEqual(try repository.load().games, imported.games)
    }

    private func cloudApp(title: String) -> CloudGameManifest {
        let app = CloudGameManifest.Artifact(kind: .app, unpackedSize: 4, entryCount: 1, inventorySHA256: "fixture",
            engineCommit: nil, shaderChain: nil, options: [:])
        return .init(version: 2, titleID: title, createdAt: .distantPast, artifacts: [app], bundleName: "Fixture.app")
    }

    private func cloudSources(title: String, folder: String, updated: Bool = false) -> CloudGameSources.DiscoveredGame {
        var files: [GameFileItem] = [.init(url: URL(fileURLWithPath: "/Fixture.nsp"), kind: .base, titleId: title, sizeBytes: 1)]
        if updated {
            files.append(.init(url: URL(fileURLWithPath: "/Update.nsp"), kind: .update,
                titleId: "0100000000004800", sizeBytes: 2))
        }
        return .init(titleID: title, name: "Fixture", directory: "GameFiles/\(folder) [\(title)]", files: files)
    }

    private func writeCloudAppFixture(at app: URL, title: String) throws {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "org.nxnative.\(title.lowercased())", "DMTitleID": title]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
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
