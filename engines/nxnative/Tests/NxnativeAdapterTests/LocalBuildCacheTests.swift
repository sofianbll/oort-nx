import XCTest
@testable import ArcanePorting

final class LocalBuildCacheTests: XCTestCase {
    private func cache(in root: URL, name: String, chain: String, ready: String?) throws -> URL {
        let cache = root.appendingPathComponent(name)
        let shaders = cache.appendingPathComponent("shader/cache")
        try FileManager.default.createDirectory(at: shaders, withIntermediateDirectories: true)
        try Data([1]).write(to: shaders.appendingPathComponent("b-\(chain).img"))
        if let ready {
            try "sha\n\(ready)\n".write(to: cache.appendingPathComponent("shader/mac-b-\(chain).key"), atomically: true, encoding: .utf8)
        }
        return cache
    }

    func testChainAndShaderCountComeFromTheCacheFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalBuildCache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try cache(in: root, name: "a", chain: "cb8db34ecfb3", ready: "28,603 of 28,603 shaders ready")
        XCTAssertEqual(LocalBuildCache.chain(ofCache: cache), "cb8db34ecfb3")
        XCTAssertEqual(LocalBuildCache.shaderCount(ofCache: cache), 28603)
        try Data([1]).write(to: cache.appendingPathComponent("shader/cache/b-000000000000.img"))
        XCTAssertNil(LocalBuildCache.chain(ofCache: cache), "Two chains: nothing is reused blindly")
        XCTAssertNil(LocalBuildCache.shaderCount(ofCache: root.appendingPathComponent("missing")))
    }

    func testAFinishedWorkFolderBecomesTheCacheAndTheOldOneIsKept() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalBuildCache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try cache(in: root, name: "Game/T_build", chain: "aaaaaaaaaaaa", ready: nil)
        let work = try cache(in: root, name: "Temp/T_build", chain: "bbbbbbbbbbbb", ready: "7 of 7 shaders ready")
        var retired: [URL] = []
        try LocalBuildCache.adopt(work, as: old) {
            XCTAssertEqual(LocalBuildCache.shaderCount(ofCache: old), 7)
            retired.append($0)
            try FileManager.default.moveItem(at: $0, to: root.appendingPathComponent("retired"))
        }
        XCTAssertEqual(retired.count, 1)
        XCTAssertNotEqual(retired.first?.path, old.path)
        XCTAssertEqual(LocalBuildCache.shaderCount(ofCache: old), 7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("retired/shader/cache/b-aaaaaaaaaaaa.img").path))
        let fresh = root.appendingPathComponent("Other/T_build")
        let again = try cache(in: root, name: "Temp2/T_build", chain: "cccccccccccc", ready: nil)
        try LocalBuildCache.adopt(again, as: fresh) { _ in XCTFail("Nothing to retire") }
        XCTAssertEqual(LocalBuildCache.chain(ofCache: fresh), "cccccccccccc")
    }

    func testFailedPreparationDoesNotTouchOldCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalBuildCache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try cache(in: root, name: "Game/T_build", chain: "aaaaaaaaaaaa", ready: nil)
        let work = try cache(in: root, name: "Temp/T_build", chain: "bbbbbbbbbbbb", ready: nil)
        XCTAssertThrowsError(try LocalBuildCache.adopt(work, as: old, prepare: { _, candidate in
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
            throw POSIXError(.ENOSPC)
        }, retire: { _ in XCTFail("Old cache must not be retired") }))
        XCTAssertEqual(LocalBuildCache.chain(ofCache: old), "aaaaaaaaaaaa")
        XCTAssertEqual(LocalBuildCache.chain(ofCache: work), "bbbbbbbbbbbb")
    }

    func testOnlyAFinishedShaderImageMakesALocalCacheUsable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalBuildCache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = try cache(in: root, name: "valid", chain: "cb8db34ecfb3", ready: nil)
        XCTAssertEqual(LocalBuildCache.usable(atPath: valid.path)?.path, valid.path)
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertNil(LocalBuildCache.usable(atPath: empty.path), "An empty folder is never a cache")
        XCTAssertNil(LocalBuildCache.usable(atPath: root.appendingPathComponent("missing").path))
        XCTAssertNil(LocalBuildCache.usable(atPath: nil))
    }
}
