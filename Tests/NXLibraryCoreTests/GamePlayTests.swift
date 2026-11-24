import XCTest
@testable import NXLibraryCore

final class GamePlayTests: XCTestCase {
    @MainActor func testRegisteringAThirdConnectorDoesNotChangeThePlayCaller() async {
        let steam = FixtureConnector(source: .steam, acceptance: .handedOff)
        let native = FixtureConnector(source: .init(rawValue: "nxnative"), acceptance: .gameOpened)
        let third = FixtureConnector(source: .init(rawValue: "fixture"), acceptance: .gameOpened)
        let profile = PlayProfile(id: UUID(), isGuest: true, blocksPlay: false)
        let record = FixtureRecord()
        let target = PlayTarget(game: .init(record: record, personalizationKey: "fixture"), sourceEnabled: true)
        let original = GamePlay([steam, native])
        XCTAssertEqual(original.availability(of: target), .unavailable(.unsupportedSource))
        XCTAssertEqual(original.play(target, profile: profile), .refused(.unsupportedSource))

        let extended = GamePlay([steam, native, third])
        var events: [PlayEvent] = []
        XCTAssertEqual(extended.availability(of: target), .available)
        XCTAssertEqual(extended.play(target, profile: profile, observe: { events.append($0) }), .accepted(.gameOpened))
        XCTAssertEqual(third.gameID, record.id)
        XCTAssertEqual(third.installation, "fixture-installation")
        XCTAssertEqual(third.profile, profile)
        XCTAssertEqual(events, [.ready, .exited])
        XCTAssertNil(steam.gameID)
        XCTAssertNil(native.gameID)

        let disabled = PlayTarget(game: target.game, sourceEnabled: false)
        XCTAssertEqual(extended.play(disabled, profile: profile), .refused(.sourceDisabled))
        XCTAssertEqual(extended.play(nil, profile: profile), .refused(.missingTarget))
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
        XCTAssertEqual(extended.play(steamTarget, profile: profile), .accepted(.handedOff))

        steamGame.installations.append(.init(libraryURL: library, contentURL: content.appendingPathComponent("Other"),
                                            applications: [application], availability: .available))
        let ambiguous = PlayTarget(game: .init(steam: steamGame), sourceEnabled: true)
        XCTAssertEqual(extended.play(ambiguous, profile: profile), .refused(.installationNeedsReview))
        XCTAssertNil(ambiguous.installation)
        XCTAssertEqual(steam.attempts, 1)
    }
}

@MainActor private final class FixtureConnector: PlayConnector {
    let source: CatalogIntegration
    let acceptance: PlayAcceptance
    var gameID: UUID?
    var installation: String?
    var profile: PlayProfile?
    var attempts = 0

    init(source: CatalogIntegration, acceptance: PlayAcceptance) {
        self.source = source
        self.acceptance = acceptance
    }

    func availability(of target: PlayTarget) -> PlayAvailability { target.installationAvailability }

    func play(_ target: PlayTarget, profile: PlayProfile, observe: PlayObserver?) -> PlayResult {
        if case .unavailable(let reason) = availability(of: target) { return .refused(reason) }
        attempts += 1
        gameID = target.game.id
        installation = target.installation?.id
        self.profile = profile
        observe?(.ready)
        observe?(.exited)
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
