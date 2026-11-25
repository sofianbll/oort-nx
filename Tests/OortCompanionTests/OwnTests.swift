import Foundation
import XCTest
@preconcurrency import NXLibraryCore
@testable import OortCompanion

private func scratch(_ name: String) -> String {
    let path = FileManager.default.temporaryDirectory.path + "/oort-own-\(name)-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return Paths.real(path)
}

private func put(_ path: String, _ data: Data) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: path))
}

private func put(_ path: String, _ text: String) { put(path, Data(text.utf8)) }

private func le(_ n: Int, _ bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8(truncatingIfNeeded: n >> (8 * $0)) } }

/// A Windows program with only resources: a header, one section, the kinds of resources asked for.
private enum FakeProgram {
    static func make(resources: [(kind: Int, id: Int, data: [UInt8])], plus: Bool = true) -> Data {
        let base = 0x1000, at = 0x400
        // Kinds, then items, then languages, then the places of the data, then the data.
        let kinds = Array(Set(resources.map(\.kind))).sorted()
        var body: [UInt8] = []
        let kindsSize = 16 + kinds.count * 8
        let itemsSize = kinds.reduce(0) { sum, k in sum + 16 + resources.filter { $0.kind == k }.count * 8 }
        let languages = resources.count * 24, places = resources.count * 16
        let ordered = kinds.flatMap { k in resources.filter { $0.kind == k } }
        body += le(0, 12) + le(0, 2) + le(kinds.count, 2)
        var itemAt = kindsSize
        for k in kinds { body += le(k, 4) + le(itemAt | 0x8000_0000, 4); itemAt += 16 + resources.filter { $0.kind == k }.count * 8 }
        var n = 0
        for k in kinds {
            let items = resources.filter { $0.kind == k }
            body += le(0, 12) + le(0, 2) + le(items.count, 2)
            for item in items { body += le(item.id, 4) + le((kindsSize + itemsSize + n * 24) | 0x8000_0000, 4); n += 1 }
        }
        for i in ordered.indices { body += le(0, 12) + le(0, 2) + le(1, 2) + le(1033, 4) + le(kindsSize + itemsSize + languages + i * 16, 4) }
        var dataAt = kindsSize + itemsSize + languages + places
        for one in ordered { body += le(base + dataAt, 4) + le(one.data.count, 4) + le(0, 8); dataAt += (one.data.count + 3) & ~3 }
        for one in ordered { body += one.data + [UInt8](repeating: 0, count: (4 - one.data.count % 4) % 4) }
        let tables = plus ? 112 : 96, optional = tables + 16 * 8
        var out: [UInt8] = [0x4d, 0x5a] + [UInt8](repeating: 0, count: 0x3a) + le(0x40, 4)
        out += le(0x4550, 4) + le(0x8664, 2) + le(1, 2) + le(0, 12) + le(optional, 2) + le(0, 2)
        out += le(plus ? 0x20b : 0x10b, 2) + [UInt8](repeating: 0, count: tables - 6) + le(16, 4) + [UInt8](repeating: 0, count: 16) + le(base, 4) + le(body.count, 4) + [UInt8](repeating: 0, count: 13 * 8)
        out += Array(".rsrc\0\0\0".utf8) + le(body.count, 4) + le(base, 4) + le(body.count, 4) + le(at, 4) + [UInt8](repeating: 0, count: 16)
        out += [UInt8](repeating: 0, count: at - out.count) + body
        return Data(out)
    }

    static func version(_ words: [(String, String)]) -> [UInt8] {
        func pad(_ b: [UInt8]) -> [UInt8] { b + [UInt8](repeating: 0, count: (4 - b.count % 4) % 4) }
        func utf16(_ s: String) -> [UInt8] { (Array(s.utf16) + [0]).flatMap { le(Int($0), 2) } }
        func block(_ key: String, value: [UInt8], count: Int, children: [[UInt8]] = []) -> [UInt8] {
            var b = pad(le(0, 2) + le(count, 2) + le(1, 2) + utf16(key)) + value
            for child in children { b = pad(b) + child }
            return le(b.count, 2) + b.dropFirst(2)
        }
        let strings = words.map { block($0.0, value: utf16($0.1), count: $0.1.utf16.count + 1) }
        let table = block("040904b0", value: [], count: 0, children: strings)
        return block("VS_VERSION_INFO", value: [UInt8](repeating: 0, count: 52), count: 52, children: [block("StringFileInfo", value: [], count: 0, children: [table])])
    }

    static func group(_ icons: [(side: Int, id: Int)]) -> [UInt8] {
        var out: [UInt8] = le(0, 2)
        out += le(1, 2)
        out += le(icons.count, 2)
        for icon in icons {
            for (n, size) in [(icon.side & 255, 1), (icon.side & 255, 1), (0, 2), (1, 2), (32, 2), (0, 4), (icon.id, 2)] { out += le(n, size) }
        }
        return out
    }

    /// A red square, its left half hidden by the mask.
    static func bitmap(_ side: Int, bits: Int) -> [UInt8] {
        var b = le(40, 4) + le(side, 4) + le(side * 2, 4) + le(1, 2) + le(bits, 2) + le(0, 24)
        for _ in 0..<side {
            var row = [UInt8]()
            for _ in 0..<side { row += bits == 32 ? [0, 0, 200, 0] : [0, 0, 200] }
            b += row + [UInt8](repeating: 0, count: (4 - row.count % 4) % 4)
        }
        for _ in 0..<side { b += [0xf0, 0, 0, 0].prefix((side + 31) / 32 * 4) }
        return b
    }
}

final class ProgramFileTests: XCTestCase {
    func testAProgramGivesItsNameItsMakerAndItsLargestIcon() throws {
        let folder = scratch("exe"), large = Picture.png(256, 256, [UInt8](repeating: 120, count: 256 * 256 * 4))
        for plus in [true, false] {
            put(folder + "/a.exe", FakeProgram.make(resources: [
                (3, 1, FakeProgram.bitmap(32, bits: 32)), (3, 2, [UInt8](large)), (14, 1, FakeProgram.group([(32, 1), (256, 2)])),
                (16, 1, FakeProgram.version([("CompanyName", "Invented Works"), ("FileDescription", "Lantern Bay game"), ("ProductName", "Lantern Bay"), ("ProductVersion", "1.2.3")])),
            ], plus: plus))
            let file = try XCTUnwrap(ProgramFile(folder + "/a.exe"))
            XCTAssertEqual(file.name, "Lantern Bay")
            XCTAssertEqual(file.about, "Lantern Bay game")
            XCTAssertEqual(file.publisher, "Invented Works")
            XCTAssertEqual(file.version, "1.2.3")
            XCTAssertEqual(file.icon, large, "a PNG is kept as it is")
        }
    }

    func testAnOldBitmapIconBecomesAPictureWithItsShape() throws {
        for bits in [32, 24] {
            let png = try XCTUnwrap(Picture.png(icon: Bytes(FakeProgram.bitmap(8, bits: bits))))
            let kind = try XCTUnwrap(Picture.kind(Bytes([UInt8](png))))
            XCTAssertEqual([kind.width, kind.height], [8, 8])
            // Stored, not compressed: the first row is where the format puts it.
            let row = [UInt8](png)[(8 + 25 + 8 + 2 + 5)...].prefix(33)
            XCTAssertEqual(Array(row.prefix(5)), [0, 200, 0, 0, 0], "hidden by the mask")
            XCTAssertEqual(Array(row.suffix(4)), [200, 0, 0, 255])
        }
    }

    func testNamesAToolLeftInPlaceAreNotShown() throws {
        let folder = scratch("generic")
        put(folder + "/b.exe", FakeProgram.make(resources: [(16, 1, FakeProgram.version([("CompanyName", "TODO: <Company name>"), ("FileDescription", "Harbour"), ("ProductName", "BootstrapPackagedGame")]))]))
        let file = try XCTUnwrap(ProgramFile(folder + "/b.exe"))
        XCTAssertEqual(file.name, "Harbour")
        XCTAssertNil(file.publisher)
        XCTAssertNil(file.icon)
        put(folder + "/c.exe", FakeProgram.make(resources: [(16, 1, FakeProgram.version([("ProductVersion", "0.0.0.0"), ("FileVersion", "2.1")]))]))
        XCTAssertEqual(ProgramFile(folder + "/c.exe")?.version, "2.1")
    }

    func testADamagedProgramNeverStopsTheApp() {
        let folder = scratch("damaged")
        let whole = [UInt8](FakeProgram.make(resources: [(3, 1, FakeProgram.bitmap(32, bits: 32)), (14, 1, FakeProgram.group([(32, 1)])), (16, 1, FakeProgram.version([("ProductName", "Any")]))]))
        var seed: UInt64 = 7
        func random(_ n: Int) -> Int { seed = seed &* 6_364_136_223_846_793_005 &+ 1; return Int(seed >> 33) % n }
        for i in 0..<400 {
            var bytes = whole
            if i % 2 == 0 { bytes = Array(bytes.prefix(random(bytes.count))) }
            else { for _ in 0..<(1 + random(12)) { bytes[random(min(bytes.count, i % 3 == 0 ? 1200 : bytes.count))] = UInt8(random(256)) } }
            put(folder + "/x.exe", Data(bytes))
            _ = ProgramFile(folder + "/x.exe")
        }
        put(folder + "/empty", Data())
        XCTAssertNil(ProgramFile(folder + "/empty"))
        XCTAssertNil(ProgramFile(folder))
        XCTAssertNil(ProgramFile(folder + "/missing"))
    }

    func testOnlyPicturesPassForPictures() {
        let folder = scratch("pictures")
        put(folder + "/a.png", Picture.png(64, 32, [UInt8](repeating: 9, count: 64 * 32 * 4)))
        put(folder + "/b.png", "<svg onload=x>")
        put(folder + "/c.jpg", Data([0xff, 0xd8, 0xff, 0xe0, 0, 4, 1, 1, 0xff, 0xc0, 0, 11, 8, 0, 90, 0, 60, 3] + [UInt8](repeating: 0, count: 20)))
        put(folder + "/d.png", Picture.png(2, 2, [UInt8](repeating: 9, count: 16)))
        XCTAssertEqual(Picture.check(folder + "/a.png")?.width, 64)
        XCTAssertNil(Picture.check(folder + "/b.png"))
        XCTAssertEqual(Picture.check(folder + "/c.jpg")?.height, 90)
        XCTAssertNil(Picture.check(folder + "/d.png"), "too small to be one")
    }

    func testAMenuEntryGivesItsProgram() throws {
        let folder = scratch("menu")
        put(folder + "/bin/lantern", "x")
        put(folder + "/a.desktop", "[Desktop Entry]\nType=Application\nName=Lantern\nName[fr]=Lanterne\nExec=lantern --wide \"two words\" %U\nIcon=lantern\n[Desktop Action x]\nExec=other\n")
        #if !os(Windows)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder + "/bin/lantern")
        let entry = try XCTUnwrap(DesktopEntry(folder + "/a.desktop", languages: ["fr-FR"], folders: [folder + "/bin"]))
        XCTAssertEqual(entry.name, "Lanterne")
        XCTAssertEqual(entry.program, folder + "/bin/lantern")
        XCTAssertEqual(entry.args, ["--wide", "two words"])
        put(folder + "/icons/hicolor/128x128/apps/lantern.png", Picture.png(128, 128, [UInt8](repeating: 9, count: 128 * 128 * 4)))
        XCTAssertEqual(DesktopEntry.icon("lantern", data: [folder]), folder + "/icons/hicolor/128x128/apps/lantern.png")
        XCTAssertNil(DesktopEntry.icon("../lantern", data: [folder]))
        #endif
    }
}

final class SteamShelfTests: XCTestCase {
    private let root = scratch("steam"), other = scratch("second")

    private func manifest(_ library: String, _ id: Int, _ name: String, flags: Int? = 4, folder: String? = nil, made: Bool = true) {
        let dir = folder ?? name
        put(library + "/steamapps/appmanifest_\(id).acf", "\"AppState\"\n{\n\t\"appid\"\t\t\"\(id)\"\n\t\"name\"\t\t\"\(name)\"\n\(flags.map { "\t\"StateFlags\"\t\t\"\($0)\"\n" } ?? "")\t\"installdir\"\t\t\"\(dir)\"\n}\n")
        if made { try? FileManager.default.createDirectory(atPath: library + "/steamapps/common/" + dir, withIntermediateDirectories: true) }
    }

    private func index() {
        let native = { (p: String) in Paths.native(p).replacingOccurrences(of: "\\", with: "\\\\") }
        put(root + "/steamapps/libraryfolders.vdf", "\"libraryfolders\"\n{\n\"0\"\n{\n\"path\"\t\"\(native(root))\"\n\"apps\"\n{\n\"10\" \"1\"\n}\n}\n\"1\"\n{\n\"path\"\t\"\(native(other))\"\n}\n\"2\"\n{\n\"path\"\t\"\(native(root))/gone\"\n}\n}\n")
    }

    func testGamesOfEveryDriveAreFoundAndTheRestLeftOut() {
        index()
        manifest(root, 900_010, "Lantern Bay")
        manifest(other, 900_020, "Coast Runner", flags: 6)
        manifest(root, 900_030, "Half There", flags: 1026)
        manifest(root, 900_040, "Gone Away", made: false)
        manifest(root, 900_050, "Lantern Bay Soundtrack")
        manifest(root, 228_980, "Steamworks Common Redistributables")
        manifest(root, 900_060, "Proton 9.0")
        manifest(root, 900_070, "Escape", folder: "../../outside")
        manifest(other, 900_010, "Lantern Bay")
        put(root + "/steamapps/appmanifest_900080.acf", "\"AppState\" { \"appid\" \"900081\" \"name\" \"Other\" \"installdir\" \"Other\" }")
        put(root + "/steamapps/appmanifest_900090.acf", "\"AppState\" { broken")
        let found = SteamShelf(root: root).scan()
        XCTAssertEqual(found.games.map(\.name).sorted(), ["Coast Runner", "Lantern Bay"])
        XCTAssertEqual(found.libraries.count, 2)
        XCTAssertEqual(found.downloading, 1)
        XCTAssertEqual(found.others, 3)
        XCTAssertTrue(Paths.isInside(found.games.first { $0.appID == 900_010 }!.folder, root), "the first library keeps it")
    }

    func testSteamsOwnWordDecidesWhenItCanBeRead() throws {
        index()
        manifest(root, 900_110, "Quiet Engine SDK")
        manifest(root, 900_120, "Amber Station")
        manifest(root, 900_130, "Amber Notes")
        func app(_ id: Int, _ body: [UInt8], _ head: Int) -> [UInt8] { le(id, 4) + le(body.count + head, 4) + [UInt8](repeating: 0, count: head) + body }
        let keys = ["appinfo", "common", "type", "config", "launch", "0", "executable", "oslist"]
        func tree(_ type: String, _ exe: String, named: Bool) -> [UInt8] {
            func key(_ i: Int) -> [UInt8] { named ? le(i, 4) : Array(keys[i].utf8) + [0] }
            func text(_ i: Int, _ v: String) -> [UInt8] { [1] + key(i) + Array(v.utf8) + [0] }
            func object(_ i: Int, _ b: [UInt8]) -> [UInt8] { [0] + key(i) + b + [8] }
            return object(0, object(1, text(2, type)) + object(3, object(4, object(5, text(6, exe) + object(3, text(7, "windows")))))) + [8]
        }
        for (magic, head) in [(0x0756_4428, 60), (0x0756_4429, 60), (0x0756_4427, 40)] {
            let named = magic == 0x0756_4429
            let apps = app(900_110, tree("Game", "bin\\quiet.exe", named: named), head) + app(900_120, tree("game", "amber.exe", named: named), head)
                + app(900_130, tree("Music", "x.exe", named: named), head) + app(900_140, tree("Tool", "y.exe", named: named), head) + le(0, 4)
            var file = le(magic, 4) + le(1, 4)
            if named { file += le(16 + apps.count, 8) + apps + le(keys.count, 4) + keys.flatMap { Array($0.utf8) + [0] } } else { file += apps + le(0, 8) }
            put(root + "/appcache/appinfo.vdf", Data(file))
            let found = SteamShelf(root: root).scan()
            XCTAssertEqual(found.games.map(\.name).sorted(), ["Amber Station", "Quiet Engine SDK"], "\(magic)")
            XCTAssertEqual(found.games.first { $0.appID == 900_110 }?.programs, ["bin/quiet.exe"])
            // Cut anywhere, it gives less and never stops the app.
            for n in stride(from: 0, to: file.count, by: 7) {
                put(root + "/appcache/appinfo.vdf", Data(file.prefix(n)))
                _ = SteamShelf(root: root).scan()
            }
        }
    }

    func testSteamsPicturesOnThisComputerAreUsed() {
        index()
        for id in [900_210, 900_220, 900_230] { manifest(root, id, "Game \(id)") }
        let picture = Picture.png(60, 90, [UInt8](repeating: 50, count: 60 * 90 * 4)), cache = root + "/appcache/librarycache"
        put(cache + "/900210_library_600x900.jpg", picture)
        put(cache + "/900220/library_hero.jpg", picture)
        put(cache + "/900220/0a1b2c/library_600x900.jpg", picture)
        put(cache + "/900230/logo.png", "not a picture")
        let games = SteamShelf(root: root).scan().games
        XCTAssertEqual(games.first { $0.appID == 900_210 }?.art.keys.sorted(), ["cover"])
        XCTAssertEqual(games.first { $0.appID == 900_220 }?.art.keys.sorted(), ["cover", "hero"])
        XCTAssertEqual(games.first { $0.appID == 900_230 }?.art, [:])
    }

    func testAnUpdateAndARemovalAreSeen() throws {
        index()
        manifest(root, 900_310, "Drift")
        let game = try XCTUnwrap(SteamShelf(root: root).scan().games.first { $0.appID == 900_310 })
        XCTAssertEqual(SteamShelf.isUpdating(game), false)
        manifest(root, 900_310, "Drift", flags: 1026)
        XCTAssertEqual(SteamShelf.isUpdating(game), true)
        try FileManager.default.removeItem(atPath: game.manifest)
        XCTAssertNil(SteamShelf.isUpdating(game))
    }

    func testSteamIsFoundWhereTheSystemSaysOrNowhere() {
        index()
        XCTAssertEqual(SteamShelf.root(named: Paths.native(root), home: "/nowhere", system: "windows"), root)
        XCTAssertNil(SteamShelf.root(named: "C:\\Nowhere", home: "/nowhere", system: "windows"))
        XCTAssertNil(SteamShelf.root(named: nil, home: "/nowhere", system: "linux"))
    }
}

final class OnlineTests: XCTestCase {
    /// Walks a lookup with what invented services answer; an address not listed answers nothing.
    @discardableResult
    private func walk(_ lookup: inout OnlineLookup, _ answers: [String: String], pictures: Set<String> = []) throws -> [String] {
        var asked: [String] = []
        for _ in 0..<20 {
            guard case .get(let url, let save, _) = lookup.step() else { return asked }
            XCTAssertTrue(OnlineLookup.allowed(url), url)
            asked.append(url)
            if save != nil { try lookup.answer(status: 200, text: nil, saved: pictures.contains { url.hasSuffix($0) }); continue }
            let text = answers.first { url.contains($0.key) }?.value
            try lookup.answer(status: text == nil ? 0 : 200, text: text, saved: false)
        }
        XCTFail("no end")
        return asked
    }

    private let search = #"{"total":2,"items":[{"type":"app","name":"Lantern Bay Soundtrack","id":900401},{"type":"app","name":"Lantern Bay™","id":900400}]}"#
    private let details = #"{"900400":{"success":true,"data":{"steam_appid":900400,"name":"Lantern Bay™","short_description":"A quiet <b>bay</b> &amp; its lamps.","genres":[{"description":"Adventure"}],"developers":["Invented Works"],"publishers":["Invented House"],"release_date":{"date":"21 nov. 2023"}}}}"#

    func testAGameIsFoundByItsNameInTheStore() throws {
        var lookup = OnlineLookup(name: "Lantern Bay (USA) [v2]", steam: nil, folder: "/d", language: .french)
        let asked = try walk(&lookup, ["storesearch": search, "appdetails": details], pictures: ["library_600x900.jpg", "library_hero_2x.jpg"])
        XCTAssertEqual(lookup.record.found, true)
        XCTAssertEqual(lookup.record.title, "Lantern Bay™")
        XCTAssertEqual(lookup.record.about, "A quiet bay & its lamps.")
        XCTAssertEqual(lookup.record.year, "2023")
        XCTAssertEqual(lookup.record.genres, ["Adventure"])
        XCTAssertEqual(lookup.record.publishers, ["Invented House"])
        XCTAssertEqual(asked.filter { $0.contains("library_600x900") }.count, 2, "the second size when the first is missing")
        XCTAssertTrue(asked[0].contains("term=Lantern%20Bay&"), "only the name goes out: \(asked[0])")
        XCTAssertTrue(asked[1].hasSuffix("appids=900400&l=french"))
        XCTAssertTrue(asked.allSatisfy { !$0.contains("USA") && !$0.contains("/d") })
    }

    func testAnotherNameIsNotTakenForIt() throws {
        var lookup = OnlineLookup(name: "Lantern", steam: nil, folder: "/d", language: .english)
        try walk(&lookup, ["storesearch": search, "wbsearchentities": #"{"search":[{"id":"Q1","label":"Lantern Festival"}]}"#])
        XCTAssertFalse(lookup.record.found)
    }

    func testWikipediaTellsWhatTheStoreDoesNotHave() throws {
        let entity = #"{"entities":{"Q900":{"labels":{"en":{"value":"Tidal Works"}},"claims":{"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q7889"}}}}],"P136":[{"mainsnak":{"datavalue":{"value":{"id":"Q901"}}}}],"P577":[{"mainsnak":{"datavalue":{"value":{"time":"+1998-11-21T00:00:00Z"}}}}]},"sitelinks":{"frwiki":{"title":"Tidal Works"}}}}}"#
        var lookup = OnlineLookup(name: "Tidal Works", steam: nil, folder: "/d", language: .french)
        try walk(&lookup, ["storesearch": #"{"items":[]}"#, "wbsearchentities": #"{"search":[{"id":"Q900","label":"Tidal Works"}]}"#, "ids=Q900": entity,
                           "fr.wikipedia.org": #"{"query":{"pages":[{"extract":"Tidal Works est un jeu inventé pour ces essais, rien de plus.","fullurl":"https://fr.wikipedia.org/wiki/Tidal_Works"}]}}"#,
                           "ids=Q901": #"{"entities":{"Q901":{"labels":{"fr":{"value":"jeu d’aventure"}}}}}"#])
        XCTAssertEqual(lookup.record.source, "Wikipedia")
        XCTAssertEqual(lookup.record.year, "1998")
        XCTAssertEqual(lookup.record.genres, ["Jeu d’aventure"])
        XCTAssertEqual(lookup.record.page, "https://fr.wikipedia.org/wiki/Tidal_Works")
        XCTAssertEqual(lookup.record.item, "Q900")
    }

    func testNoAnswerASlowDownAndNonsenseKeepNothing() throws {
        for (status, text, code) in [(0, nil, "online"), (500, "x", "online"), (429, "", "online-slow")] as [(Int, String?, String)] {
            var lookup = OnlineLookup(name: "Drift", steam: nil, folder: "/d", language: .english)
            XCTAssertThrowsError(try lookup.answer(status: status, text: text, saved: false)) { XCTAssertEqual(($0 as? Manifest.Failure)?.code, code) }
        }
        var lookup = OnlineLookup(name: "Drift", steam: nil, folder: "/d", language: .english)
        try walk(&lookup, ["storesearch": "<html>", "wbsearchentities": "{]"])
        XCTAssertFalse(lookup.record.found)
        // Its own page without any sense: the game is not found, not half found.
        var steam = OnlineLookup(name: "Drift", steam: 900_500, folder: "/d", language: .english)
        try walk(&steam, ["appdetails": #"{"900500":{"success":false}}"#, "haswbstatement": #"{"query":{"search":[]}}"#, "wbsearchentities": #"{"search":[]}"#])
        XCTAssertFalse(steam.record.found)
    }

    func testOnlyTheListedPlacesAreRead() {
        XCTAssertTrue(OnlineLookup.allowed("https://store.steampowered.com/api/storesearch/?term=a"))
        XCTAssertTrue(OnlineLookup.allowed("https://shared.akamai.steamstatic.com/x.jpg"))
        for bad in ["http://store.steampowered.com/", "https://store.steampowered.com.example.org/", "https://a@store.steampowered.com/", "https://127.0.0.1/", "file:///etc/passwd",
                    "https://store.steampowered.com:8443/", "https://evilwikipedia.org/w/api.php"] { XCTAssertFalse(OnlineLookup.allowed(bad), bad) }
    }
}

final class OwnCompanionTests: XCTestCase {
    private let root = scratch("app")
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func companion(_ system: String = "windows") throws -> Companion {
        try Companion(.init(data: root + "/data", resources: root, system: system, home: root + "/home", languages: ["fr-FR"]), now: { [unowned self] in clock })
    }

    private func ask(_ c: Companion, _ method: String, _ params: CatalogJSON = [:]) throws -> CatalogJSON {
        let line = String(decoding: try JSONEncoder().encode(["id": 7, "method": .string(method), "params": params] as CatalogJSON), as: UTF8.self)
        let reply = try JSONDecoder().decode(CatalogJSON.self, from: Data(c.answer(line).utf8))
        if let error = reply["error"]?.stringValue { throw Manifest.Failure(code: error) }
        return reply["result"] ?? .null
    }

    private func code(_ c: Companion, _ method: String, _ params: CatalogJSON = [:]) -> String? {
        do { _ = try ask(c, method, params); return nil } catch { return (error as? Manifest.Failure)?.code }
    }

    private func exe(_ path: String, _ name: String) {
        put(path, FakeProgram.make(resources: [(3, 1, FakeProgram.bitmap(32, bits: 32)), (14, 1, FakeProgram.group([(32, 1)])),
                                               (16, 1, FakeProgram.version([("ProductName", name), ("CompanyName", "Invented Works"), ("ProductVersion", "2.0")]))]))
    }

    func testAProgramOfAnEarlierVersionGetsItsIconAndNameAtTheFirstStart() throws {
        exe(root + "/games/lb_win64.exe", "Lantern Bay")
        // As alpha.1 wrote it: its file's name, nothing else.
        put(root + "/data/library.json", #"{"folders":[],"programs":[{"key":"k1","name":"lb_win64","program":"\#(root)/games/lb_win64.exe","args":[]},{"key":"k2","name":"My own name","program":"\#(root)/games/lb_win64.exe","args":["--two"]}],"shared":{},"games":{}}"#)
        let c = try companion()
        XCTAssertEqual(try ask(c, "guide")["open"], false, "a library from before is not sent to the first steps")
        XCTAssertEqual(try ask(c, "guide")["news"], true)
        let games = try ask(c, "library")["games"].items
        XCTAssertEqual(Set(games.compactMap { $0["name"]?.stringValue }), ["Lantern Bay", "My own name"])
        XCTAssertTrue(games.allSatisfy { $0["mark"] == true && $0["icon"] == false && $0["look"] == false })
        let one = try ask(c, "game", ["id": games[0]["id"]!])
        XCTAssertEqual(one["publisher"], "Invented Works")
        XCTAssertEqual(one["version"], "2.0")
        let mark = try XCTUnwrap(try ask(c, "game.art", ["id": games[0]["id"]!, "kind": "mark"]).stringValue)
        XCTAssertEqual(Picture.check(mark)?.width, 32)
        _ = try ask(c, "guide", ["seen": true])
        XCTAssertEqual(try ask(try companion(), "guide")["news"], false)
    }

    func testAChosenPictureIsCopiedAndPutAway() throws {
        exe(root + "/a.exe", "Drift")
        put(root + "/mine.png", Picture.png(60, 90, [UInt8](repeating: 1, count: 60 * 90 * 4)))
        put(root + "/fake.png", "no")
        let c = try companion()
        let id = try XCTUnwrap(try ask(c, "programs.add", ["program": .string(root + "/a.exe")])["added"])
        XCTAssertEqual(code(c, "game.picture", ["id": id, "kind": "cover", "path": .string(root + "/fake.png")]), "picture")
        XCTAssertEqual(code(c, "game.picture", ["id": id, "kind": "../x", "path": .string(root + "/mine.png")]), "value")
        let before = try ask(c, "game", ["id": id])["art"]
        let set = try ask(c, "game.picture", ["id": id, "kind": "cover", "path": .string(root + "/mine.png")])
        XCTAssertEqual(set["cover"], true)
        XCTAssertEqual(set["pictures"], ["cover"])
        XCTAssertNotEqual(set["art"], before)
        XCTAssertEqual(try ask(c, "game.picture", ["id": id, "kind": "cover"])["cover"], false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/mine.png"), "the player's own file stays")
        _ = try ask(c, "programs.rename", ["key": try XCTUnwrap(try ask(c, "game", ["id": id])["program"]?["key"]), "name": "Autre nom"])
        XCTAssertEqual(try ask(c, "game", ["id": id])["name"], "Autre nom")
    }

    func testTheFirstStepsStopAndGoOnWhereTheyWere() throws {
        var c = try companion()
        XCTAssertEqual(try ask(c, "hello")["guide"]?["open"], true)
        _ = try ask(c, "guide", ["page": "games"])
        c = try companion()
        XCTAssertEqual(try ask(c, "guide")["page"], "games")
        XCTAssertEqual(try ask(c, "guide")["open"], true)
        _ = try ask(c, "guide", ["done": true])
        c = try companion()
        XCTAssertEqual(try ask(c, "guide")["open"], false)
        XCTAssertEqual(try ask(c, "guide")["page"], "welcome", "seen again from Settings, they start over")
        XCTAssertEqual(try ask(c, "guide")["news"], false)
    }

    func testSteamIsReadOnlyWhenThePlayerSaysSo() throws {
        let steam = root + "/Steam"
        put(steam + "/steamapps/appmanifest_900600.acf", #""AppState" { "appid" "900600" "name" "Fathom" "StateFlags" "4" "installdir" "Fathom" }"#)
        exe(steam + "/steamapps/common/Fathom/fathom.exe", "Fathom")
        exe(steam + "/steamapps/common/Fathom/UnityCrashHandler64.exe", "Crash")
        let c = try companion()
        XCTAssertEqual(try ask(c, "steam")["found"], false)
        _ = try ask(c, "steam.where", ["path": .string(Paths.native(steam))])
        let seen = try ask(c, "steam")
        XCTAssertEqual([seen["found"], seen["on"], seen["chosen"], seen["games"]], [true, false, false, 1])
        XCTAssertEqual(try ask(c, "library.rescan")["total"], 0)
        _ = try ask(c, "steam.set", ["on": true])
        let game = try XCTUnwrap(try ask(c, "library")["games"].items.first)
        XCTAssertEqual([game["name"], game["kind"], game["state"], game["mark"]], ["Fathom", "steam", "ready", true])
        let plan = try ask(c, "launch.plan", ["id": game["id"]!])
        XCTAssertEqual(plan["steam"], 900_600)
        XCTAssertNil(plan["program"])
        XCTAssertEqual(try ask(c, "steam.updating", ["id": game["id"]!]), false)
        // Kept for the next start, then put away without touching Steam.
        let again = try companion()
        _ = try ask(again, "steam.where", ["path": .string(Paths.native(steam))])
        XCTAssertEqual(try ask(again, "library.rescan")["total"], 1)
        _ = try ask(again, "steam.set", ["on": false])
        XCTAssertEqual(try ask(again, "library")["total"], 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: steam + "/steamapps/appmanifest_900600.acf"))
    }

    func testASessionCanEndBeforeItsEndIsKnown() throws {
        exe(root + "/a.exe", "Drift")
        let c = try companion()
        let id = try XCTUnwrap(try ask(c, "programs.add", ["program": .string(root + "/a.exe")])["added"])
        let session = try ask(c, "session.start", ["id": id])
        clock += 70
        let end = try ask(c, "session.end", ["session": session, "code": 0, "idle": 10])
        XCTAssertEqual(end["seconds"], 60)
    }

    func testNothingIsLookedForUntilThePlayerSaysYes() throws {
        exe(root + "/a.exe", "Lantern Bay")
        let c = try companion()
        let id = try XCTUnwrap(try ask(c, "programs.add", ["program": .string(root + "/a.exe")])["added"])
        XCTAssertEqual(code(c, "online.start", ["id": id]), "online-off")
        XCTAssertEqual(code(c, "online.answer", ["status": 200, "text": "{}"]), "online-off")
        XCTAssertEqual(try ask(c, "library")["games"].items[0]["look"], false)
        _ = try ask(c, "online.set", ["on": true])
        XCTAssertEqual(try ask(c, "library")["games"].items[0]["look"], true)
        // No network: nothing is written, and it is asked again later.
        _ = try ask(c, "online.start", ["id": id])
        XCTAssertEqual(code(c, "online.answer", ["status": 0]), "online")
        XCTAssertEqual(try ask(c, "library")["games"].items[0]["look"], true)
        // Found: the texts are kept, the file's place is given for the picture.
        XCTAssertTrue(try XCTUnwrap(try ask(c, "online.start", ["id": id])["get"]?.stringValue).contains("storesearch"))
        XCTAssertTrue(try XCTUnwrap(try ask(c, "online.answer", ["status": 200, "text": #"{"items":[{"type":"app","name":"Lantern Bay","id":900700}]}"#])["get"]?.stringValue).contains("appdetails"))
        var step = try ask(c, "online.answer", ["status": 200, "text": #"{"900700":{"success":true,"data":{"steam_appid":900700,"name":"Lantern Bay","short_description":"About it.","release_date":{"date":"2 May, 2020"}}}}"#])
        let save = try XCTUnwrap(step["save"]?.stringValue)
        XCTAssertTrue(save.hasSuffix("cover"))
        put(save + ".part", Picture.png(80, 120, [UInt8](repeating: 1, count: 80 * 120 * 4)))
        step = try ask(c, "online.answer", ["status": 200])
        // A page where a picture should be, then nothing: both are left out.
        let hero = try XCTUnwrap(step["save"]?.stringValue)
        XCTAssertTrue(hero.hasSuffix("hero"))
        put(hero + ".part", "<html>not found</html>")
        step = try ask(c, "online.answer", ["status": 200])
        XCTAssertFalse(FileManager.default.fileExists(atPath: hero + ".part"))
        while step["done"] != true { step = try ask(c, "online.answer", ["status": 404]) }
        XCTAssertEqual(step["found"], true)
        let game = try ask(c, "game", ["id": id])
        XCTAssertEqual([game["about"], game["year"], game["cover"], game["look"]], ["About it.", "2020", true, false])
        XCTAssertEqual(try ask(c, "game.link", ["url": "https://store.steampowered.com/app/900700"]), true)
        XCTAssertEqual(try ask(c, "game.link", ["url": "https://store.steampowered.com/app/1"]), false)
        // Kept without a network; a month later it is asked again.
        XCTAssertEqual(try ask(try companion(), "game", ["id": id])["about"], "About it.")
        clock += 31 * 86_400
        XCTAssertEqual(try ask(c, "game", ["id": id])["look"], true)
        XCTAssertEqual(try ask(c, "game", ["id": id])["about"], "About it.", "what is known stays meanwhile")
        // Not this one: nothing is shown, nothing is asked again.
        let none = try ask(c, "online.none", ["id": id])
        XCTAssertEqual([none["about"], none["cover"], none["look"], none["chosen"]], [.null, false, false, true])
        // Another result, chosen by hand.
        _ = try ask(c, "online.start", ["id": id, "want": "choices", "text": "Coast"])
        XCTAssertTrue(try XCTUnwrap(try ask(c, "online.answer", ["status": 200, "text": #"{"items":[{"type":"app","name":"Coast Runner","id":900701}]}"#])["get"]?.stringValue).contains("wbsearchentities"))
        let choices = try ask(c, "online.answer", ["status": 200, "text": #"{"search":[]}"#])
        XCTAssertEqual(choices["choices"].items.map { $0["title"] }, ["Coast Runner"])
        XCTAssertTrue(try XCTUnwrap(try ask(c, "online.start", ["id": id, "appID": 900_701])["get"]?.stringValue).contains("appids=900701"))
        // Turned off while a question is open, then everything put away.
        _ = try ask(c, "online.set", ["on": false])
        XCTAssertEqual(code(c, "online.answer", ["status": 200, "text": "{}"]), "online-off")
        _ = try ask(c, "online.clear")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/data/online"))
        XCTAssertNil(try ask(c, "game", ["id": id])["about"]?.stringValue)
    }
}
