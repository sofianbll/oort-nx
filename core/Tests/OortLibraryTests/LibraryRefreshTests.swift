import XCTest
@testable import OortLibrary

final class LibraryRefreshTests: XCTestCase {
    func testItEndsWithItsLastPartAndSaysWhatChanged() {
        var refresh = LibraryRefresh(parts: [.apps, .cloud])
        XCTAssertEqual(refresh.outcome, .running)
        refresh.end(.apps, .read)
        XCTAssertEqual(refresh.reading, [.cloud])
        refresh.end(.cloud, .read)
        XCTAssertEqual(refresh.outcome, .upToDate)
        refresh.noteAdded(2)
        refresh.noteAdded(1)
        XCTAssertEqual(refresh.outcome, .changed(2))
    }

    func testAPartThatIsStaleIsNeverHiddenByTheOthers() {
        var refresh = LibraryRefresh(parts: [.apps, .steam, .cloud])
        refresh.noteAdded(4)
        refresh.end(.cloud, .stale("offline"))
        refresh.end(.apps, .read)
        XCTAssertEqual(refresh.outcome, .running)
        refresh.end(.steam, .read)
        XCTAssertEqual(refresh.outcome, .incomplete)
        XCTAssertEqual(refresh.stale.map(\.part), [.cloud])
        XCTAssertEqual(refresh.stale.map(\.reason), ["offline"])
    }

    func testALateAnswerChangesNothing() {
        var refresh = LibraryRefresh(parts: [.apps, .cloud])
        refresh.end(.apps, .read)
        refresh.cancel()
        XCTAssertEqual(refresh.outcome, .cancelled)
        refresh.end(.cloud, .stale("late"))
        refresh.end(.apps, .stale("late"))
        refresh.end(.steam, .read)
        XCTAssertEqual(refresh.outcome, .cancelled)
        XCTAssertEqual(refresh.states, [.apps: .read, .cloud: .cancelled])
    }

    func testNothingToReadIsUpToDate() {
        XCTAssertEqual(LibraryRefresh(parts: []).outcome, .upToDate)
    }

    func testTheRowSitsBeforeResults() {
        let refresh = UUID(), result = UUID()
        XCTAssertEqual(ActivityCenterFocus.rows(isBuilding: false, refresh: refresh, results: [result]),
                       [.refresh(refresh), .result(result), .clearAll])
    }
}
