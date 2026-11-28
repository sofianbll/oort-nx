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

    func testAProfileChangeAndAGuestAreSeen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("profiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalProfileStore(directory: directory, settings: AppSettings(), name: "First")
        var renamed = try XCTUnwrap(store.active)
        renamed.name = "Renamed"
        XCTAssertTrue(notifies({ _ = store.profiles }, when: { _ = store.update(renamed) }))
        let guest = LocalProfile(name: "Guest", look: LocalProfile.Look(AppSettings()))
        XCTAssertTrue(notifies({ _ = store.active }, when: { _ = store.beginGuest(guest) }))
    }

    func testAStartIsSeenAndAnnouncedOnce() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PlaySessionStore(fileURL: folder.appendingPathComponent("play-sessions.json"))
        var started: [UUID] = []
        store.onStart = { started.append($0) }
        let game = UUID()
        XCTAssertTrue(notifies({ _ = store.sessions }, when: { store.start(gameID: game, sourceID: "steam-440") }))
        store.start(gameID: game, sourceID: "steam-440")
        XCTAssertEqual(started, [game])
    }

    func testAPictureChoiceAndAPersonalValueAreSeen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("art-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let picks = ArtworkPicks(directory: directory)
        XCTAssertTrue(notifies({ _ = picks.revision }, when: { picks.remove(titleID: "0100", slot: .cover) }))
        let personal = SteamPersonalizationStore(directory: directory)
        XCTAssertTrue(try notifies({ _ = personal.value(titleID: "10", field: .description) }, when: {
            try personal.save(fields: [.description: "Mine"], images: [:], automatic: [], titleID: "10")
        }), "a view that reads a value redraws when it changes")
    }

    @MainActor
    func testALanguageChangeIsSeen() {
        let localization = AppLocalization()
        var settings = AppSettings()
        settings.appLanguage = settings.appLanguage == .french ? .english : .french
        XCTAssertTrue(notifies({ _ = localization.context }, when: { localization.configure(settings) }))
        L10n.setContext(AppLocale(language: .english, region: "US"))
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return raised }
    func set() { lock.lock(); raised = true; lock.unlock() }
}
