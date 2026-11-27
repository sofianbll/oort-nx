import SwiftUI
import OortLibrary
import NxnativeAdapter

extension GameOptionsView {
    @ViewBuilder
    func fullSettings(canHandleInput: @escaping () -> Bool) -> some View {
        GameSettingsScreen(gameName: current.name, items: fullSettingsItems, embedded: [.mods, .cheats, .saves],
                           canHandleInput: canHandleInput, onClose: {
            pickedRow = .game(.allSettings)
            fullSettingsOpen = false
        }) { category in
            switch category {
            case .mods:
                ModsPanel(viewModel: viewModel, game: current, online: multiplayerMode == .online,
                          onRebuild: { rebuild(current) }, onClose: reloadMods)
            case .cheats:
                CheatsPanel(viewModel: viewModel, game: current, onRebuild: { rebuild(current) },
                            onClose: { cheatsValue = viewModel.cheats.cheatRowValue(for: current) })
            case .saves:
                SavesPanel(viewModel: viewModel, game: current, onClose: {})
            default: EmptyView()
            }
        }
    }

    private static let gameSettingCatalog = GameSettingCatalog.load()

    private var fullSettingsItems: [GameSettingsCategory: [GameSettingsItem]] {
        let p = presentation
        let mainRows = p.focusableRows(level: .main, origin: origin)
        let editRows = p.focusableRows(level: .editDetails, origin: origin)
        let runtimeRows = mainRows.filter { $0.settingKey != nil }
        var pages: [GameSettingsCategory: [GameSettingsItem]] = [
            .general: mainRows.filter { [.play, .move, .favorite, .hidden, .restoreDefaults, .gameDisplay].contains($0) }
                .map(fullSettingsItem),
            .details: editRows.filter { [.changeArtwork, .changeMetadata, .storePage, .searchStore].contains($0) }
                .map(fullSettingsItem),
            .app: (mainRows.filter { [.rebuild, .showInFinder, .removeGame].contains($0) }
                + editRows.filter { [.attachSources, .openLog, .removeSources].contains($0) }).map(fullSettingsItem),
            .controls: [.init(id: "players", title: L10n.text("Players"), activate: { playersOpen = true })],
            .multiplayer: mainRows.filter { $0 == .disableOnlineRiskMods }.map(fullSettingsItem)
        ]
        if snapshot != nil {
            pages[.general, default: []].append(.init(id: "copySettings", title: L10n.text("Copy settings to another game…"),
                about: L10n.text("You see what changes first. Undo puts the other game back."),
                activate: {
                    SoundEffectService.shared.play(.click)
                    copyTargets = viewModel.runtimeSettings.copyTargets(for: current)
                }))
        }
        if snapshot == nil {
            for row in runtimeRows {
                let category: GameSettingsCategory = switch row {
                case .fullscreen, .language: .general
                case .rumble, .rumbleStrength: .controls
                case .metalHUD: .performance
                default: .picture
                }
                pages[category, default: []].append(fullSettingsItem(row))
            }
        }

        let settings = snapshot.map { snapshot in snapshot.settings.filter { snapshot.visible($0.env) } } ?? []
        let groups = Self.gameSettingCatalog.groups(for: settings, envText: fullSettingsEnvironment)
        for group in groups {
            let category = GameSettingsCategory(rawValue: group.id) ?? .other
            for setting in group.settings {
                let row = runtimeRows.first { $0.settingKey == setting.env }
                pages[category, default: []].append(row.map(fullSettingsItem) ?? fullSettingsItem(setting))
            }
            for line in group.fileLines where snapshot == nil
                ? !runtimeRows.contains(where: { $0.settingKey == line.key })
                : snapshot?.isOffered(line.key) == false {
                pages[category, default: []].append(.init(id: "env-\(line.key)", title: line.key,
                    about: L10n.text("Set in env.txt"), value: line.value, fixed: true))
            }
        }
        if (snapshot == nil && !p.showRenderScale) || p.buildSettings?.offersRenderScale == false {
            pages[.picture, default: []].append(.init(id: "resolution-note", title: L10n.text("Internal resolution"),
                                                       about: p.resolutionNote))
        }
        return pages
    }

    private func fullSettingsItem(_ row: GameOptionsRow) -> GameSettingsItem {
        let fixed = presentation.isFixed(row) || (row == .gameDisplay && fileGameDisplay != nil)
        return .init(id: row.rawValue, title: row.title, about: fixed ? L10n.text("Set in env.txt") : presentation.about(row),
                     value: accessibilityValue(row), fixed: fixed,
                     activate: { activate(row) }, cycle: row.isChoice ? { adjust(row, by: $0) } : nil)
    }

    private func fullSettingsItem(_ setting: LauncherSetting) -> GameSettingsItem {
        let value = snapshot?.value(setting.env) ?? setting.defaultValue ?? ""
        let fixed = snapshot?.fixed.contains(setting.env) == true
        let change: (Int) -> Void = { delta in
            guard !fixed else { return }
            let next = GameSettingValues.stepped(setting, from: value, by: delta)
            viewModel.runtimeSettings.setGameSetting(setting.env, to: next, for: current)
            snapshot = viewModel.runtimeSettings.settingsSnapshot(for: current)
        }
        return .init(id: "setting-\(setting.env)", title: L10n.text(setting.label),
                     about: fixed ? L10n.text("Set in env.txt") : setting.note(for: value).map { L10n.text($0) },
                     value: L10n.text(GameSettingValues.label(setting, value)), fixed: fixed,
                     activate: { change(1) }, cycle: setting.kind == "toggle" ? nil : change)
    }
}
