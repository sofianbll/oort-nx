import XCTest
import NXLibraryCore
import ArcanePorting

final class IntegrationOverviewTests: XCTestCase {
    func testAnEmptySteamScanIsNotAnUnfinishedOrSuccessfulPlayCheck() throws {
        var snapshot = IntegrationOverview()
        snapshot.steam = .ready
        let steam = try XCTUnwrap(snapshot.rows.first { $0.id == .steam })
        XCTAssertEqual(steam.status, "No games found")
        snapshot.steam = .scanning
        XCTAssertEqual(snapshot.rows.first { $0.id == .steam }?.status, "Reading Steam libraries…")
        snapshot.steam = .failed
        XCTAssertEqual(snapshot.rows.first { $0.id == .steam }?.status, "Steam scan failed")
        snapshot.steam = .partial
        XCTAssertEqual(snapshot.rows.first { $0.id == .steam }?.status, "Steam scan incomplete")
        snapshot.steam = .ready
        snapshot.steamGameCount = 2
        XCTAssertEqual(snapshot.rows.first { $0.id == .steam }?.status, "Ready here")
    }

    func testRoutesUseExistingSettingsAndBackKeepsTheOrigin() {
        var snapshot = IntegrationOverview()
        let router = AppRouter()
        router.showsIntegrationBar = true
        router.openIntegrations()
        XCTAssertTrue(snapshot.open(.steam, in: router))
        XCTAssertEqual(router.route, .settings(.sources))
        XCTAssertEqual(router.settingsRowID, "steamSource")
        router.back()
        XCTAssertEqual(router.route, .integrations)
        XCTAssertEqual(router.integrationFocus, .steam)
        XCTAssertTrue(snapshot.open(.drive, in: router))
        XCTAssertEqual(router.settingsRowID, "cloudLibrarySetup")
        router.back()
        snapshot.drive = .failed
        XCTAssertTrue(snapshot.open(.drive, in: router))
        XCTAssertEqual(router.settingsRowID, "cloudLibraryService")
        router.back()
        router.back()
        XCTAssertEqual(router.route, .library)
        XCTAssertTrue(router.integrationBarFocused)
    }

    func testOnlyCurrentPageCanOpenExistingSettingsAndAllRowsHaveAccessCopy() {
        var snapshot = IntegrationOverview()
        let router = AppRouter()
        router.showsIntegrationBar = true
        XCTAssertFalse(snapshot.open(.drive, in: router))
        XCTAssertEqual(router.route, .library)
        XCTAssertFalse(router.integrationBarFocused)
        XCTAssertEqual(snapshot.sections.map(\.id), [.sources, .engines, .services])
        XCTAssertEqual(snapshot.sections.map { $0.entries.map(\.id) },
                       [[.steam, .macApps, .drive], [.switchGames], [.nextendo, .saves, .images]])
        XCTAssertTrue(snapshot.rows.allSatisfy { !$0.reads.isEmpty && !$0.writes.isEmpty && !$0.sends.isEmpty })
        router.openCollection()
        router.openIntegrations()
        snapshot.engine = .blocked
        snapshot.nextendo = .connected
        snapshot.steamGridDB = true
        snapshot.drive = .transferring
        for (id, section, setting) in [
            (IntegrationID.switchGames, SettingsSection.engine, "engineStatus"),
            (.steam, .sources, "steamSource"),
            (.macApps, .sources, "macShortcutAdd"),
            (.drive, .cloudLibrary, "cloudLibraryEnabled"),
            (.nextendo, .profileNextendo, "nextendo"),
            (.images, .apiServices, "igdb"),
            (.saves, .cloudSaves, "cloudSaves"),
        ] {
            XCTAssertTrue(snapshot.open(id, in: router))
            XCTAssertEqual(router.route, .settings(section))
            XCTAssertEqual(router.settingsRowID, setting)
            router.back()
            XCTAssertEqual(router.integrationFocus, id)
        }
        router.back()
        XCTAssertEqual(router.route, .collection)
        XCTAssertTrue(router.integrationBarFocused)
    }

    func testDetailDoesNotOpenSettingsAndBackReturnsToSameRow() {
        let snapshot = IntegrationOverview()
        let router = AppRouter()
        router.showsIntegrationBar = true
        router.openIntegrations()
        router.showIntegrationDetail(.macApps)
        XCTAssertEqual(router.route, .integrations)
        XCTAssertEqual(router.integrationDetail, .macApps)
        XCTAssertNil(router.settingsRowID)
        XCTAssertTrue(snapshot.open(.macApps, in: router))
        router.back()
        XCTAssertEqual(router.integrationDetail, .macApps)
        router.backFromIntegration()
        XCTAssertNil(router.integrationDetail)
        XCTAssertEqual(router.integrationFocus, .macApps)
    }

    func testDetailAlwaysShowsTheThreeStepsAndSwitchBrowseDoesNotOpenSettings() throws {
        func said(_ step: IntegrationCatalog.Step<IntegrationRow.Detail>) -> String? {
            if case .say(let words)? = step.content.first { words.key } else { nil }
        }
        var snapshot = IntegrationOverview()
        let unlinked = try XCTUnwrap(snapshot.row(.drive))
        XCTAssertEqual(unlinked.steps.map(\.id), [.link, .verify, .next])
        XCTAssertEqual(unlinked.steps.map(said), ["Connect your Google Drive to begin.", nil, "Link it first to continue."])
        XCTAssertEqual(unlinked.actions, [.settings])
        snapshot.drive = .checked
        let date = Date(timeIntervalSince1970: 1)
        snapshot.driveCheckDate = date
        let drive = try XCTUnwrap(snapshot.row(.drive))
        XCTAssertEqual(drive.steps.map(\.id), [.link, .verify, .next])
        XCTAssertEqual(said(drive.steps[0]), "Linked to your Google Drive.")
        XCTAssertTrue(drive.steps[1].content.contains { if case .date(date) = $0 { true } else { false } })
        snapshot.steam = .ready
        snapshot.steamGameCount = 2
        let steam = try XCTUnwrap(snapshot.row(.steam))
        XCTAssertEqual(steam.switchOn, true)
        XCTAssertEqual(steam.steps.map { $0.content.count }, [2, 2, 1], "Link: linked to Steam, its settings; Continue: its games")
        XCTAssertEqual(snapshot.row(.macApps)?.switchOn, nil, "no switch where the owner offers none")
        snapshot.hasSwitchGames = true
        snapshot.engine = .blocked
        XCTAssertEqual(snapshot.row(.switchGames)?.actions, [.settings, .switchGames])
        let router = AppRouter()
        router.openIntegrations()
        router.showIntegrationDetail(.switchGames)
        router.browseIntegrationLibrary(.nxnative)
        XCTAssertEqual(router.route, .library)
        XCTAssertNil(router.settingsRowID)
        XCTAssertEqual(router.takeIntegrationLibraryPlatform(), .nxnative)
        XCTAssertNil(router.takeIntegrationLibraryPlatform())
    }

    /// The engine's checks say what the player needs, not a commit or a compiler number; those stay in its settings.
    func testEngineChecksArePlainWords() throws {
        func checks(_ snapshot: IntegrationOverview) throws -> [String] {
            try XCTUnwrap(snapshot.row(.switchGames)).steps[1].content.flatMap { item -> [String] in
                if case .words(let words) = item { words.map(\.key) } else { [] }
            }
        }
        var snapshot = IntegrationOverview()
        snapshot.engine = .detected
        snapshot.engineCommit = "f1c7100fabcdef"
        snapshot.expectedEngineCommit = "f1c7100f"
        snapshot.keyStatus = .available(applicationGenerations: 1)
        snapshot.xcodeVersion = "Xcode 27"
        snapshot.metalVersion = "33000.1"
        XCTAssertEqual(try checks(snapshot), ["Engine up to date", "Switch keys selected", "Apple tools ready"])
        snapshot.engineCommit = "0123456789"
        snapshot.metalVersion = nil
        XCTAssertEqual(try checks(snapshot), ["Engine not the tested version", "Switch keys selected", "Apple tools incomplete"])
        let words = try checks(snapshot).joined(separator: " ")
        for hidden in ["0123456", "f1c7100", "33000", "Xcode 27"] { XCTAssertFalse(words.contains(hidden)) }
    }

    func testTheBarOnlyTakesConfirmAfterExplicitFocusEvenWhenAServiceFails() {
        let router = AppRouter()
        router.showsIntegrationBar = true
        var profileFocused = false
        var snapshot = IntegrationOverview()
        snapshot.drive = .failed
        XCTAssertEqual(snapshot.rows.first { $0.id == .drive }?.status, "Drive check failed")
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
