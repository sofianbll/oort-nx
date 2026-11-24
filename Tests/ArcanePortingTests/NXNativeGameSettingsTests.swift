import Darwin
import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class NXNativeGameSettingsTests: XCTestCase {
    private let titleID = "040074A01BF12000"
    private let domain = "org.nxnative.040074a01bf12000"

    /// Bananza's list as the pinned engine packs it (no frame rate, language or render scale).
    private let launcherJSON = """
    {"schema":1,"game":"040074A01BF12000","settings":[
      {"env":"DM_OPMODE","kind":"choice","section":"Game","label":"Console mode","default":"1","level":"basic","options":[["1","Docked"],["0","Handheld"]]},
      {"env":"DM_PRESENT_UPSCALE","kind":"choice","section":"Game","label":"Upscaling","default":"off","options":[["off","Standard"],["metalfx","MetalFX"]]},
      {"env":"DM_FULLSCREEN","kind":"choice","section":"Game","label":"Display mode","default":"0","level":"basic","options":[["0","Window"],["1","Fullscreen"]]},
      {"env":"DM_RUMBLE","kind":"toggle","section":"Controls","label":"Game rumble","default":"1","level":"basic","on":"1","off":"0"},
      {"env":"DM_RUMBLE_GAIN","kind":"range","section":"Controls","label":"Rumble strength","default":"1.0","needs":"DM_RUMBLE=1","min":0.0,"max":3.0,"step":0.1},
      {"env":"DM_UPSCALER","kind":"choice","section":"Game","label":"Game's upscaler","default":"game","options":[["game","Game's own"],["metalfx","MetalFX"]]},
      {"env":"DM_METAL_HUD","kind":"toggle","section":"Performance","label":"Performance HUD","default":"0","on":"1","off":"0"}
    ]}
    """

    /// What NX Library 0.1.2 wrote for every game.
    private let oldEnv = """
    DM_FPS_TARGET=60
    DM_FULLSCREEN=1
    DM_LANG=it
    DM_METAL_HUD=1
    DM_OPMODE=1
    DM_PRESENT_UPSCALE=metalfx
    DM_RENDER_SCALE=1.00
    DM_RUMBLE=1
    DM_RUMBLE_GAIN=1

    """

    private struct Fixture {
        let game: PortedGame
        let support: URL
        let store: MemorySavedChoices
        let preferences: UserDefaults
        var envURL: URL { support.appendingPathComponent("040074A01BF12000/env.txt") }
    }

    private func fixture(dmSettings: Bool = true, env: String? = nil, vpn: Bool = false, online: Bool = true,
                         offeredChoices: [String: String]? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXSettings-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Donkey Kong Bananza.app")
        let dm = app.appendingPathComponent("Contents/Resources/dm")
        try FileManager.default.createDirectory(at: dm, withIntermediateDirectories: true)
        let json = vpn ? String(launcherJSON.dropLast(2)) + """
            ,{"env":"DM_NET_VPN","kind":"toggle","section":"Game","label":"Play over a VPN","default":"0","on":"1","off":"0"},
            {"env":"DM_NETWORK","kind":"choice","section":"Game","label":"Network","default":"lan","options":[["auto","Automatic"],["offline","Offline"],["ldn","Local communication"],["lan","LAN"],["nextendo","Online"]]}]}
            """ : launcherJSON
        let data: Data
        if let offeredChoices {
            // This fixture checks the wire key for every macOS control, not title-specific default values.
            let rows: [[String: Any]] = offeredChoices.map { key, value in
                ["env": key, "kind": "choice", "section": "Game", "label": key, "default": "default",
                 "options": [["default", "Default"], [value, "Selected"]]]
            }
            data = try JSONSerialization.data(withJSONObject: ["schema": 1, "game": titleID, "settings": rows])
        } else {
            data = Data((online ? json : json.replacingOccurrences(of: #",["nextendo","Online"]"#, with: "")).utf8)
        }
        try data.write(to: dm.appendingPathComponent("launcher.json"))
        var info: [String: Any] = ["CFBundleIdentifier": domain, "DMTitleID": titleID]
        if dmSettings { info["DMSettings"] = [["env": "DM_RUMBLE", "values": ["1", "0"]]] }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let support = root.appendingPathComponent("nxnative")
        if let env {
            try FileManager.default.createDirectory(at: support.appendingPathComponent(titleID),
                                                    withIntermediateDirectories: true)
            try Data(env.utf8).write(to: support.appendingPathComponent("\(titleID)/env.txt"))
        }
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.appendingPathComponent("test-preferences").path))
        let game = PortedGame(name: "Donkey Kong Bananza", url: app, platform: .macApp, sizeBytes: 1,
                              modificationDate: Date(), titleId: titleID)
        return Fixture(game: game, support: support, store: MemorySavedChoices(), preferences: preferences)
    }

    func testFilteredAmbientNeverShadowsAnyMacRuntimeChoice() throws {
        // Player controls from dm/games/settings.tsv (engine 46612553). Network/VPN have a separate launch path.
        let controls = ["DM_FPS_TARGET": "120", "DM_DYNAMIC_RESOLUTION": "1", "DM_RENDER_SCALE": "0.75",
                        "DM_ZA_SHADOW_CASCADES": "1", "DM_OPMODE": "0", "DM_PRESENT_UPSCALE": "metalfx",
                        "DM_UPSCALER": "metalfx", "DM_LANG": "fr", "DM_FULLSCREEN": "1", "DM_SHOW_FPS": "1",
                        "DM_RUMBLE": "0", "DM_RUMBLE_GAIN": "2", "DM_RUMBLE_MIN": "0.2", "DM_PAD_PRESS_TO_JOIN": "1",
                        "DM_SW2": "1", "DM_MIC": "1", "DM_MIC_GAIN": "5", "DM_SCREEN_ASPECT": "1.6",
                        "DM_PRESENT_SNAP": "0", "DM_PSO_MTL4": "0", "DM_PSO_PREBUILD": "0",
                        "DM_NVN_ENC_THREAD": "0", "DM_FPS_HOLD": "on", "DM_METAL_HUD": "1"]
        let f = try fixture(offeredChoices: controls)
        let s = try settings(f)
        XCTAssertEqual(Set(s.settings.map(\.env)), Set(controls.keys))
        let ambient = controls.mapValues { _ in "stale" }.merging(["DM_SAVED_CHOICES": "0"]) { _, value in value }
        let inherited = NSWorkspaceLauncher.gameEnvironment(inheriting: ambient, explicit: [:])
        for (key, value) in controls {
            try s.set(key, to: value)
            XCTAssertNil(inherited[key], key)
            XCTAssertEqual(s.effectiveLaunchValue(key, environment: inherited), value, key)
        }
        XCTAssertEqual(f.store.values[domain], controls)
    }

    private func settings(_ f: Fixture) throws -> NXNativeGameSettings {
        try XCTUnwrap(NXNativeGameSettings.forGame(f.game, store: f.store, supportDirectory: f.support,
                                                   preferences: f.preferences))
    }

    func testLegacyBuildHasNoAdapter() throws {
        let f = try fixture(dmSettings: false, env: oldEnv)
        XCTAssertNil(NXNativeGameSettings.forGame(f.game, store: f.store, supportDirectory: f.support,
                                                  preferences: f.preferences))
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8), oldEnv, "a legacy build's env.txt is not touched")
    }

    func testMigrationMovesOfferedKeysAndKeepsTheRest() throws {
        let f = try fixture(env: "# mine\n" + oldEnv + "DM_SHADER_LOG=1\n")
        f.preferences.set(Data("{}".utf8), forKey: GameRuntimeConfig.storageKey(for: f.game))
        try settings(f).migrate()

        // Non-default offered values became saved choices; defaults left no key.
        XCTAssertEqual(f.store.values[domain], ["DM_FULLSCREEN": "1", "DM_METAL_HUD": "1",
                                                 "DM_PRESENT_UPSCALE": "metalfx"])
        // Lines the build does not offer, the player's own and comments stay, in order.
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8),
                       "# mine\nDM_FPS_TARGET=60\nDM_LANG=it\nDM_RENDER_SCALE=1.00\nDM_SHADER_LOG=1\n")
        XCTAssertNil(f.preferences.data(forKey: GameRuntimeConfig.storageKey(for: f.game)))

        // Idempotent.
        try settings(f).migrate()
        XCTAssertEqual(f.store.values[domain]?.count, 3)
    }

    func testEnvValueReplacesAnOlderSavedChoiceAndEmptyFileGoes() throws {
        let f = try fixture(env: "DM_OPMODE=0\nDM_RUMBLE=1\n")
        f.store.values[domain] = ["DM_OPMODE": "1", "DM_RUMBLE": "0"]
        try settings(f).migrate()
        XCTAssertEqual(f.store.values[domain], ["DM_OPMODE": "0"], "env.txt is what the game used: it wins")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.envURL.path))
    }

    func testValueTheBuildRefusesStaysInEnv() throws {
        let f = try fixture(env: "DM_RUMBLE_GAIN=7\n")
        try settings(f).migrate()
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8), "DM_RUMBLE_GAIN=7\n")
        XCTAssertNil(f.store.values[domain]?["DM_RUMBLE_GAIN"])
    }

    func testSnapshotOrderAndFixedKeys() throws {
        let f = try fixture(env: "DM_UPSCALER=metalfx\n")
        f.store.values[domain] = ["DM_RUMBLE": "0", "DM_OPMODE": "2"]
        let snapshot = try settings(f).snapshot()
        XCTAssertEqual(snapshot.value("DM_UPSCALER"), "metalfx", "a hand-written env.txt line wins")
        XCTAssertEqual(snapshot.fixed, ["DM_UPSCALER"])
        XCTAssertEqual(snapshot.value("DM_RUMBLE"), "0")
        XCTAssertEqual(snapshot.value("DM_OPMODE"), "1", "a saved value the build refuses reads as the default")
        XCTAssertFalse(snapshot.visible("DM_RUMBLE_GAIN"), "needs DM_RUMBLE=1")
        XCTAssertFalse(snapshot.isOffered("DM_FPS_TARGET"))
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8), "DM_UPSCALER=metalfx\n",
                       "an unmanaged key is never migrated")
    }

    func testEffectiveLaunchValueMatchesEnginePrecedenceWithoutMigrating() throws {
        let f = try fixture(env: "DM_RUMBLE=1\r\nDM_RUMBLE=0\r\n")
        let bundled = f.game.url.appendingPathComponent("Contents/Resources/dm/env.txt")
        try Data("DM_RUMBLE=0\n".utf8).write(to: bundled)
        f.store.values[domain] = ["DM_RUMBLE": "1"]
        let s = try settings(f)
        XCTAssertEqual(s.effectiveLaunchValue("DM_RUMBLE", environment: ["DM_RUMBLE": "0"]), "0")
        XCTAssertEqual(s.effectiveLaunchValue("DM_RUMBLE", environment: [:]), "1")
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8), "DM_RUMBLE=1\r\nDM_RUMBLE=0\r\n")
        try FileManager.default.removeItem(at: f.envURL)
        XCTAssertEqual(s.effectiveLaunchValue("DM_RUMBLE", environment: [:]), "0")
        try FileManager.default.removeItem(at: bundled)
        try s.set("DM_RUMBLE", to: "0")
        XCTAssertEqual(s.effectiveLaunchValue("DM_RUMBLE", environment: [:]), "0")
        XCTAssertEqual(s.effectiveLaunchValue("DM_RUMBLE", environment: ["DM_SAVED_CHOICES": "0"]), "1")
        try Data("DM_SAVED_CHOICES=0\n".utf8).write(to: bundled)
        XCTAssertEqual(s.effectiveLaunchValue("DM_RUMBLE", environment: [:]), "1")
        XCTAssertEqual(s.effectiveLaunchValue("DM_RUMBLE", environment: ["DM_SAVED_CHOICES": "1"]), "0")
        XCTAssertNil(s.effectiveLaunchValue("UNDECLARED", environment: [:]))
    }

    func testSetWritesOnlyNonDefaultsAndRefusesUnofferedValues() throws {
        let f = try fixture()
        let s = try settings(f)
        try s.set("DM_RUMBLE_GAIN", to: "0.5")
        XCTAssertEqual(f.store.values[domain]?["DM_RUMBLE_GAIN"], "0.5")
        try s.set("DM_RUMBLE_GAIN", to: "1")
        XCTAssertNil(f.store.values[domain]?["DM_RUMBLE_GAIN"], "the default removes the key")
        XCTAssertThrowsError(try s.set("DM_OPMODE", to: "2"))
        XCTAssertThrowsError(try s.set("DM_FPS_TARGET", to: "60"))
    }

    func testRemotePlayLaunchUsesOneDistinctZeroTierAdapterDespiteTailscale() throws {
        let f = try fixture(vpn: true, online: false)
        let s = try settings(f)
        var app = AppSettings()
        app.multiplayerDefault = .local
        app.multiplayerVPN = .zeroTier
        let up = UInt32(IFF_UP)
        var adapters = RemotePlayAdapters()
        let otherAdapters: [(String, UInt32)] = [
            ("en7", 0xc0a80102), ("bridge100", 0xc0a88b03), ("bridge101", 0xc0a84001),
            ("utun8", 0x645a8010), ("en8", 0xa9fe7003),
        ]
        for (name, ipv4) in otherAdapters {
            adapters.consider(name, flags: up, ipv4: ipv4)
        }
        adapters.consider("lo0", flags: up | UInt32(IFF_LOOPBACK), ipv4: 0x7f000001)
        adapters.consider("zt0", flags: 0, ipv4: 0x0ac7920c)
        adapters.consider("zt1", flags: up, ipv4: 0xa9fe7003)
        XCTAssertEqual(s.multiplayerLaunch(settings: app, adapters: adapters, environment: [:]).warning, .ignored)

        adapters.consider("feth3971", flags: up, ipv4: 0x0ac7920b)
        adapters.consider("feth3971", flags: up, ipv4: 0x0ac7920c)
        XCTAssertEqual(adapters.connection(for: .zeroTier, manual: nil), .connected(name: "feth3971", ipv4: "10.199.146.11"))
        XCTAssertEqual(adapters.connection(for: .tailscale, manual: nil), .ambiguous)
        XCTAssertEqual(adapters.connection(for: .netBird, manual: nil), .ambiguous)
        XCTAssertEqual(adapters.connection(for: .netBird, manual: "utun8"), .connected(name: "utun8", ipv4: "100.90.128.16"))
        adapters.reportedProviders["utun8"] = .tailscale
        XCTAssertEqual(adapters.connection(for: .tailscale, manual: nil), .connected(name: "utun8", ipv4: "100.90.128.16"))
        XCTAssertEqual(adapters.connection(for: .netBird, manual: nil), .ignored)
        XCTAssertEqual(s.multiplayerLaunch(settings: app, adapters: adapters, environment: [:]).environment,
                       ["DM_NETWORK": "auto", "DM_NET_VPN": "1", "DM_NETWORK_INTERFACE": "feth3971"])
        app.multiplayerVPN = .tailscale
        XCTAssertEqual(s.multiplayerLaunch(settings: app, adapters: adapters, environment: [:]).environment,
                       ["DM_NETWORK": "auto", "DM_NET_VPN": "1", "DM_NETWORK_INTERFACE": "utun8"])

        adapters.consider("zt0", flags: up, ipv4: 0x0ac7920d)
        XCTAssertEqual(adapters.connection(for: .zeroTier, manual: nil), .ambiguous)
    }

    func testLegacyNetworkModesMapWithoutDeletingOldChoices() throws {
        let f = try fixture(vpn: true)
        let s = try settings(f)
        var app = AppSettings()
        app.multiplayerDefault = .local
        XCTAssertEqual(s.multiplayerLaunch(settings: app, adapters: .init(), environment: [:]).environment["DM_NETWORK"], "ldn",
                       "Nextendo builds do not offer an automatic mode that is local only")
        app.multiplayerLocalMode = .lan
        XCTAssertEqual(s.multiplayerLaunch(settings: app, adapters: .init(), environment: [:]).environment["DM_NETWORK"], "lan")
        for (raw, mode) in [("offline", MultiplayerMode.offline), ("ldn", .local), ("lan", .local), ("auto", .local), ("nextendo", .online)] {
            try f.store.set(raw, "DM_NETWORK", domain: domain)
            XCTAssertEqual(NXNativeGameSettings.multiplayerMode(in: s.snapshot(), default: .offline), mode)
            XCTAssertEqual(s.multiplayerMode(default: .offline), mode)
        }
        try s.setMultiplayerMode(.offline)
        XCTAssertEqual(s.multiplayerLaunch(settings: app, adapters: .init(), environment: [:]).environment, ["DM_NETWORK": "offline"])
        XCTAssertEqual(f.store.value("DM_NETWORK", domain: domain), "nextendo")
        try s.resetAll()
        XCTAssertEqual(s.multiplayerMode(default: .local), .local)
        XCTAssertThrowsError(try settings(fixture(vpn: true, online: false)).setMultiplayerMode(.online))
    }

    func testRemotePlayLaunchRequiresLocalModeAndPreservesExplicitChoices() throws {
        let f = try fixture(vpn: true, online: false)
        let s = try settings(f)
        var app = AppSettings()
        app.multiplayerDefault = .local
        app.multiplayerVPN = .zeroTier
        var adapters = RemotePlayAdapters()
        adapters.consider("zt0", flags: UInt32(IFF_UP), ipv4: 0x0ac7920b)
        let injected = ["DM_NETWORK": "auto", "DM_NET_VPN": "1", "DM_NETWORK_INTERFACE": "zt0"]
        func override(_ environment: [String: String] = [:]) -> [String: String] {
            s.multiplayerLaunch(settings: app, adapters: adapters, environment: environment).environment
        }
        try f.store.set("1", "DM_NET_VPN", domain: domain)
        XCTAssertEqual(s.multiplayerMode(default: .offline), .local, "An old VPN choice on a local-default build keeps Local")
        XCTAssertEqual(override(), injected)
        let fallback = s.multiplayerLaunch(settings: app, adapters: .init(), environment: [:])
        XCTAssertEqual(fallback.warning, .disconnected)
        XCTAssertEqual(fallback.environment, ["DM_NETWORK": "auto", "DM_NET_VPN": "0"])
        for network in ["offline", "nextendo", ""] {
            XCTAssertTrue(override(["DM_NETWORK": network]).isEmpty)
        }
        XCTAssertEqual(override(["DM_NET_VPN": "0"]), ["DM_NETWORK": "auto"])
        XCTAssertEqual(override(["DM_NETWORK_INTERFACE": "utun8"]), ["DM_NETWORK": "auto"])
        try FileManager.default.createDirectory(at: f.envURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("DM_NET_VPN=0\n".utf8).write(to: f.envURL)
        XCTAssertEqual(override(), ["DM_NETWORK": "auto"])
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8), "DM_NET_VPN=0\n")
        try Data("DM_NETWORK_INTERFACE=utun8\n".utf8).write(to: f.envURL)
        XCTAssertEqual(override(), ["DM_NETWORK": "auto"])
    }

    func testApplyWritesOnlyChangedTypedFields() throws {
        let f = try fixture()
        f.store.values[domain] = ["DM_RUMBLE_GAIN": "0.5", "DM_UPSCALER": "metalfx"]
        let s = try settings(f)
        let base = s.runtimeConfig()
        XCTAssertEqual(base.rumbleGain, 1, "0.5 shows as the nearest whole strength")
        var review = base
        review.fullscreen = true
        try s.apply(review, changedFrom: base)
        XCTAssertEqual(f.store.values[domain], ["DM_RUMBLE_GAIN": "0.5", "DM_UPSCALER": "metalfx", "DM_FULLSCREEN": "1"],
                       "untouched fields keep values the typed config cannot show")

        try s.resetAll()
        XCTAssertEqual(f.store.values[domain] ?? [:], [:])
    }

    func test120FPSChoiceSurvivesOtherOptionsAndLaunchMigration() throws {
        let f = try fixture()
        let file = f.game.url.appendingPathComponent("Contents/Resources/dm/launcher.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var rows = try XCTUnwrap(json["settings"] as? [[String: Any]])
        rows.append(["env": "DM_FPS_TARGET", "kind": "choice", "section": "Game", "label": "Frame rate",
                     "default": "60", "options": [["30", "30 fps"], ["60", "60 fps"], ["120", "120 fps"]]])
        json["settings"] = rows
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let s = try settings(f)
        try s.set("DM_FPS_TARGET", to: "120")
        let before = s.runtimeConfig() // Legacy typed defaults represent both 60 and 120 as enable60FPS.
        var changed = before
        changed.fullscreen = !before.fullscreen
        try s.apply(changed, changedFrom: before)

        let reopened = try settings(f)
        try reopened.migrate() // The same migration used before launching a saved-choices game.
        XCTAssertEqual(reopened.snapshot().value("DM_FPS_TARGET"), "120")
        XCTAssertEqual(f.store.values[domain]?["DM_FPS_TARGET"], "120")
        let fps = try XCTUnwrap(reopened.snapshot().setting("DM_FPS_TARGET"))
        XCTAssertEqual(GameSettingValues.label(fps, "120"), "120 fps")
        XCTAssertEqual(GameSettingValues.stepped(fps, from: "60", by: 1), "120")
    }
}
