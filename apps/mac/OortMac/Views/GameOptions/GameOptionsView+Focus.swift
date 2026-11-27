import SwiftUI
import AppKit
import NXLibraryCore

/// Focus: setting it, moving it, and entering and leaving Edit details.
extension GameOptionsView {
    // MARK: - Focus

    func setFocus(_ row: GameOptionsRow) {
        setFocus(.game(row))
    }

    func setFocus(_ row: GameOptionsItem) {
        if row != focusedItem { infoRow = nil }
        pickedRow = row
    }

    func moveFocus(by delta: Int) {
        let rows = self.rows
        let previous = focusedItem
        guard let previous, let index = rows.firstIndex(of: previous) else { return }
        var focus = FocusIndex(index: index)
        focus.move(by: delta, count: rows.count)
        pickedRow = rows[focus.index]
        if focusedItem != previous {
            infoRow = nil
            SoundEffectService.shared.play(.focus)
        }
    }

    func enterEditDetails() {
        // Pin the focus to the first row now; a Store page that arrives later goes above it without moving it.
        pickedRow = presentation.focusableRows(level: .editDetails, origin: origin).first.map(GameOptionsItem.game)
        infoRow = nil
        level = .editDetails
        // The store link needs the store metadata; Details asks for it the same way.
        store.loadStoreMetadata(for: current)
    }

    func leaveEditDetails() {
        infoRow = nil
        level = .main
        // Back on the main list, the focus returns to Edit details, where it was left.
        pickedRow = .game(.editDetails)
        SoundEffectService.shared.play(.focus)
    }
}
