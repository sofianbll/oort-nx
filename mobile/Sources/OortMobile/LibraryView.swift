import ShellHost
import ShellModel
import SwiftUI

/// Every game, the last played first or by name. The covers are as wide as the screen allows, never smaller than a thumb.
struct LibraryScreen: View {
    let model: ShellHostModel
    @Bindable var nav: OortNav
    @State private var focus = FocusGrid<String>()
    @State private var letter = FocusGrid<OortLetters.Key>()
    @State private var width: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var type
    @AppStorage("oort.library.byName") private var byName = false
    @AppStorage("oort.library.favoritesOnly") private var favoritesOnly = false
    @AppStorage(OortFavorites.key) private var favorites = ""

    /// The largest texts take one cover a line on a phone.
    private var columns: Int { type.isAccessibilitySize ? max(1, Int(width / 260)) : max(2, Int(width / 168)) }

    private var games: [GameDetail] {
        let marked = OortFavorites.ids(favorites)
        let found = model.details.filter { (!favoritesOnly || marked.contains($0.id)) && (nav.query.isEmpty || $0.game.title.localizedStandardContains(nav.query)) }
        return byName ? found.sorted { $0.game.title.localizedStandardCompare($1.game.title) == .orderedAscending } : found
    }

    /// Searching, sorting and adding, within the controller's reach: the bar's buttons are not.
    private static let actions = ["#search", "#sort", "#add"]
    private static let tabs = ["#all", "#favorites"]
    private var actionRows: [[String]] { type.isAccessibilitySize ? Self.actions.map { [$0] } : [Self.actions] }
    private var rows: [[String]] { actionRows + [Self.tabs] + FocusGrid.rows(games.map(\.id), columns: columns) }
    private func isKey(_ id: String) -> Bool { Self.actions.contains(id) || Self.tabs.contains(id) }
    /// What A acts on: the first game until the controller goes elsewhere.
    private var ring: String? {
        guard nav.device != nil, !nav.letters else { return nil }
        if let current = focus.current, isKey(current) || games.contains(where: { $0.id == current }) { return current }
        return games.first?.id ?? Self.actions[0]
    }

    var body: some View {
        Group {
            if model.details.isEmpty {
                EmptyLibrary(model: model, nav: nav)
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        if nav.device != nil { actionKeys }
                        tabKeys
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SeleneTokens.Space.medium), count: columns),
                                  spacing: SeleneTokens.Space.large) {
                            ForEach(games) { item in card(item).id(item.id) }
                        }
                        .padding(.horizontal, SeleneTokens.Space.panel)
                        .padding(.vertical, SeleneTokens.Space.medium)
                        .animation(.snappy, value: byName)
                        if games.isEmpty {
                            if nav.query.isEmpty {
                                ContentUnavailableView(Oort.text("No favorite yet"), systemImage: "heart",
                                                       description: Text(Oort.text("Mark a game on its page, or with a long press.")))
                            } else { ContentUnavailableView.search(text: nav.query) }
                        }
                    }
                    .onChange(of: focus.current) { _, id in withAnimation(.snappy) { scroll.scrollTo(id, anchor: .center) } }
                }
                .searchable(text: $nav.query, isPresented: $nav.typing, prompt: Oort.text("Search your games"))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background { OortBackdrop(strength: 0.5) }
        .navigationTitle(Oort.text("Library"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu(Oort.text("Sort"), systemImage: "arrow.up.arrow.down") {
                    Picker(Oort.text("Sort"), selection: $byName) {
                        Text(Oort.text("Recent")).tag(false)
                        Text(Oort.text("Name")).tag(true)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(Oort.text("Add a game"), systemImage: "plus") { nav.importing = true }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: SeleneTokens.Space.compact) {
                // No game: nothing to search.
                if nav.letters, !model.details.isEmpty { OortLetters(text: nav.query, focused: nav.device == nil ? nil : letter.current ?? OortLetters.rows[0][0]) { type($0) } }
                OortHints(nav: nav, hints: nav.letters
                    ? [(.activate, Oort.text("Select")), (.details, Oort.text("Erase")), (.back, Oort.text("Done"))]
                    : [(.activate, isKey(ring ?? "") ? Oort.text("Select") : Oort.text("Game page")), (.settings, Oort.text("Options")),
                       (.search, Oort.text("Search")), (.nextTab, Oort.text("Tabs"))])
                    .padding(.horizontal, SeleneTokens.Space.panel)
            }
        }
        .onChange(of: nav.letters) { _, shown in if !shown { letter.set(nil) } }
        .onDisappear { nav.letters = false }
        .oortInput(model, nav, handle)
    }

    private func handle(_ action: ShellInput.Action) -> Bool {
        if model.details.isEmpty {
            nav.letters = false
            guard action == .activate else { return action == .search }
            if !nav.revealing { nav.importing = true }
            return true
        }
        if nav.letters { return spell(action) }
        switch action {
        case .up, .down, .left, .right, .activate, .settings, .details:
            if focus.current != ring { focus.set(ring) }
            if nav.revealing { nav.sounds.play(.move); return true }
        default: break
        }
        switch action {
        case .up, .down, .left, .right:
            nav.sounds.play(focus.move(direction(action), in: rows) ? .move : .deny)
        case .activate:
            switch focus.current {
            case "#search": nav.search()
            case "#sort": byName.toggle(); nav.sounds.play(.select)
            case "#add": nav.sounds.play(.open); nav.importing = true
            case "#all", "#favorites": nav.sounds.play(.select); favoritesOnly = focus.current == "#favorites"
            case let id?: nav.sounds.play(.open); nav.open(.game(id))
            case nil: nav.sounds.play(.deny)
            }
        case .settings, .details:
            guard let id = focus.current, !isKey(id) else { nav.sounds.play(.deny); return true }
            nav.sounds.play(.open)
            nav.open(action == .details ? .game(id) : .options(id))
        // B first undoes the search.
        case .back:
            guard !nav.query.isEmpty else { return false }
            nav.query = ""
            nav.sounds.play(.back)
        default: return false
        }
        return true
    }

    /// The letters have the controller: nothing under them moves.
    private func spell(_ action: ShellInput.Action) -> Bool {
        if letter.current == nil { letter.set(OortLetters.rows[0][0]) }
        switch action {
        case .up, .down, .left, .right: nav.sounds.play(letter.move(direction(action), in: OortLetters.rows) ? .move : .deny)
        case .activate: if let key = letter.current { type(key) }
        case .details, .settings: type(.delete)
        case .back, .search: nav.letters = false; nav.sounds.play(.back)
        default: break
        }
        return true
    }

    private func type(_ key: OortLetters.Key) {
        nav.sounds.play(.select)
        switch key {
        case .letter(let letter): nav.query.append(contentsOf: nav.query.isEmpty ? String(letter) : letter.lowercased())
        case .space: nav.query.append(" ")
        case .delete: _ = nav.query.popLast()
        case .done: nav.letters = false
        }
    }

    /// All the games, or the favorites: the library's two tabs on a phone.
    private var tabKeys: some View {
        HStack(spacing: SeleneTokens.Space.small) {
            ForEach(Self.tabs, id: \.self) { id in
                let on = favoritesOnly == (id == "#favorites")
                Button { favoritesOnly = id == "#favorites"; nav.sounds.play(.select) } label: {
                    Text(id == "#favorites" ? Oort.text("Favorites") : Oort.text("All games")).lineLimit(2).minimumScaleFactor(Oort.fit).frame(maxWidth: .infinity)
                }
                .buttonStyle(OortKeyStyle(solid: on, focused: ring == id))
                .accessibilityAddTraits(on ? .isSelected : [])
                .id(id)
            }
        }
        .padding(.horizontal, SeleneTokens.Space.panel)
        .padding(.top, SeleneTokens.Space.compact)
    }

    private var actionKeys: some View {
        let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: SeleneTokens.Space.small))
                                              : AnyLayout(HStackLayout(spacing: SeleneTokens.Space.small))
        func key(_ id: String, _ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
            Button(action: run) {
                // The sign stands over its word: three keys stay whole on the narrowest phone.
                VStack(spacing: SeleneTokens.Space.seam) {
                    Image(systemName: symbol)
                    Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(Oort.fit)
                }
                .padding(.vertical, SeleneTokens.Space.tight)
                .frame(maxWidth: .infinity)
            }
                .buttonStyle(OortKeyStyle(focused: ring == id))
                .accessibilityAddTraits(ring == id ? .isSelected : [])
                .id(id)
        }
        return layout {
            key("#search", nav.query.isEmpty ? Oort.text("Search") : nav.query, "magnifyingglass") { nav.search() }
            key("#sort", byName ? Oort.text("Name") : Oort.text("Recent"), "arrow.up.arrow.down") { byName.toggle() }
            key("#add", Oort.text("Add"), "plus") { nav.importing = true }
        }
        .padding(.horizontal, SeleneTokens.Space.panel)
        .padding(.top, SeleneTokens.Space.compact)
    }

    private func card(_ item: GameDetail) -> some View {
        let focused = ring == item.id
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
