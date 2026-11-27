import Foundation
import XCTest
@preconcurrency import NXLibraryCore
@testable import OortCompanion

/// The rows about integrations through the core's own line protocol (desktop/PROTOCOL.md): what each row shows and what
/// its request does, decided by the core in Settings, the first steps, Add game and the activity center; the page only
/// draws them and sends back the row it was shown.
final class IntegrationsTests: XCTestCase {
    private let root = scratchFolder("integrations")
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func companion() throws -> Companion {
        try Companion(.init(data: root + "/data", system: "linux", home: root + "/home", languages: ["fr-FR"]), now: { [unowned self] in clock })
    }

    private func ask(_ c: Companion, _ method: String, _ params: CatalogJSON = [:]) throws -> CatalogJSON {
        let line = String(decoding: try JSONEncoder().encode(["id": 9, "method": .string(method), "params": params] as CatalogJSON), as: UTF8.self)
        let reply = try JSONDecoder().decode(CatalogJSON.self, from: Data(c.answer(line).utf8))
        XCTAssertEqual(reply["id"]?.int, 9)
        if let error = reply["error"]?.stringValue { throw Manifest.Failure(code: error) }
        return reply["result"] ?? .null
    }

    private func code(_ c: Companion, _ method: String, _ params: CatalogJSON) -> String? {
        do { _ = try ask(c, method, params); return nil } catch { return (error as? Manifest.Failure)?.code }
    }

    private func summaries(_ page: CatalogJSON) -> [CatalogJSON] { page["sections"].items.flatMap { $0["entries"].items } }
    private func entries(_ page: CatalogJSON) -> [CatalogJSON] {
        summaries(page).flatMap { summary in
            summary["steps"].items.flatMap { $0["items"].items.compactMap { $0["row"] } }
        } + page["entries"].items
    }
    private func entry(_ page: CatalogJSON, _ id: String) -> CatalogJSON? { entries(page).first { $0["id"]?.stringValue == id } }
    private func act(_ c: Companion, _ page: CatalogJSON, _ id: String, at place: String? = nil) throws -> CatalogJSON {
        var params: [String: CatalogJSON] = ["id": .string(id), "token": entry(page, id)?["token"] ?? .null]
        params["at"] = place.map(CatalogJSON.string)
        return try ask(c, "integrations.act", .object(params))
    }

    /// An invented Steam: installed games, and others still downloading.
    private func steam(games: [String], downloading: [String] = []) -> String {
        let folder = root + "/Steam"
        for (index, (name, flags)) in (games.map { ($0, 4) } + downloading.map { ($0, 1026) }).enumerated() {
            write(folder + "/steamapps/appmanifest_99000\(index).acf", #""AppState" { "appid" "99000\#(index)" "name" "\#(name)" "StateFlags" "\#(flags)" "installdir" "\#(name)" }"#)
            try? FileManager.default.createDirectory(atPath: folder + "/steamapps/common/" + name, withIntermediateDirectories: true)
        }
        return folder
    }

    private func found(_ count: Int) {
        for index in 0..<count {
            write(root + "/data/online/\(UUID().uuidString.lowercased())/info.json",
                  #"{"found":true,"query":"game \#(index)","language":"fr","fetchedAt":"2027-01-01T00:00:00Z"}"#)
        }
    }

    /// PC_STEAM: off and on are two different rows, and A asks for the other state, at once.
    func testSteamOffAndOnAreTwoRowsAndTheSwitchAsksForTheOther() throws {
        let c = try companion()
        _ = try ask(c, "steam.where", ["path": .string(Paths.native(steam(games: ["Glass Orchard", "Quiet Harbour"])))])
        let off = try ask(c, "integrations")
        XCTAssertEqual(entry(off, "steam")?["checked"], false)
        XCTAssertEqual(entry(off, "steam")?["value"], ["%lld games", 2])
        XCTAssertEqual(try ask(c, "library.rescan")["total"], 0, "off until the player says so")
        let on = try act(c, off, "steam")
        XCTAssertEqual(on["rescan"], true)
        XCTAssertEqual(entry(on, "steam")?["checked"], true)
        XCTAssertNotEqual(entry(on, "steam"), entry(off, "steam"), "the two states are never drawn the same")
        XCTAssertEqual(try ask(c, "steam")["on"], true)
        XCTAssertEqual(try ask(c, "library")["total"], 2)
        let offAgain = try act(c, on, "steam")
        XCTAssertEqual(entry(offAgain, "steam")?["checked"], false)
        XCTAssertEqual(try ask(c, "steam")["on"], false)
        XCTAssertEqual(try ask(c, "library")["total"], 0)
        // Without Steam on this computer the row says so, and still switches the choice.
        let none = try ask(try companion(), "integrations")
        XCTAssertEqual(entry(none, "steam")?["value"], ["Not found"])
        XCTAssertEqual(entry(none, "steam")?["help"], [["Steam was not found on this computer. It is looked for again each time."]])
    }

    /// PC_ONLINE: the switch goes both ways; Delete is offered only once something was found, and asks first.
    func testOnlineSwitchesBothWaysAndDeleteIsAskedOnlyWhenSomethingWasFound() throws {
        var c = try companion()
        let off = try ask(c, "integrations")
        XCTAssertEqual(entry(off, "online")?["checked"], false)
        XCTAssertEqual(entry(off, "online")?["value"], ["Off"])
        XCTAssertNil(entry(off, "clear"))
        let on = try act(c, off, "online")
        XCTAssertEqual(entry(on, "online")?["checked"], true)
        XCTAssertEqual(entry(on, "online")?["value"], ["%lld games known", 0])
        XCTAssertNil(entry(on, "clear"), "nothing to delete yet")
        found(2)
        c = try companion()
        let known = try ask(c, "integrations")
        let clear = try XCTUnwrap(entry(known, "clear"))
        XCTAssertEqual(clear["value"], ["%lld games", 2])
        XCTAssertEqual(clear["confirm"], ["title": ["Delete what was found online?"],
                                          "text": ["Covers and descriptions found online leave this computer. Your own pictures stay."],
                                          "label": ["Delete"]])
        XCTAssertNil(clear["checked"])
        let cleared = try act(c, known, "clear")
        XCTAssertNil(entry(cleared, "clear"))
        XCTAssertEqual(entry(cleared, "online")?["value"], ["%lld games known", 0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/data/online"))
        let offAgain = try act(c, cleared, "online")
        XCTAssertEqual(entry(offAgain, "online")?["checked"], false)
        XCTAssertEqual(try ask(c, "online")["on"], false)
    }

    /// VERIFY_WRONG_CHOICE and two requests on one row: a row is done once, as it was shown, or not at all.
    func testARowChangedSinceItWasShownOrAlreadyDoneIsRefusedAndNothingIsWritten() throws {
        let c = try companion()
        let shown = try ask(c, "integrations")
        _ = try ask(c, "steam.set", ["on": true])  // changed elsewhere after the page was drawn
        XCTAssertEqual(code(c, "integrations.act", ["id": "steam", "token": entry(shown, "steam")?["token"] ?? .null]), "stale")
        XCTAssertEqual(try ask(c, "steam")["on"], true, "the refused request wrote nothing")
        let now = try ask(c, "integrations")
        _ = try act(c, now, "steam")
        XCTAssertEqual(code(c, "integrations.act", ["id": "steam", "token": entry(now, "steam")?["token"] ?? .null]), "stale", "done once")
        XCTAssertEqual(try ask(c, "steam")["on"], false, "one change for one look")
        // Delete, confirmed after what it was about changed: refused.
        found(1)
        let again = try companion(), asked = try ask(again, "integrations")
        _ = try ask(again, "online.clear")
        XCTAssertEqual(code(again, "integrations.act", ["id": "clear", "token": entry(asked, "clear")?["token"] ?? .null]), "entry-missing",
                       "the row it was about is gone")
        // Information online, turned on elsewhere while the page showed it off: refused, still on.
        let off = try ask(again, "integrations")
        _ = try ask(again, "online.set", ["on": true])
        XCTAssertEqual(code(again, "integrations.act", ["id": "online", "token": entry(off, "online")?["token"] ?? .null]), "stale")
        XCTAssertEqual(try ask(again, "online")["on"], true)
    }

    /// The numbers a row shows change while the page is open (Steam read again while off, games found online): A on
    /// it still does what it asked.
    func testANumberThatChangedSinceTheRowWasShownDoesNotRefuseIt() throws {
        let c = try companion()
        _ = try ask(c, "steam.where", ["path": .string(Paths.native(steam(games: ["Drift"])))])
        let shown = try ask(c, "integrations")
        XCTAssertEqual(entry(shown, "steam")?["value"], ["%lld games", 1])
        _ = steam(games: ["Drift", "Ember"])
        XCTAssertEqual(entry(try ask(c, "integrations"), "steam")?["value"], ["%lld games", 2], "read again: one more game")
        let on = try act(c, shown, "steam")
        XCTAssertEqual(entry(on, "steam")?["checked"], true, "what was asked is done")
        XCTAssertEqual(try ask(c, "library")["total"], 2)
    }

    /// A page to open is not a request, a row the core never showed does not exist, nor does a place it does not know.
    func testOpeningIsNotARequestAndUnknownRowsAreRefused() throws {
        let c = try companion()
        let page = try ask(c, "integrations")
        XCTAssertEqual(page["sections"].items.map { $0["id"] }, ["sources", "engines", "services"])
        XCTAssertEqual(page["sections"].items.map { $0["entries"].items.compactMap { $0["id"]?.stringValue } },
                       [["steam", "prog"], [], ["online"]])
        XCTAssertEqual(summaries(page).map { $0["action"] }, [["Open"], ["Open"], ["Open"]])
        XCTAssertTrue(summaries(page).allSatisfy { $0["token"] == nil && $0["checked"] == nil })
        XCTAssertEqual(summaries(page).map { $0["steps"].items.compactMap { $0["id"]?.stringValue } },
                       Array(repeating: ["link", "verify", "next"], count: 3), "the template's three steps, always")
        XCTAssertEqual(summaries(page).map { $0["steps"].items.first?["items"].items.first?["say"] },
                       [["Turn on Steam to add the games it installed."], ["Add a program to begin."],
                        ["Turn it on to look for covers and game information."]], "Link says how to link")
        XCTAssertEqual(page["sections"].items.map { $0["upcoming"] },
                       [["Coming later: %@", "Epic Games · GOG · Minecraft · CrossOver"], ["Coming later: %@", "Ryujinx-Nextendo"], .null],
                       "what is announced, by role: no section is empty")
        // A switch on the row asks what the Link step's switch asks, with its token; the row's own action stays Open.
        XCTAssertEqual(summaries(page).map { $0["switch"]?["id"] }, ["steam", nil, "online"])
        XCTAssertEqual(summaries(page).map { $0["toggle"] }, [["Turn on"], nil, ["Turn on"]])
        for summary in summaries(page) where summary["switch"] != nil {
            XCTAssertEqual(summary["switch"], summary["steps"].items.first?["items"].items.compactMap { $0["row"] }.first)
        }
        let programs = try XCTUnwrap(entry(page, "prog"))
        XCTAssertEqual(programs["open"], "programs")
        XCTAssertNil(programs["token"])
        XCTAssertEqual(code(c, "integrations.act", ["id": "prog", "token": "x"]), "not-a-request")
        XCTAssertEqual(code(c, "integrations.act", ["id": "not-a-real-destination", "token": "x"]), "entry-missing")
        XCTAssertEqual(code(c, "integrations.act", ["id": "steam"]), "stale")
        XCTAssertEqual(code(c, "integrations", ["at": "elsewhere"]), "place-missing")
        XCTAssertEqual(code(c, "integrations", ["at": 3]), "place-missing")
        XCTAssertEqual(code(c, "integrations.keep", [:]), "on-missing")
        // The first steps keep their choice until they go on: their row is not done at once, and carries no token.
        let guide = try XCTUnwrap(entry(try ask(c, "integrations", ["at": "guide"]), "steam"))
        XCTAssertNil(guide["token"])
        XCTAssertEqual(code(c, "integrations.act", ["at": "guide", "id": "steam", "token": "0.0"]), "not-a-request")
        XCTAssertEqual(try ask(c, "steam")["chosen"], false, "nothing written")
    }

    /// The first steps: Steam offered on while never chosen, the choice kept only as shown and only if it changes
    /// what is in force; without Steam, a row that says so and does nothing.
    func testTheFirstStepsOfferSteamAndKeepTheShownChoiceOnlyIfItChanges() throws {
        let none = try companion()
        let missing = try XCTUnwrap(entry(try ask(none, "integrations", ["at": "guide"]), "steam"))
        XCTAssertEqual(missing["value"], ["Not found"])
        XCTAssertEqual(missing["sub"], ["Steam was not found on this computer. It is looked for again each time."])
        XCTAssertNil(missing["checked"])
        XCTAssertNil(missing["token"], "nothing to ask")
        XCTAssertEqual(try ask(none, "integrations.keep", ["on": true])["rescan"], false, "no Steam, nothing kept")
        XCTAssertEqual(try ask(none, "steam")["chosen"], false)

        let c = try companion()
        _ = try ask(c, "steam.where", ["path": .string(Paths.native(steam(games: ["Drift", "Ember"])))])
        let offered = try XCTUnwrap(entry(try ask(c, "integrations", ["at": "guide"]), "steam"))
        XCTAssertEqual(offered["checked"], true, "never chosen, it is offered on")
        XCTAssertEqual(offered["value"], ["%lld games", 2])
        XCTAssertEqual(offered["sub"], ["Reads Steam’s lists of installed games and the pictures it keeps on this computer. Changes nothing and sends nothing; Steam itself starts the games."])
        XCTAssertNil(offered["help"])
        // Switched off in the steps, then on: nothing written until they go on, and only what is shown.
        XCTAssertEqual(try ask(c, "steam")["chosen"], false)
        XCTAssertEqual(try ask(c, "integrations.keep", ["on": false])["rescan"], false, "off is already in force")
        XCTAssertEqual(try ask(c, "steam")["chosen"], false, "nothing chosen by a choice that changes nothing")
        XCTAssertEqual(try ask(c, "integrations.keep", ["on": true])["rescan"], true)
        XCTAssertEqual([try ask(c, "steam")["on"], try ask(c, "library")["total"]], [true, 2])
        XCTAssertEqual(try ask(c, "integrations.keep", ["on": true])["rescan"], false, "kept once")
        // Chosen, the steps show the choice in force.
        _ = try ask(c, "steam.set", ["on": false])
        XCTAssertEqual(entry(try ask(c, "integrations", ["at": "guide"]), "steam")?["checked"], false)
    }

    /// The steps know Steam's row before it is read: while it is looked for, and without an answer, the row of a Steam
    /// not found, as the page drew them before (`Looking…` alone; `Not found` with its sentence). Neither asks anything.
    func testTheFirstStepsKnowSteamsRowBeforeItIsRead() throws {
        let none = try companion(), c = try companion()
        _ = try ask(c, "steam.where", ["path": .string(Paths.native(steam(games: ["Drift"])))])
        for one in [none, c] {
            let before = try ask(one, "guide")["steam"]
            XCTAssertEqual(before?["looking"], ["id": "steam", "title": ["Steam"], "value": ["Looking…"], "icon": "gamepad"])
            XCTAssertEqual(before?["unanswered"], ["id": "steam", "title": ["Steam"], "value": ["Not found"], "icon": "gamepad",
                                                   "sub": ["Steam was not found on this computer. It is looked for again each time."]])
            XCTAssertEqual(try ask(one, "guide", ["page": "games"])["steam"], before, "the same rows after a turn of the steps")
        }
        XCTAssertEqual(try ask(none, "guide")["steam"]?["unanswered"], entry(try ask(none, "integrations", ["at": "guide"]), "steam"),
                       "without an answer, the row the core gives where Steam is not found")
    }

    /// Add game offers Steam while it is here and off, and A turns it on; the activity center shows what still downloads.
    func testAddGameAndTheActivityCenterShowSteamOnlyWhenItHasSomethingToSay() throws {
        let c = try companion()
        XCTAssertEqual(entries(try ask(c, "integrations", ["at": "add"])), [], "no Steam, nothing to add")
        _ = try ask(c, "steam.where", ["path": .string(Paths.native(steam(games: ["Drift", "Ember"], downloading: ["Slow Tide"])))])
        let add = try ask(c, "integrations", ["at": "add"])
        let row = try XCTUnwrap(entry(add, "steam"))
        XCTAssertEqual(row["value"], ["%lld games", 2])
        XCTAssertEqual(row["sub"], ["Adds the games Steam installed on this computer. Steam’s own files do not change."])
        XCTAssertNil(row["checked"], "a row, not a switch")
        XCTAssertEqual(entries(try ask(c, "integrations", ["at": "activity"])), [], "off, nothing to say")
        XCTAssertEqual(code(c, "integrations.act", ["id": "steam", "token": entry(try ask(c, "integrations"), "steam")?["token"] ?? .null, "at": "add"]),
                       "stale", "Settings' row is not Add game's")
        let done = try act(c, add, "steam", at: "add")
        XCTAssertEqual(done["rescan"], true)
        XCTAssertEqual(entries(done), [], "on: no longer offered")
        XCTAssertEqual([try ask(c, "steam")["on"], try ask(c, "library")["total"]], [true, 2])
        XCTAssertEqual(code(c, "integrations.act", ["id": "steam", "token": row["token"] ?? .null, "at": "add"]), "entry-missing", "done once")
        let activity = try XCTUnwrap(entry(try ask(c, "integrations", ["at": "activity"]), "steam"))
        XCTAssertEqual(activity["value"], ["%@", "1"])
        XCTAssertEqual(activity["sub"], ["%lld still downloading, left out", 1])
        XCTAssertEqual(activity["open"], "integrations")
        XCTAssertNil(activity["token"])
        let help = entry(try ask(c, "integrations"), "steam")?["help"]
        XCTAssertEqual(help.items.last, ["%lld still downloading, left out", 1], "Settings says it too, from the same count")
    }

    /// Information online in the activity center, as the page counted it before (the library's games still looked for,
    /// only while it is on), before Steam; `working` lights the control center's dot. Nothing is asked: it opens a page.
    func testTheActivityCenterSaysWhatIsStillLookedForOnline() throws {
        let c = try companion()
        _ = try ask(c, "steam.where", ["path": .string(Paths.native(steam(games: ["Drift", "Ember"], downloading: ["Slow Tide"])))])
        _ = try ask(c, "steam.set", ["on": true])
        var activity = try ask(c, "integrations", ["at": "activity"])
        XCTAssertEqual(entries(activity).map { $0["id"] }, ["steam"], "off: nothing is looked for")
        XCTAssertEqual(activity["working"], false)
        _ = try ask(c, "online.set", ["on": true])
        activity = try ask(c, "integrations", ["at": "activity"])
        XCTAssertEqual(try ask(c, "library")["games"].items.filter { $0["look"] == true }.count, 2, "what the page counted")
        XCTAssertEqual(entries(activity).map { $0["id"] }, ["online", "steam"])
        XCTAssertEqual(entry(activity, "online"), ["id": "online", "title": ["Information online"], "sub": ["Looking…"],
                                                    "value": ["%lld games", 2], "icon": "search", "open": "integrations"])
        XCTAssertEqual(activity["working"], true)
        XCTAssertEqual(code(c, "integrations.act", ["id": "online", "token": .null, "at": "activity"]), "not-a-request")
        XCTAssertEqual(try ask(c, "online")["waiting"], 2, "the same count as online’s")
        // Steam off, its games leave: a program still looked for online is all the activity center says, and Steam is not read.
        let program = root + "/emulator"
        FileManager.default.createFile(atPath: program, contents: Data())
        _ = try ask(c, "programs.add", ["program": .string(program), "name": "Lamp Keeper"])
        _ = try ask(c, "steam.set", ["on": false])
        activity = try ask(c, "integrations", ["at": "activity"])
        XCTAssertEqual(entries(activity).map { $0["id"] }, ["online"])
        XCTAssertEqual(entry(activity, "online")?["value"], ["%lld games", 1])
        XCTAssertEqual(activity["working"], true)
        _ = try ask(c, "online.set", ["on": false])
        activity = try ask(c, "integrations", ["at": "activity"])
        XCTAssertEqual(entries(activity).count, 0, "off: nothing is looked for")
        XCTAssertEqual(activity["working"], false)
    }

    /// The question asked before information online is on: once, in the core's words, with the switch's own text; the
    /// page has it from the start (hello), for the first steps and a game's details.
    func testInformationOnlineIsAskedInTheCoresWords() throws {
        let c = try companion()
        let question = try ask(c, "hello", ["languages": ["fr-FR"]])["onlineQuestion"]
        XCTAssertEqual(question, ["title": ["Look for game information online?"], "no": ["No"], "yes": ["Yes, look online"],
                                  "text": ["Oort NX looks for each game’s cover, description, year and genres on the Steam store, Wikipedia and Wikidata. It sends the game’s name, or its Steam number, and your language. Like any site, they see your internet address. No account, no key, and nothing else leaves this computer."]])
        XCTAssertEqual(question?["text"], entry(try ask(c, "integrations"), "online")?["sub"], "what the switch says")
    }

    /// Where a game comes from besides Steam, and what a game's page says of information online: decided once by the core,
    /// the same wherever the page offers them (hello, game).
    func testGameSourcesAndInformationOnlineAreTheCores() throws {
        let c = try companion(), windows = try Companion(.init(data: root + "/w", system: "windows", home: root + "/home", languages: ["en"]), now: { [unowned self] in clock })
        let sources = try ask(c, "hello")["gameSources"].items
        XCTAssertEqual(sources.map { $0["id"] }, ["program", "folder"])
        XCTAssertEqual(sources.map { $0["open"] }, ["programs", "folder"])
        XCTAssertEqual(sources.first?["sub"], ["Any game or emulator, or its menu entry. Its name and icon come with it."])
        XCTAssertEqual(try ask(windows, "hello")["gameSources"].items.first?["sub"], ["Any game or emulator you start with an .exe file. Its name and icon come with it."])
        let program = root + "/emulator"
        FileManager.default.createFile(atPath: program, contents: Data())
        let id = try XCTUnwrap(try ask(c, "programs.add", ["program": .string(program), "name": "Lamp Keeper"])["added"])
        func information() throws -> CatalogJSON { try XCTUnwrap(try ask(c, "game", ["id": id])["information"]) }
        let off = try information()
        XCTAssertEqual([off["online"]?["value"], off["online"]?["open"], off["pictures"]],
                       [["Off"], "onlineQuestion", ["Choose your own pictures, or turn on game information online."]])
        _ = try ask(c, "online.set", ["on": true])
        let uuid = try XCTUnwrap(id.stringValue.flatMap(UUID.init(uuidString:)))
        let missed: CatalogJSON = ["Nothing was found online. Look for it by another name, or choose your own pictures."]
        let found: CatalogJSON = ["Another cover, or another game if this is not the right one."]
        let states: [(OnlineRecord?, CatalogJSON, CatalogJSON)] = [
            (nil, ["Waiting"], ["Choose your own pictures, or look for this game online."]),
            (.init(), ["Not found"], missed),
            (.init(picked: true), ["None"], missed),
            (.init(about: "A game"), ["Found"], found),
            (.init(title: "An untranslated title", year: "2020"), ["%@", "An untranslated title"], found),
        ]
        for (record, value, pictures) in states {
            c.records[uuid] = record
            let shown = try information()
            XCTAssertEqual([shown["online"]?["value"], shown["online"]?["open"], shown["pictures"]],
                           [value, "match", pictures])
        }
    }

    /// Every page a row may open, in every place, is one the page knows (desktop/ui/app.js PAGES).
    func testEveryPageARowOpensIsOneThePageHas() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: repository.appendingPathComponent("desktop/ui/app.js"), encoding: .utf8)
        let pages = try XCTUnwrap(app.range(of: #"const PAGES = \{[^\n]*\};"#, options: .regularExpression).map { String(app[$0]) })
        for route in IntegrationRoute.allCases { XCTAssertTrue(pages.contains(" \(route.rawValue): "), route.rawValue) }
    }

    /// Every word a row carries is one the page has, in English and in French.
    func testEveryWordIsOneThePageHas() throws {
        let c = try companion()
        _ = try ask(c, "steam.where", ["path": .string(Paths.native(steam(games: ["Drift"], downloading: ["Slow Tide"])))])
        found(1)
        var pages = try ["settings", "guide", "add"].map { try ask(c, "integrations", ["at": .string($0)]) }
        _ = try ask(c, "steam.set", ["on": true])
        _ = try ask(c, "online.set", ["on": true])
        pages += [try ask(c, "integrations", ["at": "activity"]), try ask(try companion(), "integrations"), try ask(try companion(), "integrations", ["at": "guide"])]
        let before = try ask(c, "guide")["steam"]
        let hello = try ask(c, "hello", ["languages": ["fr-FR"]])
        pages.append(["entries": .array([before?["looking"] ?? .null, before?["unanswered"] ?? .null] + hello["gameSources"].items)])
        let id = try XCTUnwrap(try ask(c, "library")["games"].items.first?["id"])
        let information = try ask(c, "game", ["id": id])["information"]
        pages.append(["entries": .array(information?["online"].map { [$0] } ?? [])])
        var keys = Set<String>()
        if let key = information?["pictures"].items.first?.stringValue { keys.insert(key) }
        for page in pages {
            for e in entries(page) {
                for field in ["title", "value", "sub"] { if let key = e[field].items.first?.stringValue { keys.insert(key) } }
                for words in e["help"].items { if let key = Optional(words).items.first?.stringValue { keys.insert(key) } }
                for words in [e["confirm"]?["title"], e["confirm"]?["text"], e["confirm"]?["label"]] { if let key = words.items.first?.stringValue { keys.insert(key) } }
            }
        }
        let question = hello["onlineQuestion"]
        for field in ["title", "text", "no", "yes"] { if let key = question?[field].items.first?.stringValue { keys.insert(key) } }
        keys.remove("%@")
        XCTAssertGreaterThanOrEqual(keys.count, 14)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let headings = pages.flatMap { $0["sections"].items }.compactMap { $0["title"].items.first?.stringValue }
        let catalogueKeys = Set(headings + pages.flatMap(summaries).flatMap { summary -> [String] in
            ["title", "status", "capabilities", "action", "about"].compactMap { summary[$0].items.first?.stringValue } +
                summary["steps"].items.flatMap { step in
                    [step["title"].items.first?.stringValue].compactMap { $0 } +
                        step["items"].items.flatMap { item in ["label", "text", "say"].compactMap { item[$0].items.first?.stringValue } }
                } + ["toggle"].compactMap { summary[$0].items.first?.stringValue }
        } + pages.flatMap { $0["sections"].items }.compactMap { $0["upcoming"].items.first?.stringValue })
        // What the page has: desktop/scripts/generate.py's output, from the Mac catalog and desktop/strings.json.
        let generated = try String(contentsOf: repository.appendingPathComponent("desktop/ui/gen/strings.js"), encoding: .utf8)
        for key in keys.sorted() {
            let quoted = String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
            XCTAssertGreaterThanOrEqual(generated.components(separatedBy: quoted + ":").count - 1, 2, "en and fr: \(key)")
        }
        for key in catalogueKeys.sorted() {
            let quoted = String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
            XCTAssertEqual(generated.components(separatedBy: quoted + ":").count - 1, 7, "catalogue: \(key)")
        }
    }

    private func write(_ path: String, _ text: String) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }
}

private func scratchFolder(_ name: String) -> String {
    let path = FileManager.default.temporaryDirectory.path + "/oort-integrations-\(name)-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return Paths.real(path)
}
