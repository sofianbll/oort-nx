import XCTest
@testable import OortLibrary
@testable import OortMac

/// Installing an update of the Mac app: bundle checks, signature, translocation, the swap and its failures.
final class AppUpdateInstallTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    /// A minimal app bundle: Info.plist and an executable script.
    @discardableResult
    private func makeApp(_ name: String = "NXLibrary.app", in folder: URL? = nil, id: String = "local.nxlibrary",
                         version: String = "0.2.0", release: Bool = true, minimumOS: String? = nil,
                         executable: Bool = true, marker: String = "new") throws -> URL {
        let app = (folder ?? dir).appendingPathComponent(name)
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "NXLibrary",
                                   "CFBundleShortVersionString": version]
        if release { info[AppUpdate.releaseMarker] = true }
        if let minimumOS { info["LSMinimumSystemVersion"] = minimumOS }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        if executable {
            let exe = macOS.appendingPathComponent("NXLibrary")
            try Data("#!/bin/sh\n# \(marker)\n".utf8).write(to: exe)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        }
        return app
    }

    private let os = OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0)

    func testSignatureRejectsUnsignedAndTamperedBundle() throws {
        let app = try makeApp("Signed.app")
        XCTAssertFalse(AppUpdate.validCodeSignature(app))
        let executable = app.appendingPathComponent("Contents/MacOS/NXLibrary")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let resource = app.appendingPathComponent("Contents/Resources/check.txt")
        try FileManager.default.createDirectory(at: resource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: resource)
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", app.path]
        signer.standardOutput = FileHandle.nullDevice
        signer.standardError = FileHandle.nullDevice
        try signer.run(); signer.waitUntilExit()
        XCTAssertEqual(signer.terminationStatus, 0)
        XCTAssertTrue(AppUpdate.validCodeSignature(app))
        try Data("changed".utf8).write(to: resource)
        XCTAssertFalse(AppUpdate.validCodeSignature(app))
    }

    func testBundleChecks() throws {
        let good = try makeApp("Good.app")
        XCTAssertNil(AppUpdate.bundleProblem(good, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os))
        let other = try makeApp("Other.app", id: "com.example")
        XCTAssertEqual(AppUpdate.bundleProblem(other, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os),
                       .wrongIdentifier)
        let noExe = try makeApp("NoExe.app", executable: false)
        XCTAssertEqual(AppUpdate.bundleProblem(noExe, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os),
                       .noExecutable)
        XCTAssertEqual(AppUpdate.bundleProblem(good, expectedID: "local.nxlibrary", version: "0.3.0", runningOS: os),
                       .wrongVersion)
        let future = try makeApp("Future.app", minimumOS: "28.0")
        XCTAssertEqual(AppUpdate.bundleProblem(future, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os),
                       .needsNewerMacOS("28.0"))
        XCTAssertEqual(AppUpdate.bundleProblem(dir.appendingPathComponent("Missing.app"), expectedID: "local.nxlibrary",
                                               version: "0.2.0", runningOS: os), .noInfo)
    }

    func testDevelopmentDataMarkerCannotShipAsAnUpdate() throws {
        let app = try makeApp("Mixed.app")
        let file = app.appendingPathComponent("Contents/Info.plist")
        var info = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any])
        info["NXLibraryDevelopmentProfile"] = true
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: file)
        XCTAssertEqual(AppUpdate.bundleProblem(app, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os), .notRelease)
        XCTAssertEqual(AppUpdate.installability(app), .developer)
    }

    func testBundleWithoutMarkerIsRefused() throws {
        let dev = try makeApp("Dev.app", release: false)
        XCTAssertEqual(AppUpdate.bundleProblem(dev, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os),
                       .notRelease)
    }

    func testInstallabilityDeveloperWithoutMarker() throws {
        XCTAssertEqual(AppUpdate.installability(try makeApp("Dev.app", release: false)), .developer)
        XCTAssertEqual(AppUpdate.installability(try makeApp("Rel.app")), .ok)
        XCTAssertEqual(AppUpdate.installability(dir.appendingPathComponent("bare-binary")), .developer)
    }

    func testTranslocatedReleaseAsksToBeMoved() throws {
        let temporary = dir.appendingPathComponent("AppTranslocation/0A1B/d")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let release = try makeApp(in: temporary)
        XCTAssertTrue(AppUpdate.isTranslocated(release))
        XCTAssertEqual(AppUpdate.installability(release), .readOnly)
        XCTAssertTrue(AppUpdate.asksToBeMoved(release))
        XCTAssertFalse(AppUpdate.asksToBeMoved(try makeApp("Dev.app", in: temporary, release: false)), "a developer build never asks")
        XCTAssertFalse(AppUpdate.asksToBeMoved(try makeApp("Rel.app")), "a release in a normal folder never asks")
    }

    func testInstallabilityReadOnlyFolder() throws {
        let folder = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = try makeApp(in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        XCTAssertEqual(AppUpdate.installability(app), .readOnly)
    }

    func testSwapReplacesAndKeepsName() throws {
        let installed = dir.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let current = try makeApp(in: installed, version: "0.1.0", marker: "old")
        let stagedFolder = dir.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: stagedFolder, withIntermediateDirectories: true)
        let staged = try makeApp(in: stagedFolder, version: "0.2.0", marker: "new")
        let placed = try AppUpdate.install(staged, over: current, trashOld: false)
        XCTAssertEqual(placed.standardizedFileURL, current.standardizedFileURL)
        let exe = try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8)
        XCTAssertTrue(exe.contains("new"))
        let left = try FileManager.default.contentsOfDirectory(atPath: installed.path)
        XCTAssertEqual(left, ["NXLibrary.app"], "no (new) or (old) copy left behind")
    }

    func testSwapFailureKeepsCurrent() throws {
        let current = try makeApp(version: "0.1.0", marker: "old")
        XCTAssertThrowsError(try AppUpdate.install(dir.appendingPathComponent("gone/NXLibrary.app"), over: current,
                                                   trashOld: false))
        let exe = try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8)
        XCTAssertTrue(exe.contains("old"))
    }

    func testUpdatePreservesUserCopiesBesideTheCurrentApp() throws {
        for name in ["Oort NX", "Arcane", "NX Library"] {
            let installed = dir.appendingPathComponent(UUID().uuidString)
            let current = try makeApp(name + ".app", in: installed, marker: "current")
            let keptNew = try makeApp(name + " (new).app", in: installed, marker: "user-new")
            let keptOld = try makeApp(name + " (old).app", in: installed, marker: "user-old")
            let staged = try makeApp(in: dir.appendingPathComponent(UUID().uuidString), marker: "candidate")
            let placed = try AppUpdate.install(staged, over: current, trashOld: false)
            XCTAssertEqual(placed, current)
            XCTAssertTrue(try String(contentsOf: keptNew.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("user-new"))
            XCTAssertTrue(try String(contentsOf: keptOld.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("user-old"))
            XCTAssertTrue(try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("candidate"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "the verified download remains available")
        }
    }

    func testMissingCandidatePreservesUserCopies() throws {
        let current = try makeApp("Arcane.app", marker: "current")
        let keptNew = try makeApp("Arcane (new).app", marker: "user-new")
        let keptOld = try makeApp("Arcane (old).app", marker: "user-old")
        XCTAssertThrowsError(try AppUpdate.install(dir.appendingPathComponent("missing.app"), over: current, trashOld: false))
        for kept in [keptNew, keptOld, current] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: kept.appendingPathComponent("Contents/Info.plist").path))
        }
    }

    func testPartialCopyFailureKeepsCurrentAndCleansOwnedStage() throws {
        let installed = dir.appendingPathComponent("Applications")
        let current = try makeApp(in: installed, marker: "current")
        let staged = try makeApp(in: dir.appendingPathComponent("download"))
        XCTAssertThrowsError(try AppUpdate.install(staged, over: current, trashOld: false,
                                                  fileManager: UpdateCopyFailure(), io: BuildInstallIO()))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.path), ["NXLibrary.app"])
        XCTAssertTrue(try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("current"))
    }

    func testPublicationFailureKeepsCurrentAndCandidate() throws {
        let installed = dir.appendingPathComponent("Applications")
        let current = try makeApp(in: installed, marker: "current")
        let staged = try makeApp(in: dir.appendingPathComponent("download"))
        var io = BuildInstallIO()
        io.publish = { _, _, _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertThrowsError(try AppUpdate.install(staged, over: current, trashOld: false, fileManager: .default, io: io))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.path), ["NXLibrary.app"])
        XCTAssertTrue(try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("current"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }

    func testErrorAfterAtomicSwapFinishesTheInstalledUpdate() throws {
        let current = try makeApp("Arcane.app", marker: "current")
        let staged = try makeApp(in: dir.appendingPathComponent("download"), marker: "candidate")
        var io = BuildInstallIO()
        io.afterPublish = { throw CocoaError(.fileWriteUnknown) }
        XCTAssertEqual(try AppUpdate.install(staged, over: current, trashOld: false, fileManager: .default, io: io), current)
        XCTAssertTrue(try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("candidate"))
    }

    func testTrashFailureRetainsPreviousAppWithoutFailingSuccessfulInstall() throws {
        let installed = dir.appendingPathComponent("Applications")
        let current = try makeApp("Arcane.app", in: installed, marker: "current")
        let staged = try makeApp(in: dir.appendingPathComponent("download"), marker: "candidate")
        let fm = FileManager.default, refusing = TrashRefusal()
        XCTAssertEqual(try AppUpdate.install(staged, over: current, trashOld: true, fileManager: fm, io: BuildInstallIO(),
                                             trash: refusing.trash), current)
        let retained = try XCTUnwrap(refusing.retained)
        XCTAssertTrue(try String(contentsOf: retained.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("current"))
        XCTAssertEqual(retained.deletingLastPathComponent().deletingLastPathComponent().path, installed.path)
        XCTAssertTrue(try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("candidate"))
        XCTAssertEqual(try fm.attributesOfItem(atPath: retained.path)[.systemNumber] as? NSNumber,
                       try fm.attributesOfItem(atPath: current.path)[.systemNumber] as? NSNumber)
        let next = try makeApp(in: dir.appendingPathComponent("next-download"), marker: "next")
        _ = try AppUpdate.install(next, over: current, trashOld: true, fileManager: fm, io: BuildInstallIO(), trash: refusing.trash)
        let second = try XCTUnwrap(refusing.retained)
        XCTAssertNotEqual(second.deletingLastPathComponent(), retained.deletingLastPathComponent())
        XCTAssertTrue(try String(contentsOf: retained.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("current"))
        XCTAssertTrue(try String(contentsOf: second.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("candidate"))
    }

    func testAppChangedDuringCopyIsNotReplaced() throws {
        let current = try makeApp("Arcane.app", marker: "current")
        let staged = try makeApp(in: dir.appendingPathComponent("download"), marker: "candidate")
        let moved = dir.appendingPathComponent("moved.app")
        let fm = UpdateCopyHook {
            try FileManager.default.moveItem(at: current, to: moved)
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
        }
        XCTAssertThrowsError(try AppUpdate.install(staged, over: current, trashOld: false, fileManager: fm, io: BuildInstallIO()))
        XCTAssertTrue(try String(contentsOf: moved.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8).contains("current"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: current.path), [])
    }
}

private final class UpdateCopyFailure: FileManager, @unchecked Sendable {
    override func copyItem(at source: URL, to destination: URL) throws {
        try createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("partial".utf8).write(to: destination.appendingPathComponent("partial"))
        throw CocoaError(.fileWriteUnknown)
    }
}

/// A Trash that refuses every item and remembers the last one it was given.
private final class TrashRefusal: @unchecked Sendable {
    var retained: URL?
    func trash(_ url: URL) throws {
        retained = url
        throw CocoaError(.fileWriteNoPermission)
    }
}

private final class UpdateCopyHook: FileManager, @unchecked Sendable {
    let afterCopy: () throws -> Void
    init(afterCopy: @escaping () throws -> Void) { self.afterCopy = afterCopy; super.init() }
    override func copyItem(at source: URL, to destination: URL) throws {
        try super.copyItem(at: source, to: destination)
        try afterCopy()
    }
}
