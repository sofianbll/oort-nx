import ShellHost
import ShellModel
import SwiftUI

/// What a game needs now, in the player's words and with one action.
struct OortGameAction {
    var label: String
    var symbol: String
    var line: String
    var enabled = true
    var run: @MainActor () -> Void

    @MainActor init(_ detail: GameDetail, model: ShellHostModel, nav: OortNav) {
        let id = detail.id
        switch detail.game.state {
        case .playable:
            (label, symbol) = model.launchingGame ? (Oort.text("Starting…"), "hourglass") : (Oort.text("Play"), "play.fill")
            line = detail.game.recentlyPlayed ?? Oort.text("Never played")
            enabled = !model.launchingGame
            run = { nav.sounds.play(.play); model.actions.onPlay(id) }
        case .needsGameData:
            (label, symbol, line) = (Oort.text("Choose its data"), "folder", Oort.text("The game's data is not on this device yet."))
            run = { model.actions.onPickGameData(id) }
        case .needsDataUpdate:
            (label, symbol, line) = (Oort.text("Choose its data"), "folder", Oort.text("The game's data is older than the game."))
            run = { model.actions.onPickGameData(id) }
        case .joiningGameData(let percent, let done, let total):
            (label, symbol) = (Oort.text("Preparing \(percent)%"), "hourglass")
            line = Oort.text("\(done) of \(total) put together. The game opens when it is done.")
            enabled = false
            run = {}
        case .needsAppUpdate:
            (label, symbol, line) = (Oort.text("Update Oort NX"), "arrow.down.circle", Oort.text("This game was built for a newer Oort NX."))
            run = { model.actions.onAppUpdate() }
        case .broken(let reason, _, _):
            (label, symbol, line) = (Oort.text("See the problem"), "exclamationmark.triangle", reason)
            run = { nav.open(.game(id)) }
        }
    }
}

/// À la une: the last games played, the chosen one filling the screen, and Play under the thumb.
struct HomeView: View {
    private enum Target: Hashable { case game(String), play, info, options }
    let model: ShellHostModel
    @Bindable var nav: OortNav
    @State private var focus = FocusGrid<Target>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var across
    @Environment(\.verticalSizeClass) private var down
    @Environment(\.dynamicTypeSize) private var type
    /// A phone upright, or a narrow window on iPad.
    private var tall: Bool { across == .compact && down != .compact }

    private var detail: GameDetail? { model.details.first { $0.id == nav.selected } ?? model.details.first }
    private var rows: [[Target]] { [model.details.map { .game($0.id) }, [.play, .info, .options]] }

    var body: some View {
        GeometryReader { geometry in
            if let detail {
                content(detail, size: geometry.size)
            } else {
                EmptyLibrary(model: model, nav: nav)
            }
        }
        .background { backdrop }
        #if os(iOS)
        .toolbarVisibility(.hidden, for: .navigationBar)
        // A phone on its side with a controller is a console: the picture takes the bar's place, L and R change tab.
        .toolbarVisibility(down == .compact && nav.device != nil ? .hidden : .automatic, for: .tabBar)
        .statusBarHidden(down == .compact)
        .persistentSystemOverlays(down == .compact ? .hidden : .automatic)
        #endif
        .oortInput(model, nav) { action in
            if model.details.isEmpty {
                guard action == .activate else { return false }
                nav.importing = true
                return true
            }
            switch action {
            case .up, .down, .left, .right:
                if focus.current == nil { focus.set(detail.map { .game($0.id) }) }
                guard focus.move(direction(action), in: rows) else { nav.sounds.play(.deny); return true }
                nav.sounds.play(.move)
                if case .game(let id) = focus.current { withAnimation(Oort.focusCurve(reduceMotion)) { nav.selected = id } }
            case .activate:
                switch focus.current {
                case .info: openInfo()
                case .options: openOptions()
                default:
                    guard let detail else { return true }
                    let action = OortGameAction(detail, model: model, nav: nav)
                    if action.enabled { action.run() }
                }
            case .settings: openOptions()
            default: return false
            }
            return true
        }
    }

    private func openInfo() { if let detail { nav.sounds.play(.open); nav.open(.game(detail.id)) } }
    private func openOptions() { if let detail { nav.sounds.play(.open); nav.open(.options(detail.id)) } }

    private var backdrop: some View {
        ZStack {
            OortBackdrop(strength: detail?.game.banner == nil || tall ? 1 : 0.35)
            if let detail, !tall { HomeArt(detail: detail).id(detail.id).transition(.opacity) }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: SeleneTokens.Motion.detailArt), value: detail?.id)
        .ignoresSafeArea()
    }

    @ViewBuilder private func content(_ detail: GameDetail, size: CGSize) -> some View {
        let large = across == .regular && down != .compact
        let portrait = tall
        if portrait {
            // The next cover shows its edge: that is how the swipe is learnt.
            let side = max(0, min(size.width - 2 * Self.peek, size.height * (type.isAccessibilitySize ? 0.3 : 0.47)))
            ScrollView {
                VStack(alignment: .leading, spacing: SeleneTokens.Space.large) {
                    Spacer(minLength: 0)
                    covers(side: side, width: size.width)
                    places.frame(maxWidth: .infinity)
                    heading(detail, large: false).padding(.horizontal, Self.margin)
                    VStack(spacing: SeleneTokens.Space.small) {
                        keys(detail, wide: true)
                        hints
                    }
                    .padding(.horizontal, Self.margin)
                }
                .padding(.vertical, SeleneTokens.Space.medium)
                .frame(minHeight: size.height, alignment: .bottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        } else {
            let tile: CGFloat = large ? 124 : 70
            let gutter = large ? SeleneTokens.Space.chromeGutter : SeleneTokens.Space.panel
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    rail(tile: tile, gutter: gutter).padding(.top, large ? SeleneTokens.Space.section : SeleneTokens.Space.tight)
                    Spacer(minLength: SeleneTokens.Space.medium)
                    VStack(alignment: .leading, spacing: large ? SeleneTokens.Space.large : SeleneTokens.Space.small) {
                        heading(detail, large: large)
                        keys(detail, wide: false)
                    }
                    .frame(maxWidth: large ? 620 : 460, alignment: .leading)
                    .padding(.horizontal, gutter)
                    if large { Spacer(minLength: SeleneTokens.Space.section).frame(maxHeight: size.height * 0.22) }
                    hints.padding(.horizontal, gutter).padding(.top, SeleneTokens.Space.compact)
                }
                .padding(.bottom, large ? SeleneTokens.Space.section : SeleneTokens.Space.compact)
                .frame(minHeight: size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private static let margin: CGFloat = 28
    private static let peek: CGFloat = 50

    /// The covers under the thumb: a swipe changes the game, a tap on the middle one opens its page.
    private func covers(side: CGFloat, width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: SeleneTokens.Space.medium) {
                ForEach(model.details) { item in
                    let selected = item.id == detail?.id
                    Button {
                        nav.device = nil
                        if selected { nav.sounds.play(.open); nav.open(.game(item.id)) } else { withAnimation(Oort.focusCurve(reduceMotion)) { nav.selected = item.id } }
                    } label: {
                        OortTile(game: item.game, side: side, focused: selected && nav.device != nil)
                    }
                    .buttonStyle(OortCoverStyle())
                    .accessibilityLabel(item.game.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityHint(selected ? Oort.text("Opens the game page") : "")
                    .contextMenu { GameMenu(id: item.id, nav: nav) }
                    .scrollTransition(.interactive, axis: .horizontal) { [reduceMotion] cover, phase in
                        cover.scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.9).opacity(phase.isIdentity ? 1 : 0.55)
                    }
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, SeleneTokens.Space.compact)
        }
        .contentMargins(.horizontal, max(0, (width - side) / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollPosition(id: Binding(get: { detail?.id }, set: { id in
            guard let id, id != detail?.id else { return }
            nav.sounds.play(.move)
            nav.selected = id
        }), anchor: .center)
    }

    /// Where the cover is among the games, in the mark's dots.
    @ViewBuilder private var places: some View {
        let all = model.details
        if all.count > 1, all.count <= 14 {
            HStack(spacing: 9) {
                ForEach(all) { item in
                    Circle().fill(item.id == detail?.id ? Oort.focus : Oort.glyph.opacity(0.35))
                        .frame(width: item.id == detail?.id ? 8 : 5, height: item.id == detail?.id ? 8 : 5)
                }
            }
            .frame(height: 10)
            .animation(Oort.focusCurve(reduceMotion), value: detail?.id)
            .accessibilityHidden(true)
        }
    }

    private func heading(_ detail: GameDetail, large: Bool) -> some View {
        let action = OortGameAction(detail, model: model, nav: nav)
        return VStack(alignment: .leading, spacing: SeleneTokens.Space.compact) {
            Text(detail.game.title)
                .font(large ? .system(size: SeleneTokens.Text.screen.rawValue * 1.2, weight: .bold) : .largeTitle.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .foregroundStyle(Oort.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: SeleneTokens.Space.compact) {
                OortStateDot(state: detail.game.state)
                Text(action.line).lineLimit(2)
            }
            .font(.subheadline)
            .foregroundStyle(Oort.ink2)
            let facts = [detail.playSummary, detail.game.version.isEmpty ? nil : Oort.text("Version \(detail.game.version)")].compactMap { $0 }
            if !facts.isEmpty {
                Text(facts.joined(separator: "  ·  ")).font(.footnote).foregroundStyle(Oort.ink2).lineLimit(1)
            }
        }
        .shadow(color: Oort.night.opacity(0.7), radius: 8)
        .contentTransition(.opacity)
        .animation(Oort.focusCurve(reduceMotion), value: detail.id)
    }

    private func keys(_ detail: GameDetail, wide: Bool) -> some View {
        let action = OortGameAction(detail, model: model, nav: nav)
        let pad = nav.device != nil
        // The largest texts put the main key on a line of its own.
        let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: SeleneTokens.Space.small))
                                              : AnyLayout(HStackLayout(spacing: SeleneTokens.Space.small))
        return layout {
            Button(action: action.run) {
                Label(action.label, systemImage: action.symbol).lineLimit(type.isAccessibilitySize ? 2 : 1).minimumScaleFactor(0.8)
                    .frame(maxWidth: wide ? .infinity : nil)
            }
            .buttonStyle(OortKeyStyle(solid: true, focused: pad && focus.current == .play))
            .disabled(!action.enabled)
            .accessibilityHint(action.line)
            HStack(spacing: SeleneTokens.Space.small) {
                Button(action: openInfo) { Image(systemName: "info") }
                    .buttonStyle(OortKeyStyle(focused: pad && focus.current == .info, round: true))
                    .accessibilityLabel(Oort.text("Game page"))
                Button(action: openOptions) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(OortKeyStyle(focused: pad && focus.current == .options, round: true))
                    .accessibilityLabel(Oort.text("Options"))
            }
        }
    }

    private var hints: some View {
        OortHints(nav: nav, hints: [(.activate, focus.current == .options ? Oort.text("Options") : detail.map { OortGameAction($0, model: model, nav: nav).label } ?? ""),
                                    (.settings, Oort.text("Options")), (.controllers, Oort.text("Controllers")), (.nextTab, Oort.text("Library"))])
    }

    private func rail(tile: CGFloat, gutter: CGFloat = SeleneTokens.Space.large) -> some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal) {
                HStack(spacing: SeleneTokens.Space.small) {
                    ForEach(model.details) { item in
                        let selected = item.id == detail?.id
                        Button {
                            nav.device = nil
                            nav.sounds.play(selected ? .open : .move)
                            if selected { nav.open(.game(item.id)) } else { withAnimation(Oort.focusCurve(reduceMotion)) { nav.selected = item.id } }
                        } label: {
                            OortTile(game: item.game, side: tile, selected: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.game.title)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityHint(selected ? Oort.text("Opens the game page") : "")
                        .contextMenu { GameMenu(id: item.id, nav: nav) }
                        .id(item.id)
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.vertical, SeleneTokens.Space.badge)
            }
            .scrollIndicators(.hidden)
            .onChange(of: nav.selected) { _, id in withAnimation(Oort.focusCurve(reduceMotion)) { scroll.scrollTo(id, anchor: .center) } }
        }
    }
}

struct GameMenu: View {
    let id: String
    let nav: OortNav
    var body: some View {
        Button(Oort.text("Game page"), systemImage: "info.circle") { nav.open(.game(id)) }
        Button(Oort.text("Options"), systemImage: "slider.horizontal.3") { nav.open(.options(id)) }
    }
}

/// The chosen game's picture, behind everything on a wide screen. It falls into the night where the text sits.
private struct HomeArt: View {
    let detail: GameDetail
    var body: some View {
        if let banner = detail.game.banner {
            OortPicture(artwork: banner)
                .overlay {
                    LinearGradient(stops: [.init(color: Oort.night.opacity(0.55), location: 0), .init(color: Oort.night.opacity(0.1), location: 0.4),
                                           .init(color: Oort.night.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
                }
                .overlay { LinearGradient(colors: [Oort.night.opacity(0.8), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.72, y: 0.5)) }
                .accessibilityHidden(true)
        }
    }
}

/// A cover sinks under the finger as a key does.
private struct OortCoverStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? SeleneTokens.Effect.pressScale : 1)
            .animation(reduceMotion ? nil : .linear(duration: SeleneTokens.Motion.press), value: configuration.isPressed)
    }
}

struct OortPicture: View {
    let artwork: Artwork
    var body: some View {
        Color.clear.overlay { Image(decorative: artwork.image, scale: 1).resizable().interpolation(.high).scaledToFill() }.clipped()
    }
}

/// The mark in a tile's corner: what is under way, or what is missing.
struct OortTileBadge: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.caption.weight(.bold)).dynamicTypeSize(...DynamicTypeSize.xLarge).foregroundStyle(Oort.ink)
            .frame(width: SeleneTokens.Space.large, height: SeleneTokens.Space.large).background(Oort.night.opacity(0.85), in: .circle).padding(SeleneTokens.Space.chipBottom)
    }
}

/// A game without a picture: its letter on the halftone. `lit`: the part of it that is here.
struct OortLetter: View {
    let title: String
    let side: CGFloat
    var lit = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Oort.panelRaised, Oort.panelLow], startPoint: .top, endPoint: .bottom)
            if lit { Oort.cloud.opacity(SeleneTokens.Effect.panelVeil) }
            OortDots(rise: 1, color: Oort.glyph.opacity(0.12))
            Text(String(title.prefix(1))).font(.system(size: side * 0.4, weight: .semibold)).foregroundStyle(Oort.ink)
        }
    }
}

/// What every tile stands on: its ring under the controller, and its shadow.
struct OortTileChrome: ViewModifier {
    let shape: RoundedRectangle
    let ring: Bool
    func body(content: Content) -> some View {
        content
            .overlay { shape.inset(by: -SeleneTokens.Space.hairline).strokeBorder(Oort.focus, lineWidth: SeleneTokens.Space.focusStroke).opacity(ring ? 1 : 0) }
            .shadow(color: Oort.night.opacity(0.5), radius: 8, y: 3)
            .contentShape(shape)
    }
}

/// A game in the rail or the grid: its icon, or its letters on the halftone.
struct OortTile: View {
    let game: GameTile
    let side: CGFloat
    var selected = false
    var focused = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side > 100 ? Oort.tile : SeleneTokens.Radius.content, style: .continuous)
        Group {
            if let art = game.icon ?? game.banner {
                OortPicture(artwork: art)
            } else {
                OortLetter(title: game.title, side: side)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(alignment: .topTrailing) {
            if let symbol = OortStateDot.symbol(game.state) {
                OortTileBadge(symbol: symbol)
            }
        }
        .modifier(OortTileChrome(shape: shape, ring: selected || focused))
    }
}

/// Colour and shape say the state; the words beside it say it too.
struct OortStateDot: View {
    let state: GameState
    @ScaledMetric(relativeTo: .subheadline) private var side = 9
    var body: some View {
        Group {
            switch state {
            case .playable: Circle().fill(Oort.ok)
            case .joiningGameData: Circle().trim(from: 0, to: 0.7).stroke(Oort.cloud, lineWidth: 2)
            case .broken: RoundedRectangle(cornerRadius: 2).fill(Oort.danger).rotationEffect(.degrees(45))
            default: Circle().strokeBorder(Oort.warning, lineWidth: 2)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static func symbol(_ state: GameState) -> String? {
        switch state {
        case .playable: nil
        case .needsGameData, .needsDataUpdate: "folder.fill"
        case .joiningGameData: "hourglass"
        case .needsAppUpdate: "arrow.down"
        case .broken: "exclamationmark"
        }
    }
}

/// No game yet: the cloud, and the one thing to do.
struct EmptyLibrary: View {
    let model: ShellHostModel
    let nav: OortNav
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: SeleneTokens.Space.large) {
                    Text(Oort.text("No game here yet")).font(.largeTitle.bold()).foregroundStyle(Oort.ink).accessibilityAddTraits(.isHeader)
                    Text(Oort.text("Build a game with Oort NX on your Mac, then add its folder here or send it with a cable. Your games, saves and settings stay on this device."))
                        .foregroundStyle(Oort.ink2).frame(maxWidth: 420, alignment: .leading)
                    Text(Oort.text("This is an early version: Oort NX for Mac does not build games for iPhone and iPad yet."))
                        .foregroundStyle(Oort.ink2).frame(maxWidth: 420, alignment: .leading)
                    Button { nav.importing = true } label: { Label(Oort.text("Add a game"), systemImage: "plus") }
                        .buttonStyle(OortKeyStyle(solid: true, focused: nav.device != nil))
                }
                .padding(SeleneTokens.Space.section)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottomLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
