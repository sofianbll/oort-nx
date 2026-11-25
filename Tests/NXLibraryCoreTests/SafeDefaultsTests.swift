import XCTest
@testable import NXLibraryCore

/// Screens that open by themselves: the press meant for what was under them must never commit to anything.
final class SafeDefaultsTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/NXLibrary/" + path), encoding: .utf8)
    }

    func testBackOnTheFirstPageOfTheAssistantStays() throws {
        var setup = FirstRunSetup()
        setup.openTour()
        XCTAssertFalse(setup.moveTour(-1))
        XCTAssertEqual(setup.page, FirstRunSetup.Page.tour[0])
        let view = try source("Views/Setup/OnboardingView.swift")
        let back = try XCTUnwrap(view.components(separatedBy: "private func back() {").last?.components(separatedBy: "\n    }").first)
        XCTAssertFalse(back.contains("finish"), "Only the Skip setup button leaves")
        XCTAssertTrue(view.contains("if page == .welcome { finish() }"), "Which still does")
        XCTAssertTrue(view.contains("backSkips: page == .welcome"))
    }
}
