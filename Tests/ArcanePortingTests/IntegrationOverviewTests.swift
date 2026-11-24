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
        XCTAssertEqual(snapshot.rows.first { $0.id == .steam }?.status, "Steam library scanned")
    }

    func testRoutesUseExistingSettingsAndBackKeepsTheOrigin() {
        var snapshot = IntegrationOverview()
        let router = AppRouter()
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
        XCTAssertFalse(snapshot.open(.drive, in: router))
        XCTAssertEqual(router.route, .library)
        XCTAssertFalse(router.integrationBarFocused)
        XCTAssertEqual(snapshot.rows.map(\.id), [.switchGames, .steam, .drive, .nextendo, .images, .saves])
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

    func testTheBarOnlyTakesConfirmAfterExplicitFocusEvenWhenAServiceFails() {
        let router = AppRouter()
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
}
