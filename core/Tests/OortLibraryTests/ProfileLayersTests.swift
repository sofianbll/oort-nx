import XCTest
@testable import OortLibrary

/// Two layers must never take the input or draw their hints together: Y opened the wizard on top of a selector
/// that stayed visible, with two bars of hints.
final class ProfileLayersTests: XCTestCase {
    func testExactlyOneLayerOwnsInputAndHintsInEveryState() {
        for editing in [false, true] {
            for removing in [false, true] {
                let layers = ProfileLayers(editing: editing, removing: removing)
                XCTAssertEqual(ProfileLayers.Layer.allCases.filter(layers.isTop).count, 1, "\(layers)")
            }
        }
    }

    func testTheWizardReplacesTheSelector() {
        let layers = ProfileLayers(editing: true, removing: false)
        XCTAssertEqual(layers.top, .editor)
        XCTAssertFalse(layers.showsSelector)
        XCTAssertFalse(layers.isTop(.selector))
    }

    func testTheSelectorComesBackWhenTheWizardCloses() {
        XCTAssertTrue(ProfileLayers(editing: false, removing: false).isTop(.selector))
        XCTAssertTrue(ProfileLayers(editing: false, removing: false).showsSelector)
    }

    func testTheRemovalQuestionKeepsTheSelectorVisibleButSilent() {
        let layers = ProfileLayers(editing: false, removing: true)
        XCTAssertEqual(layers.top, .removal)
        XCTAssertTrue(layers.showsSelector)
        XCTAssertFalse(layers.isTop(.selector))
    }
}
