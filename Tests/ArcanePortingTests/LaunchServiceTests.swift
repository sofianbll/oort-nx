import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class LaunchServiceTests: XCTestCase {
    final class FakeLauncher: AppLaunching {
        var opened: URL?
        var environment: [String: String] = [:]
        var shouldSucceed = true
        var onExit: (() -> Void)?
        func open(_ url: URL, environment: [String: String], onExit: (() -> Void)?,
                  completion: @escaping (Bool, String?) -> Void) {
            opened = url
            self.environment = environment
            self.onExit = onExit
            completion(shouldSucceed, shouldSucceed ? nil : "sample launch error")
        }
    }

    func testWorkspaceGameEnvironmentKeepsOnlySystemAndExplicitValues() {
        let ambient = ["HOME": "/Users/fixture", "TMPDIR": "/private/fixture-temp", "PATH": "/untrusted/bin",
                       "FIXTURE_API_TOKEN": "secret", "DYLD_INSERT_LIBRARIES": "/untrusted/library",
                       "DM_ROOT": "/untrusted/game", "DM_SCREEN": "stale", "SSH_AUTH_SOCK": "/fixture/socket"]
        let explicit = ["DM_LAUNCHER": "0", "DM_SCREEN": "2", "DM_OVERLAY_DATA": "/fixture/overlay.json"]
        XCTAssertEqual(NSWorkspaceLauncher.gameEnvironment(inheriting: ambient, explicit: explicit),
                       ["HOME": "/Users/fixture", "TMPDIR": "/private/fixture-temp", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
                       .merging(explicit) { _, value in value })
        let withoutAmbient = NSWorkspaceLauncher.gameEnvironment(inheriting: [:], explicit: [:])
        XCTAssertEqual(Set(withoutAmbient.keys), ["HOME", "PATH", "TMPDIR"])
        XCTAssertTrue(withoutAmbient["HOME"]?.hasPrefix("/") == true)
        XCTAssertTrue(withoutAmbient["TMPDIR"]?.hasPrefix("/") == true)
    }

    func testInGameHomeButtonReachesTheGameEnvironmentOnlyWhenExplicit() throws {
        let launcher = FakeLauncher()
        let service = LaunchService(launcher: launcher)
        let app = URL(fileURLWithPath: "/Fixture.app")
        let key = "DM_OVERLAY_HOME_SWAP"
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.inGameHomeButton, .auto)
        for (choice, expected): (InGameHomeButton, String?) in [(.auto, nil), (.fullOverlay, "0"), (.quickAccess, "1")] {
            settings.inGameHomeButton = choice
            let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
            service.launch(appURL: app, environment: [key: "stale"], homeButton: saved.inGameHomeButton) { ok, _ in
                XCTAssertTrue(ok)
            }
            XCTAssertEqual(launcher.environment[key], expected)
            XCTAssertEqual(SettingsReset.reset(.controllers, in: saved).inGameHomeButton, .auto)
        }
    }

    func testOverlaySnapshotWireFormatPermissionsAndLifetime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXOverlay-\(UUID())")
        let app = root.appendingPathComponent("Fixture.app")
        let host = HomeMenu.hostExecutable(in: app)
        let fm = FileManager.default
        try fm.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let launcher = FakeLauncher()
        let service = LaunchService(launcher: launcher)
        var snapshot = GameOverlaySnapshot()
        let portrait = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0ioAAAAASUVORK5CYII="))
        snapshot.profile = LocalProfile(name: "Koya\nMori", portrait: portrait, look: .init(.init()))
        snapshot.color = 0x9CCBFF
        snapshot.nextendoName = "Koya"
        snapshot.presence = .online
        snapshot.week = "2 h 14 min"
        snapshot.friends = [
            .init(id: 96, name: "Milo", favorite: false, presence: .offline, game: nil, gameID: nil),
            .init(id: 87, name: "Lina", favorite: true, presence: .playing, game: nil, gameID: "PRIVATE-ID")
        ]
        snapshot.friendGameTitles = ["PRIVATE-ID": "Pokémon Legends: Z-A"]
        snapshot.achievements = AchievementSummary(achievements: (0..<6).map {
            SteamAchievement(apiName: "private-\($0)", name: "Success \($0)", description: "Excluded",
                             hidden: false, icon: "https://example.test/?token=secret",
                             grayIcon: nil, unlockedAt: $0 == 0 ? nil : Date(timeIntervalSince1970: Double($0)))
        }, percents: [:])

        try Data("DM_OVERLAY_DATAX\0".utf8).write(to: host)
        service.launch(appURL: app, environment: ["DM_OVERLAY_DATA": "/tmp/inherited"], overlay: .init(app: app),
                       snapshot: snapshot, temporaryDirectory: root) { ok, _ in XCTAssertTrue(ok) }
        XCTAssertNil(launcher.environment["DM_OVERLAY_DATA"])
        XCTAssertNil(launcher.onExit)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path), ["Fixture.app"])

        try service.writeEnvironment(settings: .init(), titleId: "test-title", baseDirectory: root)
        let env = root.appendingPathComponent("test-title/env.txt")
        let before = try Data(contentsOf: env)
        let expectedChildren: Set<String> = ["Fixture.app", "test-title"]
        try Data("DM_OVERLAY_DATA\0DM_OVERLAY_PLAY_TIME\0".utf8).write(to: host)
        let overlay = GameOverlayLaunch(app: app)
        XCTAssertNil(try overlay.writeSnapshot(.init(), in: root))
        var noSections = GameOverlaySnapshot()
        noSections.friends = []
        XCTAssertNil(try noSections.encoded())
        let environment = overlay.environment(palette: .fallback, playtime: nil, cover: nil, profilePlaytime: "20 h")
        var exits = 0
        service.launch(appURL: app, environment: environment, overlay: overlay, snapshot: snapshot,
                       temporaryDirectory: root, onExit: { exits += 1 }) { ok, _ in XCTAssertTrue(ok) }
        XCTAssertEqual(launcher.environment["DM_OVERLAY_PLAY_TIME"], "20 h")
        XCTAssertEqual(try Data(contentsOf: env), before)
        let path = try XCTUnwrap(launcher.environment["DM_OVERLAY_DATA"])
        let file = URL(fileURLWithPath: path)
        XCTAssertTrue((path as NSString).isAbsolutePath)
        XCTAssertEqual(try fm.attributesOfItem(atPath: path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try fm.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? Int, 0o700)
        let data = try Data(contentsOf: file)
        var decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var profile = try XCTUnwrap(decoded["profile"] as? [String: String])
        let avatar = try XCTUnwrap(profile.removeValue(forKey: "avatar"))
        XCTAssertLessThanOrEqual(avatar.utf16.count, 131_072)
        XCTAssertTrue(try XCTUnwrap(Data(base64Encoded: avatar)).starts(with: [0xff, 0xd8]))
        decoded["profile"] = profile
        let expected = try JSONSerialization.jsonObject(with: Data("""
            {"profile":{"name":"Koya Mori","color":"#9CCBFF","nextendo":"Koya","status":"online","week":"2 h 14 min"},
             "friends":{"shared":true,"items":[{"name":"Milo","status":"offline"},{"name":"Lina","status":"playing","game":"Pokémon Legends: Z-A"}]},
             "achievements":{"total":6,"unlocked":5,"recent":["Success 5","Success 4","Success 3","Success 2"]}}
            """.utf8))
        // An exact allowlist also rules out account IDs, credential fields and unrelated URLs.
        XCTAssertEqual(decoded as NSDictionary, expected as? NSDictionary)
        if let probe = ProcessInfo.processInfo.environment["ARCANE_OVERLAY_PARSER_PROBE"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: probe)
            process.arguments = [path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
        launcher.onExit?()
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: root.path)), expectedChildren)

        launcher.shouldSucceed = false
        service.launch(appURL: app, overlay: overlay, snapshot: snapshot, temporaryDirectory: root,
                       onExit: { exits += 1 }) { ok, _ in XCTAssertFalse(ok) }
        XCTAssertEqual(exits, 1)
        XCTAssertNotEqual(launcher.environment["DM_OVERLAY_DATA"], path)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: root.path)), expectedChildren)
    }

    func testOverlaySnapshotCapsFriendCountAndUTF16Text() throws {
        var snapshot = GameOverlaySnapshot()
        snapshot.friends = (0...100).map {
            .init(id: UInt64($0), name: String(repeating: "🎮", count: 81), favorite: false,
                  presence: .online, game: nil, gameID: nil)
        }
        let data = try XCTUnwrap(snapshot.encoded())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        let items = try XCTUnwrap(object["friends"]?["items"] as? [[String: String]])
        XCTAssertEqual(items.count, 100)
        XCTAssertEqual(items.first?["name"], String(repeating: "🎮", count: 80))
    }

    func testWritesEnvAndLaunches() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXLaunch-\(UUID().uuidString)")
        let game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/G.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                              titleId: "0100000000010000")
        var settings = GameRuntimeConfig()
        settings.fpsTarget = 30
        settings.metalHUD = true
        let launcher = FakeLauncher()
        let service = LaunchService(launcher: launcher)
        try service.writeEnvironment(settings: settings, titleId: "0100000000010000", baseDirectory: dir)
        let env = try String(contentsOf: dir.appendingPathComponent("0100000000010000/env.txt"), encoding: .utf8)
        XCTAssertTrue(env.contains("DM_FPS_TARGET=30"))
        XCTAssertTrue(env.contains("DM_METAL_HUD=1"))
        var launched = false
        var launchError: String?
        service.launch(appURL: game.url, environment: ["DM_FPS_TARGET": "30"]) { success, error in
            launched = success
            launchError = error
        }
        XCTAssertTrue(launched)
        XCTAssertNil(launchError)
        XCTAssertEqual(launcher.opened, game.url)
        XCTAssertEqual(launcher.environment["DM_FPS_TARGET"], "30")
    }

    func testOverlayOnlySendsSupportedDataAndLeavesEnvFileAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXOverlay-\(UUID())")
        let app = root.appendingPathComponent("Fixture.app")
        let host = HomeMenu.hostExecutable(in: app)
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = FakeLauncher()
        let service = LaunchService(launcher: launcher)
        let title = "0100000000000001"
        try service.writeEnvironment(settings: .init(), titleId: title, baseDirectory: root)
        let env = root.appendingPathComponent("\(title)/env.txt")
        let before = try Data(contentsOf: env)
        let cover = root.appendingPathComponent("Cover art.png")
        try Data().write(to: cover)
        let palette = SelenePalette.fallback
        XCTAssertEqual(GameOverlayLaunch(app: app).environment(palette: palette, playtime: 2599, cover: cover), [:])
        try Data("DM_OVERLAY_THEME_V10\0DM_OVERLAY_PLAYTIME_MIN\0".utf8).write(to: host)
        XCTAssertEqual(GameOverlayLaunch(app: app).environment(palette: palette, playtime: 2599, cover: cover),
                       ["DM_OVERLAY_PLAYTIME_MIN": "43"])
        try Data("DM_OVERLAY_THEME_V1\0DM_OVERLAY_PLAYTIME_MIN\0DM_OVERLAY_COVER\0".utf8).write(to: host)
        let overlay = GameOverlayLaunch(app: app)
        service.launch(appURL: app, environment: overlay.environment(palette: palette, playtime: 2599, cover: cover)) {
            ok, _ in XCTAssertTrue(ok)
        }
        XCTAssertEqual(launcher.environment["DM_OVERLAY_THEME_V1"],
                       "ink=#FFFFFFFF;surface=#14181FFF;scrim=#000000FF;focus=#FFFFFFFF;onFocus=#111111FF")
        XCTAssertEqual(launcher.environment["DM_OVERLAY_PLAYTIME_MIN"], "43")
        XCTAssertEqual(launcher.environment["DM_OVERLAY_COVER"], cover.path)
        XCTAssertEqual(try Data(contentsOf: env), before)
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("DM_OVERLAY_"))
        XCTAssertEqual(overlay.environment(palette: palette, playtime: .infinity, cover: root).count, 1)
    }

    func testOverlayThemeRejectsUnreadableColors() {
        var palette = SelenePalette.fallback
        palette.ink = palette.glass
        XCTAssertNil(GameOverlayLaunch.theme(palette))
        palette = .fallback
        palette.onFocus = palette.focus
        XCTAssertNil(GameOverlayLaunch.theme(palette))
        palette = .fallback
        palette.focus = palette.glass
        palette.onFocus = palette.ink
        XCTAssertNil(GameOverlayLaunch.theme(palette))
    }

    func testLaunchFailureIsReported() throws {
        let launcher = FakeLauncher()
        launcher.shouldSucceed = false
        let service = LaunchService(launcher: launcher)
        var launched = true
        var launchError: String?
        service.launch(appURL: URL(fileURLWithPath: "/tmp/Missing.app")) { success, error in
            launched = success
            launchError = error
        }
        XCTAssertFalse(launched)
        XCTAssertEqual(launchError, "sample launch error")
    }

    func testUnreadableEnvironmentIsKeptInsteadOfReplacingUnknownOptions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXLaunchUnreadable-\(UUID())")
        let title = "0100000000000001"
        let folder = root.appendingPathComponent(title)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let env = folder.appendingPathComponent("env.txt")
        let invalid = Data([0xff, 0xfe, 0xff])
        try invalid.write(to: env)
        let service = LaunchService(launcher: FakeLauncher())
        XCTAssertThrowsError(try service.writeEnvironment(settings: GameRuntimeConfig(), titleId: title, baseDirectory: root))
        XCTAssertEqual(try Data(contentsOf: env), invalid)
    }

    /// Arcane's Game options are the game's settings window: a game it starts skips the engine's own
    /// (dm/mac/launcher.c, DM_LAUNCHER=0), which would ask again and, on Quit, leave a process macOS never reports ended.
    func testLaunchSkipsTheEnginesSettingsWindow() {
        let launcher = FakeLauncher()
        LaunchService(launcher: launcher).launch(appURL: URL(fileURLWithPath: "/tmp/G.app"),
                                                 environment: ["DM_FPS_TARGET": "30", "DM_MODS_OFF": "Some mod"]
                                                    .merging(HomeMenu.environment(supported: true, launcherBundleID: "local.arcane")) { _, new in new }) { _, _ in }
        XCTAssertEqual(launcher.environment["DM_LAUNCHER"], "0")
        XCTAssertEqual(launcher.environment["DM_FPS_TARGET"], "30")
        XCTAssertEqual(launcher.environment["DM_MODS_OFF"], "Some mod")
        XCTAssertEqual(launcher.environment["DM_HOME_MENU_LAUNCHER"], "1")
        XCTAssertEqual(launcher.environment["DM_LAUNCHER_BUNDLE_ID"], "local.arcane")
    }

    func testEmptyCodeModsOverrideReachesTheEngineForReactivation() {
        let launcher = FakeLauncher()
        LaunchService(launcher: launcher).launch(appURL: URL(fileURLWithPath: "/tmp/G.app"),
                                                  environment: ["DM_MODS_OFF": ""]) { _, _ in }
        XCTAssertEqual(launcher.environment["DM_MODS_OFF"], "")
    }

    func testGameDisplayResolvesExplicitConnectedAndFallbackChoices() {
        let arcane = UUID(), external = UUID()
        let connected = [GameDisplay(id: arcane, name: "Built-in"), GameDisplay(id: external, name: "External")]
        XCTAssertEqual(GameDisplay.resolve("", connected: connected, arcane: arcane).id, arcane)
        let chosen = GameDisplay.resolve(external.uuidString.lowercased(), connected: connected, arcane: arcane)
        XCTAssertEqual(chosen.id, external)
        XCTAssertFalse(chosen.missing)
        let missing = GameDisplay.resolve(external.uuidString, connected: [connected[0]], arcane: arcane)
        XCTAssertEqual(missing.id, arcane)
        XCTAssertTrue(missing.missing)
        XCTAssertNil(GameDisplay.resolve("", connected: [], arcane: nil).id)
    }

    func testGameDisplayChecksTheExactInstalledHostMarker() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXDisplay-\(UUID())")
        let host = HomeMenu.hostExecutable(in: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        let capabilities = InstalledEngineCapabilities()
        for (markers, expected) in [("", false), ("DM_SCREEN_MATCH\0DM_SCREEN_ASPECT\0", false), ("DM_SCREEN\0", true)] {
            try Data(markers.utf8).write(to: host)
            let supported = await capabilities.supportsGameDisplay(in: root)
            XCTAssertEqual(supported, expected)
        }
    }

    func testGameDisplayRespectsEvenAnEmptyPlayerOverride() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXDisplay-\(UUID())")
        let title = "0100000000000001"
        let game = PortedGame(name: "Fixture", url: root.appendingPathComponent("Fixture.app"), platform: .macApp,
                              sizeBytes: 0, modificationDate: .now, titleId: title)
        let bundle = game.url.appendingPathComponent("Contents/Resources/dm")
        let player = root.appendingPathComponent(title)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: player, withIntermediateDirectories: true)
        let uuid = UUID().uuidString
        try "DM_SCREEN=\(uuid)\n".write(to: bundle.appendingPathComponent("env.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GameDisplay.fileOverride(for: game, support: root), uuid)
        try "# DM_SCREEN=comment\r\n DM_SCREEN = \r\nDM_SCREEN=second\r\n".write(
            to: player.appendingPathComponent("env.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GameDisplay.fileOverride(for: game, support: root), "")
    }
}
