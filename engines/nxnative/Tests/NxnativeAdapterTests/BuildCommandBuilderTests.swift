import XCTest
@testable import OortLibrary
@testable import NxnativeAdapter

final class BuildCommandBuilderTests: XCTestCase {
    func testExtractedInputOmitsKeysAndNamesSelectedTitleAndVersion() {
        let repo = URL(fileURLWithPath: "/tmp/engine")
        let command = BuildCommandBuilder.make(repo: repo,
            toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
            workspace: URL(fileURLWithPath: "/tmp/dump"), keys: nil,
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
            titleId: "0400000000000000", packageVersion: "v65536")
        XCTAssertFalse(command.arguments.contains("-k"))
        XCTAssertTrue(command.arguments.contains("--title-id"))
        XCTAssertTrue(command.arguments.contains("0400000000000000"))
        XCTAssertTrue(command.arguments.contains("-p"))
        XCTAssertTrue(command.arguments.contains("v65536"))
    }
    func testEachGameSuppliesItsBuildLanguageAndAutoAddsNoOverride() throws {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        for language in ["it", "ja", "auto"] {
            let config = GameRuntimeConfig(language: language)
            let command = BuildCommandBuilder.make(repo: repo,
                toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
                workspace: URL(fileURLWithPath: "/tmp/work"), keys: URL(fileURLWithPath: "/tmp/prod.keys"),
                output: URL(fileURLWithPath: "/tmp/Game.app"),
                developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
                language: config.languageForBuild)
            if language == "auto" {
                XCTAssertFalse(command.arguments.contains("-l"))
            } else {
                let flag = try XCTUnwrap(command.arguments.firstIndex(of: "-l"))
                XCTAssertEqual(command.arguments[flag + 1], language)
            }
        }
    }

    func testMacOnlyJSONCommand() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let cmd = BuildCommandBuilder.make(
            repo: repo, toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
            workspace: URL(fileURLWithPath: "/tmp/work"),
            keys: URL(fileURLWithPath: "/tmp/prod.keys"),
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode-beta.app/Contents/Developer")
        )
        XCTAssertTrue(cmd.arguments.contains("--platform"))
        XCTAssertTrue(cmd.arguments.contains("mac-app"))
        XCTAssertTrue(cmd.arguments.contains("--progress"))
        XCTAssertTrue(cmd.arguments.contains("json"))
        XCTAssertFalse(cmd.arguments.contains("--show-fps"))
        XCTAssertFalse(cmd.arguments.contains("--mods"))
        XCTAssertFalse(cmd.arguments.contains("--work-dir"))
        XCTAssertFalse(cmd.arguments.contains("--allow-other-metal"))
        XCTAssertTrue(cmd.environment["DEVELOPER_DIR"]?.contains("Xcode-beta") == true)
    }

    func testVerifiedCachePathIsSeparateFromSources() throws {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let sources = repo.appendingPathComponent("sources")
        let cache = repo.appendingPathComponent("restored cache")
        let command = BuildCommandBuilder.make(repo: repo,
            toolchain: EngineToolchain.resolve(runtime: nil, repo: repo), workspace: sources, workDir: cache,
            keys: nil, output: repo.appendingPathComponent("Game.app"), developerDir: repo)
        XCTAssertEqual(command.arguments[1], sources.path)
        let index = try XCTUnwrap(command.arguments.firstIndex(of: "--work-dir"))
        XCTAssertEqual(command.arguments[index + 1], cache.path)
    }

    func testCodeModsFolderIsOneMacBuildArgument() throws {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let folder = repo.appendingPathComponent("Code mods")
        let command = BuildCommandBuilder.make(
            repo: repo, toolchain: EngineToolchain.resolve(runtime: nil, repo: repo), workspace: repo,
            keys: nil, output: repo.appendingPathComponent("Game.app"), developerDir: repo, codeModsFolder: folder
        )
        let index = try XCTUnwrap(command.arguments.firstIndex(of: "--mods"))
        XCTAssertEqual(command.arguments[index + 1], folder.path)
    }

    func testUntestedToolchainOverrideReachesTheEngine() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let cmd = BuildCommandBuilder.make(
            repo: repo,
            toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
            workspace: URL(fileURLWithPath: "/tmp/work"),
            keys: URL(fileURLWithPath: "/tmp/prod.keys"),
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
            allowUntestedToolchain: true
        )
        XCTAssertTrue(cmd.arguments.contains("--allow-other-metal"))
    }

    func testNextendoRequiresAnEngineFlagAndConfiguredClientID() throws {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scripts = repo.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        let cli = scripts.appendingPathComponent("build_ipa_from_nsp.py")
        let toolchain = EngineToolchain.resolve(runtime: nil, repo: repo)

        for supported in [false, true] {
            try (supported ? "ap.add_argument('--nextendo')\n" : "").write(to: cli, atomically: true, encoding: .utf8)
            for clientID in [nil, "sample-client", "invalid client"] as [String?] {
                let expectedID = supported && clientID == "sample-client" ? clientID : nil
                let command = BuildCommandBuilder.make(
                    repo: repo, toolchain: toolchain, workspace: repo, keys: nil,
                    output: repo.appendingPathComponent("Game.app"), developerDir: repo,
                    nextendoClientID: clientID,
                    extraArguments: expectedID == nil ? ["--nextendo", "--allow-damaged"] : ["--allow-damaged"]
                )
                XCTAssertEqual(command.arguments.filter { $0 == "--nextendo" }.count, expectedID == nil ? 0 : 1)
                XCTAssertEqual(command.environment["DM_NEXTENDO_CLIENT_ID"], expectedID)
                XCTAssertTrue(command.arguments.contains("--allow-damaged"))
            }
        }
    }

    func testBuildRecordKeepsNextendoRequestAndDecodesOlderRecords() throws {
        let record = BuildRecord(nextendoRequested: true)
        let encoded = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(BuildRecord.self, from: encoded), record)
        let legacy = Data(#"{"startedAt":0,"toolchainVerified":true,"cancelled":false}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(BuildRecord.self, from: legacy).nextendoRequested)
    }

    func testMotionAndRomfsFlags() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let cmd = BuildCommandBuilder.make(
            repo: repo,
            toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
            workspace: URL(fileURLWithPath: "/tmp/work"),
            keys: URL(fileURLWithPath: "/tmp/prod.keys"),
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
            motion: true,
            romfsMode: "separate"
        )
        XCTAssertTrue(cmd.arguments.contains("--motion"))
        XCTAssertTrue(cmd.arguments.contains("--romfs"))
        XCTAssertTrue(cmd.arguments.contains("separate"))
    }

    func testBuildCommandUsesToolchain() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let runtime = BundledRuntime(root: URL(fileURLWithPath: "/App/Contents/Resources/Runtime"))
        let toolchain = EngineToolchain.resolve(runtime: runtime, repo: repo)
        let cmd = BuildCommandBuilder.make(
            repo: repo, toolchain: toolchain,
            workspace: URL(fileURLWithPath: "/tmp/work"),
            keys: URL(fileURLWithPath: "/tmp/prod.keys"),
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer")
        )
        XCTAssertEqual(cmd.executable, toolchain.python)
        XCTAssertTrue(cmd.environment["PATH"]?.hasPrefix("/App/Contents/Resources/Runtime/bin:") == true)
        XCTAssertEqual(cmd.environment["PYTHONNOUSERSITE"], "1")
        XCTAssertEqual(cmd.environment["PYTHONUNBUFFERED"], "1")
    }
}
