import SwiftUI
import AppKit
import NXLibraryCore

enum GameSettingsCategory: String, CaseIterable, Hashable {
    case general, picture, controls, sound, multiplayer, performance, mods, cheats, saves, details, app, other

    var titleKey: String {
        switch self {
        case .general: "General"
        case .picture: "Picture"
        case .controls: "Controls"
        case .sound: "Sound"
        case .multiplayer: "Multiplayer"
        case .performance: "Performance"
        case .mods: "Mods"
        case .cheats: "Game settings: Cheats"
        case .saves: "Saves"
        case .details: "Details and artwork"
        case .app: "Mac app"
        case .other: "Other"
        }
    }

    var icon: MaterialIcon {
        switch self {
        case .general: .settings
        case .picture: .monitor
        case .controls: .gamepad
        case .sound: .volume
        case .multiplayer: .link
        case .performance: .timeline
        case .mods: .puzzle
        case .cheats: .casino
        case .saves: .save
        case .details: .image
        case .app: .folder
        case .other: .tune
        }
    }
}

struct GameSettingsItem: Identifiable {
    let id: String
    let title: String
    var about: String? = nil
    var value: String? = nil
    var fixed = false
    var activate: (() -> Void)? = nil
    var cycle: ((Int) -> Void)? = nil
}

/// Both Steam and Switch supply content only. Input remains in the screen or its embedded pane, never both.
struct GameSettingsScreen<Pane: View>: View {
    let gameName: String
    let items: [GameSettingsCategory: [GameSettingsItem]]
    var embedded: Set<GameSettingsCategory> = []
    let canHandleInput: () -> Bool
    let onClose: () -> Void
    @ViewBuilder var pane: (GameSettingsCategory) -> Pane

    @State private var category: GameSettingsCategory = .general
    @State private var inDetail = false
    @State private var focus = FocusIndex()
    @State private var keyMonitor: Any?
    @State private var paneLocked = false
    @State private var nestedPane = false
    @Environment(\.nxAppLocale) private var locale

    private var categories: [GameSettingsCategory] {
        GameSettingsCategory.allCases.filter { items[$0]?.isEmpty == false || embedded.contains($0) }
    }
    private var current: GameSettingsCategory { categories.contains(category) ? category : categories.first ?? .general }
    private var categoryItems: [GameSettingsItem] { items[current] ?? [] }
    private var rows: [GameSettingsItem] {
        if embedded.contains(current) && !categoryItems.isEmpty {
            return categoryItems + [.init(id: "open-pane", title: L10n.text(current.titleKey),
                                          activate: { nestedPane = true })]
        }
        return categoryItems
    }
    private var row: GameSettingsItem? { rows.indices.contains(focus.index) ? rows[focus.index] : nil }
    private var showsPane: Bool { embedded.contains(current) && (categoryItems.isEmpty || nestedPane) }
    private var panelOwnsInput: Bool { showsPane && inDetail }

    var body: some View {
        VStack(spacing: 0) {
            OortSettingsShell(title: L10n.text(current.titleKey, context: locale), onBack: inDetail && nestedPane ? goBack : nil) {
                OortSettingsSidebar(sections: [.init(title: nil, items: categories.map {
                    .init(id: $0, title: L10n.text($0.titleKey, context: locale), icon: $0.icon)
                })], selected: current, focused: !inDetail, onSelect: select) {
                    OortReadout(text: gameName)
                }
                .disabled(paneLocked)
            } detail: {
                if showsPane {
                    pane(current)
                        .environment(\.oortSettingsPane, .init(active: $inDetail, locked: $paneLocked,
                                                               onBack: leavePane))
                        .id(current)
                } else {
                    OortSettingsRows(focus: inDetail ? row?.id : nil) {
                        ForEach(rows) { item in
                            OortGameSettingRow(title: item.title, about: item.about, value: item.value,
                                               fixed: item.fixed, focused: inDetail && item.id == row?.id,
                                               action: item.activate.map { action in
                                { focus.index = rows.firstIndex { $0.id == item.id } ?? 0; inDetail = true; action() }
                            })
                            .id(item.id)
                        }
                    }
                    .id(current)
                }
            }
            if !panelOwnsInput {
                SeleneHintsBar(left: [HintItem(.b, "Back", action: goBack)], right: commandHints)
            }
        }
        .background(SeleneBackdrop(still: true))
        .environment(\.seleneMinimumFont, SeleneTokens.Space.pageMinimumFont)
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .onAppear(perform: installKeys)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    private var commandHints: [HintItem] {
        if !inDetail { return [HintItem(.a, "Open", action: enterDetail)] }
        guard let row, !row.fixed, let action = row.activate else { return [] }
        return [HintItem(.a, row.cycle == nil ? "Select" : "Change", action: action)]
    }

    private func select(_ selected: GameSettingsCategory) {
        guard !paneLocked else { return }
        category = selected
        nestedPane = false
        focus = FocusIndex()
        inDetail = false
    }

    private func goBack() {
        if panelOwnsInput {
            NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: GamepadAction.cancel)
        } else if inDetail {
            inDetail = false
        } else {
            // Next turn of the run loop: the panel behind must not take this same press.
            RunLoop.main.perform { MainActor.assumeIsolated { onClose() } }
        }
    }

    private func enterDetail() {
        if showsPane { RunLoop.main.perform { MainActor.assumeIsolated { inDetail = true } } }
        else { inDetail = true }
    }

    private func leavePane() {
        RunLoop.main.perform {
            MainActor.assumeIsolated {
                if nestedPane { nestedPane = false }
                else { inDetail = false }
            }
        }
    }

    private func handle(_ action: GamepadAction) {
        guard canHandleInput(), !panelOwnsInput else { return }
        switch action {
        case .navigateUp, .navigateDown:
            let delta = action == .navigateUp ? -1 : 1
            if inDetail { focus.move(by: delta, count: rows.count) }
            else if let next = categories.stepped(from: current, delta) { select(next) }
        case .navigateLeft:
            if let cycle = row?.cycle, inDetail, row?.fixed == false { cycle(-1) }
            else if inDetail { inDetail = false }
        case .navigateRight:
            if inDetail, row?.fixed == false { row?.cycle?(1) }
            else if !inDetail { enterDetail() }
        case .jumpToStart, .jumpToEnd:
            if inDetail { focus.move(by: action == .jumpToStart ? -rows.count : rows.count, count: rows.count) }
            else if let next = action == .jumpToStart ? categories.first : categories.last { select(next) }
        case .tabPrevious, .tabNext:
            if let next = categories.stepped(from: current, action == .tabPrevious ? -1 : 1) { select(next) }
        case .confirm:
            if !inDetail { enterDetail() }
            else if row?.fixed == false { row?.activate?() }
        case .cancel: goBack()
        default: break
        }
    }

    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard canHandleInput(), !panelOwnsInput, !NativeMenuCommands.shared.isTracking,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil, !(window.firstResponder is NSText),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 12: action = .tabPrevious
            case 14: action = .tabNext
            case 36, 49, 76:
                if event.isARepeat { return nil }
                action = .confirm
            case 53: action = .cancel
            default: return event
            }
            NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: action)
            return nil
        }
    }
}
