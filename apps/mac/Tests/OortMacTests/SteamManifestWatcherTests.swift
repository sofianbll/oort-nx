import XCTest
@testable import OortMac

final class SteamManifestWatcherTests: XCTestCase {
    @MainActor
    func testRetriesTheSameLibraryWhenItsFolderBecomesAvailable() async throws {
        let f = try WatchedSteamFolders.temporary(in: self)
        let library = f.root.appendingPathComponent("Later")
        let changed = expectation(description: "Newly available library is watched")
        let watcher = SteamManifestWatcher { changed.fulfill() }
        defer { watcher.stop() }
        watcher.watch([library], root: library)
        _ = try f.library("Later")
        watcher.watch([library], root: library)
        try f.manifest(in: library)
        await fulfillment(of: [changed], timeout: 6)
    }

    @MainActor
    func testAddsANewlyAvailableLibraryAlongsideAnExistingStream() async throws {
        let f = try WatchedSteamFolders.temporary(in: self)
        let root = try f.library()
        let library = f.root.appendingPathComponent("Later")
        let changed = expectation(description: "Additional library is watched")
        let watcher = SteamManifestWatcher { changed.fulfill() }
        defer { watcher.stop() }
        watcher.watch([root, library], root: root)
        _ = try f.library("Later")
        watcher.watch([root, library], root: root)
        try f.manifest(in: library)
        await fulfillment(of: [changed], timeout: 6)
    }

    @MainActor
    func testTheStreamKeepsItsWatcherAliveUntilStopped() throws {
        let f = try WatchedSteamFolders.temporary(in: self)
        let library = try f.library()
        weak var weakWatcher: SteamManifestWatcher?
        do {
            let watcher = SteamManifestWatcher()
            watcher.watch([library], root: library)
            weakWatcher = watcher
        }
        // A callback already queued must still find its watcher.
        XCTAssertNotNil(weakWatcher)
        weakWatcher?.stop()
        // The stream lets go of its context on its queue (the main one).
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(weakWatcher)
    }
}

/// Steam folders the watcher can see: a library's `steamapps` and one manifest; nothing else is read.
private struct WatchedSteamFolders {
    let root: URL

    static func temporary(in test: XCTestCase) throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SteamWatcherTests-" + UUID().uuidString)
            .resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        test.addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return Self(root: root)
    }

    func library(_ relative: String = "Steam") throws -> URL {
        let library = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("steamapps/common"), withIntermediateDirectories: true)
        return library
    }

    func manifest(in library: URL) throws {
        let text = "\"AppState\" { \"appid\" \"10\" \"name\" \"First game\" \"installdir\" \"First\" }"
        try Data(text.utf8).write(to: library.appendingPathComponent("steamapps/appmanifest_10.acf"))
    }
}
