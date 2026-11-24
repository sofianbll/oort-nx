import Foundation
import XCTest
import NXLibraryCore

final class PlayerLaunchEnvironmentTests: XCTestCase {
    private let all = PlayerLaunchCapabilities(pressToJoin: true, merge: true, nickname: true)

    func testOnlyPreparedSupportedModeAddsAFlagAndNeverConflictsWithEnvFile() {
        func values(_ plan: PlayerPlan?, _ capabilities: PlayerLaunchCapabilities,
                    keys: Set<String> = []) -> [String: String] {
            PlayerLaunchEnvironment.values(plan: plan, capabilities: capabilities, networkMode: .automatic, envFileKeys: keys)
        }

        XCTAssertEqual(values(nil, all), [:])
        XCTAssertEqual(values(.init(mode: .inOrder), all), [:])
        XCTAssertEqual(values(.init(), all), ["DM_PAD_PRESS_TO_JOIN": "1"])
        XCTAssertEqual(values(.init(mode: .merge), all), ["DM_PAD_MERGE": "1"])
        XCTAssertEqual(values(.init(mode: .merge), .init(pressToJoin: true)), [:])
        XCTAssertEqual(values(.init(), .init(merge: true)), [:])
        for key in ["DM_PAD_PRESS_TO_JOIN", "DM_PAD_MERGE"] {
            XCTAssertEqual(values(.init(), all, keys: [key]), [:])
            XCTAssertEqual(values(.init(mode: .merge), all, keys: [key]), [:])
        }
    }

    func testOnlyPlayerOneCanSupplyANicknameAndOnlyOfflineOrLocal() throws {
        let look = LocalProfile.Look(AppSettings())
        let first = LocalProfile(name: "Local name", look: look)
        let second = LocalProfile(name: "Not player one", look: look)
        var plan = PlayerPlan(mode: .merge)
        try plan.set(.init(profileID: second.id), at: 2)
        func values(_ mode: PlayerLaunchNetworkMode, keys: Set<String> = [],
                    capabilities: PlayerLaunchCapabilities? = nil) -> [String: String] {
            PlayerLaunchEnvironment.values(plan: plan, capabilities: capabilities ?? all, networkMode: mode,
                                           envFileKeys: keys, profiles: [first, second])
        }

        XCTAssertNil(values(.offline)["DM_NICK"])
        try plan.set(.init(), at: 1)
        XCTAssertNil(values(.offline)["DM_NICK"])
        try plan.set(.init(profileID: first.id), at: 1)
        XCTAssertEqual(values(.offline), ["DM_PAD_MERGE": "1", "DM_NICK": "Local name"])
        XCTAssertEqual(values(.local)["DM_NICK"], "Local name")
        XCTAssertNil(values(.nextendo)["DM_NICK"])
        XCTAssertNil(values(.automatic)["DM_NICK"])
        XCTAssertNil(values(.local, keys: ["DM_NICK"])["DM_NICK"])
        XCTAssertNil(values(.offline, capabilities: .init(merge: true))["DM_NICK"])
    }

    func testLockedNameNeedsPINClearedAccessAndTruncatesByWholeUTF8Character() throws {
        let family = "👨‍👩‍👧‍👦" // 25 bytes as one Character.
        var profile = LocalProfile(name: "1234567" + family + "!", look: .init(AppSettings()))
        XCTAssertTrue(profile.setPIN("1234"))
        var plan = PlayerPlan(mode: .inOrder)
        try plan.set(.init(profileID: profile.id), at: 1)
        func nick(unlocked: Set<UUID> = []) -> String? {
            PlayerLaunchEnvironment.values(plan: plan, capabilities: all, networkMode: .offline, envFileKeys: [],
                                           profiles: [profile], unlockedProfileIDs: unlocked)["DM_NICK"]
        }
        XCTAssertNil(nick())
        XCTAssertEqual(nick(unlocked: [profile.id]), "1234567" + family)
        profile.name = "12345678" + family + "!"
        XCTAssertEqual(nick(unlocked: [profile.id]), "12345678")
        profile.name = "name\u{0}suffix"
        XCTAssertNil(nick(unlocked: [profile.id]))
    }
}
