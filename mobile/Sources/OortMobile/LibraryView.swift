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

    /// The largest texts take one cover a line on a phone.
    private var columns: Int { type.isAccessibilitySize ? max(1, Int(width / 260)) : max(2, Int(width / 168)) }

    private var games: [GameDetail] {
        let found = model.details.filter { nav.query.isEmpty || $0.game.title.localizedStandardContains(nav.query) }
        return byName ? found.sorted { $0.game.title.localizedStandardCompare($1.game.title) == .orderedAscending } : found
    }

    /// Searching, sorting and adding, within the controller's reach: the bar's buttons are not.
    private static let actions = ["#search", "#sort", "#add"]
    private var actionRows: [[String]] { type.isAccessibilitySize ? Self.actions.map { [$0] } : [Self.actions] }
    private var rows: [[String]] { actionRows + FocusGrid.rows(games.map(\.id), columns: columns) }
    /// What A acts on: the first game until the controller goes elsewhere.
    private var ring: String? {
        guard nav.device != nil, !nav.letters else { return nil }
        if let current = focus.current, Self.actions.contains(current) || games.contains(where: { $0.id == current }) { return current }
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
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SeleneTokens.Space.medium), count: columns),
                                  spacing: SeleneTokens.Space.large) {
                            ForEach(games) { item in card(item).id(item.id) }
                        }
                        .padding(.horizontal, SeleneTokens.Space.panel)
                        .padding(.vertical, SeleneTokens.Space.medium)
                        .animation(.snappy, value: byName)
                        if games.isEmpty { ContentUnavailableView.search(text: nav.query) }
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
                        Text(Oort.text("Last played")).tag(false)
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
                if nav.letters { OortLetters(text: nav.query, focused: nav.device == nil ? nil : letter.current ?? OortLetters.rows[0][0]) { type($0) } }
                OortHints(nav: nav, hints: nav.letters
                    ? [(.activate, Oort.text("Select")), (.settings, Oort.text("Delete")), (.back, Oort.text("Done"))]
                    : [(.activate, Self.actions.contains(ring ?? "") ? Oort.text("Select") : Oort.text("Game page")), (.settings, Oort.text("Options")),
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
            guard action == .activate else { return action == .search }
            if !nav.revealing { nav.importing = true }
            return true
        }
        if nav.letters { return spell(action) }
        switch action {
        case .up, .down, .left, .right, .activate, .settings:
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
            case let id?: nav.sounds.play(.open); nav.open(.game(id))
            case nil: nav.sounds.play(.deny)
            }
        case .settings:
            guard let id = focus.current, !Self.actions.contains(id) else { nav.sounds.play(.deny); return true }
            nav.sounds.play(.open)
            nav.open(.options(id))
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
        case .settings: type(.delete)
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

    private var actionKeys: some View {
        let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: SeleneTokens.Space.small))
                                              : AnyLayout(HStackLayout(spacing: SeleneTokens.Space.small))
        func key(_ id: String, _ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
            Button(action: run) { Label(title, systemImage: symbol).lineLimit(2).minimumScaleFactor(0.7).frame(maxWidth: .infinity) }
                .buttonStyle(OortKeyStyle(focused: ring == id))
                .accessibilityAddTraits(ring == id ? .isSelected : [])
                .id(id)
        }
        return layout {
            key("#search", nav.query.isEmpty ? Oort.text("Search") : nav.query, "magnifyingglass") { nav.search() }
            key("#sort", byName ? Oort.text("Name") : Oort.text("Last played"), "arrow.up.arrow.down") { byName.toggle() }
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
