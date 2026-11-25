import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Spotlight's single row of square tiles (Main.xaml SeleneGameRow + SeleneTileStyle).
///
/// Geometry in Selene units, relative to the stage (`SpotlightRowGeometry`): the row's top edge is the view's top
/// (120 + 10 on the stage), and the row's 80 start padding puts the first slot's face at x = 80. The tiles sit in
/// the row and one camera slides the whole row, so it moves as one piece however quickly the selection moves.
struct SpotlightRowView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.nxAppLocale) private var locale

    let items: [SpotlightItem]
    let gamesByID: [UUID: PortedGame]
    var catalogGamesByID: [UUID: CatalogGame] = [:]
    let selectedKey: String?
    var platforms: SpotlightPlatforms? = nil
    var platform: SpotlightPlatforms.Card? = nil
    var platformOpen = false
    /// Bumped when a choice is confirmed (the card's press).
    var platformPress = 0
    var platformInfo: PlatformCardInfo = .nameAndCount
    /// The tile lifted for moving: raised 12u, its ring stays.
    var liftedKey: String? = nil
    let isEmptyFilter: LibraryFilter?
    var isPlatformScoped = false
    let artwork: ArtworkStore
    /// The porting look of a game's tile (`PortingTileLook`).
    var tileLook: (PortedGame) -> PortingTileLook = { _ in .normal }
    @ObservedObject var cloud: CloudLibraryModel
    let showsCloudBadges: Bool
    var badgePosition: TileBadgePosition = .topRight
    /// Mods' art for the Mods card's face (up to four); empty draws Selene's own face.
    var modsCover: [URL] = []
    /// Spotlight's entrance (`SpotlightView+Entrance`): the tiles fly in from the centre while it plays.
    var entrance: SpotlightEntrance.Phase = .landed
    /// The flight is over: everything is in.
    var onEntranceEnd: () -> Void = {}
    var onPlatformMove: (Int) -> Void = { _ in }
    var onPlatformPick: (SpotlightPlatforms.Card) -> Void = { _ in }
    let onSelect: (SpotlightItem) -> Void
    let onActivate: (SpotlightItem) -> Void
    var onOptions: (SpotlightItem) -> Void = { _ in }

    @State private var titleVisible = false
    @State private var titleTask: Task<Void, Never>?
    /// The tile last lifted for moving, while it is still the selection.
    @State private var lastLifted: String?
    @State private var entranceEnd: Task<Void, Never>?

    static let pitch = SpotlightRowGeometry.pitch
    static let host = SpotlightRowGeometry.host
    static let grow = SpotlightRowGeometry.grow

    var body: some View {
        // A key that is not in the row (yet) means no selection, not the first item.
        let selected = selectedKey.flatMap { key in items.firstIndex { $0.key == key } }
        let offset = selected.map(SpotlightState.scrollOffset(selectedIndex:)) ?? 0
        let window = visibleRange(offset: offset)
        // The one value every tile and the camera glide on (`SpotlightRowGeometry`).
        let position = selected.map { CGFloat($0) } ?? SpotlightRowGeometry.noSelection
        // While a tile is lifted, and after it is put down until the selection moves on, only it is grown: the
        // tiles it passes swap places under it at their own size.
        let alone = liftedKey != nil || (lastLifted != nil && lastLifted == selectedKey)
        let flights = entranceFlights(window: window, position: position)
        let launched = entrance == .playing || entrance == .landed
        ZStack(alignment: .topLeading) {
            ForEach(window.map { (index: $0, item: items[$0]) }, id: \.item.key) { entry in
                let index = entry.index, item = entry.item
                let isSelected = index == selected
                tile(item, selected: isSelected)
                    .allowsHitTesting(!platformOpen || item == .platform)
                    .accessibilityHidden(platformOpen && item != .platform)
                    // Inside the glide: the tile grows about its own centre; the shift is undone by its own size.
                    .entrance(flights.isEmpty ? nil : flights[index - window.lowerBound], launched: launched,
                              unit: canvas.u(1),
                              outerScale: alone ? (isSelected ? SpotlightRowGeometry.grow : 1)
                                  : SpotlightRowGeometry.scale(of: CGFloat(index), at: position))
                    .modifier(TileGlide(position: position, index: CGFloat(index),
                                        rise: item.key == liftedKey ? 3 - 12 : 3,
                                        grown: alone ? isSelected : nil, unit: canvas.u(1)))
                    .zIndex(isSelected ? 10 : 0)
                    .transition(.identity)
            }
            if let selected {
                // The one ring: it travels with the selection, over the tiles it passes.
                SeleneTileRing(cornerRadius: canvas.u(SeleneTokens.Radius.spotlightFocus), active: true)
                    .frame(width: canvas.u(Self.host), height: canvas.u(Self.host))
                    .modifier(RingGlide(position: position, rise: liftedKey != nil ? 3 - 12 : 3, unit: canvas.u(1)))
                    .opacity(entrance == .landed ? 1 : 0)
                    .animation(reduceMotion ? nil : SeleneTheme.arrival, value: entrance)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(10.5)
                let item = items[selected]
                Text(title(of: item))
                    .seleneFont(.row)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                    .frame(width: canvas.u(420), alignment: .leading)
                    .offset(x: canvas.u(SpotlightRowGeometry.place(of: selected, selected: selected)
                                        + 1 + Self.host * Self.grow + 16),
                            y: canvas.u(3 + 7 * Self.grow + 160 + 14))
                    .opacity(titleVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .zIndex(11)
            }
            if let isEmptyFilter {
                // Beside the last card, whatever the card count and selection, never over them.
                emptyMessage(isEmptyFilter)
                    .entrance(entrance == .landed ? nil : SpotlightEntrance.message(after: flights),
                              launched: launched, unit: canvas.u(1))
                    .offset(x: canvas.u(SpotlightRowGeometry.place(of: items.count, selected: selected) + 32),
                            y: canvas.u(3 + Self.host / 2 - 26))
                    .transition(.opacity)
            }
        }
        // The camera: the one slide of the whole row, on the tiles' own glide.
        .modifier(RailCamera(position: position - CGFloat(SpotlightState.anchorSlot),
                             maximum: CGFloat(SpotlightState.scrollOffset(selectedIndex: items.count - 1)),
                             pitch: canvas.u(SpotlightRowGeometry.pitch)))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: canvas.u(260), alignment: .topLeading)
        .animation(Motion.rail(reduceMotion, .spotlight), value: selectedKey)
        .animation(Motion.rail(reduceMotion, .spotlight), value: items.map(\.key))
        .animation(Motion.rail(reduceMotion, .spotlight), value: liftedKey)
        .animation(Motion.rowMessage(reduceMotion), value: isEmptyFilter)
        .onAppear { scheduleTitle(delay: 0) }
        .onChange(of: selectedKey) { _, key in
            if key != lastLifted { lastLifted = nil }
            scheduleTitle(delay: 0.23)
        }
        .onChange(of: liftedKey) { _, key in
            if let key { lastLifted = key }
        }
        .onChange(of: entrance) { _, phase in
            entranceEnd?.cancel()
            guard phase == .playing else { return }
            scheduleTitle(delay: SpotlightEntrance.titleDelay)
            let layout = currentLayout()
            let end = SpotlightEntrance.end(of: entranceFlights(window: layout.window, position: layout.position))
            entranceEnd = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(end * 1_000_000_000))
                guard !Task.isCancelled else { return }
                onEntranceEnd()
            }
        }
        .onDisappear {
            titleTask?.cancel()
            entranceEnd?.cancel()
        }
    }

    /// The visible tiles and the selection's glide position, as `body` works them out.
    private func currentLayout() -> (window: Range<Int>, position: CGFloat) {
        let selected = selectedKey.flatMap { key in items.firstIndex { $0.key == key } }
        let offset = selected.map(SpotlightState.scrollOffset(selectedIndex:)) ?? 0
        return (visibleRange(offset: offset), selected.map { CGFloat($0) } ?? SpotlightRowGeometry.noSelection)
    }

    /// The entrance's flight for each tile in `window`, in order, from where each one sits in the window (Selene
    /// measures the row, which spans the window); empty once landed.
    private func entranceFlights(window: Range<Int>, position: CGFloat) -> [SpotlightEntrance.Flight?] {
        guard entrance != .landed else { return [] }
        let unit = max(canvas.u(1), 0.0001)
        let shift = SpotlightRowGeometry.camera(at: position) + canvas.stageOrigin.x / unit
        let tiles = window.map { index -> ClosedRange<CGFloat> in
            let i = CGFloat(index)
            let x = SpotlightRowGeometry.place(of: i, at: position) + 1 + shift
            return x...(x + Self.host * SpotlightRowGeometry.scale(of: i, at: position))
        }
        return SpotlightEntrance.flights(tiles: tiles, rowWidth: canvas.size.width / unit)
    }

    /// Items from a few tiles left of the screen to a few past its right edge; tiles
    /// outside never render, so a long library stays cheap.
    private func visibleRange(offset: Int) -> Range<Int> {
        let pitch = max(canvas.u(Self.pitch), 1)
        return SpotlightRowGeometry.window(count: items.count, offset: offset,
                                           tilesLeftOfStage: Int((canvas.stageOrigin.x / pitch).rounded(.up)),
                                           tilesAcross: Int((canvas.size.width / pitch).rounded(.up)))
    }

    /// A tile at its own size; `TileGlide` places and grows it.
    private func tile(_ item: SpotlightItem, selected: Bool) -> some View {
        let native: PortedGame? = if case .game(let id) = item { gamesByID[id] } else { nil }
        let cloudState = native.flatMap(cloud.stateForTile)
        return Group {
            if item == .platform, let platform, let platforms {
                face(item, selected: selected, cloudState: cloudState)
                    .padding(canvas.u(SeleneTokens.Space.badge))
                .frame(width: canvas.u(Self.host), height: canvas.u(Self.host), alignment: .topLeading)
                .contentShape(Rectangle())
                .overlay { platformActions(platform, selected: selected) }
            } else {
                OortGameTile(title: title(of: item), selected: selected, preset: .spotlight,
                             select: { onSelect(item) }, activate: { onActivate(item) }, options: { onOptions(item) }) {
                    face(item, selected: selected, cloudState: cloudState)
                }
            }
        }
        .modifier(CloudLibraryTileBadge(state: cloudState, showsCopyBadge: showsCloudBadges, position: badgePosition,
                                        look: native.map(tileLook) ?? .normal, onlineTitleID: native?.titleId))
    }

    @ViewBuilder
    private func face(_ item: SpotlightItem, selected: Bool, cloudState: CloudLibraryState?) -> some View {
        let side = canvas.u(160)
        let face = RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous)
        ZStack {
            if case .game(let id) = item, let game = gamesByID[id] {
                SpotlightTileArtwork(game: game, side: side, artwork: artwork, ownIconFirst: true,
                                     cloudTile: .init(state: cloudState, buildLook: tileLook(game),
                                                      cornerRadius: canvas.u(SeleneTokens.Radius.content),
                                                      backplateRadius: canvas.u(SeleneTokens.Radius.badge)))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous).fill(SeleneTheme.ink15)
                    switch item {
                    case .platform:
                        if let platforms, let platform {
                            platformRibbon(platform, in: platforms, side: side)
                        }
                    case .game(let id):
                        if let game = catalogGamesByID[id] {
                            CatalogNativeArtwork(game: game, role: .square, look: PortingTileLook.make(catalog: game))
                                .frame(width: side, height: side)
                                .clipShape(face)
                        }
                    case .card(.mods):
                        ModsCardCover(urls: modsCover, side: side)
                            .clipShape(face)
                            .overlay(face.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
                    case .card(let card):
                        OortKeyFace(kind: .quiet, radius: canvas.u(SeleneTokens.Radius.content), lit: selected, outlined: false)
                            .overlay(MaterialIconView(card.icon, size: 60).foregroundColor(SeleneTheme.ink))
                    }
                }
                .frame(width: side, height: side)
                // Draw words and glyphs as one picture so they don't snap individually when a tile grows or slides.
                // The ribbon's cards leave the tile's square, so each is its own picture.
                .modifier(TilePicture(whole: item != .platform, shadow: canvas.u(9)))
            }
            // So is a download's pulsing mark.
            if case .game(let id) = item, gamesByID[id] == nil, let game = catalogGamesByID[id] {
                PortingDownloadMark(look: PortingTileLook.make(catalog: game), width: side, height: side)
            }
            SeleneShine(cornerRadius: canvas.u(SeleneTokens.Radius.content), active: selected)
        }
        .frame(width: side, height: side)
    }

    private func title(of item: SpotlightItem) -> String {
        switch item {
        case .platform: return platform.map(platformTitle) ?? ""
        case .card(let card): return card.title
        case .game(let id): return gamesByID[id]?.name ?? catalogGamesByID[id]?.name ?? ""
        }
    }

    private func platformKind(_ card: SpotlightPlatforms.Card) -> PlatformKind {
        switch card.integration {
        case .nxnative: .switch1
        case .steam: .steam
        case .macShortcut: .mac
        default: .library
        }
    }

    private func platformName(_ card: SpotlightPlatforms.Card) -> String {
        let kind = platformKind(card)
        if kind == .library, let integration = card.integration { return integration.rawValue }
        return L10n.text(kind == .mac ? "Mac apps" : kind.rawValue, context: locale)
    }

    private func platformCount(_ card: SpotlightPlatforms.Card) -> String {
        L10n.count("%lld games", card.count, context: locale)
    }

    /// Beside the selected card, where a game's name stands.
    private func platformTitle(_ card: SpotlightPlatforms.Card) -> String {
        switch platformInfo {
        case .nameAndCount: "\(platformName(card)) · \(platformCount(card))"
        case .name: platformName(card)
        case .none: ""
        }
    }

    private func platformRibbon(_ current: SpotlightPlatforms.Card, in platforms: SpotlightPlatforms, side: CGFloat) -> some View {
        let cursor = platforms.cards.firstIndex { $0.integration == current.integration } ?? 0
        return OortCardRibbon(ids: platforms.cards.map(\.integration), cursor: cursor, open: platformOpen,
                              locked: current.integration != nil, press: platformPress, side: side,
                              onPick: { onPlatformPick(platforms.cards[$0]) }) { id, here in
            OortKeyFace(kind: .quiet, radius: canvas.u(SeleneTokens.Radius.content), lit: here && platformOpen, outlined: false)
                .overlay {
                    PlatformMark(kind: platformKind(platforms.card(for: id)), size: SeleneTokens.Space.group + SeleneTokens.Space.small)
                        .foregroundStyle(SeleneTheme.ink)
                }
                .drawingGroup()
        }
        .accessibilityHidden(true)
    }

    private func platformActions(_ card: SpotlightPlatforms.Card, selected: Bool) -> some View {
        Button { onActivate(.platform) } label: {
            Spacer().frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .accessibilityLabel(platformName(card))
        .accessibilityValue(platformCount(card))
        .accessibilityHint(L10n.text(platformOpen ? "Select" : "Open", context: locale))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAdjustableAction { direction in
            guard platformOpen else { return }
            onPlatformMove(direction == .increment ? 1 : -1)
        }
    }

    /// The title hides at once on a move and fades in (0.2 s) once the row has settled.
    private func scheduleTitle(delay: Double) {
        titleTask?.cancel()
        var hide = Transaction()
        hide.disablesAnimations = true
        withTransaction(hide) { titleVisible = false }
        titleTask = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            withAnimation(SeleneTheme.arrival) { titleVisible = true }
        }
    }

    private func emptyMessage(_ filter: LibraryFilter) -> some View {
        let (title, hint): (String, String) = {
            if isPlatformScoped { return (L10n.text("No games match this filter.", context: locale), "") }
            return (L10n.text(filter.emptyCopy.title, context: locale), L10n.text(filter.emptyCopy.hint, context: locale))
        }()
        return VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(title).seleneFont(.row, .medium).foregroundColor(SeleneTheme.ink90)
            if !hint.isEmpty {
                Text(hint).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                    .frame(maxWidth: canvas.u(380), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A tile's place and size, worked out from the selection's position (`SpotlightRowGeometry`) at every frame of the
/// glide. Each tile glides the same value as its neighbours and the camera, so the row keeps its gaps in any rhythm
/// of presses. `grown` overrides the size while a tile is lifted (true for it, false for the rest).
private struct TilePicture: ViewModifier {
    let whole: Bool
    let shadow: CGFloat

    func body(content: Content) -> some View {
        // One shadow for a whole tile; the ribbon's cards cast their own.
        Group { if whole { content.drawingGroup() } else { content } }
            .oortArtShadow(whole ? shadow : 0)
    }
}

private struct TileGlide: GeometryEffect {
    var position: CGFloat
    var index: CGFloat
    /// The tile's top edge in the row, in Selene units (raised while lifted).
    var rise: CGFloat
    let grown: Bool?
    let unit: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(position, index), rise) }
        set {
            position = newValue.first.first
            index = newValue.first.second
            rise = newValue.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let scale = grown.map { $0 ? SpotlightRowGeometry.grow : 1 }
            ?? SpotlightRowGeometry.scale(of: index, at: position)
        // The 1u is the item's start margin.
        let x = (SpotlightRowGeometry.place(of: index, at: position) + 1) * unit
        return ProjectionTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: rise * unit))
    }
}

/// The ring at the selection's own place and size, on the tiles' glide.
private struct RingGlide: GeometryEffect {
    var position: CGFloat
    var rise: CGFloat
    let unit: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(position, rise) }
        set { (position, rise) = (newValue.first, newValue.second) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = (SpotlightRowGeometry.place(of: position, at: position) + 1) * unit
        return ProjectionTransform(CGAffineTransform(a: SpotlightRowGeometry.grow, b: 0, c: 0, d: SpotlightRowGeometry.grow,
                                                     tx: x, ty: rise * unit))
    }
}

/// The Mods card's face, filling the tile like a game icon: four mods' art as a mosaic (one when fewer), blurred
/// and dimmed, with the puzzle glyph in the middle like the other cards. With no art yet the ground is Selene's
/// accent gradient; the two crossfade under the glyph. Only the art GameBanana shows for the mods. New art comes
/// already decoded (`ModStoreHost`) and the whole mosaic crossfades, never one cell after another.
struct ModsCardCover: View {
    @Environment(\.seleneCanvas) private var canvas
    let urls: [URL]
    let side: CGFloat

    /// The cells' decode size.
    static let pixelSize = 700

    var body: some View {
        ZStack {
            LinearGradient(colors: [SeleneTheme.focus.opacity(SeleneTokens.Alpha.heavy), SeleneTheme.glassSolid],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if !urls.isEmpty {
                mosaic
                    .blur(radius: canvas.u(5), opaque: true)
                    .overlay(SeleneTheme.artShade.opacity(SeleneTokens.Alpha.shade))
                    .id(urls)
                    .transition(.opacity)
            }
            MaterialIconView(.puzzle, size: 60)
                .foregroundColor(SeleneTheme.ink)
                .oortShadow(.text)
        }
        .frame(width: side, height: side)
        .animation(SeleneTheme.settle(SeleneTokens.Motion.detailArt), value: urls)
        .drawingGroup()
    }

    @ViewBuilder
    private var mosaic: some View {
        if urls.count >= 4 {
            let half = side / 2
            VStack(spacing: 0) {
                HStack(spacing: 0) { cell(urls[0], half); cell(urls[1], half) }
                HStack(spacing: 0) { cell(urls[2], half); cell(urls[3], half) }
            }
            .frame(width: side, height: side)
        } else {
            cell(urls[0], side)
        }
    }

    private func cell(_ url: URL, _ size: CGFloat) -> some View {
        GameBananaImageView(url: url, maxPixelSize: Self.pixelSize)
            .frame(width: size, height: size)
            .clipped()
    }
}
