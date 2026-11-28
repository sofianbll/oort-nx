import Foundation
import XCTest
@testable import OortLibrary

final class ProfilePageCardsTests: XCTestCase {
    func testDisabledCardKeepsItsOrderAcrossChangesAndPersistence() throws {
        var cards = ProfilePageCards()
        cards.toggle(.recent)
        cards.move(.recent, by: 1)
        XCTAssertEqual(cards.ordered.prefix(2), [.achievements, .recent])
        XCTAssertFalse(cards.visible(hasAccount: true).contains(.recent))
        XCTAssertFalse(cards.visible(hasAccount: false).contains(.friends))
        XCTAssertTrue(cards.visible(hasAccount: true).contains(.friends))
        let decoded = try JSONDecoder().decode(ProfilePageCards.self, from: JSONEncoder().encode(cards))
        XCTAssertEqual(decoded, cards)
        let original = LocalProfile(name: "Alex", look: .init(.init()))
        var profile = original
        profile.pageCards = decoded
        XCTAssertEqual(try JSONDecoder().decode(LocalProfile.self, from: JSONEncoder().encode(profile)).pageCards, decoded)
        XCTAssertNil(try JSONDecoder().decode(LocalProfile.self, from: JSONEncoder().encode(original)).pageCards)
        cards.toggle(.recent)
        XCTAssertEqual(cards.visible(hasAccount: false).prefix(2), [.achievements, .recent])
        cards.move(.achievements, by: -1)
        XCTAssertEqual(cards.ordered.first, .achievements)
    }

    func testTileColumnsAndFriendsRailBreakpoints() {
        XCTAssertEqual(ProfilePageCards.columns(width: 320), 1)
        XCTAssertEqual(ProfilePageCards.columns(width: 960), 2)
        XCTAssertEqual(ProfilePageCards.columns(width: 1150), 3)
        XCTAssertEqual(ProfilePageCards.columns(width: 1750), 4)
        XCTAssertNil(ProfilePageCards.friendsColumnWidth(available: 1049))
        XCTAssertEqual(ProfilePageCards.friendsColumnWidth(available: 1050), 350)
    }

    func testProfileActivityExcludesOtherProfilesAndExternalTotals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 10_000)
        let store = PlaySessionStore(fileURL: directory.appendingPathComponent("play-sessions.json"), now: { now })
        let game = UUID()
        let other = UUID()
        let external = UUID()
        XCTAssertTrue(store.start(gameID: game, sourceID: "native", announces: false))
        now.addTimeInterval(60)
        _ = store.end(gameID: game)
        store.profileID = UUID()
        XCTAssertTrue(store.start(gameID: other, sourceID: "steam", announces: false))
        now.addTimeInterval(120)
        _ = store.end(gameID: other)
        XCTAssertEqual(store.profileActivity(at: now)[other]?.duration, 120)
        XCTAssertNil(store.profileActivity(at: now)[game])
        store.profileID = nil
        store.setExternal([external: .init(duration: 180, lastPlayed: now, since: now)])
        XCTAssertEqual(store.totalDuration(for: external), 180)
        XCTAssertEqual(store.profileActivity(at: now)[game]?.duration, 60)
        XCTAssertNil(store.profileActivity(at: now)[other])
        XCTAssertNil(store.profileActivity(at: now)[external])
    }
}
