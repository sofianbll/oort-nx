import XCTest
@testable import OortCore

final class CreditsTests: XCTestCase {
    private func credits() throws -> Credits {
        try Credits(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("design/credits.json"))
    }

    func testEverySystemThanksTheProjectsItIsBuiltOn() throws {
        let credits = try credits()
        let people = Dictionary(uniqueKeysWithValues: credits.credits.map { ($0.name, $0) })
        for (name, author, page) in [("Arcane", "Bium23", "Bium23/NxLibrary"), ("Selene", "Matthew Silva", "mattxslv/Selene"),
                                     ("Playnite", "Josef Nemec", "JosefNemec/Playnite"), ("nxnative", "seedds", "seedds/nxnative"),
                                     ("NX2Apple", "LNPANDY", "LNPANDY/NX2Apple")] {
            let credit = try XCTUnwrap(people[name])
            XCTAssertEqual(credit.author, author)
            XCTAssertEqual(credit.license, "MIT")
            XCTAssertEqual(credit.url.absoluteString, "https://github.com/" + page)
            XCTAssertTrue(credits.base.contains(credit.id))
        }
        for system in [Credits.System.mac, .windows, .linux, .ios, .android] {
            XCTAssertTrue(Set(credits.groups(for: system).flatMap(\.credits).map(\.id)).isDisjoint(with: credits.base), system.rawValue)
            XCTAssertFalse(credits.statements(for: system, in: "fr").isEmpty)
        }
    }

    func testGroupsShowEachCreditOnceAndOnlyWhereItBelongs() throws {
        let credits = try credits()
        let base = try XCTUnwrap(credits.baseGroup)
        XCTAssertEqual(base.credits.map(\.name), ["Arcane", "Selene", "Playnite", "nxnative", "NX2Apple", "Nextendo"])
        XCTAssertEqual(base.id, "base")
        let mac = base.credits + credits.groups(for: .mac).flatMap(\.credits)
        XCTAssertEqual(mac.count, Set(mac.map(\.id)).count)
        XCTAssertEqual(mac.count, credits.credits.filter { $0.systems.contains("mac") }.count)
        XCTAssertFalse(mac.contains { $0.id == "padwake" })
        XCTAssertFalse(credits.groups(for: .mac).contains { $0.id == "base" })
    }

    func testAGridIsFullOrItIsAList() throws {
        let credits = try credits()
        XCTAssertEqual([3, 2, 1].map { credits.columns(for: credits.base.count, fitting: $0) }, [3, 2, 1])
        for count in 1...30 {
            for fitting in 0...4 {
                let columns = credits.columns(for: count, fitting: fitting)
                XCTAssertTrue((1...credits.columns).contains(columns))
                XCTAssertEqual(count % columns, 0, "\(count) cards in \(columns) columns")
            }
        }
        XCTAssertEqual(credits.columns(for: 21, fitting: 2), 1)
        XCTAssertEqual(credits.columns(for: 16, fitting: 3), 1)
    }

    func testWordsFollowTheLanguageThenEnglish() throws {
        let credits = try credits()
        let words = ["en": "Thanks", "fr": "Merci", "pt-BR": "Obrigado"]
        XCTAssertEqual(Credits.words(words, in: "fr"), "Merci")
        XCTAssertEqual(Credits.words(words, in: "pt-PT"), "Obrigado")
        XCTAssertEqual(Credits.words(words, in: "ja"), "Thanks")
        let gametdb = try XCTUnwrap(credits.credits.first { $0.id == "gametdb" })
        XCTAssertEqual(credits.byline(of: gametdb, in: "fr"), "Service en ligne")
        let soho = try XCTUnwrap(credits.credits.first { $0.id == "soho" })
        XCTAssertTrue(credits.byline(of: soho, in: "fr").hasSuffix(" · Licence non indiquée"))
        XCTAssertEqual(credits.role(of: gametdb, in: "en"), "Switch box covers")
    }

    func testAPictureIsShownOnlyWhereItMayBe() throws {
        let credits = try credits()
        XCTAssertEqual(credits.credits.first { $0.id == "selene" }?.picture, "selene")
        XCTAssertNil(try XCTUnwrap(credits.credits.first { $0.id == "nxnative" }).picture)
    }
}
