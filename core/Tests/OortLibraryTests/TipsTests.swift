import XCTest
@testable import NXLibraryCore

final class TipsTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tips-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try XCTUnwrap(UserDefaults(suiteName: root.appendingPathComponent("prefs").path))
    }

    func testATipShowsOnceAtItsMomentAndNeverAgain() throws {
        let store = try defaults()
        let tips = Tips(defaults: store)
        tips.libraryAppeared(games: 11, enabled: true)
        XCTAssertNil(tips.shown)
        tips.libraryAppeared(games: 12, enabled: true)
        XCTAssertEqual(tips.shown, .search)
        tips.dismiss()
        tips.libraryAppeared(games: 40, enabled: true)
        XCTAssertNil(tips.shown)
        let restarted = Tips(defaults: store)
        restarted.libraryAppeared(games: 40, enabled: true)
        XCTAssertNil(restarted.shown)
    }

    func testOnlyOnePerSession() throws {
        let tips = Tips(defaults: try defaults())
        let one = UUID(), two = UUID()
        tips.settingChanged(for: one, enabled: true)
        tips.settingChanged(for: one, enabled: true)
        XCTAssertNil(tips.shown)
        tips.settingChanged(for: two, enabled: true)
        XCTAssertEqual(tips.shown, .copySettings)
        tips.dismiss()
        tips.libraryAppeared(games: 99, enabled: true)
        XCTAssertNil(tips.shown)
    }

    func testTurnedOffNothingIsShownOrUsedUp() throws {
        let store = try defaults()
        let tips = Tips(defaults: store)
        tips.libraryAppeared(games: 99, enabled: false)
        XCTAssertNil(tips.shown)
        XCTAssertNil(store.object(forKey: Tips.storageKey))
        tips.libraryAppeared(games: 99, enabled: true)
        XCTAssertEqual(tips.shown, .search)
    }

    func testThreeTipsAtMost() { XCTAssertLessThanOrEqual(Tip.allCases.count, 3) }
}
