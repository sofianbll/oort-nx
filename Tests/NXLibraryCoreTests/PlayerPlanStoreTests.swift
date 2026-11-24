import Foundation
import XCTest
import NXLibraryCore

final class PlayerPlanStoreTests: XCTestCase {
    func testMissingAndPreparedPlansAreDifferentAndRoundTrip() throws {
        try withStore { url, store in
            XCTAssertNil(try store.load())
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            var plan = PlayerPlan()
            try store.save(plan)
            XCTAssertEqual(try store.load(), plan)
            plan.mode = .inOrder
            try plan.set(.init(profileID: UUID(), controller: .init(modelKey: "synthetic")), at: 8)
            try store.save(plan)
            XCTAssertEqual(try store.load(), plan)
        }
    }

    func testUnknownFieldsSurviveEditingIncludingNestedObjectsAndLargeIntegers() throws {
        try withStore { url, store in
            let input = Data("""
                {"version":1,"mode":"merge","slots":{"1":{
                  "profileID":"8EF3099F-EA86-4EE4-B0FB-BB1FA345C3E8","futureSlot":null,
                  "controller":{"id":"C9C0B20E-01AC-4FBA-AF69-EF1FAA743228","modelKey":"pad",
                                "futureController":{"sequence":18446744073709551615}}}},
                 "futureRoot":[1,"x",false]}
                """.utf8)
            try input.write(to: url)
            var plan = try XCTUnwrap(store.load())
            var slot = try XCTUnwrap(plan.slot(1))
            slot.profileID = nil
            try plan.set(slot, at: 1)
            plan.mode = .inOrder
            try store.save(plan)
            let previous = try JSONDecoder().decode(CatalogJSON.self, from: input)
            let result = try JSONDecoder().decode(CatalogJSON.self, from: Data(contentsOf: url))
            XCTAssertEqual(result["futureRoot"], previous["futureRoot"])
            XCTAssertEqual(result["slots"]?["1"]?["futureSlot"], .null)
            XCTAssertNil(result["slots"]?["1"]?["profileID"])
            XCTAssertEqual(result["slots"]?["1"]?["controller"]?["futureController"],
                           previous["slots"]?["1"]?["controller"]?["futureController"])

            slot.controller = .init(modelKey: "replacement")
            try plan.set(slot, at: 1)
            try store.save(plan)
            let replaced = try JSONDecoder().decode(CatalogJSON.self, from: Data(contentsOf: url))
            XCTAssertNil(replaced["slots"]?["1"]?["controller"]?["futureController"])
        }
    }

    func testMalformedUnknownVersionAndInvalidSlotsNeverGetOverwritten() throws {
        try withStore { url, store in
            for text in ["{", #"{"version":2,"mode":"merge","slots":{}}"#,
                         #"{"version":1,"mode":"unknown","slots":{}}"#,
                         #"{"version":1,"mode":"inOrder","slots":{"9":{}}}"#,
                         #"{"version":1,"mode":"inOrder","slots":{"1":{"profileID":"broken"}}}"#] {
                let bytes = Data(text.utf8)
                try bytes.write(to: url)
                XCTAssertThrowsError(try store.load(), text)
                XCTAssertThrowsError(try store.save(PlayerPlan()), text)
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
        }
    }

    func testABrokenSymlinkIsNotAnAbsentPlan() throws {
        try withStore { url, store in
            let target = url.deletingLastPathComponent().appendingPathComponent("missing.json")
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(PlayerPlan()))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), target.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        }
    }

    private func withStore(_ body: (URL, PlayerPlanStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("players.json")
        try body(url, PlayerPlanStore(url: url))
    }
}
