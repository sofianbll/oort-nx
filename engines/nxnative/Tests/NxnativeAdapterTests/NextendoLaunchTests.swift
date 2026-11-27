import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class NextendoLaunchTests: XCTestCase {
    func testGuestOfflineAndGameTitleRequiresTwoOptIns() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: app) }
        let host = app.appendingPathComponent("Contents/MacOS/dmhost")
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        var profile = LocalProfile(name: "Player", look: .init(.init()))
        XCTAssertThrowsError(try NextendoLaunch.presenceEnvironment(profile: profile, in: app)) {
            XCTAssertEqual($0 as? NextendoError, .presenceHost)
        }
        try Data("DM_NEXTENDO_PRESENCE\0".utf8).write(to: host)
        let hidden = ["DM_NEXTENDO_PRESENCE": "0"]
        XCTAssertEqual(try NextendoLaunch.presenceEnvironment(profile: profile, in: app), hidden)
        profile.appearsOnline = true
        XCTAssertEqual(try NextendoLaunch.presenceEnvironment(profile: profile, in: app), hidden)
        profile.showsCurrentGame = true
        XCTAssertEqual(try NextendoLaunch.presenceEnvironment(profile: profile, in: app), [:])
        profile.appearsOnline = false
        XCTAssertEqual(try NextendoLaunch.presenceEnvironment(profile: profile, in: app), hidden)
        XCTAssertEqual(NextendoLaunch.guestEnvironment(), ["DM_NETWORK": "offline", "DM_NEXTENDO_PRESENCE": "0"])
    }

    private func networkSetting(online: Bool) throws -> LauncherSetting {
        let option = online ? #",["nextendo","Nextendo (online)"]"# : ""
        let json = """
        {"env":"DM_NETWORK","kind":"choice","section":"Game","label":"Network","default":"offline",
         "options":[["offline","Offline"],["lan","LAN"],["ldn","Local wireless"]\(option)]}
        """
        let setting = try JSONDecoder().decode(LauncherSetting.self, from: Data(json.utf8))
        return try XCTUnwrap(NextendoLaunch.networkSetting(in: [setting]))
    }

    func testNetworkMovesOutOfMoreSettingsAndOnlineRequiresBuildSupport() throws {
        let setting = try networkSetting(online: true)
        let snapshot = GameSettingsSnapshot(settings: [setting], values: ["DM_NETWORK": "offline"], fixed: [])
        XCTAssertTrue(snapshot.extraSettings.isEmpty)
        XCTAssertEqual(snapshot.multiplayerModes, [.offline, .local, .online])
        let local = GameSettingsSnapshot(settings: [try networkSetting(online: false)], values: [:], fixed: [])
        XCTAssertEqual(local.multiplayerModes, [.offline, .local])
        for (settings, onlineRiskMods) in [(local, false), (snapshot, true)] {
            let presentation = GameOptionsPresentation(supportsRenderScale: false, isPlayable: true, sourcesDetached: false,
                                                       settings: settings, onlineRiskMods: onlineRiskMods)
            let rows = presentation.focusableRows(level: .main, origin: .details)
            XCTAssertEqual(Array(rows.prefix(2)), [.play, .multiplayer])
            XCTAssertEqual(GameOptionsFocus(row: nil, in: rows).row(in: rows), .play)
            XCTAssertTrue(rows.contains(.favorite))
        }
        XCTAssertNil(NextendoLaunch.networkSetting(in: []))
    }

    func testOnlySupportedOnlinePlayAddsClientIDWithoutReplacingNetworkChoice() async throws {
        let setting = try networkSetting(online: true)
        for (setting, mode) in [(setting, "offline"), (setting, "ldn"), (setting, "lan"),
                                (try networkSetting(online: false), "nextendo")] {
            let environment = try await NextendoLaunch.environment(setting: setting, mode: mode, clientID: nil) { _ in
                XCTFail("Offline, local and unsupported launches must not contact Nextendo")
                return false
            }
            XCTAssertEqual(environment, [:])
        }
        let online = try await NextendoLaunch.environment(setting: setting, mode: "nextendo", clientID: "sample-client") { client in
            XCTAssertEqual(client, "sample-client")
            return true
        }
        XCTAssertEqual(online, ["DM_NEXTENDO_CLIENT_ID": "sample-client"])
    }

    func testSignedOutOnlinePlayIsBlocked() async throws {
        let setting = try networkSetting(online: true)
        do {
            _ = try await NextendoLaunch.environment(setting: setting, mode: "nextendo", clientID: "sample-client") { _ in false }
            XCTFail("Missing session should block the supported online launch")
        } catch let error as NextendoError { XCTAssertEqual(error, .signedOut) }
    }

    func testProfileDirectoriesStaySeparateAndOnlyPassToOnlineGames() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let first = UUID(), second = UUID(), third = UUID()
        XCTAssertEqual(NextendoLaunch.tokenStore(profileID: first, originalID: first, root: root).directory,
                       NextendoTokenStore().directory)
        let store = NextendoLaunch.tokenStore(profileID: second, originalID: first, root: root)
        XCTAssertNotEqual(store.directory, NextendoLaunch.tokenStore(profileID: third, originalID: first, root: root).directory)
        XCTAssertTrue(store.directory.path.hasPrefix(root.path + "/profile-credentials/"))
        let setting = try networkSetting(online: true)
        let environment = try await NextendoLaunch.environment(setting: setting, mode: "nextendo", clientID: "sample-client",
                                                               tokenStore: store) { _ in true }
        XCTAssertEqual(environment[NextendoLaunch.loginDirectoryKey], store.directory.path)
        let auto = try await NextendoLaunch.environment(setting: setting, mode: "auto", clientID: "sample-client",
                                                        tokenStore: store) { _ in true }
        XCTAssertEqual(auto, environment)
        let offline = try await NextendoLaunch.environment(setting: setting, mode: "offline", clientID: nil,
                                                           tokenStore: store) { _ in false }
        XCTAssertTrue(offline.isEmpty)
        let host = root.appendingPathComponent("Contents/MacOS/dmhost")
        XCTAssertFalse(NextendoLaunch.supportsProfileLogin(in: root))
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("host\0DM_NEXTENDO_LOGIN_DIR\0".utf8).write(to: host)
        XCTAssertTrue(NextendoLaunch.supportsProfileLogin(in: root))
    }

    func testEngineProbeRequiresBuildFlagAndActualSetting() throws {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("NextendoEngine-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: repo) }
        let cli = repo.appendingPathComponent("scripts/build_ipa_from_nsp.py")
        let table = repo.appendingPathComponent("dm/games/settings.tsv")
        for url in [cli, table] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        XCTAssertFalse(NextendoLaunch.engineSupportsSignIn(at: repo))
        try Data("ap.add_argument('--nextendo')\n".utf8).write(to: cli)
        try Data("# DM_NETWORK\tchoice\tnextendo=Nextendo\n".utf8).write(to: table)
        XCTAssertFalse(NextendoLaunch.engineSupportsSignIn(at: repo))
        try Data("DM_NETWORK\tchoice\toffline=Offline,nextendo=Nextendo?build:DM_NEXTENDO\r\n".utf8).write(to: table)
        XCTAssertTrue(NextendoLaunch.engineSupportsSignIn(at: repo))
    }

    func testSearchAndChangedDoNotSurfaceUnsupportedConnection() {
        var settings = AppSettings()
        settings.nextendoClientID = "sample-client"
        let nextendoRows = ["nextendo", "nextendoClientID"]
        XCTAssertTrue(SettingsCatalog.search("Nextendo").allSatisfy { !nextendoRows.contains($0.id) })
        XCTAssertTrue(SettingsCatalog.changed(in: settings).isEmpty)
        let engine = SettingsCatalog.search("Nextendo", supportsNextendo: true).filter { nextendoRows.contains($0.id) }
        XCTAssertEqual(engine.map(\.id), ["nextendoClientID"])
        XCTAssertEqual(engine.map(\.group), [.multiplayer])
        let account = SettingsCatalog.search("Nextendo", hasProfileAccount: true).filter { nextendoRows.contains($0.id) }
        XCTAssertEqual(account.map(\.id), ["nextendo"])
        XCTAssertEqual(account.map(\.group), [.profileNextendo])
        XCTAssertEqual(SettingsCatalog.all.filter { $0.group == .apiServices }.map(\.id), ["igdb", "steamGridDB"])
        XCTAssertEqual(SettingsCatalog.changed(in: settings, supportsNextendo: true).map(\.id), ["nextendoClientID"])
    }
}
