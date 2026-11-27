import Foundation
import XCTest
import OortLibrary

final class PlayerPlanTests: XCTestCase {
    func testPreparedDefaultAndEightNumberedSlotsWithoutRenumbering() throws {
        var plan = PlayerPlan()
        XCTAssertEqual(plan.mode, .pressToJoin)
        for number in 1...8 { try plan.set(.init(), at: number) }
        XCTAssertThrowsError(try plan.set(.init(), at: 0))
        XCTAssertThrowsError(try plan.set(.init(), at: 9))
        plan.remove(at: 2)
        XCTAssertEqual(plan.slots.keys.sorted(), [1, 3, 4, 5, 6, 7, 8])
        XCTAssertNil(plan.slot(2))
        XCTAssertEqual(plan.slot(8)?.profileAccess(in: []), .guest)
    }

    func testDisconnectKeepsThePlanAndOnlyStrongEvidenceRestoresAutomatically() throws {
        var plan = PlayerPlan()
        let saved = RememberedPlayerController(stableID: "hid:one", modelKey: "pad")
        try plan.set(.init(controller: saved), at: 1)
        let unknown = ConnectedPlayerController(id: "unknown", modelKey: "other")
        let wrong = ConnectedPlayerController(id: "replacement", stableID: "hid:two", modelKey: "pad")
        let old = ConnectedPlayerController(id: "old", stableID: "hid:one", modelKey: "pad")
        XCTAssertEqual(plan.resolveControllers([old]).slots[1], .connected("old"))
        let away = plan.resolveControllers([unknown, wrong], confirmed: [1: "old"])
        XCTAssertEqual(away.slots[1], .disconnected)
        XCTAssertEqual(away.unassignedControllerIDs, ["unknown", "replacement"])
        XCTAssertEqual(plan.slot(1)?.controller, saved)
        let returned = ConnectedPlayerController(id: "new", stableID: "hid:one", modelKey: "pad")
        XCTAssertEqual(plan.resolveControllers([unknown, returned]).slots[1], .connected("new"))
    }

    func testIdenticalModelsStaySeparateAndNeedAnExplicitChoice() throws {
        var plan = PlayerPlan()
        try plan.set(.init(controller: .init(modelKey: "pad")), at: 1)
        try plan.set(.init(controller: .init(modelKey: "pad")), at: 2)
        let a = ConnectedPlayerController(id: "one", modelKey: "pad")
        let b = ConnectedPlayerController(id: "two", modelKey: "pad")
        let unresolved = plan.resolveControllers([a, b])
        XCTAssertEqual(unresolved.slots, [1: .needsConfirmation(["one", "two"]), 2: .needsConfirmation(["one", "two"])])
        XCTAssertEqual(unresolved.unassignedControllerIDs, ["one", "two"])
        XCTAssertEqual(plan.resolveControllers([a]).slots[1], .needsConfirmation(["one"]))
        let chosen = plan.resolveControllers([a, b], confirmed: [1: "two"])
        XCTAssertEqual(chosen.slots, [1: .connected("two"), 2: .needsConfirmation(["one"])])
        XCTAssertEqual(chosen.unassignedControllerIDs, ["one"])
        XCTAssertEqual(plan.resolveControllers([a, b], confirmed: [1: "one", 2: "one"]), unresolved)
    }

    func testEvenStrongIdentityMustBeUniqueInTheObservationsAndThePlan() throws {
        var plan = PlayerPlan()
        try plan.set(.init(controller: .init(stableID: "duplicate")), at: 1)
        let a = ConnectedPlayerController(id: "one", stableID: "duplicate")
        let b = ConnectedPlayerController(id: "two", stableID: "duplicate")
        XCTAssertEqual(plan.resolveControllers([a, b]).slots[1], .needsConfirmation(["one", "two"]))
        try plan.set(.init(controller: .init(stableID: "duplicate")), at: 2)
        XCTAssertEqual(plan.resolveControllers([a]).slots, [1: .needsConfirmation(["one"]), 2: .needsConfirmation(["one"])])
        plan.mode = .merge
        XCTAssertEqual(plan.resolveControllers([a]).slots, [1: .needsConfirmation(["one"]), 2: .inactive])
        XCTAssertNotNil(plan.slot(2))
    }

    func testGuestMissingAndPINLockedProfileRemainDistinct() {
        var profile = LocalProfile(name: "Owner", look: .init(AppSettings()))
        let slot = PlayerSlot(profileID: profile.id)
        XCTAssertEqual(PlayerSlot().profileAccess(in: [profile]), .guest)
        XCTAssertEqual(slot.profileAccess(in: []), .missing)
        XCTAssertEqual(slot.profileAccess(in: [profile]), .ready(profile))
        XCTAssertTrue(profile.setPIN("1234"))
        XCTAssertEqual(slot.profileAccess(in: [profile]), .locked)
        XCTAssertEqual(slot.profileAccess(in: [profile], unlockedProfileIDs: [profile.id]), .ready(profile))
    }
}
