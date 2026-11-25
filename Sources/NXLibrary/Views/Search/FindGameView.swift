import SwiftUI
import AppKit
import NXLibraryCore

extension Notification.Name {
    static let nxFindGameGamepadAction = Notification.Name("NXFindGameGamepadAction")
    /// Posted with the picked game's UUID; the home screen selects it.
    static let nxFindGameSelect = Notification.Name("NXFindGameSelect")
}

/// Find a game (View hold or ⌘F): a pill field over a glass scrim, square results as you type.
/// Y or ⌘K takes the words typed to the command palette.
struct FindGameView: View {
    @ObservedObject var router: AppRouter
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var playSessions: PlaySessionStore
    let artwork: ArtworkStore

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var query = ""
    /// nil while the field has focus; otherwise the result under focus.
    @State private var focused: Int?
    @State private var keyMonitor: Any?
    @State private var hover = SeleneHoverFocus()
    @FocusState private var fieldFocused: Bool

    private static let columns = 6
    private static let limit = 12

    private var results: [CatalogGame] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let all = LibraryQuery(filter: .all, searchText: query)
            .applyCatalog(to: viewModel.visibleCatalogGames, history: playSessions)
        return Array(all.prefix(Self.limit))
    }

    var body: some View {
        SeleneOverlay(style: .search, alignment: .top, onOutside: close) {
            VStack(spacing: canvas.u(SeleneTokens.Space.dialogInset)) {
                field
                grid
                Spacer(minLength: 0)
            }
            .padding(.top, canvas.u(SeleneTokens.Space.stageHeader))
            .padding(.horizontal, canvas.u(SeleneTokens.Space.stageGutter))
            VStack {
                Spacer()
                SeleneHintsBar(right: [
                    HintItem(.y, "Search everywhere", keyboard: .text(PaletteAction.paletteShortcut)) { searchEverywhere() },
                    HintItem(.b, L10n.text("Close")) { close() },
                    HintItem(.a, L10n.text("Select"))
                ], bottom: SeleneBottomScrim.hintsBottom)
            }
        }
        .onAppear {
            fieldFocused = true
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: query) { focused = nil }
        .onChange(of: results.map(\.id)) { focused = nil }
        .onReceive(NotificationCenter.default.publisher(for: .nxFindGameGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handle(action)
        }
    }

    private var field: some View {
        OortSearchField(query: $query, lit: focused == nil) {
            TextField(L10n.text("Find a game"), text: $query)
                .focused($fieldFocused)
                .onSubmit { pick(results.first) }
        }
        .frame(width: canvas.u(SeleneTokens.Space.transferMeasure))
    }

    @ViewBuilder private var grid: some View {
        let games = results
        if !query.isEmpty && games.isEmpty {
            Text(L10n.text("No games match."))
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink60)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(canvas.u(160)), spacing: canvas.u(SeleneTokens.Space.feature)),
                                     count: Self.columns),
                      spacing: canvas.u(SeleneTokens.Space.feature)) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    tile(game, selected: focused == index)
                        .onTapGesture { pick(game) }
                        .onHover {
                            guard hover.moved($0), focused != index else { return }
                            fieldFocused = false
                            focused = index
                        }
                        .accessibilityAction { pick(game) }
                }
            }
        }
    }

    private func tile(_ game: CatalogGame, selected: Bool) -> some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            Group {
                if let native = game.nxnativeGame { SpotlightTileArtwork(game: native, side: canvas.u(160), artwork: artwork) }
                else { CatalogNativeArtwork(game: game, role: .square) }
            }
                .frame(width: canvas.u(160), height: canvas.u(160))
                .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous))
                .overlay(SeleneTileRing(cornerRadius: canvas.u(SeleneTokens.Radius.content), active: selected))
                .scaleEffect(selected && !reduceMotion ? 1.06 : 1)
                .animation(Motion.focus(reduceMotion), value: selected)
            Text(game.name)
                .seleneFont(.text, selected ? .semibold : .regular)
                .foregroundColor(selected ? SeleneTheme.ink : SeleneTheme.ink60)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: canvas.u(160))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Input

    private func handle(_ action: GamepadAction) {
        let count = results.count
        switch action {
        case .navigateDown:
            if let index = focused {
                if index + Self.columns < count { move(to: index + Self.columns) }
            } else if count > 0 {
                fieldFocused = false
                move(to: 0)
            }
        case .navigateUp:
            if let index = focused {
                if index >= Self.columns {
                    move(to: index - Self.columns)
                } else {
                    focused = nil
                    fieldFocused = true
                }
            }
        case .jumpToStart, .jumpToEnd:
            guard count > 0 else { break }
            fieldFocused = false
            move(to: action == .jumpToStart ? 0 : count - 1)
        case .navigateLeft:
            if let index = focused, index > 0 { move(to: index - 1) }
        case .navigateRight:
            if let index = focused, index + 1 < count { move(to: index + 1) }
        case .confirm:
            let games = results
            pick(focused.flatMap { games.indices.contains($0) ? games[$0] : nil } ?? games.first)
        case .cancel:
            close()
        case .contextAction:
            searchEverywhere()
        default:
            break
        }
    }

    private func searchEverywhere() {
        NotificationCenter.default.post(name: .nxLibraryOpenPalette, object: query)
    }

    private func move(to index: Int) {
        focused = index
        SoundEffectService.shared.play(.focus)
    }

    private func pick(_ game: CatalogGame?) {
        guard let game else { return }
        SoundEffectService.shared.play(.click)
        router.isSearchPresented = false
        if case .detail = router.route {
            router.setInitialRoute(.library)
            router.requestSpotlightSelect(game.id)
            return
        }
        // The home screen applies its own landing rule.
        NotificationCenter.default.post(name: .nxFindGameSelect, object: game.id)
    }

    private func close() {
        SoundEffectService.shared.play(.back)
        router.isSearchPresented = false
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard router.isSearchPresented, !router.isMenuPresented,
                  !viewModel.shellDialogOwnsInput, !viewModel.isWelcomeOpen,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil else { return event }
            let typing = fieldFocused
            if event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command],
               event.charactersIgnoringModifiers?.lowercased() == "k" {
                if !event.isARepeat { searchEverywhere() }
                return nil
            }
            switch event.keyCode {
            case 53:                                   // Esc
                handle(.cancel)
            case 125:                                  // Down
                handle(.navigateDown)
            case 126:                                  // Up
                if typing { return event }
                handle(.navigateUp)
            case 123:                                  // Left
                if typing { return event }
                handle(.navigateLeft)
            case 124:                                  // Right
                if typing { return event }
                handle(.navigateRight)
            case 36, 76:                               // Return
                if typing { return event }
                handle(.confirm)
            case 49:                                   // Space
                if typing { return event }
                handle(.confirm)
            default:
                return event
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
