import XCTest
@testable import NXLibraryCore

final class LaunchExitTests: XCTestCase {
    func testTheWayOutComesAfterAFewSecondsAndNamesWhatWorks() {
        XCTAssertEqual(LaunchExit.offer(elapsed: 0, appActive: true), .none)
        XCTAssertEqual(LaunchExit.offer(elapsed: 3.9, appActive: true), .none)
        XCTAssertEqual(LaunchExit.offer(elapsed: 4, appActive: true), .button)
        XCTAssertEqual(LaunchExit.offer(elapsed: 4, appActive: false), .click, "The game has the keys and the controller")
    }

    /// Every key under the launch screen stops at it, and the controller reaches it before anything else.
    func testTheShellHandsBackToTheLaunchScreen() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent("Sources/NXLibrary/" + path), encoding: .utf8)
        }
        XCTAssertTrue(try source("ViewModels/AppViewModel.swift").contains("|| launchOverlay != nil }"))
        let routing = try source("Views/Shell/AppShellView+Startup.swift")
        let launch = try XCTUnwrap(routing.range(of: "if launch.offersExit, action == .cancel {"))
        let screens = try XCTUnwrap(routing.range(of: "if viewModel.cloudQuitRequested {"))
        XCTAssertLessThan(launch.lowerBound, screens.lowerBound)
        XCTAssertTrue(try source("Views/Shell/AppShellView+Input.swift").contains("if viewModel.launchOverlay != nil"))
    }
}
