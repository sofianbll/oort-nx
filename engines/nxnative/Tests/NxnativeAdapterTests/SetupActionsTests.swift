import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class SetupActionsTests: XCTestCase {
    private let pin = "af616f54652fa7f50a2e223ceed1d08a9bc83848"

    func testEngineAction() {
        XCTAssertEqual(SetupActions.engineAction(for: .missing, pinned: pin), .clone)
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: "ee369f0", relation: .behind, tree: .clean), pinned: pin), .checkout)
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: "ee369f0", relation: .behind, tree: .modified), pinned: pin), .none)
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: "ee369f0", relation: .behind, tree: .unreadable), pinned: pin), .none)
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: pin, relation: .current, tree: .clean), pinned: pin), .none)
        XCTAssertEqual(SetupActions.engineAction(for: .notACheckout, pinned: pin), .none)
    }

    func testCloneArgv() {
        let folder = URL(fileURLWithPath: "/Users/a b/nx native")
        XCTAssertEqual(SetupActions.gitCommands(for: .clone, folder: folder, pinned: pin), [
            ["clone", "--progress", SetupActions.engineRemote, "/Users/a b/nx native"],
            ["-C", "/Users/a b/nx native", "checkout", "--detach", pin],
        ])
        XCTAssertEqual(SetupActions.engineRemote, "https://github.com/seedds/nxnative")
    }

    func testCheckoutArgv() {
        let folder = URL(fileURLWithPath: "/Users/me/nxnative")
        XCTAssertEqual(SetupActions.gitCommands(for: .checkout, folder: folder, pinned: pin), [
            ["-C", "/Users/me/nxnative", "fetch", "--progress", "origin"],
            ["-C", "/Users/me/nxnative", "checkout", "--detach", pin],
        ])
        XCTAssertEqual(SetupActions.gitCommands(for: .none, folder: folder, pinned: pin), [])
    }

    func testReleasePlistSelectsBothEngineValuesOrNeither() throws {
        let repo = "https://github.com/sofianbll/nxnative"
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "NXLibraryEngineRepository": repo, "NXLibraryEngineCommit": pin,
        ], format: .xml, options: 0)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let engine = try XCTUnwrap(SetupActions.engineOverride(in: plist))
        XCTAssertEqual(engine.remote, repo)
        XCTAssertEqual(engine.commit, pin)
        XCTAssertNil(SetupActions.engineOverride(in: [:]))
        XCTAssertNil(SetupActions.engineOverride(in: ["NXLibraryEngineCommit": pin]))
        XCTAssertNil(SetupActions.engineOverride(in: ["NXLibraryEngineRepository": repo, "NXLibraryEngineCommit": "af616f5"]))
        XCTAssertNil(SetupActions.engineOverride(in: ["NXLibraryEngineRepository": "\(repo)?bad", "NXLibraryEngineCommit": pin]))
    }

    func testPersonalEngineClonesAndUpdatesFromForkWithoutChangingOrigin() {
        let repo = "https://github.com/sofianbll/nxnative"
        let folder = URL(fileURLWithPath: "/tmp/nx native")
        let checkout = ["-C", folder.path, "checkout", "--detach", pin]
        let clone = SetupActions.engineAction(for: .missing, pinned: pin)
        let update = SetupActions.engineAction(for: .checkout(head: "ee369f0", relation: .behind, tree: .clean), pinned: pin)
        XCTAssertEqual(SetupActions.gitCommands(for: clone, folder: folder, pinned: pin, remote: repo),
                       [["clone", "--progress", repo, folder.path], checkout])
        XCTAssertEqual(SetupActions.gitCommands(for: update, folder: folder, pinned: pin, remote: repo),
                       [["-C", folder.path, "fetch", "--progress", repo, pin], checkout])
    }
}
