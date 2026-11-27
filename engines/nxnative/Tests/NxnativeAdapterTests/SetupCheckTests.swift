import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class SetupCheckTests: XCTestCase {
    func testKeysAreOptionalOnlyForAnEngineSupportingExtractedFolders() {
        var input = facts()
        input.keys = .required
        input.keysOptional = true
        let optional = SetupCheck.items(from: input).first { $0.id == .keys }
        XCTAssertEqual(optional?.state, .ready)
        XCTAssertEqual(optional?.chip, "Optional")
        input.keysOptional = false
        XCTAssertEqual(SetupCheck.items(from: input).first { $0.id == .keys }?.state, .missing)
    }

    func testKeysCardKeepsAnImportErrorVisibleWhenKeysAreOptionalOrAlreadyPresent() {
        var input = facts()
        input.keysOptional = true
        input.keysError = "The key file has no header_key."
        let existing = SetupCheck.items(from: input).first { $0.id == .keys }
        XCTAssertEqual(existing?.inlineError, "The key file has no header_key.")
        XCTAssertEqual(existing?.actionTitle, "Replace")
        input.keys = .required
        let optional = SetupCheck.items(from: input).first { $0.id == .keys }
        XCTAssertEqual(optional?.inlineError, "The key file has no header_key.")
        XCTAssertEqual(optional?.actionTitle, "Choose file")
        XCTAssertEqual(optional?.state, .ready)
    }

    private let pin = "af616f54652fa7f50a2e223ceed1d08a9bc83848"
    private let folder = URL(fileURLWithPath: "/Users/a b/nxnative")

    private func facts() -> SetupFacts {
        SetupFacts(xcodeStatus: 0, metalVersion: "32023.921", certifiedMetal: "32023.921", allowUntested: false,
                   engine: .checkout(head: pin, relation: .current, tree: .clean), engineFolder: folder, pinnedCommit: pin,
                   runtimeProblem: nil,
                   keys: .available(applicationGenerations: 3), keysError: nil,
                   libraryReadable: true)
    }

    private func item(_ id: SetupItemID, _ change: (inout SetupFacts) -> Void = { _ in }) -> SetupItem {
        var f = facts()
        change(&f)
        return SetupCheck.items(from: f).first { $0.id == id }!
    }

    func testAllReadyInCardOrder() {
        let items = SetupCheck.items(from: facts())
        XCTAssertEqual(items.map(\.id), SetupItemID.allCases)
        XCTAssertTrue(items.allSatisfy { $0.state == .ready }, items.map(\.chip).joined(separator: ", "))
    }

    func testXcode() {
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = nil }.state, .missing)
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = nil }.chip, "Not installed")
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = nil }.actionTitle, "Get Xcode")
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = 69 }.state, .needsYou)
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = 69 }.chip, "Open Xcode once")
        XCTAssertEqual(item(.xcode).chip, "✓ Ready")

        let old = item(.xcode) { $0.xcodeVersion = "26.4" }
        XCTAssertEqual(old.state, .needsYou)
        XCTAssertEqual(old.chip, "Update Xcode")
        XCTAssertEqual(old.actionTitle, "Open App Store")
        XCTAssertTrue(old.detail.contains("27.2"))
        XCTAssertEqual(item(.xcode) { $0.xcodeVersion = "27.2" }.state, .ready)
    }

    func testMetal() {
        let missing = item(.metal) { $0.metalVersion = nil }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "Not installed")
        XCTAssertEqual(missing.actionTitle, "Install")

        let other = item(.metal) { $0.metalVersion = "32023.917" }
        XCTAssertEqual(other.state, .warning)
        XCTAssertEqual(other.chip, "Not certified")
        XCTAssertEqual(other.actionTitle, "Install 32023.921")

        let unknown = item(.metal) { $0.metalVersion = "32023.921"; $0.certifiedMetal = "32024.5" }
        XCTAssertEqual(unknown.state, .warning)
        XCTAssertEqual(unknown.chip, "Waiting for engine")
        XCTAssertNil(unknown.actionTitle)
        XCTAssertTrue(unknown.detail.contains("still play"))

        let overridden = item(.metal) { $0.metalVersion = "32023.917"; $0.allowUntested = true }
        XCTAssertEqual(overridden.state, .ready)
        XCTAssertTrue(overridden.detail.contains("untested toolchain override is on"))

        XCTAssertEqual(item(.metal).state, .ready)
    }

    /// nxnative 641636e2 commits its tools as native executables: Setup has no .NET card.
    func testNoDotnetCard() {
        XCTAssertNil(SetupItemID(rawValue: "dotnet"))
        XCTAssertFalse(SetupCheck.items(from: facts()).contains { $0.title.contains(".NET") })
    }

    func testEngine() {
        let missing = item(.engine) { $0.engine = .missing }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "Not installed")
        XCTAssertEqual(missing.actionTitle, "Clone")

        XCTAssertEqual(item(.engine).state, .ready)

        // After an Arcane update the engine here is older than the pin: an update, not an error.
        for relation: EngineCheckout.Relation in [.behind, .unknown] {
            let update = item(.engine) { $0.engine = .checkout(head: "ee369f0", relation: relation, tree: .clean) }
            XCTAssertEqual(update.state, .warning, "still reopens Setup; updating is explicit")
            XCTAssertEqual(update.chip, "Update ready")
            XCTAssertEqual(update.actionTitle, "Update")
            XCTAssertEqual(update.detail, "This version of Oort NX uses nxnative af616f5; the engine here is at ee369f0. Update downloads it and switches to it. Games you built keep playing.")
        }
        // A checkout ahead of the pin (or on another branch) is moved back, said as such.
        let ahead = item(.engine) { $0.engine = .checkout(head: "ee369f0", relation: .divergent, tree: .clean) }
        XCTAssertEqual(ahead.state, .warning)
        XCTAssertEqual(ahead.chip, "Other version")
        XCTAssertEqual(ahead.actionTitle, "Switch")
        XCTAssertEqual(ahead.detail, "The engine here is at ee369f0, not the af616f5 this version of Oort NX is tested with. Switch moves it to af616f5. Games you built keep playing.")

        let dirty = item(.engine) { $0.engine = .checkout(head: "ee369f0", relation: .unknown, tree: .modified) }
        XCTAssertEqual(dirty.state, .warning)
        XCTAssertEqual(dirty.chip, "Local changes")
        XCTAssertNil(dirty.actionTitle)
        XCTAssertTrue(dirty.detail.contains(folder.path))

        let notRepo = item(.engine) { $0.engine = .notACheckout }
        XCTAssertEqual(notRepo.state, .warning)
        XCTAssertEqual(notRepo.chip, "Not a checkout")
        XCTAssertNil(notRepo.actionTitle)
    }

    func testRuntime() {
        XCTAssertEqual(item(.runtime).chip, "✓ Included")
        let broken = item(.runtime) { $0.runtimeProblem = "capstone 6" }
        XCTAssertEqual(broken.state, .failed)
        XCTAssertEqual(broken.chip, "Reinstall app")
        XCTAssertNil(broken.actionTitle)
        XCTAssertTrue(broken.detail.contains("capstone 6"))
    }

    func testUnbundledRuntimeDoesNotRecommendReinstalling() {
        let missing = item(.runtime) {
            $0.runtimeIsBundled = false
            $0.runtimeProblem = "Python or its modules (capstone 5, lz4, fontTools, zbic, nsz) did not start"
        }
        XCTAssertEqual(missing.state, .failed)
        XCTAssertEqual(missing.chip, "Not included")
        XCTAssertEqual(missing.about, "This build does not include Python and tools.")
        XCTAssertFalse(missing.detail.contains("DMG"))
        XCTAssertNil(missing.actionTitle)
        XCTAssertEqual(item(.runtime) { $0.runtimeIsBundled = false }.chip, "✓ Ready")
    }

    func testDivergedPersonalEngineNamesTheConfiguredRepositoryAndPin() {
        let fork = "https://github.com/sofianbll/nxnative"
        let card = item(.engine) {
            $0.engine = .checkout(head: "ee369f0", relation: .divergent, tree: .clean)
            $0.engineRemote = fork
            $0.pinnedCommit = "a35babeade0c34b3f928e0b32310ba66eb98bc86"
        }
        XCTAssertEqual(card.about, fork)
        XCTAssertEqual(card.actionTitle, "Switch")
        XCTAssertTrue(card.detail.contains("a35babe"))
    }

    func testKeys() {
        let ready = item(.keys)
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(ready.chip, "✓ Imported")
        XCTAssertTrue(ready.detail.contains("3"), ready.detail)

        let missing = item(.keys) { $0.keys = .required }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "Not imported")
        XCTAssertEqual(missing.actionTitle, "Choose file")

        let invalid = item(.keys) { $0.keys = .invalid(.missingHeaderKey); $0.keysError = "The keys file has no header_key." }
        XCTAssertEqual(invalid.state, .missing)
        XCTAssertEqual(invalid.detail, "The keys file has no header_key.")
    }

    func testLibrary() {
        let missing = item(.library) { $0.libraryReadable = nil }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "Not chosen")
        XCTAssertEqual(missing.actionTitle, "Choose folder")
        XCTAssertEqual(item(.library) { $0.libraryReadable = false }.state, .warning)
        XCTAssertEqual(item(.library) { $0.libraryReadable = false }.chip, "Not readable")
        XCTAssertEqual(item(.library).state, .ready)
    }

    func testGameAppsFolderNeedsExplicitFirstSetupChoiceEvenWhenReadable() {
        let card = item(.library) {
            $0.libraryFolder = URL(fileURLWithPath: "/Users/a b/Applications")
            $0.libraryNeedsConfirmation = true
        }
        XCTAssertEqual(card.state, .needsYou)
        XCTAssertEqual(card.actionTitle, "Choose folder")
        XCTAssertTrue(card.detail.contains("/Users/a b/Applications"))
        XCTAssertTrue(card.isRequired)
    }

    func testGameFolderCardsLeadSetupAndShowDifferentPurposes() throws {
        var input = facts()
        input.libraryFolder = URL(fileURLWithPath: "/Volumes/Games/Mac apps")
        input.sourcesFolder = URL(fileURLWithPath: "/Volumes/Games/Packages")
        input.sourcesReadable = true
        let cards = SetupCheck.items(from: input)
        XCTAssertEqual(Array(cards.prefix(2)).map(\.id.rawValue), ["library", "sources"])
        let apps = try XCTUnwrap(cards.first { $0.id == .library })
        XCTAssertTrue(apps.detail.contains("/Volumes/Games/Mac apps"))
        let files = try XCTUnwrap(cards.first { $0.id.rawValue == "sources" })
        XCTAssertTrue(files.detail.contains("/Volumes/Games/Packages"))
        for format in ["NSP", "XCI", "NSZ", "XCZ"] {
            XCTAssertTrue(files.about.contains(format), "Missing \(format)")
        }
        XCTAssertFalse(files.about.lowercased().contains("extracted"))

        input.extractedFoldersSupported = true
        let supported = try XCTUnwrap(SetupCheck.items(from: input).first { $0.id.rawValue == "sources" })
        XCTAssertTrue(supported.about.lowercased().contains("extracted folders"))
    }

    func testGameFilesFolderIsOptionalWhenUnchosenOrUnavailable() throws {
        for readable in [nil, false] as [Bool?] {
            var input = facts()
            input.sourcesReadable = readable
            if readable != nil { input.sourcesFolder = URL(fileURLWithPath: "/Volumes/Disconnected/Sources") }
            let cards = SetupCheck.items(from: input)
            let files = try XCTUnwrap(cards.first { $0.id.rawValue == "sources" })
            XCTAssertFalse(files.isRequired)
            XCTAssertEqual(files.state, readable == nil ? .ready : .warning)
            XCTAssertTrue(cards.filter(\.isRequired).allSatisfy { $0.state == .ready })
            XCTAssertFalse(SetupCheck.shouldReopen(previous: [files.id: .ready], current: cards))
            XCTAssertEqual(SetupCheck.automatic(cards), [])
        }
    }

    func testOverridesWin() {
        var f = facts()
        f.engine = .missing
        let items = SetupCheck.applying([.engine: .working("CLONING…")], to: SetupCheck.items(from: f))
        let engine = items.first { $0.id == .engine }!
        XCTAssertEqual(engine.state, .working)
        XCTAssertEqual(engine.chip, "CLONING…")
        XCTAssertNil(engine.actionTitle)
        XCTAssertEqual(items.first { $0.id == .xcode }!.state, .ready)
        XCTAssertNil(engine.progress)

        f.metalVersion = nil
        let downloading = SetupCheck.applying([.metal: .working("DOWNLOADING…", progress: 0.25, detail: "50 of 200 MB")],
                                              to: SetupCheck.items(from: f)).first { $0.id == .metal }!
        XCTAssertEqual(downloading.chip, "DOWNLOADING… 25%")
        XCTAssertEqual(downloading.progress, 0.25)
        XCTAssertEqual(downloading.detail, "50 of 200 MB")
    }

    func testAutomaticActions() {
        var f = facts()
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f)), [])

        f.metalVersion = "32023.917"
        f.engine = .missing
        f.keys = .required
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f)), [.metal, .engine])
        // Metal comes through Xcode: nothing to try until Xcode is ready.
        f.xcodeVersion = "26.4"
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f)), [.engine])
        f.xcodeVersion = nil
        f.xcodeStatus = nil
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f)), [.engine])
        f.xcodeStatus = 0

        // Neither a known divergence nor an update to an existing checkout is automatic.
        for relation: EngineCheckout.Relation in [.behind, .divergent, .unknown] {
            f.engine = .checkout(head: "ee369f0", relation: relation, tree: .clean)
            XCTAssertFalse(SetupCheck.automatic(SetupCheck.items(from: f)).contains(.engine))
        }

        f.certifiedMetal = "32024.5"
        f.engine = .checkout(head: "ee369f0", relation: .unknown, tree: .modified)
        let items = SetupCheck.applying([.metal: .working("DOWNLOADING…")], to: SetupCheck.items(from: f))
        XCTAssertEqual(SetupCheck.automatic(items), [])
    }

    func testShouldReopenOnlyOnRegression() {
        var f = facts()
        f.metalVersion = "32023.917"
        f.keys = .required
        let current = SetupCheck.items(from: f)
        XCTAssertTrue(SetupCheck.shouldReopen(previous: [.metal: .ready], current: current))
        XCTAssertFalse(SetupCheck.shouldReopen(previous: [.keys: .missing], current: current))
        XCTAssertFalse(SetupCheck.shouldReopen(previous: [:], current: current))
    }

    // MARK: - Probe

    private final class FakeRunner: CommandRunning, @unchecked Sendable {
        var responses: [String: CommandResult] = [:]
        var calls: [(executable: URL, arguments: [String])] = []
        func run(_ executable: URL, _ arguments: [String],
                 environment: [String: String]?, currentDirectory: URL?) throws -> CommandResult {
            calls.append((executable, arguments))
            let key = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            return responses.first { key.hasSuffix($0.key) }?.value ?? CommandResult(status: 0, stdout: "", stderr: "")
        }
    }

    private func probe(_ runner: FakeRunner, engine: URL, home: URL,
                       library: URL? = nil, sources: URL? = nil, needsConfirmation: Bool = false) -> SetupProbe {
        SetupProbe(runner: runner, toolchain: .resolve(runtime: nil, repo: engine), developerDir: nil,
                   engineFolder: engine, pinnedCommit: pin, certifiedMetal: "32023.921", allowUntested: false,
                   keysDirectory: home.appendingPathComponent("keys"), libraryFolder: library,
                   sourcesFolder: sources, libraryNeedsConfirmation: needsConfirmation)
    }

    func testReadOnlyGameAppsFolderWarnsThatNewBuildsCannotBeInstalled() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        let library = home.appendingPathComponent("Existing game apps")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path)
            try? fm.removeItem(at: home)
        }
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: library.path)
        XCTAssertTrue(fm.isReadableFile(atPath: library.path))
        XCTAssertFalse(fm.isWritableFile(atPath: library.path))

        let facts = SetupProbe(runner: FakeRunner(), toolchain: .resolve(runtime: nil, repo: home),
                               developerDir: nil, engineFolder: home, pinnedCommit: pin,
                               certifiedMetal: "32023.921", allowUntested: false,
                               keysDirectory: home.appendingPathComponent("keys"),
                               libraryFolder: library).facts()
        let card = SetupCheck.items(from: facts).first { $0.id == .library }
        XCTAssertEqual(card?.state, .warning)
        XCTAssertNotNil(card?.actionTitle)
    }

    func testProbeRejectsFilesAndKeepsUnavailableFolderPaths() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let file = home.appendingPathComponent("file.nsp")
        try Data().write(to: file)
        let missing = home.appendingPathComponent("disconnected sources")

        let facts = probe(FakeRunner(), engine: home, home: home, library: file, sources: missing,
                          needsConfirmation: true).facts()
        XCTAssertEqual(facts.libraryReadable, false, "App discovery needs a directory, not a readable file")
        XCTAssertEqual(facts.libraryFolder, file)
        XCTAssertTrue(facts.libraryNeedsConfirmation)
        XCTAssertEqual(facts.sourcesReadable, false)
        XCTAssertEqual(facts.sourcesFolder, missing)
    }

    func testProbeReadsOptionalSourceFolderAndEngineCapabilities() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        let scripts = home.appendingPathComponent("scripts")
        let sources = home.appendingPathComponent("sources")
        try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sources.path)
            try? fm.removeItem(at: home)
        }
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sources.path)
        let script = scripts.appendingPathComponent("build_ipa_from_nsp.py")
        try "import pack_dump\nparser.add_argument('--title-id')".write(to: script, atomically: true, encoding: .utf8)

        let facts = probe(FakeRunner(), engine: home, home: home, library: home, sources: sources).facts()
        XCTAssertEqual(facts.sourcesReadable, true)
        XCTAssertEqual(facts.sourcesFolder, sources)
        XCTAssertTrue(facts.extractedFoldersSupported)
        XCTAssertTrue(facts.keysOptional)
        let card = SetupCheck.items(from: facts).first { $0.id == .sources }
        XCTAssertEqual(card?.state, .ready)
        XCTAssertTrue(card?.about.contains("extracted folders") == true)

        try "parser.add_argument('--nsp')".write(to: script, atomically: true, encoding: .utf8)
        let legacy = probe(FakeRunner(), engine: home, home: home, library: home, sources: sources).facts()
        XCTAssertFalse(legacy.extractedFoldersSupported)
    }

    func testProbeWarnsForUnreadableGameAppsDirectory() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        let library = home.appendingPathComponent("apps")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path)
            try? fm.removeItem(at: home)
        }
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: library.path)
        XCTAssertFalse(fm.isReadableFile(atPath: library.path))
        let facts = probe(FakeRunner(), engine: home, home: home, library: library).facts()
        XCTAssertEqual(facts.libraryReadable, false)
        XCTAssertEqual(SetupCheck.items(from: facts).first { $0.id == .library }?.state, .warning)
    }

    /// `-I` makes Python ignore PYTHONDONTWRITEBYTECODE, so each call passes `-B` itself: a bundled
    /// runtime that writes __pycache__ into the app breaks its code signature.
    func testProbeNeverWritesBytecodeIntoTheBundle() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner()
        let python = home.appendingPathComponent("Runtime/python/bin/python3")
        let toolchain = EngineToolchain(python: python, extraPath: [], isBundled: true)
        _ = SetupProbe(runner: runner, toolchain: toolchain, developerDir: nil, engineFolder: home,
                       pinnedCommit: pin, certifiedMetal: "32023.921", allowUntested: false,
                       keysDirectory: home.appendingPathComponent("keys"), libraryFolder: nil).facts()
        let pythonCalls = runner.calls.filter { $0.executable == python }
        XCTAssertFalse(pythonCalls.isEmpty)
        for call in pythonCalls { XCTAssertTrue(call.arguments.contains("-B"), call.arguments.joined(separator: " ")) }
    }

    func testProbeFacts() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let engine = home.appendingPathComponent("nx native")
        let runner = FakeRunner()
        runner.responses["xcodebuild -version"] = CommandResult(status: 69, stdout: "", stderr: "license")
        runner.responses["metal --version"] = CommandResult(status: 0, stdout: "Apple metal version 32023.921 (metalfe-32023.921.6)\n", stderr: "")
        runner.responses["rev-parse HEAD"] = CommandResult(status: 0, stdout: pin + "\n", stderr: "")
        runner.responses["status --porcelain"] = CommandResult(status: 0, stdout: " M dm/gfx/nvn/dmsh_chain.h\n?? x/_build/a\n", stderr: "")

        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().engine, .missing)

        try FileManager.default.createDirectory(at: engine, withIntermediateDirectories: true)
        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().engine, .notACheckout)

        try FileManager.default.createDirectory(at: engine.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let facts = probe(runner, engine: engine, home: home).facts()
        XCTAssertEqual(facts.engine, .checkout(head: pin, relation: .current, tree: .clean))
        XCTAssertEqual(facts.xcodeStatus, 69)
        XCTAssertNil(facts.xcodeVersion)
        XCTAssertEqual(facts.metalVersion, "32023.921")
        XCTAssertEqual(facts.keys, .required)
        XCTAssertNil(facts.libraryReadable)

        runner.responses["status --porcelain"] = CommandResult(status: 0, stdout: " M scripts/build_ipa_from_nsp.py\n", stderr: "")
        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().engine, .checkout(head: pin, relation: .current, tree: .modified))

        runner.responses["xcodebuild -version"] = CommandResult(status: 0, stdout: "Xcode 27.1\nBuild version 27A9275\n", stderr: "")
        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().xcodeVersion, "27.1")
    }

    func testAdapterDistinguishesTheThreeCheckoutStates() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let place = Place(UUID())
        let runner = SystemCommandRunner()
        let engine: any EngineAdapter = MacNXNative(place: place, checkout: folder.path, prescribed: pin, expected: "badcafe")
        let missing = try await engine.workshop(place)
        XCTAssertEqual(missing.checkout, .missing)
        try Data().write(to: folder)
        let occupied = try await engine.workshop(place)
        XCTAssertEqual(occupied.checkout, .notACheckout)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ordinary = try await engine.workshop(place)
        XCTAssertEqual(ordinary.checkout, .notACheckout)
        XCTAssertEqual(missing.versions, ordinary.versions)
        func git(_ args: [String]) throws -> String {
            let result = try runner.run(URL(fileURLWithPath: "/usr/bin/git"), ["-C", folder.path] + args,
                                        environment: nil, currentDirectory: nil)
            XCTAssertEqual(result.status, 0, result.stderr)
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try git(["init", "-q"])
        _ = try git(["-c", "commit.gpgsign=false", "-c", "user.name=Fixture",
                     "-c", "user.email=fixture@users.noreply.github.com", "commit", "--allow-empty", "-qm", "Fixture"])
        let checkout = try await engine.workshop(place)
        let head = try git(["rev-parse", "HEAD"])
        XCTAssertEqual(checkout.checkout, .checkout(head: head, relation: .unknown, tree: .clean))
        XCTAssertEqual(checkout.versions.selected.value, head)
        XCTAssertEqual(checkout.versions.expected, "badcafe")
        XCTAssertEqual(checkout.versions.reference, pin)

        let commit = ["-c", "commit.gpgsign=false", "-c", "user.name=Fixture",
                      "-c", "user.email=fixture@users.noreply.github.com", "commit", "--allow-empty", "-qm"]
        _ = try git(commit + ["Second fixture"])
        let tip = try git(["rev-parse", "HEAD"])
        func snapshot(reference: String) -> Workshop {
            MacNXNative(place: place, checkout: folder.path, prescribed: reference, expected: "badcafe").workshop()
        }
        XCTAssertEqual(snapshot(reference: head).checkout, .checkout(head: tip, relation: .divergent, tree: .clean))
        _ = try git(["checkout", "--detach", head])
        XCTAssertEqual(snapshot(reference: tip).checkout, .checkout(head: head, relation: .behind, tree: .clean))
    }

}
