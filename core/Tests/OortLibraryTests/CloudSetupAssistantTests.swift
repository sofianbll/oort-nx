import XCTest
@testable import NXLibraryCore

final class CloudSetupAssistantTests: XCTestCase {
    func testOptInBlocksActivationUntilMoveCompletesForCurrentFolder() {
        var draft = CloudSetupAssistantDraft()
        draft.chooseAccount("drive")
        draft.browse("New")
        XCTAssertFalse(draft.wantsMove)
        let stale = draft.ticket
        draft.toggleMove()
        XCTAssertTrue(draft.useFolder())
        draft.acceptAccessCheck(draft.ticket)
        draft.acceptMove(stale)
        XCTAssertNil(draft.activation)
        draft.acceptMove(draft.ticket)
        XCTAssertEqual(draft.activation?.root, "New")
        draft.backToFolders()
        draft.browse("Other")
        XCTAssertFalse(draft.wantsMove)
        XCTAssertNil(draft.activation)
    }

    func testGoogleIDIsStricterThanCredentialSyntax() {
        XCTAssertTrue(CloudSetupAssistantDraft.validGoogleClientID(" 123-example.apps.googleusercontent.com "))
        XCTAssertTrue(RcloneConfiguration.validCredential("not-a-google-client"))
        XCTAssertFalse(CloudSetupAssistantDraft.validGoogleClientID("not-a-google-client"))
        XCTAssertFalse(CloudSetupAssistantDraft.validGoogleClientID(".apps.googleusercontent.com"))
        XCTAssertFalse(CloudSetupAssistantDraft.validGoogleClientID("x.apps.googleusercontent.com.evil"))
    }

    func testBrowsingAndOldTicketsCannotAuthorizeActivation() {
        var draft = CloudSetupAssistantDraft()
        draft.chooseAccount("drive")
        let stale = draft.browse("Games")
        let current = draft.browse("Archive/Games")
        XCTAssertFalse(draft.matches(stale))
        XCTAssertTrue(draft.matches(current))
        XCTAssertNil(draft.activation)
        XCTAssertTrue(draft.useFolder())
        let check = draft.ticket
        draft.backToFolders()
        draft.browse("Other")
        XCTAssertTrue(draft.useFolder())
        draft.acceptAccessCheck(check)
        XCTAssertNil(draft.activation)
        draft.acceptAccessCheck(draft.ticket)
        XCTAssertEqual(draft.activation?.storage, "drive:Other")
        XCTAssertEqual(draft.activation?.enabled, true)
    }

    /// Opening a step lights what is useful, never the way back; a player's own move is kept.
    func testTheFirstUsefulTargetIsLitNeverTheWayBackAndAMoveIsKept() {
        var focus = CloudSetupAssistantFocus()
        let rows: [[CloudSetupAssistantFocus.Target]] = [[.folder("A")], [.cancel, .primary]]
        XCTAssertEqual(focus.current(in: rows), .primary)
        XCTAssertEqual(focus.current(in: [[.haveClient], [.helpCreate], [.cancel]], initial: nil), .haveClient)
        XCTAssertEqual(focus.current(in: [[.cancel, .create]], initial: .create), .create)
        XCTAssertEqual(focus.current(in: [[.cancel, .confirmMove]], initial: .cancel), .cancel, "Games are moved only on purpose")
        XCTAssertEqual(focus.current(in: [[.cancel]]), .cancel)
        focus.move(.left, in: rows)
        XCTAssertEqual(focus.current(in: rows), .cancel)
        focus.move(.up, in: rows)
        XCTAssertEqual(focus.current(in: rows), .folder("A"))
        focus.move(.down, in: rows)
        XCTAssertEqual(focus.current(in: rows), .primary, "Down reaches the way forward, not the way back below")
        focus.reset()
        XCTAssertEqual(focus.current(in: rows), .primary)
    }

    func testTheRailIsOnTheLeftAndTabReachesEverythingOnce() {
        var focus = CloudSetupAssistantFocus()
        let rows: [[CloudSetupAssistantFocus.Target]] = [[.change(.sources)], [.change(.library)], [.cancel, .primary]]
        let rail: [CloudSetupAssistantFocus.Target] = [.step(0), .step(1)]
        focus.move(.left, in: rows, rail: rail)
        focus.move(.left, in: rows, rail: rail)
        XCTAssertEqual(focus.current(in: rows, rail: rail), .step(1))
        focus.move(.up, in: rows, rail: rail)
        XCTAssertEqual(focus.current(in: rows, rail: rail), .step(0))
        focus.move(.right, in: rows, rail: rail)
        XCTAssertEqual(focus.current(in: rows, rail: rail), .change(.sources))
        focus.reset()
        var seen = Set<CloudSetupAssistantFocus.Target>()
        for _ in 0..<6 {
            seen.insert(focus.current(in: rows, rail: rail))
            focus.tab(1, in: rows, rail: rail)
        }
        XCTAssertEqual(seen, Set(rows.flatMap { $0 } + rail))
        let here = focus.current(in: rows, rail: rail)
        focus.tab(1, in: rows, rail: rail)
        focus.tab(-1, in: rows, rail: rail)
        XCTAssertEqual(focus.current(in: rows, rail: rail), here)
        focus.select(.step(0))
        focus.retainSelection(in: rows, rail: rail)
        XCTAssertEqual(focus.current(in: rows, rail: rail), .step(0))
        focus.retainSelection(in: rows)
        XCTAssertEqual(focus.current(in: rows), .primary)
    }

    func testGoingBackToTheAccountForgetsWhatWasCheckedForIt() {
        var draft = CloudSetupAssistantDraft()
        draft.chooseAccount("drive")
        draft.browse("New")
        draft.toggleMove()
        XCTAssertTrue(draft.useFolder())
        draft.acceptAccessCheck(draft.ticket)
        let stale = draft.ticket
        draft.backToAccount()
        XCTAssertEqual(draft.step, .account)
        XCTAssertNil(draft.activation)
        XCTAssertFalse(draft.wantsMove)
        draft.acceptAccessCheck(stale)
        XCTAssertNil(draft.activation)
    }
}
