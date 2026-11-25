import Foundation
import XCTest
@testable import OortCore

final class ShelfTests: XCTestCase {
    private final class Choices: ShelfChoices, @unchecked Sendable {
        var values: [String: Set<String>] = [:]
        func permissions(of connector: String) -> Set<String>? { values[connector] }
        func set(_ permissions: Set<String>?, of connector: String) { values[connector] = permissions }
    }

    private struct Empty: ShelfSource {
        let root = "R"
        func children(of folder: String) async throws -> [ShelfNode] { [] }
        func fetch(_ file: ShelfNode, range: Range<Int64>, to destination: URL) async throws { throw ShelfError.notFound }
    }

    private final class Counter: @unchecked Sendable { var opened = 0, forgotten = 0 }

    private func connector(_ permissions: Set<ShelfConnector.Permission>, _ counter: Counter) -> ShelfConnector {
        .init(id: "x", hosts: [], permissions: permissions, open: { counter.opened += 1; return Empty() }, forget: { counter.forgotten += 1 })
    }

    func testAConnectorIsOffUntilThePlayerAgreesToEverythingItAsks() async throws {
        let choices = Choices(), counter = Counter()
        let connectors = ShelfConnectors([connector([.network, .readLibrary], counter)], choices: choices)
        XCTAssertFalse(connectors.isOn("x"))
        do { _ = try await connectors.source("x"); XCTFail("opened") } catch { XCTAssertEqual(error as? ShelfError, .sourceOff) }
        XCTAssertThrowsError(try connectors.turnOn("x", granting: [.network]))
        XCTAssertThrowsError(try connectors.turnOn("unknown", granting: [.network]))
        XCTAssertEqual(counter.opened, 0)
        try connectors.turnOn("x", granting: [.network, .readLibrary])
        _ = try await connectors.source("x")
        XCTAssertEqual(counter.opened, 1)
        // A version that asks for more is off again.
        let wider = ShelfConnectors([connector([.network, .readLibrary, .storeBuilds], counter)], choices: choices)
        XCTAssertFalse(wider.isOn("x"))
        // A build of the app without it does not know it any more.
        XCTAssertFalse(ShelfConnectors([], choices: choices).isOn("x"))
        try await connectors.turnOff("x")
        XCTAssertFalse(connectors.isOn("x"))
        XCTAssertEqual(counter.forgotten, 1)
    }

    func testVersionsAndNames() {
        XCTAssertEqual(ShelfNames.compareVersions("26", "26.0"), 0)
        XCTAssertEqual(ShelfNames.compareVersions("26.10", "26.9"), 1)
        XCTAssertEqual(ShelfNames.compareVersions("18.7.1", "26"), -1)
        for bad in ["", ".", "1.", "1.x", "-1", "1.2.3.4.5", "9999999", "\u{0661}"] { XCTAssertNil(ShelfNames.compareVersions(bad, "1"), bad) }
        XCTAssertEqual(ShelfNames.titleID(inFolder: "A [0100000000010000]"), "0100000000010000")
        XCTAssertEqual(ShelfNames.titleID(inFolder: "0100000000010000"), "0100000000010000")
        for bad in ["A[0100000000010000]", "A [010000000001000]", "A [0100000000010abc]", "A/B [0100000000010000]", "A [0100000000010000] "] {
            XCTAssertNil(ShelfNames.titleID(inFolder: bad), bad)
        }
        XCTAssertEqual(ShelfNames.displayName("\u{202E}", titleID: "0100000000010000"), "0100000000010000")
        for good in ["a", "Game.framework/Info.plist", "data/romfs.img", "é/日本.bin", "a b/c"] { XCTAssertTrue(ShelfNames.isSafePath(good), good) }
    }

    func testRetryWaitsLongerEachTimeAndLeavesOtherErrorsAlone() async throws {
        let waits = WaitLog()
        let retry = ShelfRetry(attempts: 4) { waits.add($0) }
        do { try await retry.run { throw ShelfError.server } ; XCTFail("no error") } catch { XCTAssertEqual(error as? ShelfError, .server) }
        XCTAssertEqual(waits.all, [1, 2, 4])
        do { try await retry.run { throw ShelfError.accessDenied } ; XCTFail("no error") } catch { XCTAssertEqual(error as? ShelfError, .accessDenied) }
        XCTAssertEqual(waits.all, [1, 2, 4])
    }

    private final class WaitLog: @unchecked Sendable {
        private(set) var all: [Int] = []
        func add(_ seconds: Int) { all.append(seconds) }
    }
}
