import XCTest
@testable import OortLibrary

/// Synthetic library folders in a throwaway home: the paths a copy must not leave in the old folder.
final class LibraryPathsTests: XCTestCase {
    private var home: URL!
    private var old: URL { support("NXLibrary") }
    private var new: URL { support("Oort NX") }
    private var preferences: [String: Any] = [:]
    private let fm = FileManager.default

    private func support(_ name: String) -> URL { home.appendingPathComponent("Library/Application Support/" + name, isDirectory: true) }

    override func setUpWithError() throws {
        // An accented account name, as macOS may spell it composed or decomposed.
        home = fm.temporaryDirectory.appendingPathComponent("paths-\(UUID())/Zoé", isDirectory: true)
        preferences = [:]
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: home.deletingLastPathComponent()) }

    private func put(_ text: String, _ name: String, in root: URL) throws {
        let url = root.appendingPathComponent(name)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func text(_ name: String, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    private func json(_ values: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]), as: UTF8.self)
    }

    private func values(_ name: String, in root: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(name))) as? [String: Any])
    }

    private func link(_ target: String, _ name: String, in root: URL) throws {
        let url = root.appendingPathComponent(name)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target)
    }

    private func tree(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for case let name as String in try XCTUnwrap(fm.enumerator(atPath: root.path)) {
            let url = root.appendingPathComponent(name)
            let attributes = try fm.attributesOfItem(atPath: url.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink?: result[name] = "-> " + (try fm.destinationOfSymbolicLink(atPath: url.path))
            case .typeDirectory?: result[name] = "d"
            default: result[name] = String(attributes[.posixPermissions] as? Int ?? 0, radix: 8) + ":" + (try Data(contentsOf: url)).base64EncodedString()
            }
        }
        return result
    }

    private func move() throws -> [String: Any] {
        var saved: [String: Any] = [:]
        _ = try LibraryMove(from: old, to: new).prepare { preferences } savePreferences: { saved = $0 }
        return saved
    }

    // MARK: - At the moment of the copy

    func testTheCopyLeavesNoPathInTheOldFolder() throws {
        let workspace = old.appendingPathComponent("workspaces/0100AAAA", isDirectory: true)
        let elsewhere = "/Users/other/Library/Application Support/NXLibrary/workspaces/0100AAAA"
        try put("synthetic", "workspaces/0100AAAA/game.txt", in: old)
        try put("old log", "Logs/0100AAAA.log", in: old)
        try put(try json([
            "url": workspace.absoluteString,
            "workspacePath": workspace.path,
            "buildCachePath": workspace.path + "/0100AAAA_build", // Planned, not built yet.
            "logPath": old.path + "/Logs/0100AAAA.log", // Logs are not copied: the only file is the old one.
            "elsewhere": elsewhere,
            "sibling": old.path + " (before)/x",
            "nested": [["tempApp": workspace.absoluteString + "game.txt"]],
            "size": 1.5,
        ]), "catalog.json", in: old)
        try put(try json(["launcherChoices": ["gameSourcesPath": workspace.path]]), "settings.json", in: old)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: old.appendingPathComponent("settings.json").path)
        for name in ["build-queue.json", "activity-results.json", "cloud-transfer-queue.json", "profiles.json", "play-sessions-state.json"] {
            try put(try json(["entries": [["url": workspace.absoluteString]]]), name, in: old)
        }
        // The legacy library is fingerprinted by the catalog, the move journal names Drive folders: both stay as written.
        try put(try json(["path": workspace.path]), "library.json", in: old)
        preferences = ["list": [workspace.path, "/elsewhere"], "map": [workspace.path: workspace.path],
                       "blob": Data(try json(["executable": workspace.path]).utf8), "raw": Data([0, 1, 2]), "flag": true]
        let before = try tree(old)

        let saved = try move()

        XCTAssertEqual(try tree(old), before)
        let moved = new.appendingPathComponent("workspaces/0100AAAA", isDirectory: true)
        let catalog = try values("catalog.json", in: new)
        XCTAssertEqual(catalog["url"] as? String, moved.absoluteString)
        XCTAssertEqual(catalog["workspacePath"] as? String, moved.path)
        XCTAssertEqual(catalog["buildCachePath"] as? String, moved.path + "/0100AAAA_build")
        XCTAssertEqual(catalog["logPath"] as? String, old.path + "/Logs/0100AAAA.log")
        XCTAssertEqual(catalog["elsewhere"] as? String, elsewhere)
        XCTAssertEqual(catalog["sibling"] as? String, old.path + " (before)/x")
        XCTAssertEqual((catalog["nested"] as? [[String: String]])?.first?["tempApp"], moved.absoluteString + "game.txt")
        XCTAssertEqual(catalog["size"] as? Double, 1.5)
        XCTAssertEqual((try values("settings.json", in: new)["launcherChoices"] as? [String: String])?["gameSourcesPath"], moved.path)
        XCTAssertEqual(try fm.attributesOfItem(atPath: new.appendingPathComponent("settings.json").path)[.posixPermissions] as? Int, 0o600)
        for name in ["build-queue.json", "activity-results.json", "cloud-transfer-queue.json", "profiles.json", "play-sessions-state.json"] {
            XCTAssertEqual((try values(name, in: new)["entries"] as? [[String: String]])?.first?["url"], moved.absoluteString, name)
        }
        XCTAssertEqual(try text("library.json", in: new), try text("library.json", in: old))
        XCTAssertEqual(saved["list"] as? [String], [moved.path, "/elsewhere"])
        XCTAssertEqual(saved["map"] as? [String: String], [moved.path: moved.path])
        let blob = try XCTUnwrap(saved["blob"] as? Data)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: blob) as? [String: String])?["executable"], moved.path)
        XCTAssertEqual(saved["raw"] as? Data, Data([0, 1, 2]))
        XCTAssertEqual(saved["flag"] as? Bool, true)
    }

    func testADamagedFileIsCopiedAsItIs() throws {
        try put("{ \"url\": \"\(old.path)/x", "catalog.json", in: old)
        _ = try move()
        XCTAssertEqual(try text("catalog.json", in: new), try text("catalog.json", in: old))
    }

    func testAnInterruptedRemovalKeepsItsOriginalCatalogAndDoesNotArmTheCopy() throws {
        let original = try json(["workspacePath": old.path])
        try put(original, "catalog.json", in: old)
        try put("{}", LibraryPaths.removalJournal, in: old)
        _ = try move()
        XCTAssertEqual(try text("catalog.json", in: old), original)
        XCTAssertEqual(try text(LibraryPaths.removalJournal, in: old), "{}")
        XCTAssertEqual(try values("catalog.json", in: new)["workspacePath"] as? String, new.path)
        XCTAssertEqual(try text(LibraryPaths.inheritedRemoval, in: new), "{}")
        XCTAssertFalse(fm.fileExists(atPath: new.appendingPathComponent(LibraryPaths.removalJournal).path))
    }

    // MARK: - Once, for a library already copied

    /// A library as 0.5.0 left it: copied and marked, its paths still naming the old folder.
    private func copiedByAnEarlierVersion(_ catalog: [String: Any]? = nil) throws {
        let workspace = old.appendingPathComponent("workspaces/0100AAAA", isDirectory: true)
        for root in [old, new] {
            try put("synthetic", "workspaces/0100AAAA/game.txt", in: root)
            try put(try json(catalog ?? ["url": workspace.absoluteString, "workspacePath": workspace.path,
                "buildCachePath": workspace.path + "/0100AAAA_build", "logPath": old.path + "/Logs/0100AAAA.log"]),
                    "catalog.json", in: root)
            try put(try json(["url": workspace.absoluteString]), "catalog.json.bak", in: root)
            try put(try json(["launcherChoices": ["gameSourcesPath": workspace.path]]), "settings.json", in: root)
        }
        try put("old log", "Logs/0100AAAA.log", in: old)
        try put("{}", LibraryMove.marker, in: new)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: new.appendingPathComponent("settings.json").path)
        preferences = ["folder": workspace.path, "gone": old.path + "/never/copied", "flag": true]
    }

    private func repair(checks: [String: DevelopmentProfileImporter.Check] = [:],
                        replace: @escaping (URL, Data) throws -> Void = LibraryPaths.replace,
                        save: (([String: Any]) throws -> Void)? = nil) throws -> Bool {
        try LibraryPathRepair(from: old, to: new, replace: replace).prepare(checks: checks, preferences: { preferences },
                                                                            savePreferences: { values in
            if let save { try save(values) } else { preferences.merge(values) { $1 } }
        })
    }

    private var moved: URL { new.appendingPathComponent("workspaces/0100AAAA", isDirectory: true) }
    private var backup: URL { new.appendingPathComponent(LibraryPathRepair.backupFolder, isDirectory: true) }

    func testOnlyWhatExistsInTheNewFolderIsRepairedOnceWithABackup() throws {
        try copiedByAnEarlierVersion()
        let oldBefore = try tree(old), catalog = try text("catalog.json", in: new), kept = preferences
        var saved: [String: Any] = [:]
        XCTAssertTrue(try repair(save: { saved = $0 }))

        XCTAssertEqual(try tree(old), oldBefore)
        let repaired = try values("catalog.json", in: new)
        XCTAssertEqual(repaired["url"] as? String, moved.absoluteString)
        XCTAssertEqual(repaired["workspacePath"] as? String, moved.path)
        XCTAssertEqual(repaired["buildCachePath"] as? String, moved.path + "/0100AAAA_build")
        XCTAssertEqual(repaired["logPath"] as? String, old.path + "/Logs/0100AAAA.log")
        XCTAssertEqual(try values("catalog.json.bak", in: new)["url"] as? String, moved.absoluteString)
        XCTAssertEqual(try fm.attributesOfItem(atPath: new.appendingPathComponent("settings.json").path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(saved.keys.sorted(), ["folder"])
        XCTAssertEqual(saved["folder"] as? String, moved.path)
        // The way back: every changed file and value as it was.
        XCTAssertEqual(try text("catalog.json", in: backup), catalog)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: backup.path).sorted(),
                       ["catalog.json", "catalog.json.bak", "preferences.plist", "settings.json"])
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: backup.appendingPathComponent("preferences.plist")), format: nil)
        XCTAssertEqual(plist as? [String: String], ["folder": try XCTUnwrap(kept["folder"] as? String)])
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: new.path).allSatisfy { !$0.hasPrefix(".catalog-stage") })

        try put("{\"url\":\"\(old.path)\"}", "catalog.json", in: new)
        XCTAssertFalse(try repair())
        XCTAssertEqual(try values("catalog.json", in: new)["url"] as? String, old.path)
    }

    func testAWorkspaceOrCacheInNeitherFolderMovesToo() throws {
        let never = old.path + "/workspaces/0100BBBB", onlyOld = old.path + "/workspaces/0100CCCC"
        try copiedByAnEarlierVersion(["workspacePath": never, "buildCachePath": never + "/0100BBBB_build",
            "url": URL(fileURLWithPath: never, isDirectory: true).absoluteString,
            "onlyOld": onlyOld, "logPath": old.path + "/Logs/gone.log", "elsewhere": old.path + "/never/copied"])
        try put("synthetic", "workspaces/0100CCCC/game.txt", in: old)
        XCTAssertTrue(try repair())
        let repaired = try XCTUnwrap(values("catalog.json", in: new) as? [String: String])
        let expected = new.path + "/workspaces/0100BBBB"
        XCTAssertEqual(repaired["workspacePath"], expected)
        XCTAssertEqual(repaired["buildCachePath"], expected + "/0100BBBB_build")
        XCTAssertEqual(repaired["url"], URL(fileURLWithPath: expected, isDirectory: true).absoluteString)
        // What only the old folder holds, logs and anything outside the workspaces keep their name.
        XCTAssertEqual(repaired["onlyOld"], onlyOld)
        XCTAssertEqual(repaired["logPath"], old.path + "/Logs/gone.log")
        XCTAssertEqual(repaired["elsewhere"], old.path + "/never/copied")
        XCTAssertFalse(fm.fileExists(atPath: expected), "nothing is made on disk")
    }

    func testTheOldFolderMayBeGone() throws {
        try copiedByAnEarlierVersion()
        try fm.removeItem(at: old)
        XCTAssertTrue(try repair())
        XCTAssertEqual(try values("catalog.json", in: new)["workspacePath"] as? String, moved.path)
        XCTAssertFalse(fm.fileExists(atPath: old.path))
    }

    func testALibraryThatWasNeverCopiedIsLeftAlone() throws {
        try copiedByAnEarlierVersion()
        try fm.removeItem(at: new.appendingPathComponent(LibraryMove.marker))
        let before = try tree(new)
        XCTAssertFalse(try repair())
        XCTAssertEqual(try tree(new), before)
        try fm.removeItem(at: new)
        XCTAssertFalse(try repair())
        XCTAssertFalse(fm.fileExists(atPath: new.path))
    }

    func testAnotherAccountsFolderIsNotThisOnes() throws {
        let other = "/Users/another/Library/Application Support/NXLibrary/workspaces/0100AAAA"
        try copiedByAnEarlierVersion(["url": "file://" + other.replacingOccurrences(of: " ", with: "%20"),
                                      "workspacePath": other, "escape": old.path + "/workspaces/../../NXLibrary"])
        let before = try text("catalog.json", in: new)
        XCTAssertTrue(try repair())
        XCTAssertEqual(try text("catalog.json", in: new), before)
    }

    func testEncodedAndDecomposedSpellingsAreTheSameFolder() throws {
        let name = "Pokémon Légendes"
        let composed = name.precomposedStringWithCanonicalMapping, decomposed = name.decomposedStringWithCanonicalMapping
        let account = old.path
        let spelledOld = [account.precomposedStringWithCanonicalMapping, account.decomposedStringWithCanonicalMapping]
        var catalog: [String: String] = [:]
        for (index, root) in spelledOld.enumerated() {
            catalog["path\(index)"] = root + "/workspaces/" + (index == 0 ? decomposed : composed)
            catalog["url\(index)"] = "file://" + catalog["path\(index)"]!.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + "/"
        }
        try copiedByAnEarlierVersion(catalog)
        try put("synthetic", "workspaces/" + composed + "/game.txt", in: new)
        // A normalization-sensitive filesystem stores these as different directory entries.
        if !fm.fileExists(atPath: new.path + "/workspaces/" + decomposed) {
            try put("synthetic", "workspaces/" + decomposed + "/game.txt", in: new)
        }
        XCTAssertTrue(try repair())
        let repaired = try XCTUnwrap(values("catalog.json", in: new) as? [String: String])
        for (key, value) in repaired {
            let path = key.hasPrefix("url") ? try XCTUnwrap(URL(string: value)).path : value
            XCTAssertTrue(path.contains("/Oort NX/workspaces/"), key)
            XCTAssertTrue(fm.fileExists(atPath: path), key)
        }
        // What follows the folder keeps its own spelling.
        XCTAssertTrue(repaired["path0"]!.unicodeScalars.elementsEqual((new.path + "/workspaces/" + decomposed).unicodeScalars))
        XCTAssertTrue(repaired["url1"]!.hasSuffix(composed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + "/"))
    }

    func testALockedCatalogOrARunningCopyIsTriedAgain() throws {
        try copiedByAnEarlierVersion()
        let before = try tree(new)
        let fd = open(new.appendingPathComponent(".catalog.lock").path, O_RDWR | O_CREAT, 0o600)
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try repair()) { XCTAssertEqual($0 as? CatalogStoreError, .busy) }
        close(fd)
        try fm.removeItem(at: new.appendingPathComponent(".catalog.lock"))
        XCTAssertEqual(try tree(new), before)
        var lease: DowngradeCheckpoint.ProfileLease? = try DowngradeCheckpoint.ProfileLease(in: new)
        XCTAssertThrowsError(try repair())
        XCTAssertEqual(try text("catalog.json", in: new), try text("catalog.json", in: old))
        withExtendedLifetime(lease) {}
        lease = nil
        XCTAssertTrue(try repair())
    }

    func testAnInterruptedRepairFinishesAndKeepsTheFirstBackup() throws {
        struct Stopped: Error {}
        // Stops after each step in turn: every file, then the preferences.
        for stop in 0...3 {
            try? fm.removeItem(at: home)
            try copiedByAnEarlierVersion()
            let originals = try ["catalog.json", "catalog.json.bak", "settings.json"].map { try text($0, in: new) }
            var written = 0
            XCTAssertThrowsError(try repair(replace: { file, data in
                if written == stop { throw Stopped() }
                written += 1
                try LibraryPaths.replace(file, with: data)
            }, save: { _ in throw Stopped() }), "stop \(stop)")
            XCTAssertFalse(fm.fileExists(atPath: new.appendingPathComponent(LibraryPathRepair.marker).path))
            XCTAssertTrue(try repair(), "stop \(stop)")
            XCTAssertEqual(try values("catalog.json", in: new)["workspacePath"] as? String, moved.path)
            XCTAssertEqual(try values("catalog.json.bak", in: new)["url"] as? String, moved.absoluteString)
            XCTAssertEqual(preferences["folder"] as? String, moved.path)
            XCTAssertEqual(try ["catalog.json", "catalog.json.bak", "settings.json"].map { try text($0, in: backup) }, originals)
        }
    }

    func testAFileThatFailsItsCheckOrAPendingRemovalWaits() throws {
        struct Damaged: Error {}
        try copiedByAnEarlierVersion()
        let bak = try text("catalog.json.bak", in: new)
        XCTAssertTrue(try repair(checks: ["catalog.json.bak": { _, _ in throw Damaged() }]))
        XCTAssertEqual(try text("catalog.json.bak", in: new), bak)
        XCTAssertEqual(try values("catalog.json", in: new)["workspacePath"] as? String, moved.path)
        XCTAssertFalse(fm.fileExists(atPath: backup.appendingPathComponent("catalog.json.bak").path))
        // Not done while a file waits; what changed since is kept beside the first copy.
        let changed = try json(["url": old.path + "/workspaces/0100AAAA"])
        try put(changed, "catalog.json", in: new)
        XCTAssertTrue(try repair())
        XCTAssertEqual(try text("catalog.json.2", in: backup), changed)
        XCTAssertTrue(try text("catalog.json", in: backup).contains("buildCachePath"))
        XCTAssertFalse(try repair())

        try fm.removeItem(at: home)
        try copiedByAnEarlierVersion()
        try put("{}", "catalog-removal-pending.json", in: new)
        let before = try text("catalog.json", in: new)
        XCTAssertThrowsError(try repair()) { XCTAssertEqual($0 as? LibraryPathRepair.Failure, .removalPending) }
        XCTAssertEqual(try text("catalog.json", in: new), before)
    }

    func testARewrittenFileThatFailsItsCheckChangesNothing() throws {
        struct Refused: Error {}
        try copiedByAnEarlierVersion()
        let before = try tree(new)
        XCTAssertThrowsError(try repair(checks: ["settings.json": { data, _ in
            if String(decoding: data, as: UTF8.self).contains("Oort") { throw Refused() }
        }]))
        var after = try tree(new)
        after[".catalog.lock"] = nil
        XCTAssertEqual(after, before)
    }

    // MARK: - Dead links

    func testDeadWorkspaceLinksAreIgnoredReportedAndKept() throws {
        try copiedByAnEarlierVersion(["source": old.path + "/workspaces/0100AAAA/dead.nsp"])
        try link("/Volumes/absent/dead.nsp", "workspaces/0100AAAA/dead.nsp", in: new)
        try link("/Volumes/absent/dlc", "workspaces/0100AAAA/dlc/0100AAAA/0/romfs", in: new)
        try link(new.appendingPathComponent("settings.json").path, "workspaces/0100AAAA/alive.nsp", in: new)
        try link("/Volumes/absent/cache", "workspaces/0100AAAA/0100AAAA_build/inside", in: new)
        XCTAssertTrue(try repair())
        XCTAssertEqual(try values("catalog.json", in: new)["source"] as? String, old.path + "/workspaces/0100AAAA/dead.nsp")
        let dead = ["workspaces/0100AAAA/dead.nsp", "workspaces/0100AAAA/dlc/0100AAAA/0/romfs"]
        XCTAssertEqual(LibraryPaths.deadWorkspaceLinks(in: new), dead)
        for name in dead { XCTAssertNoThrow(try fm.destinationOfSymbolicLink(atPath: new.appendingPathComponent(name).path)) }
        var inputs = DiagnosticsReport.Inputs()
        XCTAssertFalse(DiagnosticsReport.markdown(inputs).contains("lead nowhere"))
        inputs.deadWorkspaceLinks = dead + (1...25).map { "workspaces/x/\($0)" }
        let report = DiagnosticsReport.markdown(inputs)
        XCTAssertTrue(report.contains("- Workspace links that lead nowhere (kept): 27\n  - workspaces/0100AAAA/dead.nsp\n"), report)
        XCTAssertTrue(report.contains("  - … and 7 more"))
    }

    // MARK: - The first launch

    func testTheFirstLaunchCopiesThenRepairsAndNeverFailsForTheRepair() throws {
        let profile = AppDataProfile(home: home, isDevelopment: false)
        try copiedByAnEarlierVersion()
        let fd = open(new.appendingPathComponent(".catalog.lock").path, O_RDWR | O_CREAT, 0o600)
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        func launch() throws {
            try AppData.adoptLegacyLibrary(profile, checks: [:], legacyPreferences: { [:] }, preferences: { preferences },
                                           savePreferences: { preferences.merge($0) { $1 } })
        }
        // The marker of an earlier copy is complete.
        try put("{\"version\":1,\"ready\":true,\"files\":1}", LibraryMove.marker, in: new)
        XCTAssertNoThrow(try launch())
        XCTAssertEqual(try values("catalog.json", in: new)["workspacePath"] as? String, old.path + "/workspaces/0100AAAA")
        close(fd)
        try launch()
        XCTAssertEqual(try values("catalog.json", in: new)["workspacePath"] as? String, moved.path)
    }
}
