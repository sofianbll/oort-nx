import XCTest
@testable import OortLibrary

final class SettingsResetQuestionTests: XCTestCase {
    func testEveryResetAsksExceptTheOneThatAsksForTheCode() {
        for section in SettingsSection.allCases where SettingsReset.canReset(section) {
            XCTAssertEqual(SettingsReset.question(section, title: section.title) == nil, section == .profileSecurity, "\(section)")
        }
    }

    func testReplacingTheIdentityIsSaid() {
        XCTAssertTrue(SettingsReset.question(.profileIdentity, title: "Profile")!.message.contains("replaced now"))
        XCTAssertTrue(SettingsReset.question(.look, title: "Look")!.message.contains("Save"))
    }

    /// X and the hint only ask; the reset is reachable only through the question.
    func testNothingResetsWithoutTheQuestion() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("apps/mac/OortMac/Views/Settings/SettingsView.swift"), encoding: .utf8)
        XCTAssertEqual(view.components(separatedBy: "resetSection(").count - 1, 3, "Its definition and the two ways through askToReset")
    }
}
