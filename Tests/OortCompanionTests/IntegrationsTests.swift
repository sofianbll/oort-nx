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

    private func entries(_ page: CatalogJSON) -> [CatalogJSON] { page["sections"].items.flatMap { $0["entries"].items } + page["entries"].items }
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
        XCTAssertEqual(page["sections"].items.map { $0["entries"].items.compactMap { $0["id"]?.stringValue } }, [["steam", "online"], ["prog"]])
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
        pages += [try ask(c, "integrations", ["at": "activity"]), try ask(try companion(), "integrations"), try ask(try companion(), "integrations", ["at": "guide"])]
        let before = try ask(c, "guide")["steam"]
        pages.append(["entries": .array([before?["looking"] ?? .null, before?["unanswered"] ?? .null])])
        var keys = Set<String>()
        for page in pages {
            for e in entries(page) {
                for field in ["title", "value", "sub"] { if let key = e[field].items.first?.stringValue { keys.insert(key) } }
                for words in e["help"].items { if let key = Optional(words).items.first?.stringValue { keys.insert(key) } }
                for words in [e["confirm"]?["title"], e["confirm"]?["text"], e["confirm"]?["label"]] { if let key = words.items.first?.stringValue { keys.insert(key) } }
            }
        }
        keys.remove("%@")
        XCTAssertGreaterThanOrEqual(keys.count, 14)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // What the page has: desktop/scripts/generate.py's output, from the Mac catalog and desktop/strings.json.
        let generated = try String(contentsOf: repository.appendingPathComponent("desktop/ui/gen/strings.js"), encoding: .utf8)
        for key in keys.sorted() {
            let quoted = String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
            XCTAssertGreaterThanOrEqual(generated.components(separatedBy: quoted + ":").count - 1, 2, "en and fr: \(key)")
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
