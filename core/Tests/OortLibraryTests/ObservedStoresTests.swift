import Observation
import XCTest
@testable import OortLibrary

/// The stores a screen watches tell it when what it shows changes, and only then (Observation, on every system).
final class ObservedStoresTests: XCTestCase {
    /// Whether reading `read` and then running `change` notifies the reader.
    private func notifies(_ read: () -> Void, when change: () throws -> Void) rethrows -> Bool {
        let told = LockedFlag()
        withObservationTracking(read, onChange: { told.set() })
        try change()
        return told.value
    }

    func testATipShownOrDismissedIsSeen() {
        let suite = "oort.tests.tips.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tips = Tips(defaults: defaults)
        XCTAssertTrue(notifies({ _ = tips.shown }, when: { tips.libraryAppeared(games: Tips.longLibrary, enabled: true) }))
        XCTAssertTrue(notifies({ _ = tips.shown }, when: { tips.dismiss() }))
    }

    func testAnUndoOfferAndItsNoticeAreSeen() {
        let offers = UndoOffers()
        XCTAssertTrue(notifies({ _ = offers.offer }, when: { offers.offer("Removed", undo: {}) }))
        let id = try! XCTUnwrap(offers.offer?.id)
        XCTAssertTrue(notifies({ _ = offers.isShown }, when: { offers.hide(id) }))
    }

    func testAMetadataPickBumpsTheRevisionAScreenReads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("picks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let picks = MetadataPicks(directory: directory)
        XCTAssertTrue(try notifies({ _ = picks.revision }, when: { try picks.set("A game", titleID: "0100", field: .description) }))
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return raised }
    func set() { lock.lock(); raised = true; lock.unlock() }
}
