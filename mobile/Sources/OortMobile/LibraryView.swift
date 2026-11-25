import ShellHost
import ShellModel
import SwiftUI

/// Every game, the last played first or by name. The covers are as wide as the screen allows, never smaller than a thumb.
struct LibraryScreen: View {
    let model: ShellHostModel
    @Bindable var nav: OortNav
    @State private var query = ""
    @State private var focus = FocusGrid<String>()
    @State private var width: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var type
    @AppStorage("oort.library.byName") private var byName = false

    /// The largest texts take one cover a line on a phone.
    private var columns: Int { type.isAccessibilitySize ? max(1, Int(width / 260)) : max(2, Int(width / 168)) }

    private var inCloud: Bool { nav.cloudShown && hasCloud }
    private var hasCloud: Bool { nav.hasCloud }
    private var cloudGames: [CloudModel.Game] {
        (nav.cloud?.cloudGames ?? []).filter { query.isEmpty || $0.build.name.localizedStandardContains(query) }
    }

    private var games: [GameDetail] {
        let found = model.details.filter { query.isEmpty || $0.game.title.localizedStandardContains(query) }
        return byName ? found.sorted { $0.game.title.localizedStandardCompare($1.game.title) == .orderedAscending } : found
    }

    var body: some View {
        Group {
            if inCloud, let cloud = nav.cloud {
                CloudLibrary(cloud: cloud, model: model, nav: nav, query: query, columns: columns, focus: focus)
                    .searchable(text: $query, prompt: Oort.text("Search your games"))
            } else if model.details.isEmpty {
                VStack(spacing: 0) {
                    CloudFilter(nav: nav)
                    EmptyLibrary(model: model, nav: nav)
                }
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        CloudFilter(nav: nav)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SeleneTokens.Space.medium), count: columns),
                                  spacing: SeleneTokens.Space.large) {
                            ForEach(games) { item in card(item).id(item.id) }
                        }
                        .padding(.horizontal, SeleneTokens.Space.panel)
                        .padding(.vertical, SeleneTokens.Space.medium)
                        .animation(.snappy, value: byName)
                        if games.isEmpty { ContentUnavailableView.search(text: query) }
                    }
                    .onChange(of: focus.current) { _, id in withAnimation(.snappy) { scroll.scrollTo(id, anchor: .center) } }
                }
                .searchable(text: $query, prompt: Oort.text("Search your games"))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background { OortBackdrop(strength: 0.5) }
        .navigationTitle(Oort.text("Library"))
        .onChange(of: nav.cloudShown) { focus = FocusGrid() }
        .toolbar {
            if !inCloud { ToolbarItem(placement: .primaryAction) {
                Menu(Oort.text("Sort"), systemImage: "arrow.up.arrow.down") {
                    Picker(Oort.text("Sort"), selection: $byName) {
                        Text(Oort.text("Last played")).tag(false)
                        Text(Oort.text("Name")).tag(true)
                    }
                }
            } }
            ToolbarItem(placement: .primaryAction) {
                Button(Oort.text("Add a game"), systemImage: "plus") { nav.importing = true }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OortHints(nav: nav, hints: [(.activate, Oort.text("Game page")), (.settings, Oort.text("Options")), (.back, Oort.text("Back"))])
                .padding(.horizontal, SeleneTokens.Space.panel)
        }
        .oortInput(model, nav) { action in
            switch action {
            case .up where hasCloud && (focus.current == nil || top.contains(focus.current!)):
                // Above the first row: the other games.
                nav.cloudShown.toggle()
                nav.sounds.play(.select)
            case .up, .down, .left, .right:
                nav.sounds.play(focus.move(direction(action), in: FocusGrid.rows(ids, columns: columns)) ? .move : .deny)
            case .activate:
                guard let id = focus.current else { return true }
                nav.sounds.play(.open)
                nav.open(inCloud ? .cloudGame(id) : .game(id))
            case .settings:
                guard let id = focus.current, !inCloud else { return false }
                nav.sounds.play(.open)
                nav.open(.options(id))
            default: return false
            }
            return true
        }
    }

    private var ids: [String] { inCloud ? cloudGames.map(\.id) : games.map(\.id) }
    private var top: [String] { Array(ids.prefix(columns)) }

    private func card(_ item: GameDetail) -> some View {
        let focused = nav.device != nil && focus.current == item.id
        return Button {
            nav.device = nil
            nav.selected = item.id
            nav.sounds.play(.open)
            nav.open(.game(item.id))
        } label: {
            VStack(alignment: .leading, spacing: SeleneTokens.Space.compact) {
                GeometryReader { OortTile(game: item.game, side: $0.size.width, focused: focused) }.aspectRatio(1, contentMode: .fit)
                Text(item.game.title).font(.subheadline.weight(.semibold)).foregroundStyle(Oort.ink).lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.game.title)
        .accessibilityValue(OortGameAction(item, model: model, nav: nav).line)
        .contextMenu { GameMenu(id: item.id, nav: nav) }
    }
}

/// This device's games, or the cloud's: only when the module is on and has a code. It goes with the page.
struct CloudFilter: View {
    @Bindable var nav: OortNav
    var body: some View {
        if nav.hasCloud {
            Picker(Oort.text("Which games"), selection: $nav.cloudShown) {
                Text(Oort.text("On this device")).tag(false)
                Text(Oort.text("Cloud")).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal, SeleneTokens.Space.panel)
            .padding(.vertical, SeleneTokens.Space.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
