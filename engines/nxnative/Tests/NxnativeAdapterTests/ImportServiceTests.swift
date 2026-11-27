import XCTest
@testable import OortLibrary
@testable import ArcanePorting

final class ImportServiceTests: XCTestCase {
    func testAdoptionValidatesIdentityAndResignsWithoutAManifest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Game apps")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Source.app")
        let service = ImportService()
        try signedApp(at: source, bundleID: "org.nxnative.01007ef00011e000")
        XCTAssertEqual(try service.prepareAdoption(from: source, into: folder, existing: []).app.titleId, "01007EF00011E000")
        XCTAssertThrowsError(try service.prepareAdoption(from: URL(string: "https://example.test/Source.app")!,
                                                         into: folder, existing: []))
        let unrelated = root.appendingPathComponent("Unrelated.app")
        try signedApp(at: unrelated, bundleID: "org.example.other")
        XCTAssertThrowsError(try service.prepareAdoption(from: unrelated, into: folder, existing: [])) {
            XCTAssertEqual($0 as? CloudArchiveError, .invalidApp)
        }
        let seal = source.appendingPathComponent("Contents/_CodeSignature/CodeResources")
        try FileManager.default.removeItem(at: seal)
        XCTAssertNotEqual(try verify(source).status, 0)
        let plan = try service.prepareAdoption(from: source, into: folder, existing: [])
        let staged = try await service.stageAdoption(plan, replacing: false)
        defer { service.cleanupAdoption(staged, published: true) }
        XCTAssertTrue(staged.contentUnverified)
        try service.publishAdoption(staged) { _ in }
        XCTAssertEqual(try verify(plan.destination).status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: seal.path))
    }

    func testAdoptionRepairsTransferDamageOnlyInStaging() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Game apps")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Source.app")
        let contents = source.appendingPathComponent("Contents")
        let payload = Data("sealed data".utf8)
        let specs = [("GameData", "romfs.img"), ("ShaderLibraries", "msl/library"),
                     ("PipelineArchive", "pso/cache"), ("AddOnContent", "aoc/dlc"),
                     ("GameData2", "p2/romfs.img")]
        for (bundleName, resource) in specs {
            let bundle = contents.appendingPathComponent("PlugIns/\(bundleName).bundle")
            let target = bundle.appendingPathComponent("Contents/Resources/\(resource)")
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": "org.example.\(bundleName)", "CFBundlePackageType": "BNDL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            try payload.write(to: target)
            try sign(bundle)
            let name = resource.hasPrefix("p2/") ? resource : String(resource.split(separator: "/")[0])
            let link = contents.appendingPathComponent("Resources/\(name)")
            let relative = String(repeating: "../", count: name.split(separator: "/").count)
                + "PlugIns/\(bundleName).bundle/Contents/Resources/\(name)"
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: relative)
        }
        try signedApp(at: source, bundleID: "org.nxnative.01007ef00011e000")
        XCTAssertEqual(try verify(source).status, 0)
        for (bundleName, _) in specs {
            try fm.removeItem(at: contents.appendingPathComponent("PlugIns/\(bundleName).bundle/Contents/_CodeSignature/CodeSignature"))
        }
        let executable = contents.appendingPathComponent("MacOS/Fixture")
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
        let flattened = contents.appendingPathComponent("Resources/romfs.img")
        try fm.removeItem(at: flattened)
        try payload.write(to: flattened)
        try fm.removeItem(at: contents.appendingPathComponent("Resources/msl"))
        try fm.removeItem(at: contents.appendingPathComponent("Resources/p2/romfs.img"))
        let pso = contents.appendingPathComponent("Resources/pso")
        let sidecar = pso.appendingPathExtension("rclonelink")
        try Data(fm.destinationOfSymbolicLink(atPath: pso.path).utf8).write(to: sidecar)
        try fm.removeItem(at: pso)
        let seals = ["_CodeSignature/CodeResources",
                     "PlugIns/PipelineArchive.bundle/Contents/_CodeSignature/CodeResources"]
        for path in seals {
            let seal = contents.appendingPathComponent(path)
            try fm.moveItem(at: seal, to: seal.appendingPathExtension("xml"))
        }
        let quarantine = "0081;00000000;Fixture;"
        let quarantined = ["Contents/Resources", "Contents/MacOS/Fixture"]
            + seals.map { "Contents/\($0).xml" }
        for url in [source] + quarantined.map({ source.appendingPathComponent($0) }) {
            XCTAssertEqual(setxattr(url.path, "com.apple.quarantine", quarantine, quarantine.utf8.count, 0, 0), 0)
        }
        XCTAssertNotEqual(try verify(source).status, 0)

        let service = ImportService()
        let plan = try service.prepareAdoption(from: source, into: folder, existing: [])
        let staged = try await service.stageAdoption(plan, replacing: false)
        XCTAssertFalse(staged.contentUnverified)
        try service.publishAdoption(staged) { _ in }
        service.cleanupAdoption(staged, published: true)
        XCTAssertEqual(try verify(plan.destination).status, 0)
        let repaired = plan.destination.appendingPathComponent("Contents")
        XCTAssertTrue(fm.isExecutableFile(atPath: repaired.appendingPathComponent("MacOS/Fixture").path))
        XCTAssertFalse(fm.isExecutableFile(atPath: executable.path))
        XCTAssertEqual(try Data(contentsOf: flattened), payload)
        XCTAssertEqual(getxattr(source.path, "com.apple.quarantine", nil, 0, 0, 0), quarantine.utf8.count)
        XCTAssertEqual(getxattr(plan.destination.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
        for path in quarantined {
            let original = source.appendingPathComponent(path)
            let installed = plan.destination.appendingPathComponent(path)
            let repairedFile = path.hasSuffix(".xml") ? installed.deletingPathExtension() : installed
            XCTAssertEqual(getxattr(original.path, "com.apple.quarantine", nil, 0, 0, 0), quarantine.utf8.count)
            XCTAssertTrue(fm.fileExists(atPath: repairedFile.path))
            XCTAssertEqual(getxattr(repairedFile.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
            if path.hasSuffix(".xml") { XCTAssertFalse(fm.fileExists(atPath: installed.path)) }
        }
        XCTAssertTrue(fm.fileExists(atPath: sidecar.path))
        XCTAssertFalse(fm.fileExists(atPath: repaired.appendingPathComponent("Resources/pso.rclonelink").path))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: repaired.appendingPathComponent("Resources/pso").path),
                       "../PlugIns/PipelineArchive.bundle/Contents/Resources/pso")
        for (bundleName, resource) in specs {
            let sig = "PlugIns/\(bundleName).bundle/Contents/_CodeSignature/CodeSignature"
            XCTAssertEqual(try Data(contentsOf: repaired.appendingPathComponent(sig)), Data())
            XCTAssertFalse(fm.fileExists(atPath: contents.appendingPathComponent(sig).path))
            XCTAssertEqual(try Data(contentsOf: repaired.appendingPathComponent("Resources/\(resource)")), payload)
        }
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: repaired.appendingPathComponent("Resources/msl").path),
                       "../PlugIns/ShaderLibraries.bundle/Contents/Resources/msl")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path), [plan.destination.lastPathComponent])
    }

    func testAdoptionRejectsUnsafeSidecarTargets() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Game apps")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Source.app")
        try signedApp(at: source, bundleID: "org.nxnative.01007ef00011e000")
        let service = ImportService()
        let plan = try service.prepareAdoption(from: source, into: folder, existing: [])
        let sidecar = source.appendingPathComponent("Contents/escape.rclonelink")
        for target in ["../../outside", "/tmp"] {
            try Data(target.utf8).write(to: sidecar)
            await expectAdoptionError(.unsafePath) { try await service.stageAdoption(plan, replacing: false) }
            XCTAssertTrue(try fm.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
    }

    func testAdoptionCopiesRegistersAndReplacesOnlyAfterConfirmationAndSpaceCheck() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Game apps")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Source.app")
        try signedApp(at: source, bundleID: "org.example.port", dmTitle: "01007EF00011E000")
        let service = ImportService()
        let repository = CatalogRepository(store: CatalogStore(directory: root.appendingPathComponent("Catalog")))
        let plan = try service.prepareAdoption(from: source, into: folder, existing: [])
        XCTAssertFalse(plan.conflicts)
        await expectAdoptionError(.insufficientSpace) {
            try await service.stageAdoption(plan, replacing: false, capacity: { _ in 0 })
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: folder.path).isEmpty)
        let staged = try await service.stageAdoption(plan, replacing: false)
        try service.publishAdoption(staged) {
            _ = try repository.recordLocalAppAdoption(service.makeGame(from: $0), replacing: nil)
        }
        service.cleanupAdoption(staged, published: true)
        XCTAssertTrue(fm.fileExists(atPath: source.path))
        let old = try XCTUnwrap(repository.load().nxnativeGames.first)
        XCTAssertEqual(old.status, .builtSourcesMissing)
        XCTAssertEqual(old.url, plan.destination)
        XCTAssertNil(old.lastBuild)
        try repository.toggleFavorite(for: old.id)
        let replacement = root.appendingPathComponent("Replacement.app")
        try signedApp(at: replacement, bundleID: "org.nxnative.01007ef00011e000", version: "2")
        let existing = try repository.load().nxnativeGames
        let conflict = try service.prepareAdoption(from: replacement, into: folder, existing: existing)
        XCTAssertTrue(conflict.conflicts)
        XCTAssertEqual(conflict.destination, old.url)
        await expectAdoptionError(.confirmationRequired) {
            try await service.stageAdoption(conflict, replacing: false)
        }
        let incoming = try await service.stageAdoption(conflict, replacing: true)
        XCTAssertThrowsError(try service.publishAdoption(incoming) { _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertEqual(BuildOutputInstaller.version(of: old.url), "1")
        service.cleanupAdoption(incoming, published: false)
        let retry = try service.prepareAdoption(from: replacement, into: folder, existing: existing)
        let confirmed = try await service.stageAdoption(retry, replacing: true)
        try service.publishAdoption(confirmed) {
            _ = try repository.recordLocalAppAdoption(service.makeGame(from: $0), replacing: retry.existing)
        }
        let updated = try XCTUnwrap(repository.load().nxnativeGames.first)
        XCTAssertEqual(updated.id, old.id)
        XCTAssertEqual(updated.versionString, "2")
        XCTAssertTrue(updated.isFavorite)
        XCTAssertTrue(fm.fileExists(atPath: replacement.path))
    }

    func testAdoptionPreservesDestinationEditedAfterPreview() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Apps")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let installed = folder.appendingPathComponent("Installed.app")
        let replacement = root.appendingPathComponent("Replacement.app")
        let bundleID = "org.nxnative.01007ef00011e000"
        try signedApp(at: installed, bundleID: bundleID, version: "1")
        try signedApp(at: replacement, bundleID: bundleID, version: "2")
        let resources = installed.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        let resource = resources.appendingPathComponent("fixture.txt")
        try Data("before".utf8).write(to: resource)
        let service = ImportService()
        let plan = try service.prepareAdoption(from: replacement, into: folder, existing: [])
        XCTAssertTrue(plan.conflicts)
        XCTAssertEqual(plan.destination.path, installed.path)
        let edited = Data("edited".utf8)
        try edited.write(to: resource)
        let staged = try await service.stageAdoption(plan, replacing: true)
        defer { service.cleanupAdoption(staged, published: false) }
        XCTAssertThrowsError(try service.publishAdoption(staged) { _ in }) {
            XCTAssertEqual($0 as? CloudArchiveError, .localChanged)
        }
        XCTAssertEqual(BuildOutputInstaller.version(of: installed), "1")
        XCTAssertEqual(try Data(contentsOf: resource), edited)
    }

    private func expectAdoptionError(_ expected: CloudArchiveError, line: UInt = #line,
                                     _ stage: () async throws -> ImportService.StagedAdoption) async {
        do {
            _ = try await stage()
            XCTFail("Expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? CloudArchiveError, expected, line: line)
        }
    }

    private func signedApp(at url: URL, bundleID: String, dmTitle: String? = nil, version: String = "1") throws {
        let fm = FileManager.default
        let contents = url.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/Fixture")
        try fm.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        var info = ["CFBundleIdentifier": bundleID, "CFBundleName": "Fixture",
                    "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL",
                    "CFBundleShortVersionString": version]
        info["DMTitleID"] = dmTitle
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try sign(url)
    }

    private func sign(_ url: URL) throws {
        let signature = try SystemCommandRunner().run(URL(fileURLWithPath: "/usr/bin/codesign"),
            ["--force", "--sign", "-", url.path], environment: nil, currentDirectory: nil)
        XCTAssertEqual(signature.status, 0, signature.stderr)
    }

    private func verify(_ url: URL) throws -> CommandResult {
        try SystemCommandRunner().run(URL(fileURLWithPath: "/usr/bin/codesign"),
            ["--verify", "--deep", "--strict", url.path], environment: nil, currentDirectory: nil)
    }

    func testDuplicateTitleKeepsTheInstalledPathAndItsOwnMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("Installed.app")
        let newURL = root.appendingPathComponent("Backup.app")
        for app in [oldURL, newURL] {
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        }
        let old = ImportedApp(name: "Installed", version: "1.0", titleId: "01007EF00011E000",
            bundleId: "org.nxnative.old", appURL: oldURL, sizeBytes: 100,
            modificationDate: Date(timeIntervalSince1970: 1))
        let newer = ImportedApp(name: "Backup", version: "2.0", titleId: old.titleId,
            bundleId: "org.nxnative.new", appURL: newURL, sizeBytes: 200,
            modificationDate: Date(timeIntervalSince1970: 2))
        let service = ImportService()
        let store = CatalogRepository(store: CatalogStore(directory: root.appendingPathComponent("Catalog")))
        try store.configureSource(.nxnative, enabled: true, root: nil)
        _ = try store.mergeNXNative(scanned: [service.makeGame(from: old)])
        let selected = service.appsForLibrary(scanned: [newer, old], existing: try store.load().nxnativeGames)
        XCTAssertEqual(selected.count, 1)
        let library = try store.mergeNXNative(scanned: selected.map { service.makeGame(from: $0) })
        let game = try XCTUnwrap(library.nxnativeGames.first)
        XCTAssertEqual(game.url, oldURL)
        XCTAssertEqual(game.name, "Installed")
        XCTAssertEqual(game.versionString, "1.0")
        XCTAssertEqual(game.modificationDate, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(selected.first?.sizeBytes, 100)
        // A different chosen folder does not silently switch an existing installed app.
        XCTAssertTrue(service.appsForLibrary(scanned: [newer], existing: library.nxnativeGames).isEmpty)
        // If the old app is actually removed, the discovered build can replace its reference.
        try FileManager.default.removeItem(at: oldURL)
        XCTAssertEqual(service.appsForLibrary(scanned: [newer], existing: library.nxnativeGames).first?.appURL, newURL)
        // A new title with multiple builds starts with the newest scan result, once.
        XCTAssertEqual(service.appsForLibrary(scanned: [newer, old], existing: []).count, 1)
    }

    func testFindsNestedAppsWithoutEnteringBundlesOrFollowingDirectoryLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = root.appendingPathComponent("Games/Platform/Title/Game.app/Contents")
        let hidden = root.appendingPathComponent("Games/Other.app/Contents/Hidden.app/Contents")
        let outside = root.appendingPathComponent("Outside/External.app/Contents")
        for folder in [game, hidden, outside] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try nxnativePlist().write(to: folder.appendingPathComponent("Info.plist"))
        }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Games/Loop").path,
                                                   withDestinationPath: root.appendingPathComponent("Games").path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Games/External").path,
                                                   withDestinationPath: root.appendingPathComponent("Outside").path)
        let apps = ImportService().scan(directories: [root.appendingPathComponent("Games")])
        XCTAssertEqual(apps.map { $0.appURL.lastPathComponent }, ["Game.app"])
    }

    func testOverlappingRootsDoNotDuplicateTheSameApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Game.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try nxnativePlist().write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertEqual(ImportService().scan(directories: [root, root]).count, 1)
    }

    func testDepthLimitReportsAnIncompleteScanAndPreservesShallowResults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Direct.app", "Subfolder/Deep.app"] {
            let contents = root.appendingPathComponent(name + "/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try nxnativePlist().write(to: contents.appendingPathComponent("Info.plist"))
        }
        let service = ImportService(maximumDepth: 0)
        XCTAssertEqual(service.scan(directories: [root]).map { $0.appURL.lastPathComponent }, ["Direct.app"])
        XCTAssertFalse(service.scanWarnings.isEmpty)
    }

    func testDirectoryBudgetAndUnreadableRootAreReported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Subfolder"), withIntermediateDirectories: true)
        let service = ImportService(maximumDirectories: 1)
        XCTAssertTrue(service.scan(directories: [root]).isEmpty)
        XCTAssertFalse(service.scanWarnings.isEmpty)
        XCTAssertTrue(service.scan(directories: [root.appendingPathComponent("Missing")]).isEmpty)
        XCTAssertFalse(service.scanWarnings.isEmpty)
    }

    func testFindsOnlyNxnativeApps() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXImport-\(UUID().uuidString)")
        let nxnative = root.appendingPathComponent("Zelda.app/Contents")
        let other = root.appendingPathComponent("Other.app/Contents")
        try FileManager.default.createDirectory(at: nxnative, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try nxnativePlist().write(to: nxnative.appendingPathComponent("Info.plist"))
        try otherPlist().write(to: other.appendingPathComponent("Info.plist"))
        let apps = ImportService().scan(directories: [root])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.titleId, "01007EF00011E000")
        XCTAssertEqual(apps.first?.name, "The Legend of Zelda: Breath of the Wild")

        let game = ImportService().makeGame(from: try XCTUnwrap(apps.first))
        XCTAssertEqual(game.status, .builtSourcesMissing)
        XCTAssertEqual(game.titleId, "01007EF00011E000")
        XCTAssertEqual(game.bundleId, "org.nxnative.01007ef00011e000")
        XCTAssertEqual(game.versionString, "1.9.0")
        XCTAssertEqual(game.url.lastPathComponent, "Zelda.app")
    }

    private func nxnativePlist() -> Data {
        try! PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "The Legend of Zelda: Breath of the Wild",
            "CFBundleIdentifier": "org.nxnative.01007ef00011e000",
            "CFBundleShortVersionString": "1.9.0",
            "DMTitleID": "01007EF00011E000",
        ], format: .xml, options: 0)
    }

    private func otherPlist() -> Data {
        try! PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Other",
            "CFBundleIdentifier": "com.example.other",
        ], format: .xml, options: 0)
    }

    func testRejectsInvalidTitleIdsAndFallsBackToBundleSuffix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXImportIDs-\(UUID().uuidString)")
        let bad = root.appendingPathComponent("Bad.app/Contents")
        let suffixOnly = root.appendingPathComponent("Suffix.app/Contents")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: suffixOnly, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Bad",
            "CFBundleIdentifier": "org.nxnative.app",
            "DMTitleID": "../../../Documents/x",
        ], format: .xml, options: 0).write(to: bad.appendingPathComponent("Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Suffix",
            "CFBundleIdentifier": "org.nxnative.01007ef00011e000",
        ], format: .xml, options: 0).write(to: suffixOnly.appendingPathComponent("Info.plist"))

        let apps = ImportService().scan(directories: [root])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.titleId, "01007EF00011E000")
        try? FileManager.default.removeItem(at: root)
    }
}
