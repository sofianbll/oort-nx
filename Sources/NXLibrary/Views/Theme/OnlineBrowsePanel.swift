import SwiftUI
import AppKit
import NXLibraryCore

/// One source's grid as the Theme screen browses it: the state, and its pages
/// loading in the background. The screen never waits on the network.
@MainActor
final class OnlineBrowser: ObservableObject {
    @Published private(set) var state: OnlineBrowseState?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var task: Task<Void, Never>?

    func open(_ source: BackgroundSourceID) {
        reset()
        state = OnlineBrowseState(source: source)
        loadIfWanted()
    }

    func close() {
        reset()
        state = nil
    }

    /// Changes the state; a new category or search drops the page on its way.
    @discardableResult
    func update(_ change: (inout OnlineBrowseState) -> Bool) -> Bool {
        guard var next = state else { return false }
        let before = (next.categoryIndex, next.query)
        let changed = change(&next)
        if (next.categoryIndex, next.query) != before {
            task?.cancel()
            loading = false
            failed = false
        }
        state = next
        loadIfWanted()
        return changed
    }

    private func reset() {
        task?.cancel()
        task = nil
        loading = false
        failed = false
    }

    private func loadIfWanted() {
        guard let state, state.wantsMore, !loading, !failed else { return }
        let key = (state.source, state.category, state.query, state.nextPage)
        loading = true
        task = Task { [weak self] in
            let page = try? await OnlineBackgroundService.shared.page(key.0, category: key.1, query: key.2, page: key.3)
            guard let self, !Task.isCancelled, var current = self.state, current.source == key.0,
                  current.category == key.1, current.query == key.2, current.nextPage == key.3 else { return }
            self.loading = false
            if let page {
                current.append(page)
                self.state = current
                self.loadIfWanted()
            } else {
                self.failed = true
            }
        }
    }
}

/// The download of the chosen item, with its progress. Cancelling forgets it.
@MainActor
final class OnlineTransfer: ObservableObject {
    @Published private(set) var itemID: String?
    @Published private(set) var progress: Double = 0
    private var task: Task<Void, Never>?

    func start(_ item: OnlineBackground, done: @escaping (Result<String, Error>) -> Void) {
        task?.cancel()
        itemID = item.id
        progress = 0
        let report: @Sendable (Double) -> Void = { share in
            Task { @MainActor in
                if self.itemID == item.id { self.progress = share }
            }
        }
        task = Task { [weak self] in
            let result: Result<String, Error>
            do {
                result = .success(try await OnlineBackgroundService.shared.download(item, progress: report))
            } catch {
                result = .failure(error)
            }
            guard let self, self.itemID == item.id else { return }
            self.itemID = nil
            done(result)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        itemID = nil
    }
}

/// The left column while browsing a source: category chips, the search field on
/// Search, a status line, and the grid of thumbnails with their resolution badges.
struct OnlineBrowsePanel: View {
    let state: OnlineBrowseState
    let loading: Bool
    let failed: Bool
    let downloadingID: String?
    let progress: Double
    /// Ids (online/<source>-<id>) already downloaded.
    let downloaded: Set<String>
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onChip: (Int) -> Void
    let onTile: (Int) -> Void

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    static let gridHeight: CGFloat = 500

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chips
                .padding(.bottom, canvas.u(SeleneTokens.Space.line))
            if state.category.isSearch {
                searchField
                    .padding(.bottom, canvas.u(SeleneTokens.Space.small))
            }
            Text(status)
                .seleneFont(.text, .semibold)
                .foregroundColor(SeleneTheme.ink75)
                .padding(.leading, canvas.u(SeleneTokens.Space.small))
                .padding(.bottom, canvas.u(SeleneTokens.Space.small))
            grid
        }
    }

    private var status: String {
        let source = state.source.title
        if failed { return L10n.format("%@ IS UNAVAILABLE RIGHT NOW", [String(describing: source.uppercased())]) }
        if state.category.isSearch && state.query.isEmpty { return L10n.text("TYPE WHAT YOU'RE LOOKING FOR, THEN RETURN") }
        if state.items.isEmpty { return loading ? L10n.format("LOOKING ON %@…", [String(describing: source.uppercased())]) : L10n.text("NOTHING FOUND") }
        return L10n.format("ONLINE · %@ · %@", [String(describing: source.uppercased()), String(describing: state.category.displayTitle.uppercased())])
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                OortTabs(items: state.categories.enumerated().map { .init(id: $0.offset, title: $0.element.displayTitle) },
                         selected: state.categoryIndex, focused: state.focus == .chips ? state.categoryIndex : nil, select: onChip)
                    .padding(canvas.u(SeleneTokens.Space.hairline))
            }
            .scrollIndicators(.hidden)
            .frame(width: canvas.u(3 * 226))
            .horizontalEdgeFade(0.06)
            .onChange(of: state.categoryIndex) { _, index in
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private var searchField: some View {
        OortSearchField(query: $searchText, lit: searchFocused.wrappedValue) {
            TextField("", text: $searchText, prompt: Text(L10n.format("Search %@", [String(describing: state.source.title)])).foregroundColor(SeleneTheme.ink60))
                .focused(searchFocused)
                .onSubmit(onSubmit)
        }
        .frame(width: canvas.u(3 * 226 - 20))
        .padding(.leading, canvas.u(SeleneTokens.Space.small))
    }

    private var grid: some View {
        let height = Self.gridHeight - (state.category.isSearch ? 58 : 0)
        let items = state.items
        let focusedIndex: Int? = { if case .tile(let index) = state.focus { return index } else { return nil } }()
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stride(from: 0, to: items.count, by: OnlineBrowseState.columns)), id: \.self) { first in
                        HStack(spacing: 0) {
                            ForEach(first..<min(first + OnlineBrowseState.columns, items.count), id: \.self) { index in
                                OnlineTile(item: items[index], focused: index == focusedIndex,
                                           downloaded: downloaded.contains(OnlineDownload.wallpaperID(for: items[index])),
                                           progress: downloadingID == items[index].id ? progress : nil)
                                    .id(index)
                                    .onTapGesture { onTile(index) }
                            }
                        }
                    }
                }
                .padding(.vertical, canvas.u(SeleneTokens.Space.small))
            }
            .scrollIndicators(.hidden)
            .frame(width: canvas.u(3 * 226), height: canvas.u(height))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                         .init(color: .black, location: 1 - 150 / height),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: focusedIndex) { _, index in
                guard let index else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                    proxy.scrollTo(index - index % OnlineBrowseState.columns, anchor: .center)
                }
            }
        }
    }
}

/// An online item: its thumbnail, a resolution badge, a check once downloaded,
/// and a progress ring while it downloads.
private struct OnlineTile: View {
    let item: OnlineBackground
    let focused: Bool
    let downloaded: Bool
    let progress: Double?

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(SeleneTheme.baseGradient)
            WallpaperThumb(url: item.thumbnailURL)
            OortTag(text: ResolutionBadge.label(width: item.width, height: item.height),
                    icon: item.kind == .video ? .play : nil, preset: .art)
            .padding(canvas.u(SeleneTokens.Space.compact))
            if downloaded {
                MaterialIconView(.check, size: 20)
                    .foregroundColor(SeleneTheme.artInk)
                    .oortShadow(.text)
                    .padding(canvas.u(SeleneTokens.Space.compact))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let progress {
                SeleneTheme.artShade.opacity(SeleneTokens.Alpha.half)
                ZStack {
                    Circle().stroke(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.line), lineWidth: canvas.u(SeleneTokens.Space.ringStroke))
                    Circle().trim(from: 0, to: max(0.02, progress))
                        .stroke(SeleneTheme.focus, style: StrokeStyle(lineWidth: canvas.u(SeleneTokens.Space.ringStroke), lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 0.15), value: progress)
                }
                .frame(width: canvas.u(44), height: canvas.u(44))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: canvas.u(204), height: canvas.u(115))
        .clipShape(shape)
        .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: SeleneTokens.Space.thinStroke))
        .oortRing(focused, radius: canvas.u(SeleneTokens.Radius.card), gap: canvas.u(SeleneTokens.Space.hairline))
        .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: focused)
        .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
        .padding(.top, canvas.u(SeleneTokens.Space.small))
        .padding(.bottom, canvas.u(SeleneTokens.Space.line))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("%@, %@ by %@", [String(describing: item.title), String(describing: item.width), String(describing: item.height)]))
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }
}
