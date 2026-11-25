import Foundation
import XCTest
@preconcurrency import NXLibraryCore
@testable import OortCompanion

final class ManifestTests: XCTestCase {
    func testTheSDKShapesRead() throws {
        // Shapes of the SDK's examples (MIT), shortened, with a key newer than the schema.
        let m = try Manifest(Data(#"""
        {"format":1,"repo":"a/b","inputs":[{"id":"disc1","label":"Disc 1","role":"disc","formats":[{"type":"file","extensions":["ISO"]}],"check":{"ids":["SLUS-1"]}},
        {"id":"dlc1","label":"DLC","role":"dlc","optional":true,"formats":[{"type":"file"}]}],
        "prepare":{"program":["p.exe"],"args":["--d={input:disc1}"],"timeout":10800,"options":[{"id":"l","label":"L","args":["-a"],"license":{"name":"N","url":"https://x"},"default":true}]},
        "start":{"program":["bin/g.exe","g"],"args":["--iso","{input:disc1}"]},
        "config":[{"format":"toml","file":[{"path":"{install}/a.toml","if":"{install}/portable.txt"},{"path":"{documents}/a.toml"}],"ensure":{"a":"\"b\""}}],
        "settings":[{"id":"s","label":"S","in":"args","choices":[{"label":"x","args":[]},{"label":"y","args":["--y"]}]}],"exit_codes":{"1":"ok"}}
        """#.utf8))
        XCTAssertEqual(m.inputs.map(\.id), ["disc1", "dlc1"])
        XCTAssertEqual(m.inputs[0].formats[0].extensions, ["iso"])
        XCTAssertTrue(m.inputs[0].unchecked)
        XCTAssertEqual(m.configs[0].id, "main")
        XCTAssertEqual(m.settings[0].within, "args")
        XCTAssertEqual(m.prepare?.options.first?.startsOn, false, "only the player accepts a licence")
        XCTAssertTrue(m.unsupported.isEmpty)
    }

    func testTheOldGameFieldReadsAsInputs() throws {
        let m = try Manifest(Data(#"{"format":1,"game":{"kind":"iso_or_folder","label":"L","check":{"file":"a"},"update":{"into":"u","label":"U","optional":true}}}"#.utf8))
        XCTAssertEqual(m.inputs.map(\.id), ["game", "update"])
        XCTAssertEqual(m.inputs[0].formats.map(\.isFolder), [false, true])
        XCTAssertEqual(m.inputs[0].checkFile, "a")
        XCTAssertTrue(m.unsupported.isEmpty, "an optional file that is not placed does not stop the game")
    }

    func testOtherFormatsAndBrokenFilesAreRefused() {
        func code(_ text: String) -> String? {
            do { _ = try Manifest(Data(text.utf8)); return nil } catch { return (error as? Manifest.Failure)?.code }
        }
        XCTAssertEqual(code(#"{"format":2}"#), "manifest-format")
        XCTAssertEqual(code("{"), "manifest-json")
        XCTAssertEqual(code("[]"), "manifest-json")
        XCTAssertNil(code("\u{feff}{\"format\":1}"))
    }

    func testAGameOfASeriesAsksForItsOwnFilesAndTheSharedOnes() throws {
        let m = try Manifest(Data(#"{"format":1,"inputs":[{"id":"d1","label":""},{"id":"d2","label":""},{"id":"all","label":""}],"games":[{"id":"a","name":"A","inputs":["d1"]},{"id":"b","name":"B","inputs":["d2"]}]}"#.utf8))
        XCTAssertEqual(m.inputs(for: "a", picked: [:]).map(\.id), ["d1", "all"])
        XCTAssertEqual(m.inputs(for: "b", picked: [:]).map(\.id), ["d2", "all"])
    }

    func testAKeyIsAskedForOnlyWithTheFormatThatNeedsIt() throws {
        let folder = scratch("key")
        let file = folder + "/a.nsp"
        FileManager.default.createFile(atPath: file, contents: Data())
        let m = try Manifest(Data(#"{"format":1,"inputs":[{"id":"game","label":"","formats":[{"type":"folder"},{"type":"file","extensions":["nsp"],"requires":["keys"]}]},{"id":"keys","label":"","role":"key","shared":"switch.prod-keys"}]}"#.utf8))
        XCTAssertEqual(m.inputs(for: nil, picked: [:]).map(\.id), ["game"])
        XCTAssertEqual(m.inputs(for: nil, picked: ["game": folder]).map(\.id), ["game"])
        XCTAssertEqual(m.inputs(for: nil, picked: ["game": file]).map(\.id), ["game", "keys"])
    }
}

final class PlacesTests: XCTestCase {
    private func places(_ install: String = "/g") -> Places {
        var p = Places(install: install, documents: "/d", local: "/l", config: "/c", home: "/h")
        p.inputs = ["game", "dlc"]
        p.picked = ["game": "/copies/a {home}.iso"]
        return p
    }

    func testPlaceholdersFillOnceAndDropWhatWasNotPicked() throws {
        let p = places()
        XCTAssertEqual(try p.fill("--iso={input:game}"), "--iso=/copies/a {home}.iso")
        XCTAssertEqual(try p.fill("{game}"), "/copies/a {home}.iso")
        XCTAssertEqual(try p.fill("{data}/x {other} {"), "/g/recompdata/x {other} {")
        XCTAssertNil(try p.fill("--dlc={input:dlc}"))
        XCTAssertThrowsError(try p.fill("{input:nope}"))
        XCTAssertEqual(try p.fill(["a", "--dlc={input:dlc}"]), ["a"])
    }

    func testWritingStaysInTheFormatsPlaces() {
        let p = places("/games/one")
        XCTAssertTrue(p.mayWrite("/games/one/a.toml"))
        XCTAssertTrue(p.mayWrite("/d/Game/a.ini"))
        XCTAssertFalse(p.mayWrite("/games/two/a.toml"))
        XCTAssertFalse(p.mayWrite("/games/one-more/a.toml"))
        XCTAssertFalse(p.mayWrite("/games/one/../two/a.toml"))
        XCTAssertFalse(p.mayWrite("a.toml"))
        XCTAssertFalse(Places(install: "/games/one", home: "/").mayWrite("/etc/hosts"))
    }

    func testAProgramIsAFileInsideTheGame() throws {
        let folder = scratch("program"), game = folder + "/game"
        try FileManager.default.createDirectory(atPath: game + "/bin", withIntermediateDirectories: true)
        for path in [game + "/bin/run", folder + "/outside"] { FileManager.default.createFile(atPath: path, contents: Data("x".utf8)) }
        let p = places(game)
        XCTAssertNotNil(p.program(["missing", "bin/run"]))
        XCTAssertNotNil(p.program(["bin\\run"]), "a manifest may write Windows separators")
        for bad in ["bin", "missing", "../outside", "/bin/sh", "C:\\Windows\\System32\\cmd.exe", "C:run"] { XCTAssertNil(p.program([bad]), bad) }
        #if !os(Windows)
        try FileManager.default.createSymbolicLink(atPath: game + "/link", withDestinationPath: folder + "/outside")
        XCTAssertNil(p.program(["link"]), "a link out of the folder is not the game's program")
        #endif
    }

    func testSystemVariablesAreNeverSet() {
        for name in ["MYRECOMP_DATA", "SDL_VIDEODRIVER", "_x"] { XCTAssertTrue(Places.mayName(name), name) }
        for name in ["PATH", "Path", "LD_PRELOAD", "DYLD_INSERT_LIBRARIES", "RECOMPLAUNCHER_DATA", "1A", "A-B", "", "TEMP", "É"] {
            XCTAssertFalse(Places.mayName(name), name)
        }
    }
}

final class GameFileTests: XCTestCase {
    private let toml = "# mine\nscale = 1 # keep\nname = \"a # b\"\n\n[video]\nfullscreen = false\n\n[other]\nx = 1\n"

    func testTOMLKeepsCommentsOrderAndOtherKeys() throws {
        var f = GameFile(kind: .toml, text: toml)
        XCTAssertEqual(f.value("scale"), "1")
        XCTAssertEqual(f.value("name"), "\"a # b\"")
        XCTAssertEqual(f.value("video/fullscreen"), "false")
        XCTAssertNil(f.value("fullscreen"))
        try f.set("scale", "2")
        XCTAssertEqual(f.text, toml.replacingOccurrences(of: "scale = 1", with: "scale = 2"))
        try f.set("video/vsync", "true")
        XCTAssertTrue(f.text.contains("fullscreen = false\nvsync = true\n\n[other]"))
        try f.set("new/key", "3")
        XCTAssertTrue(f.text.hasSuffix("x = 1\n\n[new]\nkey = 3\n"))
        XCTAssertThrowsError(try f.set("scale", "1\nevil = 2"))
        var empty = GameFile(kind: .toml, text: "")
        try empty.set("a", "1")
        XCTAssertEqual(empty.text, "a = 1\n")
    }

    func testINIKeepsWindowsLineEnds() throws {
        var f = GameFile(kind: .ini, text: "; c\r\n[Audio]\r\nVolume=5\r\n")
        try f.set("Audio/Volume", "7")
        XCTAssertEqual(f.text, "; c\r\n[Audio]\r\nVolume=7\r\n")
        try f.set("Audio/Mute", "0")
        XCTAssertEqual(f.text, "; c\r\n[Audio]\r\nVolume=7\r\nMute=0\r\n")
    }

    func testJSONNestsAndRefusesABrokenFile() throws {
        var f = GameFile(kind: .json, text: #"{"z":1,"a":{"b":true}}"#)
        try f.set("a/b", "false")
        XCTAssertEqual(f.value("a/b"), "false")
        XCTAssertEqual(f.value("z"), "1")
        try f.set("disc", GameFile.quoted(#"C:\a "b".iso"#, .json))
        XCTAssertEqual(f.value("disc"), #""C:\\a \"b\".iso""#)
        var broken = GameFile(kind: .json, text: "{broken")
        XCTAssertThrowsError(try broken.set("a", "1"), "a file that does not read is never replaced")
        XCTAssertEqual(broken.text, "{broken")
    }

    func testValuesCompareAndNumbersPrint() {
        let f = GameFile(kind: .toml, text: "")
        XCTAssertTrue(f.same("\"xenos\"", "xenos") && f.same("True", "true") && f.same("1.0", "1"))
        XCTAssertFalse(f.same("1", "2"))
        XCTAssertEqual(GameFile.number("%.2f", 1.5), "1.50")
        XCTAssertEqual(GameFile.number("%.2f", -0.05), "-0.05")
        XCTAssertEqual(GameFile.number("%d", 2.6), "3")
        XCTAssertEqual(GameFile.number("%g", 0.15000000000000002), "0.15")
        XCTAssertEqual(GameFile.number("%.1f px", 2), "2.0 px")
    }
}

final class CompanionTests: XCTestCase {
    private var root = ""
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() { root = scratch("companion") }

    private func companion() throws -> Companion {
        try Companion(.init(data: root + "/data", resources: root, system: "linux", home: root + "/home", documents: root + "/docs",
                            local: root + "/local", config: root + "/config", languages: ["fr-FR"]), now: { [unowned self] in clock })
    }

    private func ask(_ c: Companion, _ method: String, _ params: CatalogJSON = [:]) throws -> CatalogJSON {
        let line = String(decoding: try JSONEncoder().encode(["id": 7, "method": .string(method), "params": params] as CatalogJSON), as: UTF8.self)
        let reply = try JSONDecoder().decode(CatalogJSON.self, from: Data(c.answer(line).utf8))
        XCTAssertEqual(reply["id"]?.int, 7)
        if let error = reply["error"]?.stringValue { throw Manifest.Failure(code: error) }
        return reply["result"] ?? .null
    }

    private func code(_ c: Companion, _ method: String, _ params: CatalogJSON = [:]) -> String? {
        do { _ = try ask(c, method, params); return nil } catch { return (error as? Manifest.Failure)?.code }
    }

    /// A game as a player unzips one, with a program that is only a file.
    @discardableResult
    private func install(_ name: String, _ manifest: String, programs: [String] = ["run"]) throws -> String {
        let folder = root + "/games/" + name
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: URL(fileURLWithPath: folder + "/recomplauncher.json"))
        for p in programs { FileManager.default.createFile(atPath: folder + "/" + p, contents: Data("x".utf8)) }
        return folder
    }

    private func only(_ c: Companion) throws -> CatalogJSON {
        let list = try ask(c, "library.rescan")["games"].items
        XCTAssertEqual(list.count, 1)
        return ["id": list[0]["id"] ?? .null]
    }

    private func merged(_ a: CatalogJSON, _ b: CatalogJSON) -> CatalogJSON {
        guard case .object(let x) = a, case .object(let y) = b else { return a }
        return .object(x.merging(y) { $1 })
    }

    func testEveryLineGetsOneLine() throws {
        let c = try companion()
        for line in ["nonsense", "{}", "[]", #"{"id":1,"method":"nope"}"#, "\u{0}"] {
            let reply = c.answer(line)
            XCTAssertFalse(reply.contains("\n"))
            XCTAssertNotNil(try? JSONDecoder().decode(CatalogJSON.self, from: Data(reply.utf8)))
        }
    }

    func testAGameIsFoundPlannedAndItsSettingsFileWritten() throws {
        let folder = try install("One", #"""
        {"format":1,"name":"One Recomp","repo":"a/one","inputs":[{"id":"game","label":"copy","formats":[{"type":"file","extensions":["iso"]}]},{"id":"dlc","label":"dlc","optional":true,"formats":[{"type":"file"}]}],
        "start":{"program":["run.exe","run"],"args":["--iso","{input:game}","--dlc={input:dlc}"],"env":{"ONE_DATA":"{data}","PATH":"/evil"}},
        "config":[{"format":"toml","file":[{"path":"{install}/one.toml"}],"game_path":"disc","ensure":{"vsync":"true"},"always":{"mode":"\"oort\""},"new":{"scale":"2"}}],
        "settings":[{"id":"scale","label":"Scale","choices":[{"label":"1x","set":{"scale":"1"}},{"label":"2x","set":{"scale":"2"}}],"defaults":{"scale":"1"}},
        {"id":"intro","label":"Intro","in":"args","choices":[{"label":"Play","args":[]},{"label":"Skip","args":["--no-intro"]}]},
        {"id":"sens","label":"Sens","in":"args","slider":{"min":0,"max":2,"step":0.5,"format":"%.1f","args":["--sens","{value}"]}}],
        "exit_codes":{"3":"Wrong copy."}}
        """#)
        let c = try companion()
        XCTAssertEqual(code(c, "folders.add", ["path": .string(root + "/nowhere")]), "folder-missing")
        _ = try ask(c, "folders.add", ["path": .string(root + "/games")])
        let id = try only(c)
        XCTAssertEqual(try ask(c, "game", id)["state"], "inputs")
        XCTAssertEqual(code(c, "launch.plan", id), "inputs-missing")

        let copy = root + "/my copy.iso"
        FileManager.default.createFile(atPath: copy, contents: Data())
        XCTAssertEqual(code(c, "game.input", merged(id, ["input": "game", "path": .string(folder)])), "input-kind")
        _ = try ask(c, "game.input", merged(id, ["input": "game", "path": .string(copy)]))
        XCTAssertEqual(code(c, "game.input", merged(id, ["input": "dlc", "path": .string(copy)])), "input-twice")

        let plan = try ask(c, "launch.plan", id)
        let real = system(Paths.real(copy))
        XCTAssertEqual(plan["args"].strings, ["--iso", real], "the file that was not picked is left out whole")
        XCTAssertTrue(plan["program"]?.stringValue?.hasSuffix(system("/One/run")) == true)
        XCTAssertEqual(plan["env"]?["ONE_DATA"]?.stringValue, system(folder + "/recompdata"))
        XCTAssertNil(plan["env"]?["PATH"])
        XCTAssertEqual(plan["env"]?["RECOMPLAUNCHER"], "1")
        let written = try String(contentsOfFile: folder + "/one.toml", encoding: .utf8)
        for line in ["scale = 2", "vsync = true", "mode = \"oort\"", "disc = \"\(real.replacingOccurrences(of: "\\", with: "\\\\"))\""] { XCTAssertTrue(written.contains(line), line) }

        // Changes: one in the file, two on the command line.
        var page = try ask(c, "game.setting", merged(id, ["setting": "scale", "value": 0]))
        XCTAssertEqual(page["settings"].items[0]["value"]?.int, 0)
        XCTAssertTrue(try String(contentsOfFile: folder + "/one.toml", encoding: .utf8).contains("scale = 1"))
        _ = try ask(c, "game.setting", merged(id, ["setting": "intro", "value": 1]))
        page = try ask(c, "game.setting", merged(id, ["setting": "sens", "value": .number(1.5)]))
        XCTAssertEqual(page["settings"].items[2]["text"], "1.5")
        XCTAssertEqual(code(c, "game.setting", merged(id, ["setting": "sens", "value": 9])), "value")
        XCTAssertEqual(code(c, "game.setting", merged(id, ["setting": "intro", "value": 5])), "value")
        XCTAssertEqual(try ask(c, "launch.plan", id)["args"].strings, ["--iso", real, "--no-intro", "--sens", "1.5"])

        // A file the game wrote and that does not read stops the launch, and stays as it is.
        try Data([0xff, 0xfe, 0x00]).write(to: URL(fileURLWithPath: folder + "/one.toml"))
        XCTAssertEqual(code(c, "launch.plan", id), "config-unreadable")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: folder + "/one.toml")).count, 3)
    }

    func testAConfigOutsideItsPlacesIsNeverWritten() throws {
        try install("Bad", #"{"format":1,"start":{"program":["run"]},"config":[{"format":"ini","file":[{"path":"/etc/oort.ini"}],"always":{"a":"1"}}]}"#)
        let c = try companion()
        _ = try ask(c, "folders.add", ["path": .string(root + "/games")])
        XCTAssertEqual(code(c, "launch.plan", try only(c)), "config-place")
    }

    func testTheSetupStepRunsOnceForAReleaseAndAgainForTheNext() throws {
        let folder = try install("Prep", #"""
        {"format":1,"prepare":{"program":["prep"],"args":["--out","{data}/built"],"done":["{data}/built"],"options":[{"id":"sdk","label":"SDK","args":["--sdk"],"license":{"name":"L","url":"https://x"},"required":true},{"id":"win","label":"W","args":["--win"],"os":["windows"]}]},"start":{"program":["run"]}}
        """#, programs: ["run", "prep"])
        let c = try companion()
        _ = try ask(c, "folders.add", ["path": .string(root + "/games")])
        let id = try only(c)
        XCTAssertEqual(code(c, "launch.plan", id), "prepare-first")
        XCTAssertEqual(code(c, "prepare.plan", id), "option-required", "a licence is never accepted for the player")
        _ = try ask(c, "game.option", merged(id, ["option": "sdk", "on": true]))
        let plan = try ask(c, "prepare.plan", id)
        XCTAssertEqual(plan["args"].strings.last, "--sdk")
        XCTAssertFalse(plan["args"].strings.contains("--win"), "another system's option is neither shown nor passed")
        let tmp = try XCTUnwrap(plan["env"]?["TMPDIR"]?.stringValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp))
        XCTAssertEqual(try ask(c, "prepare.line", ["line": "progress 0.4 Unpacking art"]), ["value": .number(0.4), "text": "Unpacking art"])
        XCTAssertEqual(try ask(c, "prepare.line", ["line": "progress nan x"]), .null)
        XCTAssertEqual(try ask(c, "prepare.line", ["line": "hello"]), .null)

        XCTAssertEqual(try ask(c, "prepare.end", merged(id, ["code": 2]))["done"], false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp))
        XCTAssertEqual(try ask(c, "prepare.end", merged(id, ["code": 0]))["done"], false, "what it says it leaves is not there")
        FileManager.default.createFile(atPath: folder + "/recompdata/built", contents: Data())
        XCTAssertEqual(try ask(c, "prepare.end", merged(id, ["code": 0]))["done"], true)
        XCTAssertNotNil(try ask(c, "launch.plan", id)["program"])
        try Data("a longer program".utf8).write(to: URL(fileURLWithPath: folder + "/prep"))
        XCTAssertEqual(code(c, "launch.plan", id), "prepare-first")
    }

    func testWhatIsNotDoneIsSaid() throws {
        try install("Placed", #"{"format":1,"inputs":[{"id":"game","label":"","formats":[{"type":"file"}],"into":"game"}],"start":{"program":["run"]}}"#)
        let c = try companion()
        _ = try ask(c, "folders.add", ["path": .string(root + "/games")])
        let id = try only(c)
        XCTAssertEqual(try ask(c, "game", id)["state"], "unsupported")
        XCTAssertEqual(code(c, "launch.plan", id), "unsupported-placing")
    }

    func testABrokenManifestIsShownAndSeriesSplit() throws {
        try install("Broken", "{")
        try install("Deep/v1", #"{"format":1,"repo":"a/series","start":{"program":["run"]},"games":[{"id":"a","name":"First","args":["--a"]},{"id":"b","name":"Second","args":["--b"]}]}"#)
        let c = try companion()
        _ = try ask(c, "folders.add", ["path": .string(root + "/games")])
        let games = try ask(c, "library", ["sort": "name"])["games"].items
        XCTAssertEqual(games.compactMap { $0["name"]?.stringValue }, ["Broken", "First", "Second"])
        XCTAssertEqual(games[0]["state"], "broken")
        XCTAssertEqual(try ask(c, "launch.plan", ["id": games[2]["id"] ?? .null])["args"].strings, ["--b"])
        XCTAssertEqual(code(c, "launch.plan", ["id": games[0]["id"] ?? .null]), "manifest-json")
    }

    func testAProgramWithArguments() throws {
        let program = root + "/emulator", rom = root + "/A game.bin"
        for path in [program, rom] { FileManager.default.createFile(atPath: path, contents: Data()) }
        let c = try companion()
        XCTAssertEqual(code(c, "programs.add", ["program": .string(root)]), "program-missing")
        _ = try ask(c, "programs.add", ["program": .string(program), "args": #"--fullscreen --name "two words" ''"#, "target": .string(rom)])
        XCTAssertEqual(code(c, "programs.add", ["program": .string(program), "args": #"--fullscreen --name "two words" ''"#, "target": .string(rom)]), "program-known")
        let id = try only(c)
        XCTAssertEqual(try ask(c, "game", id)["name"], "A game")
        XCTAssertEqual(try ask(c, "launch.plan", id)["args"].strings, ["--fullscreen", "--name", "two words", "", system(Paths.real(rom))])
        XCTAssertNil(try ask(c, "launch.plan", id)["env"]?["RECOMPLAUNCHER"], "an ordinary program gets nothing of the format")
    }

    func testPlayTimeIsKeptThroughACutAndPerProfile() throws {
        try install("Timed", #"{"format":1,"start":{"program":["run"]},"exit_codes":{"3":"Wrong copy.","4294967295":"ok"}}"#)
        var c = try companion()
        _ = try ask(c, "folders.add", ["path": .string(root + "/games")])
        let id = try only(c)
        var session = try ask(c, "session.start", id)
        clock += 60
        _ = try ask(c, "session.beat", ["session": session])
        clock += 30
        var end = try ask(c, "session.end", ["session": session, "code": 3])
        XCTAssertEqual(end["seconds"]?.int, 90)
        XCTAssertEqual(end["message"], "Wrong copy.")
        XCTAssertEqual(code(c, "session.end", ["session": session]), "session", "a session ends once")

        session = try ask(c, "session.start", id)
        clock += 120
        _ = try ask(c, "session.beat", ["session": session])
        clock += 500
        c = try companion()
        XCTAssertEqual(try ask(c, "game", id)["seconds"]?.int, 210, "a cut session counts to its last beat")

        session = try ask(c, "session.start", id)
        end = try ask(c, "session.end", ["session": session, "code": -1])
        XCTAssertEqual(end["crashed"], false, "4294967295 is how Windows writes -1")
        end = try ask(c, "session.end", ["session": try ask(c, "session.start", id), "code": 9])
        XCTAssertEqual(end["crashed"], true)
        end = try ask(c, "session.end", ["session": try ask(c, "session.start", id), "code": 9, "closed": true])
        XCTAssertEqual(end["crashed"], false)

        // The first profile takes what was played before; the next starts at nothing.
        let list = try ask(c, "profiles.add", ["name": "Ana"])
        XCTAssertEqual(list["list"].items.count, 2)
        XCTAssertEqual(try ask(c, "game", id)["seconds"]?.int, 210)
        _ = try ask(c, "profiles.select", ["profile": list["list"].items[1]["id"] ?? .null])
        XCTAssertEqual(try ask(c, "game", id)["seconds"]?.int, 0)
        _ = try ask(c, "game.favorite", merged(id, ["on": true]))
        XCTAssertEqual(try ask(c, "library", ["tab": "Favorites"])["games"].items.count, 1)
        _ = try ask(c, "profiles.pin", ["pin": "1234"])
        _ = try ask(c, "profiles.select", ["profile": list["list"].items[0]["id"] ?? .null])
        XCTAssertEqual(try ask(c, "library", ["tab": "Favorites"])["games"].items.count, 0)
        XCTAssertEqual(code(c, "profiles.select", ["profile": list["list"].items[1]["id"] ?? .null, "pin": "0000"]), "pin")
        XCTAssertNil(code(c, "profiles.select", ["profile": list["list"].items[1]["id"] ?? .null, "pin": "1234"]))
        XCTAssertFalse(try String(contentsOfFile: root + "/data/profiles.json", encoding: .utf8).contains("1234"))
    }

    func testSettingsAreTriedThenSaved() throws {
        var c = try companion()
        XCTAssertEqual(try ask(c, "hello")["view"]?["language"], "fr", "Automatic follows the system")
        var page = try ask(c, "settings")
        XCTAssertEqual(page["categories"].items.compactMap { $0["id"]?.stringValue },
                       ["general", "appearance", "sound", "controllers", "account", "home", "library", "integrations", "about"])
        let appearance = page["categories"].items[1]
        XCTAssertEqual(appearance["subjects"].items.first?["title"], "Advanced", "two levels")
        XCTAssertEqual(appearance["rows"].items.compactMap { $0["id"]?.stringValue }, ["colorThemeID", "interfaceZoom"])

        page = try ask(c, "settings.set", ["id": "interfaceZoom", "value": .number(1.1)])
        XCTAssertEqual(page["view"]?["zoom"]?.double, 1.1, "tried at once")
        XCTAssertEqual(page["pending"], true)
        XCTAssertEqual(page["changes"].items.first?["before"], "1")
        page = try ask(c, "settings.set", ["id": "interfaceZoom", "value": 9])
        XCTAssertEqual(page["view"]?["zoom"]?.double, 1.25)
        XCTAssertEqual(code(c, "settings.set", ["id": "interfaceZoom", "value": "big"]), "value")
        XCTAssertEqual(code(c, "settings.set", ["id": "soundPack", "value": "nope"]), "value")
        page = try ask(c, "settings.discard")
        XCTAssertEqual(page["view"]?["zoom"]?.double, 1)
        _ = try ask(c, "settings.set", ["id": "appLanguage", "value": "en"])
        _ = try ask(c, "settings.remember", ["home": "collection"])
        XCTAssertEqual(try ask(c, "settings")["pending"], true, "what is remembered leaves the draft alone")
        _ = try ask(c, "settings.save")
        c = try companion()
        XCTAssertEqual(try ask(c, "hello")["view"]?["language"], "en")
        page = try ask(c, "settings.reset", ["section": "startUp"])
        XCTAssertEqual(page["view"]?["language"], "fr")
    }

    func testAFileThatDoesNotReadIsSetAside() throws {
        _ = try ask(try companion(), "settings.remember", ["home": "collection"])
        try Data("{".utf8).write(to: URL(fileURLWithPath: root + "/data/settings.json"))
        _ = try ask(try companion(), "settings.remember", ["home": "spotlight"])
        let kept = try FileManager.default.contentsOfDirectory(atPath: root + "/data").filter { $0.contains("unreadable") }
        XCTAssertEqual(kept.count, 1)
    }

    func testFilesShowNamesOnly() throws {
        let c = try companion()
        try install("One", #"{"format":1}"#)
        FileManager.default.createFile(atPath: root + "/games/a.ISO", contents: Data())
        FileManager.default.createFile(atPath: root + "/games/.hidden", contents: Data())
        let page = try ask(c, "files", ["path": .string(root + "/games"), "extensions": ["iso"]])
        XCTAssertEqual(page["entries"].items.compactMap { $0["name"]?.stringValue }, ["a.ISO", "One"])
        XCTAssertEqual(page["games"]?.int, 1)
        XCTAssertEqual(try ask(c, "files", ["path": .string(root + "/games"), "folders": true])["entries"].items.count, 1)
        XCTAssertEqual(code(c, "files", ["path": .string(root + "/none")]), "folder-missing")
    }

    func testSoundsAreMadeHere() throws {
        let c = try companion()
        let wav = try XCTUnwrap(try ask(c, "sound", ["event": "move", "step": 3, "figure": "major"]).stringValue.flatMap { Data(base64Encoded: $0) })
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertGreaterThan(wav.count, 4_000)
        XCTAssertEqual(try ask(c, "sound", ["event": "ambience"]), .null)
        XCTAssertEqual(code(c, "sound", ["event": "move", "pack": "nope"]), "sound")
        XCTAssertEqual(try ask(c, "prompts")["nintendo"]?["menu"], "+")
    }
}

/// A path as a program on this system is given one.
private func system(_ path: String) -> String {
    #if os(Windows)
    return path.replacingOccurrences(of: "/", with: "\\")
    #else
    return path
    #endif
}

private func scratch(_ name: String) -> String {
    let path = FileManager.default.temporaryDirectory.path + "/oort-companion-\(name)-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return Paths.real(path)
}
