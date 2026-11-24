import XCTest
@testable import NXLibraryCore

final class RcloneConfigurationTests: XCTestCase {
    func testRCConfigMutationTransfersParametersOverStdinToLocalFixture() async throws {
        guard let executable = RcloneStorageBackend.findExecutable() else { throw XCTSkip("rclone is not installed") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("rclone.conf")
        let environment = ["RCLONE_CONFIG_PASS": "test-only"]
        let control = RcloneRemoteControl()
        defer { control.stop() }
        let response = try await control.call("config/create", [
            "name": "local-fixture", "type": "local", "parameters": ["description": "stdin marker"],
        ], executable: executable, environment: environment,
           flags: RcloneConfiguration.flags(config: config, environment: environment), sensitive: true)
        XCTAssertNotNil(response)
        let result = try await SystemCommandRunner().runCancellable(executable, ["config", "show", "local-fixture"]
            + RcloneConfiguration.flags(config: config, environment: environment), environment: environment)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("description = stdin marker"))
    }

    func testLegacyPreferenceAndDisabledSelection() {
        XCTAssertFalse(CloudLibraryPreference(storage: nil, enabled: nil).enabled)
        XCTAssertEqual(CloudLibraryPreference(storage: "gdrive", enabled: nil).root, "Games")
        let legacy = CloudLibraryPreference(storage: " gdrive:Library/Arcade ", enabled: nil)
        XCTAssertEqual(legacy.remote, "gdrive")
        XCTAssertEqual(legacy.root, "Library/Arcade")
        XCTAssertTrue(legacy.enabled)
        XCTAssertFalse(CloudLibraryPreference(storage: legacy.storage, enabled: false).enabled)
        XCTAssertNil(CloudLibraryPreference(storage: "bad,remote:Games", enabled: nil).remote)
        XCTAssertNil(CloudLibraryPreference(storage: "gdrive:../Games", enabled: nil).remote)
        let folderFirst = CloudLibraryPreference(storage: ":New Games", enabled: nil)
        XCTAssertNil(folderFirst.remote)
        XCTAssertEqual(folderFirst.storage, ":New Games")
    }

    func testSourcesRootDefaultsToLibraryGameFilesOrUsesAnIndependentPath() {
        XCTAssertEqual(CloudLibraryPreference(storage: nil, enabled: nil).sourcesRoot, "Games/GameFiles")
        XCTAssertEqual(CloudLibraryPreference(storage: "drive:Games/Switch/Arcane-nx/", enabled: true).sourcesRoot,
                       "Games/Switch/Arcane-nx/GameFiles")
        for library in ["Games/Switch/Arcane-nx", "Archive/Arcane"] {
            let preference = CloudLibraryPreference(storage: "drive:\(library)", enabled: true, sourcesRoot: "Games/Switch/Jeux")
            XCTAssertEqual(preference.storage, "drive:\(library)")
            XCTAssertEqual(preference.sourcesRoot, "Games/Switch/Jeux")
            XCTAssertEqual(preference.sourcesStorage, "drive:Games/Switch/Jeux")
        }
        for invalid in ["", " ", "../Jeux", "other:Jeux", "/Games/Jeux"] {
            let preference = CloudLibraryPreference(storage: "drive:Archive", enabled: true, sourcesRoot: invalid)
            XCTAssertNil(preference.sourcesRootOverride)
            XCTAssertEqual(preference.sourcesRoot, "Archive/GameFiles")
        }
    }

    func testListParsesFileRemotesAndReportsConfigurationNotNetworkStatus() throws {
        let remotes = try RcloneConfiguration.parseRemotes(Self.list)
        XCTAssertEqual(remotes.map(\.name), ["gdrive", "other drive"])
        XCTAssertEqual(remotes.map(\.type), ["drive", "sftp"])
        let config = CloudLibraryPreference(storage: "gdrive:Games", enabled: false)
        XCTAssertEqual(config.connection(in: remotes), .connected(remotes[0]))
        XCTAssertEqual(config.connection(in: []), .notConnected)
        XCTAssertEqual(config.connection(in: nil), .unknown)
        XCTAssertEqual(CloudLibraryPreference(storage: nil, enabled: true).connection(in: nil), .notConnected)
        XCTAssertThrowsError(try RcloneConfiguration.parseRemotes("gdrive:"))
    }

    func testConnectEncryptsBeforeBrowserAndVerifiesRemote() async throws {
        let fixture = Fixture([
            .ok(Self.list),
            CommandResult(status: 1, stdout: "", stderr: "Error: config file is NOT encrypted"),
            .ok(), .ok(), .ok(),
            .ok(#"[{"name":"gdrive-2","type":"drive","source":"file"}]"#),
        ])
        let remote = try await fixture.client.connect(clientID: "fake-client", secret: "fake-secret")
        XCTAssertEqual(remote.name, "gdrive-2")
        let commands = await fixture.recorder.commands
        let flags = ["--ask-password=false", "--config", fixture.config.path,
                     "--password-command", "/usr/bin/security find-generic-password -a rclone -s rclone-config -w"]
        XCTAssertEqual(commands, [
            ["listremotes", "--json"], ["config", "encryption", "check"],
            ["KEYCHAIN"], ["config", "encryption", "set"], ["config", "encryption", "check"],
            ["AUTHORIZE", "gdrive-2"],
            ["listremotes", "--json"],
        ].map { ["KEYCHAIN", "AUTHORIZE"].contains($0[0]) ? $0 : $0 + flags })
    }

    func testEncryptedConfigIsNotChangedAndFailureDropsProcessOutput() async throws {
        let fixture = Fixture([.ok(Self.list), .ok(), CommandResult(status: 1,
            stdout: "fake-secret", stderr: #"{"access_token":"fake-token"}"#)])
        do {
            _ = try await fixture.client.connect(clientID: "fake-client", secret: "fake-secret")
            XCTFail("OAuth failed")
        } catch {
            XCTAssertEqual(error as? RcloneConfiguration.Failure, .connect)
            XCTAssertFalse(error.localizedDescription.contains("fake-"))
        }
        let commands = await fixture.recorder.commands
        XCTAssertEqual(commands.count, 3)
        XCTAssertFalse(commands.contains(["KEYCHAIN"]))
    }

    func testReadOnlyFolderTestRejectsFilesAndDisconnectDeletesOnlyLocalConfig() async throws {
        let folder = Fixture([.ok(Self.list), .ok(#"{"IsDir":true}"#), .ok("synthetic-file"), .ok(), .ok("[]")])
        let config = CloudLibraryPreference(storage: "gdrive:Games", enabled: true)
        try await folder.client.test(config)
        try await folder.client.disconnect("gdrive")
        let commands = await folder.recorder.commands.map { Array($0.prefix(3)) }
        XCTAssertEqual(commands, [["listremotes", "--json", "--ask-password=false"],
                                  ["lsjson", "gdrive:Games", "--stat"], ["lsf", "gdrive:Games", "--max-depth"],
                                  ["config", "delete", "gdrive"], ["listremotes", "--json", "--ask-password=false"]])

        let file = Fixture([.ok(Self.list), .ok(#"{"IsDir":false}"#)])
        do {
            try await file.client.test(config)
            XCTFail("A file is not a folder")
        } catch {
            XCTAssertEqual(error as? RcloneConfiguration.Failure, .test)
        }
        let count = await file.recorder.commands.count
        XCTAssertEqual(count, 2)
    }

    func testCloudConnectionFailuresHaveDistinctRecoveryWithoutLeakingOutput() async {
        let samples: [(Int32, String, CloudLibraryFailure, CloudLibraryFailure.Action)] = [
            (1, #"{"msg":"Failed to create file system: lookup www.googleapis.com: no such host"}"#, .offline, .retry),
            (1, #"{"msg":"oauth2: invalid_grant: fake-token"}"#, .authentication, .reconnect),
            (1, "token expired", .authentication, .reconnect),
            (1, "googleapi: Error 401: Unauthorized", .authentication, .reconnect),
            (3, "directory not found", .folderMissing, .chooseFolder),
            (1, "googleapi: Error 403: storageQuotaExceeded", .quotaFull, .manageDriveStorage),
            (1, "googleapi: Error 403: Drive storage quota exceeded", .quotaFull, .manageDriveStorage),
            (1, "googleapi: Error 403: rateLimitExceeded", .unavailable, .retry),
        ]
        for (status, stderr, failure, action) in samples {
            let fixture = Fixture([.ok(Self.list), .init(status: status, stdout: "", stderr: stderr)])
            do {
                try await fixture.client.test(.init(storage: "gdrive:Games", enabled: true))
                XCTFail("A failed command cannot verify a folder")
            } catch {
                let issue = error as? CloudLibraryFailure ?? .unavailable
                XCTAssertEqual(issue, failure)
                XCTAssertEqual(issue.action, action)
                XCTAssertFalse(error.localizedDescription.contains("fake-token"))
            }
        }
    }

    private static let list = """
    [
        {"name":"gdrive","type":"drive","source":"file","description":"do not display"},
        {"name":"other drive","type":"sftp","source":"file"},
        {"name":"external","type":"sftp","source":"environment"},
        {"name":"unexpected,options","type":"drive","source":"file"}
    ]
    """

    private struct Fixture {
        let config = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("rclone.conf")
        let recorder: Recorder
        init(_ replies: [CommandResult]) { recorder = Recorder(replies) }
        var client: RcloneConfiguration {
            let recorder = recorder
            return RcloneConfiguration(executable: URL(fileURLWithPath: "/fake/rclone"), config: config,
                run: { _, args, _ in await recorder.run(args) },
                ensurePassword: { await recorder.recordPassword() },
                authorize: { _, _, _, name, _, _, replacing in
                    let result = await recorder.run(["AUTHORIZE", name])
                    guard result.status == 0, !replacing else { throw RcloneConfiguration.Failure.connect }
                })
        }
    }

    private actor Recorder {
        var commands: [[String]] = []
        var replies: [CommandResult]
        init(_ replies: [CommandResult]) { self.replies = replies }
        func run(_ args: [String]) -> CommandResult {
            commands.append(args)
            return replies.isEmpty ? CommandResult(status: 1, stdout: "", stderr: "") : replies.removeFirst()
        }
        func recordPassword() { commands.append(["KEYCHAIN"]) }
    }
}

private extension CommandResult {
    static func ok(_ stdout: String = "") -> Self { .init(status: 0, stdout: stdout, stderr: "") }
}
