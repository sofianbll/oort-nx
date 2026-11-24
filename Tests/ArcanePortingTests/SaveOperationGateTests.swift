import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class SaveOperationGateTests: XCTestCase {
    func testSharedTitleIsExclusiveAndOtherGamesRemainFree() throws {
        let gate = SaveOperationGate()
        let token = try XCTUnwrap(gate.begin(titleID: "01000000000000ab"))
        XCTAssertNil(gate.begin(titleID: "01000000000000AB"))
        XCTAssertNotNil(gate.begin(titleID: "0100000000000002"))
        gate.end(titleID: "01000000000000AB", token: UUID())
        XCTAssertTrue(gate.isBusy(titleID: "01000000000000ab"))
        gate.end(titleID: "01000000000000AB", token: token)
        XCTAssertFalse(gate.isBusy(titleID: "01000000000000ab"))
    }
    func testRecoveryBlockSurvivesLeaseAndCanBeRecoveredUnderLease() throws {
        let gate = SaveOperationGate()
        let title = "0100000000000001"
        let root = FileManager.default.temporaryDirectory
        let a = try SaveLocation.profileLocation(titleID: title, profileID: UUID(), in: root)
        let b = try SaveLocation.profileLocation(titleID: title, profileID: UUID(), in: root)
        gate.setRecoveryBlocked(true, location: a)
        XCTAssertNil(gate.begin(titleID: title, recoveryLocation: a))
        let token = try XCTUnwrap(gate.begin(titleID: title, recoveryLocation: a, recovering: true))
        XCTAssertNil(gate.begin(titleID: title, recoveryLocation: b), "Active recovery still leases the entire title")
        gate.end(titleID: title, token: token)
        XCTAssertTrue(gate.isBusy(titleID: title, recoveryLocation: a))
        XCTAssertFalse(gate.isBusy(titleID: title, recoveryLocation: b))
        gate.setRecoveryBlocked(false, location: a)
        XCTAssertNotNil(gate.begin(titleID: title, recoveryLocation: a))
    }

    func testAppUpdateWaitsForActiveIOAndExcludesNewOperations() throws {
        let gate = SaveOperationGate()
        let title = "0100000000000001"
        let operation = try XCTUnwrap(gate.begin(titleID: title))
        XCTAssertTrue(gate.hasActiveOperations)
        XCTAssertNil(gate.beginAppUpdate())
        gate.end(titleID: title, token: operation)
        let update = try XCTUnwrap(gate.beginAppUpdate())
        XCTAssertNil(gate.begin(titleID: title))
        XCTAssertNil(gate.begin(titleID: "0100000000000002", recovering: true))
        gate.endAppUpdate(token: UUID())
        XCTAssertNil(gate.begin(titleID: title))
        gate.endAppUpdate(token: update)
        XCTAssertNotNil(gate.begin(titleID: title))
    }

    func testAnInactiveRecoveryBlockDoesNotPreventAnAppUpdate() throws {
        let gate = SaveOperationGate()
        let title = "0100000000000001"
        let location = try SaveLocation.profileLocation(titleID: title, profileID: UUID(), in: FileManager.default.temporaryDirectory)
        gate.setRecoveryBlocked(true, location: location)
        XCTAssertFalse(gate.hasActiveOperations)
        let update = try XCTUnwrap(gate.beginAppUpdate())
        gate.endAppUpdate(token: update)
        XCTAssertTrue(gate.isBusy(titleID: title, recoveryLocation: location))
    }
}
