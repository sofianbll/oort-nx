import XCTest
@testable import OortLibrary
@testable import NxnativeAdapter

/// The Mac's own observations and its settings effect; the decisions are tested in IntegrationScreenTests.
final class IntegrationOverviewTests: XCTestCase {
    func testRoutesUseExistingSettingsAndBackKeepsTheOrigin() {
        var facts = IntegrationOverview.mac
        let router = AppRouter()
        router.showsIntegrationBar = true
        router.openIntegrations()
        XCTAssertTrue(IntegrationOverview.open(.steam, facts, in: router))
        XCTAssertEqual(router.route, .settings(.sources))
        XCTAssertEqual(router.settingsRowID, "steamSource")
        router.back()
        XCTAssertEqual(router.route, .integrations)
        XCTAssertEqual(router.integrationFocus, .steam)
        XCTAssertTrue(IntegrationOverview.open(.drive, facts, in: router))
        XCTAssertEqual(router.settingsRowID, "cloudLibrarySetup")
        router.back()
        facts.drive = .failed
        XCTAssertTrue(IntegrationOverview.open(.drive, facts, in: router))
        XCTAssertEqual(router.settingsRowID, "cloudLibraryService")
        router.back()
        router.back()
        XCTAssertEqual(router.route, .library)
        XCTAssertTrue(router.integrationBarFocused)
    }

    func testOnlyCurrentPageCanOpenExistingSettings() {
        var facts = IntegrationOverview.mac
        let router = AppRouter()
        router.showsIntegrationBar = true
        XCTAssertFalse(IntegrationOverview.open(.drive, facts, in: router))
        XCTAssertEqual(router.route, .library)
        XCTAssertFalse(router.integrationBarFocused)
        router.openCollection()
        router.openIntegrations()
        facts.engine = .blocked
        facts.nextendo = .connected
        facts.steamGridDB = true
        facts.drive = .transferring
        for (id, section, setting) in [
            (IntegrationID.switchGames, SettingsSection.engine, "engineStatus"),
            (.steam, .sources, "steamSource"),
            (.macApps, .sources, "macShortcutAdd"),
            (.drive, .cloudLibrary, "cloudLibraryEnabled"),
            (.nextendo, .profileNextendo, "nextendo"),
            (.images, .apiServices, "igdb"),
            (.saves, .cloudSaves, "cloudSaves"),
        ] {
            XCTAssertTrue(IntegrationOverview.open(id, facts, in: router))
            XCTAssertEqual(router.route, .settings(section))
            XCTAssertEqual(router.settingsRowID, setting)
            router.back()
            XCTAssertEqual(router.integrationFocus, id)
        }
        XCTAssertFalse(IntegrationOverview.open(.online, facts, in: router), "not offered on the Mac")
        router.back()
        XCTAssertEqual(router.route, .collection)
        XCTAssertTrue(router.integrationBarFocused)
    }

    func testDetailDoesNotOpenSettingsAndBackReturnsToSameRow() {
        let facts = IntegrationOverview.mac
        let router = AppRouter()
        router.showsIntegrationBar = true
        router.openIntegrations()
        router.showIntegrationDetail(.macApps)
        XCTAssertEqual(router.route, .integrations)
        XCTAssertEqual(router.integrationDetail, .macApps)
        XCTAssertNil(router.settingsRowID)
        XCTAssertTrue(IntegrationOverview.open(.macApps, facts, in: router))
        router.back()
        XCTAssertEqual(router.integrationDetail, .macApps)
        router.backFromIntegration()
        XCTAssertNil(router.integrationDetail)
        XCTAssertEqual(router.integrationFocus, .macApps)
        router.showIntegrationDetail(.switchGames)
        router.browseIntegrationLibrary(.nxnative)
        XCTAssertEqual(router.route, .library)
        XCTAssertNil(router.settingsRowID)
        XCTAssertEqual(router.takeIntegrationLibraryPlatform(), .nxnative)
        XCTAssertNil(router.takeIntegrationLibraryPlatform())
    }

    /// Which check blocks says what is blamed: Metal is Apple's tools, a commit alone the engine's version.
    func testBuildBlockNamesTheRealCause() {
        func report(_ blocking: [String]) -> CompatibilityReport {
            .init(ok: blocking.isEmpty, checks: ["commit", "tree", "metal", "python", "cli"].map {
                .init(id: $0, title: $0, status: blocking.contains($0) ? .block : .pass, detail: "")
            })
        }
        XCTAssertEqual(IntegrationOverview.buildBlock(report(["metal", "commit"]), canPass: false, canBuild: true), .appleTools)
        XCTAssertEqual(IntegrationOverview.buildBlock(report(["commit"]), canPass: false, canBuild: true), .engineVersion)
        XCTAssertEqual(IntegrationOverview.buildBlock(report(["tree"]), canPass: false, canBuild: true), .buildTools)
        XCTAssertEqual(IntegrationOverview.buildBlock(report(["python", "commit"]), canPass: false, canBuild: true), .buildTools)
        XCTAssertNil(IntegrationOverview.buildBlock(report(["metal"]), canPass: true, canBuild: true), "the override lets it pass")
        XCTAssertEqual(IntegrationOverview.buildBlock(nil, canPass: false, canBuild: false), .buildTools)
        XCTAssertNil(IntegrationOverview.buildBlock(nil, canPass: false, canBuild: nil))
    }

    func testKeysAndSavesAreSaidAsFacts() {
        XCTAssertEqual(IntegrationOverview.keys(.available(applicationGenerations: 1)), .selected)
        XCTAssertNil(IntegrationOverview.keys(nil))
        XCTAssertEqual(IntegrationOverview.saves(.folder("/fixture")), .folder)
    }

    func testTheBarOnlyTakesConfirmAfterExplicitFocusEvenWhenAServiceFails() {
        let router = AppRouter()
        router.showsIntegrationBar = true
        var profileFocused = false
        var facts = IntegrationOverview.mac
        facts.drive = .failed
        XCTAssertEqual(facts.rows.first { $0.id == .drive }?.status, "Drive check failed")
        XCTAssertFalse(router.stepIntegrationBar(.confirm, profileFocused: &profileFocused, hasProfile: true))
        XCTAssertEqual(router.route, .library)
        profileFocused = true
        XCTAssertTrue(router.stepIntegrationBar(.left, profileFocused: &profileFocused, hasProfile: true))
        XCTAssertTrue(router.integrationBarFocused)
        XCTAssertFalse(profileFocused)
        XCTAssertTrue(router.stepIntegrationBar(.down, profileFocused: &profileFocused, hasProfile: true))
        XCTAssertFalse(router.stepIntegrationBar(.confirm, profileFocused: &profileFocused, hasProfile: true))
    }

    func testWithoutTheBarNothingFocusesItAndSettingsOpensThePage() {
        let router = AppRouter()
        var profileFocused = true
        XCTAssertFalse(router.stepIntegrationBar(.left, profileFocused: &profileFocused, hasProfile: true))
        XCTAssertTrue(profileFocused)
        router.openSettings(.sources)
        router.openIntegrations()
        XCTAssertEqual(router.route, .integrations)
        router.back()
        XCTAssertEqual(router.route, .settings(.sources))
        XCTAssertFalse(router.integrationBarFocused)
    }
}

/// From the real observation to the core's facts: a Steam read by its source, with three fictive games.
@MainActor
final class IntegrationSteamObservationTests: XCTestCase {
    func testSteamIsObservedFromItsSourceAsTheCoreDecidesIt() async throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        _ = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: fixture.root)
        let repository = CatalogRepository(store: CatalogStore(directory: fixture.root))
        let initial = try XCTUnwrap(try repository.load().source(.steam))
        let root = fixture.root
        let games: [SteamGameObservation] = ([10, 11, 12] as [UInt32]).map { id in
            let content = root.appendingPathComponent("steamapps/common/Game \(id)")
            let app = content.appendingPathComponent("Game.app")
            let native = NativeMacApplication(url: app, executableURL: app.appendingPathComponent("Contents/MacOS/game"),
                                              bundleIdentifier: "test.steam.\(id)", name: "Steam game \(id)", architectures: [.arm64],
                                              isDeclaredGame: true, fileObservations: [])
            return .init(appID: id, name: "Steam game \(id)", installationURL: content, libraryURL: root,
                         reportedSizeBytes: 1, buildID: nil, nativeApps: [native], state: .nativeReady)
        }
        let scan = SteamLibrarySnapshot(libraries: [.init(root: root, isReadable: true, isComplete: true)], games: games, issues: [])
        let read = expectation(description: "three games read")
        let sources = CatalogSourcesModel(repository: repository, initialConfiguration: initial, scanner: { _, _ in scan }) { document in
            if document.games.filter({ $0.steamGame != nil }).count == 3 { read.fulfill() }
        }
        XCTAssertEqual(IntegrationOverview.steam(sources), SteamFacts(enabled: false, read: .disabled, games: 0))
        sources.configure(enabled: true, root: root)
        await fulfillment(of: [read], timeout: 5)
        let steam = IntegrationOverview.steam(sources)
        XCTAssertEqual(steam, SteamFacts(enabled: true, read: .ready, games: 3))
        var facts = IntegrationOverview.mac
        facts.steam = steam
        XCTAssertEqual(facts.row(.steam)?.status, "Ready here")
        XCTAssertEqual(facts.row(.steam)?.browse?.target, .steamGames)
    }
}
