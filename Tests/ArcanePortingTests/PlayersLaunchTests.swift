import XCTest
import ImageIO
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

        func writeRules(_ options: [String: [String]], commit: String? = nil) throws {
            var properties: [String: Any] = [
                "CFBundleIdentifier": domain, "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL",
                "DMTitleID": id,
                "DMSettings": options.map { ["env": $0.key, "values": $0.value] },
            ]
            properties["DMCommit"] = commit
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

    func testEngineFingerprintVectorAndDuplicates() throws {
        let hash = try XCTUnwrap(PlayerPadFingerprint.make(transport: "hid", vendor: 0x057e, product: 0x2009,
                                                           serial: "synthetic-pad-A"))
        // Shared vector: nxnative dm/host/tests/t_hid.c, pad_order_hash launch contract.
        XCTAssertEqual(hash, "63175a1f3b3d6edf2eb9f38e9b83ca9f9bda37d1ea527d77af61aeaca0260eaf")
        XCTAssertNotEqual(hash, PlayerPadFingerprint.make(transport: "hid", vendor: 0x057e, product: 0x2009,
                                                            serial: "synthetic-pad-A "))
        XCTAssertNil(PlayerPadFingerprint.make(transport: "hid", vendor: 0, product: 0, serial: "A\0B"))
        XCTAssertNil(PlayerPadFingerprint.make(transport: "hid", vendor: 0, product: 0, serial: String(repeating: "é", count: 256)))
        XCTAssertEqual(PlayerPadFingerprint.unique([(hash, "first")]), ["first": hash])
        XCTAssertTrue(PlayerPadFingerprint.unique([(hash, "first"), (hash, nil)]).isEmpty)
        XCTAssertTrue(PlayerPadFingerprint.unique([(hash, "first"), ("other", "first")]).isEmpty)
    }

    func testPackedCommitMustProveEachFeatureAndTheMacFix() async throws {
        typealias Features = PlayersLaunch.EngineFeatures
        struct Graph: CommandRunning, Sendable {
            let commits: Set<String>
            func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                     currentDirectory: URL?) throws -> CommandResult {
                let status: Int32
                if arguments.suffix(2).last != "123abcd" { status = 128 }
                else { status = commits.contains(arguments[4]) ? 0 : 1 }
                return .init(status: status, stdout: "", stderr: "")
            }
        }
        let f = try fixture()
        try f.write("\0DM_PAD_ORDER\0DM_PAD_MERGE\0DM_USER_%d_NAME\0DM_USER_%d_IMAGE\0", to: f.host)
        let controllerCommits: Set<String> = [Features.orderCommit, Features.mergeCommit]
        func prove(commit: String?, ancestors: Set<String>) async throws -> Features {
            try f.writeRules([:], commit: commit)
            let git = EngineAncestry(runner: Graph(commits: ancestors), engineFolder: f.home)
            return await Features.installed(in: f.app, ancestry: git)
        }
        let accepted = try await prove(commit: "123abcd",
                                       ancestors: controllerCommits.union([Features.macFix, Features.namesCommit]))
        XCTAssertEqual(accepted, .init(order: true, extendedMerge: true, names: true))
        let withoutFix = try await prove(commit: "123abcd", ancestors: controllerCommits.union([Features.imagesCommit]))
        XCTAssertEqual(withoutFix, .init(images: true))
        for commit in ["123abcd+dirty", "123abce", nil] {
            let unknown = try await prove(commit: commit, ancestors: controllerCommits.union([Features.macFix,
                                                    Features.namesCommit, Features.imagesCommit]))
            XCTAssertEqual(unknown, .init())
        }
    }

    func testVerifiedControllerOrderMergeAndGamePriority() throws {
        let f = try fixture()
        try f.write("\0\(join)\0\(merge)\0", to: f.host)
        let hash = String(repeating: "a", count: 64)
        var plan = PlayerPlan(mode: .pressToJoin)
        try plan.set(.init(controller: .init(stableID: "opaque")), at: 3)
        try plan.set(.init(controller: .init(stableID: "other")), at: 5)
        let live = [ConnectedPlayerController(id: "connection", stableID: "opaque")]
        func run(_ features: PlayersLaunch.EngineFeatures, player: Int = 1, options: [String: String] = [:]) -> PlayersLaunch {
            PlayersLaunch.evaluate(plan: plan, app: f.app, titleID: f.id, home: f.home, environment: options,
                                   savedChoices: MemorySavedChoices(), features: features, mergePlayer: player,
                                   connected: live, fingerprints: ["opaque": hash])
        }
        let features = PlayersLaunch.EngineFeatures(order: true, extendedMerge: true)
        XCTAssertEqual(run(features).additions, [join: "1", "DM_PAD_ORDER": "3:\(hash)"])
        XCTAssertEqual(run(features).status.controllerOrder, [5: .disconnectedController])
        XCTAssertEqual(run(.init()).additions, [join: "1"])
        XCTAssertEqual(run(.init()).status.controllerOrder[3], .unsupportedEngine)
        let explicit = ["DM_PAD_ORDER": "user order"]
        XCTAssertEqual(run(features, options: explicit).additions, [join: "1"])
        XCTAssertEqual(run(features, options: explicit).status.controllerOrder[3], .gameOption)
        plan.mode = .merge
        XCTAssertEqual(run(features, player: 3).additions, [merge: "3"])
        XCTAssertEqual(run(features, player: 3).status.controllerOrder[3], .mergeMode)
        XCTAssertEqual(run(.init(), player: 3).additions, [merge: "1"])
        XCTAssertEqual(run(.init(), player: 3).status.controllerMode, .unsupportedEngine)
        XCTAssertEqual(run(features, player: 3, options: [merge: "2"]).status.controllerMode, .gameOption)
        XCTAssertTrue(run(features, player: 3, options: explicit).additions.isEmpty)
        XCTAssertEqual(run(features, player: 9).status.controllerMode, .invalidMergePlayer)
    }

    func testPortraitsAndNamesHonorEachKeyAndLiveUntilExitOrOpenFailure() throws {
        let f = try fixture()
        try f.write("\0\(nick)\0", to: f.host)
        let first = LocalProfile(name: "First", look: .init(.init()))
        let second = LocalProfile(name: String(repeating: "é", count: 17), look: .init(.init()))
        var locked = LocalProfile(name: "Locked", look: .init(.init()))
        XCTAssertTrue(locked.setPIN("1234"))
        var plan = PlayerPlan(mode: .inOrder)
        for (number, profile) in [(1, first), (2, second), (8, locked)] {
            try plan.set(.init(profileID: profile.id), at: number)
        }
        try f.write("DM_USER_1_IMAGE=/fixture/preferred.jpg", to: f.titleEnv)
        func run(_ mode: String, features: PlayersLaunch.EngineFeatures = .init(names: true, images: true),
                 root: URL? = nil) -> PlayersLaunch {
            PlayersLaunch.evaluate(plan: plan, app: f.app, titleID: f.id, home: f.home,
                                   environment: [network: mode], savedChoices: MemorySavedChoices(),
                                   profiles: [first, second, locked], features: features,
                                   avatarSymbols: ["person.fill"], portraitDirectory: root)
        }
        let old = run("offline", features: .init(), root: f.home)
        XCTAssertEqual(old.additions, [nick: "First"])
        XCTAssertEqual(launch(f, players: old), launch(f, players: run("offline", features: .init(), root: nil)))
        XCTAssertEqual(run("nextendo", root: f.home).additions, [:])
        XCTAssertEqual(run("nextendo").status.portraits[2], .networkMode(.nextendo))
        XCTAssertEqual(run("auto").status.profileNames[2], .networkMode(.automatic))
        let preview = run("lan")
        XCTAssertNil(preview.additions["DM_USER_2_IMAGE"])
        XCTAssertNil(preview.status.portraits[2])
        XCTAssertEqual(run("offline", root: f.home.appendingPathComponent("missing")).status.portraits[2], .portraitExportFailed)
        for success in [true, false] {
            let players = run("offline", root: f.home)
            XCTAssertEqual(players.status.portraits[1], .environmentFile)
            XCTAssertEqual(players.status.portraits[8], .lockedProfile)
            XCTAssertEqual(players.status.profileNames[8], .lockedProfile)
            XCTAssertEqual(players.additions["DM_USER_2_NAME"], String(repeating: "é", count: 16))
            let path = try XCTUnwrap(players.additions["DM_USER_2_IMAGE"])
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            XCTAssertTrue(data.starts(with: [0xff, 0xd8]))
            XCTAssertLessThanOrEqual(data.count, 128 * 1024)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 256)
            XCTAssertEqual(image.height, 256)
            let folder = url.deletingLastPathComponent()
            let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
            XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
            let stub = LaunchServiceTests.FakeLauncher()
            stub.shouldSucceed = success
            LaunchService(launcher: stub).launch(appURL: f.app, environment: [:], homeButton: .auto,
                                                overlay: nil, snapshot: nil, players: players, onExit: nil) { opened, _ in
                XCTAssertEqual(opened, success)
            }
            XCTAssertEqual(stub.environment["DM_USER_2_IMAGE"], path)
            XCTAssertEqual(FileManager.default.fileExists(atPath: path), success)
            if success { try XCTUnwrap(stub.onExit)() }
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        }
    }
}
