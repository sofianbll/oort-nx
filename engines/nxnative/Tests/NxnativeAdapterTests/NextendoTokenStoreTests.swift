import Darwin
import XCTest
@testable import NxnativeAdapter

final class NextendoTokenStoreTests: XCTestCase {
    private func fixture() -> NextendoTokenStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Nextendo-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return NextendoTokenStore(directory: directory)
    }

    private func mode(_ url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        return try XCTUnwrap(value).intValue
    }

    func testPrivateAtomicReplacementAndLocalSignOut() async throws {
        let store = fixture()
        let file = store.directory.appendingPathComponent("refresh_token")
        let lock = store.directory.appendingPathComponent(".lock")
        XCTAssertFalse(try store.hasToken())
        try await NextendoOAuth(store: store).signOut()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))

        _ = try await store.withLock { try $0.write("first") }
        XCTAssertEqual(try mode(store.directory), 0o700)
        XCTAssertEqual(try mode(file), 0o600)
        XCTAssertEqual(try mode(lock), 0o600)
        XCTAssertTrue(try store.hasToken())
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        _ = try await store.withLock { try $0.write("second") }
        XCTAssertEqual(try reader.readToEnd(), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: file), Data("second".utf8))
        XCTAssertEqual(try mode(file), 0o600)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: store.directory.path)), [".lock", "refresh_token"])
        try await NextendoOAuth(store: store).signOut()
        try await NextendoOAuth(store: store).signOut()
        XCTAssertFalse(try store.hasToken())
        XCTAssertTrue(FileManager.default.fileExists(atPath: lock.path))
    }

    func testLockInteroperatesWithPOSIXAndCancellationDoesNotWrite() async throws {
        let store = fixture()
        _ = try await store.withLock { try $0.write("first") }
        let fd = open(store.directory.appendingPathComponent(".lock").path, O_RDWR | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = try await store.withLock { _ in
            XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), -1)
            XCTAssertEqual(errno, EWOULDBLOCK)
        }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        let pending = Task {
            try await store.withLock { file in
                XCTFail("A second writer entered the locked store")
                try file.write("wrong")
            }
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        pending.cancel()
        do {
            _ = try await pending.value
            XCTFail("Expected cancellation while waiting for the lock")
        } catch is CancellationError {}
        XCTAssertEqual(flock(fd, LOCK_UN), 0)
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("refresh_token")), Data("first".utf8))
    }

    func testRejectsInvalidCredentialsAndDoesNotFollowFileLink() async throws {
        let store = fixture()
        _ = try await store.withLock { try $0.write("first") }
        let file = store.directory.appendingPathComponent("refresh_token")
        do {
            _ = try await store.withLock { try $0.write(String(repeating: "x", count: 8193)) }
            XCTFail("Oversized refresh token must not replace the old one")
        } catch let error as NextendoError { XCTAssertEqual(error, .storage) }
        XCTAssertEqual(try Data(contentsOf: file), Data("first".utf8))
        XCTAssertEqual(chmod(file.path, 0o644), 0)
        XCTAssertThrowsError(try store.hasToken())
        let target = store.directory.appendingPathComponent("unrelated")
        try FileManager.default.moveItem(at: file, to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertThrowsError(try store.hasToken())
        try await NextendoOAuth(store: store).signOut()
        XCTAssertEqual(try Data(contentsOf: target), Data("first".utf8))
    }
}
