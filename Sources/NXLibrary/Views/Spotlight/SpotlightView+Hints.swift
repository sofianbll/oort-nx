import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// The hints bar: what the buttons do for the focus and state on screen.
extension SpotlightView {
    func optionsHint(_ label: String, action: (() -> Void)? = nil) -> HintItem {
        .browsingOptions(GamepadLayout(settings.settings), label, hasHome: controllerHomeAvailable, action: action)
    }
    // MARK: - Hints

    /// The A slot keeps one width per place (row, page), so the prompts hold still
    /// as the focus moves. Y and B sit leftmost, where a longer label shifts nothing.
    func hintReserve(_ state: SpotlightState) -> [[String]] {
        if platformPicker != nil || state.isLifted || cardMenu != nil { return [] }
        switch state.focus {
        case .row: return [[], ["Play", "Resume", "Download", "Build", "Pick", "Open", "Show"]]
        case .pills, .strip, .mods, .about, .actions, .more, .achievements: return [[], ["Select", "View", "Show", "Open", "Cancel"]]
        case .store: return [[], ["Sort", "View"]]
        case .topGames: return []
        }
    }

    private var buildHistoryHint: HintItem {
        HintItem(.x, settings.settings.showsRecentBuilds ? "Hide builds" : "Show builds") { handle(.secondaryAction) }
    }

    func contextHints(_ model: Snapshot, _ state: SpotlightState) -> [HintItem] {
        if model.platformCursor != nil {
            let direction = model.platforms.cards.count > 1 ? [HintItem(.vertical, "Change platform")] : []
            return direction + [HintItem(.b, "Close") { handle(.cancel) }, HintItem(.a, "Close") { handle(.confirm) }]
        }
        if state.isLifted {
            return [HintItem(.move, "Move"), HintItem(.a, L10n.text("Drop")), HintItem(.b, L10n.text("Cancel"))]
        }
        if cardMenu != nil {
            return [HintItem(.a, L10n.text("Select")), HintItem(.b, L10n.text("Back"))]
        }
        switch state.focus {
        case .pills:
            let cancels = model.selectedGame.map { viewModel.portingPills($0).cancelsQueuedBuild(at: state.pillIndex) } ?? false
            return [HintItem(.b, "Back"), HintItem(.a, cancels ? "Cancel" : "Select")]
        case .strip:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("View"))]
        case .mods, .about, .actions:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Select"))]
        case .more:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Show"))]
        case .achievements:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Open"))]
        case .topGames:
            return [buildHistoryHint, HintItem(.a, L10n.text("Show"))]
        case .store:
            // On the sort bar A sorts, and only when the focused order is not the one shown already.
            guard storeHost.focus.kind == .sort else { return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("View"))] }
            let chosen = ModStoreSort.allCases.firstIndex(of: storeHost.sort) == storeHost.focus.index
            return chosen ? [HintItem(.b, L10n.text("Back"))] : [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Sort"))]
        case .row:
            switch model.selectedItem {
            case .platform:
                return [HintItem(.a, "Open") { handle(.confirm) }]
            case .card(let card):
                if card == .inbox { return [HintItem(.a, L10n.text("Open"))] }
                let more = [optionsHint("Card options")]
                return more + [HintItem(.a, card == .surprise ? L10n.text("Pick") : card == .mods ? L10n.text("Browse") : L10n.text("Open"))]
                    + (card == .activity ? [buildHistoryHint] : [])
            case .game:
                if let steam = model.selectedCatalogGame, steam.integration == .steam {
                    return [optionsHint("Options")] + SteamPlayCoordinator.shared.hint(for: steam)
                }
                if let record = model.selectedCatalogGame, record.macShortcut != nil {
                    return (viewModel.macShortcuts.canEdit ? [optionsHint("Tile options") { viewModel.macShortcuts.showTileOptions(record) }] : [])
                        + [HintItem(.a, "Open") { activate(.game(record.id)) }]
                }
                guard let game = model.selectedGame else { return [] }
                let pills = viewModel.portingPills(game)
                if pills == .porting {
                    return [optionsHint("Options"), HintItem(.a, "Show")]
                }
                if let item = downloadItem(game), pills != .queued {
                    return [optionsHint("Options"), HintItem(.a, item.primaryDownloadTitle)]
                }
                if pills.unavailableReason != nil, !runningGames.isRunning(game) {
                    return [optionsHint("Options")]
                }
                if game.isPlayableLocally {
                    return [optionsHint("Options"), HintItem(.a, runningGames.isRunning(game) ? "Resume" : "Play")]
                }
                if pills == .queued { return [optionsHint("Options"), HintItem(.a, "Show")] }
                return [optionsHint("Options"), HintItem(.a, L10n.text("Build"))]
            case nil:
                return []
            }
        }
    }
}
