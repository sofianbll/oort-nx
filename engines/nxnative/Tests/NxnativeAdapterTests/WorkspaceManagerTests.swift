import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class WorkspaceManagerTests: XCTestCase {
    func testStagedWorkspaceUsesSymlinksAndFindsCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXWork-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let file = sources.appendingPathComponent("Game [0100000000010000].nsp")
        try Data("x".utf8).write(to: file)
        let source = DetectedSource(id: UUID(), url: file, kind: .base,
                                    titleId: 0x0100000000010000, version: 0,
                                    sizeBytes: 1)
        let game = DetectedGame(baseTitleId: 0x0100000000010000, name: "Game",
                                base: source, updates: [], dlcs: [])
        let manager = WorkspaceManager(root: root.appendingPathComponent("workspaces"))
        let planned = manager.plannedWorkspace(for: game, mode: .staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: planned.directory.path), "A blocked build only plans paths")
        let sourcesOnly = try manager.makeWorkspace(for: game, mode: .staged, createCache: false)
        XCTAssertEqual(sourcesOnly.directory, planned.directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: planned.buildCache.path))
        let backup = planned.directory.appendingPathComponent(".arcane-cloud-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        let backupLink = backup.appendingPathComponent("preserved-link")
        try FileManager.default.createSymbolicLink(atPath: backupLink.path, withDestinationPath: "kept")
        let ws = try manager.makeWorkspace(for: game, mode: .staged)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: backupLink.path), "kept")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: ws.directory.appendingPathComponent(file.lastPathComponent).path))
        let link = try FileManager.default.destinationOfSymbolicLink(
            atPath: ws.directory.appendingPathComponent(file.lastPathComponent).path)
        XCTAssertTrue(link.hasSuffix(file.lastPathComponent))
        try Data("cache".utf8).write(to: ws.buildCache.appendingPathComponent("marker"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ws.buildCache.appendingPathComponent("marker").path))
        try? FileManager.default.removeItem(at: root)
    }

    func testStagingRejectsDistinctSourcesWithTheSameNameBeforeChangingExistingLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NXWorkDuplicate-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let baseURL = root.appendingPathComponent("base/Game.nsp")
        let dlcURL = root.appendingPathComponent("dlc/Game.nsp")
        for url in [baseURL, dlcURL] {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
        let base = DetectedSource(id: UUID(), url: baseURL, kind: .base, titleId: 0x0100000000010000,
                                  version: 0, sizeBytes: 1)
        let dlc = DetectedSource(id: UUID(), url: dlcURL, kind: .dlc, titleId: 0x0100000000011001,
                                 version: 0, sizeBytes: 1)
        let shared = DetectedSource(id: UUID(), url: baseURL, kind: .dlc, titleId: dlc.titleId,
                                    version: 0, sizeBytes: 1)
        let manager = WorkspaceManager(root: root.appendingPathComponent("workspaces"))
        let valid = DetectedGame(baseTitleId: base.titleId, name: "Game", base: base, updates: [], dlcs: [shared])
        let workspace = try manager.makeWorkspace(for: valid, mode: .staged)
        XCTAssertEqual(workspace.links.count, 1, "one physical package may contain both items")
        let invalid = DetectedGame(baseTitleId: base.titleId, name: "Game", base: base, updates: [], dlcs: [dlc])
        XCTAssertThrowsError(try manager.makeWorkspace(for: invalid, mode: .staged))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: XCTUnwrap(workspace.links.first).path), baseURL.path)
    }

    func testFolderModeKeepsFolderAndBuildCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXWorkFolder-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Game Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = DetectedSource(id: UUID(), url: folder.appendingPathComponent("a.nsp"),
                                    kind: .base, titleId: 0x0100000000010000,
                                    version: 0, sizeBytes: 1)
        let game = DetectedGame(baseTitleId: 0x0100000000010000, name: "Game",
                                base: source, updates: [], dlcs: [])
        let manager = WorkspaceManager(root: root.appendingPathComponent("workspaces"))
        let ws = try manager.makeWorkspace(for: game, mode: .folder(folder))
        XCTAssertEqual(ws.directory, folder)
        XCTAssertTrue(ws.links.isEmpty)
        XCTAssertTrue(ws.buildCache.lastPathComponent.hasSuffix("_build"))
        try? FileManager.default.removeItem(at: root)
    }

    func testSpacesApostrophesAndBrokenLinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXWorkNames-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sorgenti è prova")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let file = sources.appendingPathComponent("Gioco dell'Eroe [0100000000010000].nsp")
        try Data("x".utf8).write(to: file)
        let source = DetectedSource(id: UUID(), url: file, kind: .base,
                                    titleId: 0x0100000000010000, version: 0, sizeBytes: 1)
        let game = DetectedGame(baseTitleId: 0x0100000000010000, name: "Gioco",
                                base: source, updates: [], dlcs: [])
        let manager = WorkspaceManager(root: root.appendingPathComponent("workspaces"))
        let ws = try manager.makeWorkspace(for: game, mode: .staged)
        let link = ws.directory.appendingPathComponent(file.lastPathComponent)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                       file.path)
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(manager.brokenLinks(in: ws.directory).contains(link))
        try? FileManager.default.removeItem(at: root)
    }
}
