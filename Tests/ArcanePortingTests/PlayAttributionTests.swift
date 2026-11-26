import Foundation
import XCTest
@testable import ArcanePorting

final class PlayAttributionTests: XCTestCase {
    func testOnlyOneNewProcessBornAfterTheGestureCanBeAttributed() {
        let gesture = Date(timeIntervalSince1970: 100)
        let after = gesture.addingTimeInterval(1)
        let proof = PlayAttribution(startedAt: gesture, before: [1])
        XCTAssertTrue(proof.accepts(pid: 2, born: after, after: [1, 2], belongsToGesture: true))
        XCTAssertFalse(proof.accepts(pid: 1, born: after, after: [1], belongsToGesture: true))
        XCTAssertFalse(proof.accepts(pid: 2, born: gesture, after: [2], belongsToGesture: true))
        XCTAssertFalse(proof.accepts(pid: 2, born: nil, after: [2], belongsToGesture: true))
        XCTAssertFalse(proof.accepts(pid: 2, born: after, after: [1, 2, 3], belongsToGesture: true))
        XCTAssertFalse(proof.accepts(pid: 2, born: after, after: [1], belongsToGesture: true))
        // An outside launch in the gap fits all the timing and PID conditions.
        XCTAssertFalse(proof.accepts(pid: 2, born: after, after: [2], belongsToGesture: false))
    }
}
