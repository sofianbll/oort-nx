import XCTest
@testable import NXLibraryCore

final class PlayEngineTests: XCTestCase {
    @MainActor func testRegisteringAThirdAdapterDoesNotChangeThePlayCaller() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let steam = FixtureAdapter(source: .steam, acceptance: .handedOff)
        let native = FixtureAdapter(source: .init(rawValue: "nxnative"), acceptance: .gameOpened)
        let third = FixtureAdapter(source: .init(rawValue: "fixture"), acceptance: .gameOpened)
        let profile = PlayProfile(id: UUID(), isGuest: true, blocksPlay: false)
        let record = FixtureRecord()
        let target = PlayTarget(game: .init(record: record, personalizationKey: "fixture"), sourceEnabled: true)
        let original = PlayEngine([steam, native], directory: directory)
        XCTAssertEqual(original.availability(of: target), .unavailable(.unsupportedSource))
        XCTAssertEqual(original.play(target, profile: profile, request: RequestID(UUID())).admission, .refused(.unsupportedSource))

        let extended = PlayEngine([steam, native, third], directory: directory)
        let request = RequestID(UUID())
        var events: [PlayEvent] = []
        XCTAssertEqual(extended.availability(of: target), .available)
        let received = extended.play(target, profile: profile, request: request, observe: { events.append($0) })
        XCTAssertEqual(received.admission, .accepted(.gameOpened))
        XCTAssertEqual(extended.play(target, profile: profile, request: request), received)
        let restarted = PlayEngine([steam, native, third], directory: directory)
        var replayed: [PlayEvent] = []
        XCTAssertEqual(restarted.play(target, profile: profile, request: request, observe: { replayed.append($0) }), received)
        XCTAssertEqual(replayed, events)
        XCTAssertEqual(third.gameID, record.id)
        XCTAssertEqual(third.installation, "fixture-installation")
        XCTAssertEqual(third.profile, profile)
        XCTAssertEqual(events, [.ready, .exited])
        XCTAssertNil(steam.gameID)
        XCTAssertNil(native.gameID)

        let disabled = PlayTarget(game: target.game, sourceEnabled: false)
        XCTAssertEqual(extended.play(disabled, profile: profile, request: request).admission, .refused(.stale))
        XCTAssertEqual(extended.play(disabled, profile: profile, request: RequestID(UUID())).admission, .refused(.sourceDisabled))
        XCTAssertEqual(extended.play(nil, profile: profile, request: RequestID(UUID())).admission, .refused(.missingTarget))
        XCTAssertEqual(third.attempts, 1, "The fake starts only a usable installation.")

        var steamGame = SteamCatalogGame(appID: 42, name: "Steam fixture")
        steamGame.hasBeenRecognized = true
        let library = URL(fileURLWithPath: "/fixture/Steam")
        let content = library.appendingPathComponent("steamapps/common/Fixture")
        let app = content.appendingPathComponent("Fixture.app")
        let application = CatalogNativeApplication(NativeMacApplication(
            url: app, executableURL: app.appendingPathComponent("Contents/MacOS/Fixture"),
            bundleIdentifier: "test.fixture", name: "Fixture", architectures: [.arm64],
            isDeclaredGame: true, fileObservations: []))
        let installation = SteamCatalogInstallation(libraryURL: library, contentURL: content,
                                                    applications: [application], availability: .available)
        steamGame.installations = [installation]
        let steamTarget = PlayTarget(game: .init(steam: steamGame), sourceEnabled: true)
        XCTAssertEqual(extended.play(steamTarget, profile: profile, request: RequestID(UUID())).admission, .accepted(.handedOff))

        steamGame.installations.append(.init(libraryURL: library, contentURL: content.appendingPathComponent("Other"),
                                            applications: [application], availability: .available))
        let ambiguous = PlayTarget(game: .init(steam: steamGame), sourceEnabled: true)
        XCTAssertEqual(extended.play(ambiguous, profile: profile, request: RequestID(UUID())).admission, .refused(.installationNeedsReview))
        XCTAssertNil(ambiguous.installation)
        XCTAssertEqual(steam.attempts, 1)
    }

    @MainActor func testInterruptedHandoffCannotBeResubmittedByEitherAlias() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let adapter = FixtureAdapter(source: FixtureRecord.integration, acceptance: .pending)
        let original = PlayEngine([adapter], directory: directory)
        let target = PlayTarget(game: .init(record: FixtureRecord(), personalizationKey: "one"), sourceEnabled: true)
        let alias = PlayTarget(game: .init(record: FixtureRecord(), personalizationKey: "two"), sourceEnabled: true)
        let profile = PlayProfile(id: nil, isGuest: false, blocksPlay: false)
        let request = RequestID(UUID())
        let received = original.play(target, profile: profile, request: request)
        XCTAssertEqual(received.admission, .accepted(.pending))
        XCTAssertEqual(original.play(target, profile: profile, request: request), received)
        XCTAssertEqual(original.play(alias, profile: profile, request: RequestID(UUID())).admission, .refused(.outcomeUnknown))
        let restarted = PlayEngine([adapter], directory: directory)
        XCTAssertEqual(restarted.play(target, profile: profile, request: request).admission, .refused(.outcomeUnknown))
        XCTAssertEqual(restarted.play(alias, profile: profile, request: RequestID(UUID())).admission, .refused(.outcomeUnknown))
        XCTAssertEqual(adapter.attempts, 1)
    }
}

@MainActor private final class FixtureAdapter: PlayAdapter {
    let source: CatalogIntegration
    let acceptance: PlayAcceptance
    var gameID: UUID?
    var installation: String?
    var profile: PlayProfile?
    var attempts = 0
    private var waiting: PlayGesture?

    init(source: CatalogIntegration, acceptance: PlayAcceptance) {
        self.source = source
        self.acceptance = acceptance
    }

    func availability(of target: PlayTarget) -> PlayAvailability { target.installationAvailability }

    func admit(_ target: PlayTarget, profile: PlayProfile, gesture: PlayGesture) -> PlayResult {
        if case .unavailable(let reason) = availability(of: target) { return .refused(reason) }
        if acceptance == .pending, let reason = gesture.reserve("fixture-app") { return .refused(reason) }
        if acceptance == .pending { waiting = gesture }
        attempts += 1
        gameID = target.game.id
        installation = target.installation?.id
        self.profile = profile
        if acceptance != .pending {
            gesture.emit(.ready)
            gesture.emit(.exited)
        }
        return .accepted(acceptance)
    }
}

private struct FixtureRecord: CatalogSourceRecord {
    static let integration = CatalogIntegration(rawValue: "fixture")
    var id = UUID()
    var name = "Fixture"
    var isFavorite = false
    var isHidden = false
    var isInstalledForLibrary: Bool { true }
    var librarySearchTerms: [String] { [] }

    func validateRecord(personalizationKey: String) throws {}

    func presence(sourceEnabled: Bool) -> CatalogRecordPresence {
        .init(requiresReview: false, isDownloading: false, isListedNormally: sourceEnabled,
              launchTarget: nil, installations: [
                .init(id: "fixture-installation", contentURL: URL(fileURLWithPath: "/fixture"),
                      applicationURL: nil, executableURL: nil, bundleIdentifier: nil, availability: .available, size: .unknown)
              ])
    }
}
