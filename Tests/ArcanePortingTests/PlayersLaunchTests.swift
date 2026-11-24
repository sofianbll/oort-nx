import XCTest
import NXLibraryCore
@testable import ArcanePorting

final class PlayersLaunchTests: XCTestCase {
    private let merge = PlayerLaunchEnvironment.mergeKey
    private let join = PlayerLaunchEnvironment.pressToJoinKey
    private let nick = PlayerLaunchEnvironment.nicknameKey
    private let network = NextendoLaunch.networkKey

    private struct Fixture {
        let home: URL
        let id = "0100000000000001"
        let domain = "local.fixture.players"
        var app: URL { home.appendingPathComponent("Fixture.app") }
        var host: URL { HomeMenu.hostExecutable(in: app) }
        var plan: URL { home.appendingPathComponent("players.json") }
        var bundleEnv: URL { app.appendingPathComponent("Contents/Resources/dm/env.txt") }
        var titleEnv: URL { home.appendingPathComponent("Library/Application Support/nxnative/\(id)/env.txt") }
        var info: URL { app.appendingPathComponent("Contents/Info.plist") }

        func write(_ text: String, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func writeRules(_ options: [String: [String]]) throws {
            let properties: [String: Any] = [
                "CFBundleIdentifier": domain, "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL",
                "DMTitleID": id,
                "DMSettings": options.map { ["env": $0.key, "values": $0.value] },
            ]
            try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: info)
        }
    }

    private func fixture() throws -> Fixture {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("PlayersLaunch-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        return Fixture(home: home)
    }

    private func run(_ fixture: Fixture, _ plan: PlayerPlan, explicit: [String: String] = [:],
                     choices: SavedChoicesStore = MemorySavedChoices(), profiles: [LocalProfile] = []) -> PlayersLaunch {
        PlayersLaunch.evaluate(plan: plan, app: fixture.app, titleID: fixture.id, home: fixture.home,
                               environment: explicit, savedChoices: choices, profiles: profiles)
    }

    private func launch(_ fixture: Fixture, players: PlayersLaunch? = nil,
                        explicit: [String: String] = [:]) -> [String: String] {
        let stub = LaunchServiceTests.FakeLauncher()
        LaunchService(launcher: stub).launch(appURL: fixture.app, environment: explicit, players: players) { success, _ in
            XCTAssertTrue(success)
        }
        XCTAssertEqual(stub.opened, fixture.app)
        return NSWorkspaceLauncher.gameEnvironment(
            inheriting: ["HOME": fixture.home.path, "TMPDIR": fixture.home.path, "LANG": "fr", merge: "1", join: "1"],
            explicit: stub.environment, suppressInheritedPlayerMode: stub.suppressInheritedPlayerMode)
    }

    func testAbsentUnreadableAndUnusablePlanNeverBlockPlayAndKeepTheLegacyEnvironment() async throws {
        let f = try fixture()
        let library = PlayerPlanLibrary(url: f.plan)
        let explicit = ["HOME": f.home.path, network: "offline"]
        let baseline = launch(f, explicit: explicit)
        XCTAssertEqual(baseline, [
            "HOME": f.home.path, "TMPDIR": f.home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "fr", "DM_LAUNCHER": "0", network: "offline", merge: "1",
        ])
        func prepare() async -> PlayersLaunch {
            await PlayersLaunch.prepare(library: library, app: f.app, titleID: f.id, explicit: explicit, profiles: [])
        }
        let absent = await prepare()
        XCTAssertEqual(absent.status.plan, .absent)
        XCTAssertEqual(launch(f, players: absent, explicit: explicit), baseline)
        try f.write("{", to: f.plan)
        let malformed = await prepare()
        XCTAssertEqual(malformed.status.plan, .unreadable)
        XCTAssertEqual(launch(f, players: malformed, explicit: explicit), baseline)
        let directory = PlayerPlanLibrary(url: f.home)
        let unreadable = await PlayersLaunch.prepare(
            library: directory, app: f.app, titleID: f.id, explicit: explicit, profiles: [])
        XCTAssertEqual(unreadable.status.plan, .unreadable)
        XCTAssertEqual(launch(f, players: unreadable, explicit: explicit), baseline)
    }

    func testEveryStartReadsTheSavedPlanAndOnlyExactInstalledEngineKeysEnableIt() async throws {
        let f = try fixture()
        let library = PlayerPlanLibrary(url: f.plan)
        let explicit = ["HOME": f.home.path]
        func prepare() async -> PlayersLaunch {
            await PlayersLaunch.prepare(library: library, app: f.app, titleID: f.id, explicit: explicit, profiles: [])
        }
        try await library.save(.init(mode: .merge))
        try f.write("\0\(join)\0NOT_\(merge)\0\(merge)_SUFFIX\0", to: f.host)
        let unsupported = await prepare()
        XCTAssertEqual(unsupported.status.controllerMode, .unsupportedEngine)
        XCTAssertNil(launch(f, players: unsupported)[merge])
        XCTAssertNil(launch(f, players: unsupported)[join])

        try f.write("\0\(join)\0\(merge)\0", to: f.host)
        let first = await prepare()
        let runningEnvironment = launch(f, players: first)
        XCTAssertEqual(runningEnvironment[merge], "1")
        XCTAssertNil(runningEnvironment[join])
        try await library.save(.init(mode: .pressToJoin))
        let second = await prepare()
        XCTAssertEqual(launch(f, players: second)[join], "1")
        XCTAssertNil(launch(f, players: second)[merge])
        XCTAssertEqual(runningEnvironment[merge], "1") // The earlier child is not reconfigured.
        try await library.save(.init(mode: .inOrder))
        let third = await prepare()
        XCTAssertNil(launch(f, players: third)[merge])
        XCTAssertNil(launch(f, players: third)[join])
        XCTAssertNil(third.status.controllerMode)
    }

    func testBothEnvFilesAndExplicitOrSavedGameOptionsKeepPriority() throws {
        let f = try fixture()
        try f.write("\0\(join)\0\(merge)\0\(nick)\0", to: f.host)
        let profile = LocalProfile(name: "Local name", look: .init(.init()))
        var plan = PlayerPlan(mode: .merge)
        try plan.set(.init(profileID: profile.id), at: 1)
        try f.write(" # \(merge)=1\r\n\t\(join) =\r\n\(network)=offline\r\n", to: f.titleEnv)
        try f.write("\(nick)=Game file name\n\(network)=nextendo\n", to: f.bundleEnv)
        let file = run(f, plan, profiles: [profile])
        XCTAssertEqual(file.status.controllerMode, .environmentFile)
        XCTAssertEqual(file.status.nickname, .environmentFile)
        XCTAssertTrue(file.additions.isEmpty)
        XCTAssertNil(launch(f, players: file)[merge])

        try f.write("\(network)=offline\n", to: f.titleEnv)
        try f.write("\(join)=0\n\(network)=nextendo\n", to: f.bundleEnv)
        let bundled = run(f, plan, profiles: [profile])
        XCTAssertEqual(bundled.additions, [nick: "Local name"])
        XCTAssertEqual(bundled.status.controllerMode, .environmentFile)

        try f.write("# No fixed options\n", to: f.bundleEnv)
        let forced = [join: "0", nick: "Explicit name"]
        let option = run(f, plan, explicit: forced, profiles: [profile])
        XCTAssertEqual(option.status.controllerMode, .gameOption)
        XCTAssertEqual(option.status.nickname, .gameOption)
        XCTAssertEqual(launch(f, players: option, explicit: forced)[join], "0")
        XCTAssertEqual(launch(f, players: option, explicit: forced)[nick], "Explicit name")

        try f.writeRules([join: ["0", "1"], nick: ["Saved name"]])
        let store = MemorySavedChoices()
        try store.set("0", join, domain: f.domain)
        try store.set("Saved name", nick, domain: f.domain)
        let saved = run(f, plan, choices: store, profiles: [profile])
        XCTAssertEqual(saved.status, .init(plan: .active, controllerMode: .gameOption, nickname: .gameOption))
        XCTAssertTrue(saved.additions.isEmpty)
        let ignored = run(f, plan, explicit: ["DM_SAVED_CHOICES": "0"], choices: store, profiles: [profile])
        XCTAssertEqual(ignored.additions, [merge: "1", nick: "Local name"])
        try store.set("no longer supported", join, domain: f.domain)
        XCTAssertEqual(run(f, plan, choices: store, profiles: [profile]).additions, [merge: "1"])

        let packedTitle = PlayersLaunch.evaluate(plan: plan, app: f.app, titleID: "0100000000000002",
                                                 home: f.home, environment: [:], savedChoices: store, profiles: [profile])
        XCTAssertEqual(packedTitle.status.nickname, .gameOption)
        XCTAssertEqual(packedTitle.additions, [merge: "1"])
    }

    func testUnreadableFileNeverAllowsAnInjection() throws {
        let f = try fixture()
        try f.write("\0\(merge)\0", to: f.host)
        try f.write("\(merge)=0", to: f.titleEnv)
        try Data([0xff]).write(to: f.titleEnv)
        let broken = run(f, .init(mode: .merge))
        XCTAssertEqual(broken.status.controllerMode, .environmentFileUnreadable)
        XCTAssertNil(launch(f, players: broken)[merge])
        try f.write("", to: f.titleEnv)
        let empty = run(f, .init(mode: .merge))
        XCTAssertEqual(empty.additions, [merge: "1"])
        try f.write("\(merge)=\u{0301}\n", to: f.titleEnv)
        XCTAssertEqual(run(f, .init(mode: .merge)).status.controllerMode, .environmentFile)
        try f.write(String(repeating: "X", count: 4095), to: f.bundleEnv)
        XCTAssertEqual(run(f, .init(mode: .merge)).status.controllerMode, .environmentFileUnreadable)
    }

    func testNetworkModeAndProfileReasonsDoNotBlockControllerMode() throws {
        let f = try fixture()
        try f.write("\0\(merge)\0\(nick)\0", to: f.host)
        var profile = LocalProfile(name: "Local name", look: .init(.init()))
        var plan = PlayerPlan(mode: .merge)
        try plan.set(.init(profileID: profile.id), at: 1)
        let missing = run(f, plan, explicit: [network: "offline"])
        XCTAssertEqual(missing.status.nickname, .missingProfile)
        XCTAssertEqual(missing.additions, [merge: "1"])
        for mode in ["offline", "ldn", "lan"] {
            XCTAssertEqual(run(f, plan, explicit: [network: mode], profiles: [profile]).additions[nick], "Local name")
        }
        for (mode, reason) in [("nextendo", PlayerLaunchNetworkMode.nextendo), ("auto", .automatic),
                               ("unknown", .automatic), (" offline", .automatic)] {
            let result = run(f, plan, explicit: [network: mode], profiles: [profile])
            XCTAssertEqual(result.status.nickname, .networkMode(reason))
            XCTAssertNil(result.additions[nick])
        }
        try f.write("\(network)=nextendo\n", to: f.titleEnv)
        XCTAssertEqual(run(f, plan, explicit: [network: "offline"], profiles: [profile]).additions[nick], "Local name")
        XCTAssertNil(run(f, plan, profiles: [profile]).additions[nick])
        try f.write("\r\(network)=offline\n", to: f.titleEnv)
        let store = MemorySavedChoices()
        try f.writeRules([network: ["offline", "nextendo"]])
        try store.set("nextendo", network, domain: f.domain)
        XCTAssertEqual(run(f, plan, choices: store, profiles: [profile]).status.nickname, .networkMode(.nextendo))
        try store.set("offline", network, domain: f.domain)
        XCTAssertEqual(run(f, plan, choices: store, profiles: [profile]).additions[nick], "Local name")
        try f.write("\0\(merge)\0", to: f.host)
        XCTAssertEqual(run(f, plan, explicit: [network: "offline"], profiles: [profile]).status.nickname, .unsupportedEngine)
        try f.write("\0\(merge)\0\(nick)\0", to: f.host)
        profile.name = "\0"
        XCTAssertEqual(run(f, plan, explicit: [network: "offline"], profiles: [profile]).status.nickname, .invalidNickname)
    }

    func testLockedProfileNeverBlocksPlayAndPINGrantIsLimitedToCurrentPlan() async throws {
        let f = try fixture()
        let library = PlayerPlanLibrary(url: f.plan)
        try f.write("\0\(merge)\0\(nick)\0", to: f.host)
        var profile = LocalProfile(name: "Private name", look: .init(.init()))
        XCTAssertTrue(profile.setPIN("1234"))
        var plan = PlayerPlan(mode: .merge)
        try plan.set(.init(profileID: profile.id), at: 1)
        try await library.save(plan)
        let explicit = ["HOME": f.home.path, network: "offline"]
        func prepare() async -> PlayersLaunch {
            await PlayersLaunch.prepare(library: library, app: f.app, titleID: f.id, explicit: explicit, profiles: [profile])
        }
        let locked = await prepare()
        XCTAssertEqual(locked.status.nickname, .lockedProfile)
        XCTAssertEqual(launch(f, players: locked, explicit: explicit)[merge], "1")
        XCTAssertNil(launch(f, players: locked, explicit: explicit)[nick])
        let rejected = try await library.authorize(profile, pin: "9999", for: plan)
        XCTAssertFalse(rejected)
        let authorized = try await library.authorize(profile, pin: "1234", for: plan)
        XCTAssertTrue(authorized)
        let unlocked = await prepare()
        XCTAssertEqual(launch(f, players: unlocked, explicit: explicit)[nick], "Private name")
        plan.mode = .inOrder
        try await library.save(plan)
        let changed = await prepare()
        XCTAssertEqual(changed.status.nickname, .lockedProfile)
        XCTAssertNil(launch(f, players: changed, explicit: explicit)[nick])
        XCTAssertFalse(try String(contentsOf: f.plan, encoding: .utf8).contains("1234"))
    }
}
