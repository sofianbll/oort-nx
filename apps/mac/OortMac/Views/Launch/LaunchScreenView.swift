import SwiftUI
import AppKit
import OortLibrary

/// The launch screen of a game Play started here, nxnative or Steam.
struct LaunchOverlayState: Equatable {
    let game: PlayedGame
    var isReady = false
    /// B and Esc close the screen; it says so since `LaunchExit.offerDelay`.
    var offersExit = false

    init(game: PlayedGame, isReady: Bool = false) {
        self.game = game
        self.isReady = isReady
    }
}

/// Selene's launch screen: art drifting closer and the logo coming in once (`LaunchMotion`) while the game starts,
/// then fade to black and out once the game's window is on screen (`LaunchReadinessProbe`). Shown in its own
/// window over every app (`LaunchCoverWindow`). A Steam game's screen also leaves when Steam is
/// late or Play ends (`SteamPlayCoordinator.launchScreen`).
struct LaunchScreenView: View {
    let state: LaunchOverlayState
    @ObservedObject var viewModel: AppViewModel
    /// The Nintendo store's data (`StoreMetadataModel`): descriptions, screenshots and names shown here.
    @ObservedObject var store: StoreMetadataModel
    let artwork: ArtworkStore
    let settings: AppSettings
    let reduceMotion: Bool

    @Environment(\.seleneCanvas) private var canvas
    @State private var hero: NSImage?
    @State private var logo: NSImage?
    @State private var shown = false
    /// When the screen appeared, for the logo's entrance after the screen's fade.
    @State private var appearedAt: CFTimeInterval = 0
    @State private var blackout = false
    @State private var leaving = false
    @State private var exit = LaunchExit.Offer.none

    private var game: PlayedGame { state.game }

    /// The longest the screen stays: past a Steam cold start (45 s), the game's start and the 60 s window probe.
    static let ceiling: TimeInterval = 120

    private var shadeOpacity: Double {
        switch settings.launchShade {
        case .none: return 0
        case .soft: return 0.35
        case .dark: return 0.6
        }
    }

    private var showsArt: Bool {
        settings.launchStyle == .artAndLogo || settings.launchStyle == .artOnly
    }

    var body: some View {
        ZStack {
            SeleneTheme.artShade
            if showsArt {
                art
            }
            centrePiece
            exitHint
            SeleneTheme.artShade.opacity(blackout ? 1 : 0)
        }
        .ignoresSafeArea()
        .opacity(shown && !leaving ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Starting %@", [String(describing: game.name)]))
        .accessibilityAction(named: Text(L10n.text("Close"))) { finish() }
        .onReceive(NotificationCenter.default.publisher(for: .nxLaunchScreenExit)) { _ in finish() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in offerExit() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in offerExit() }
        .task(id: game.id) {
            try? await Task.sleep(nanoseconds: UInt64((LaunchExit.offerDelay + 0.1) * 1_000_000_000))
            if !Task.isCancelled { offerExit() }
        }
        .onAppear(perform: appear)
        .onChange(of: state.isReady) { _, ready in
            if ready { finish() }
        }
        .task(id: game.id) { await loadArt() }
        .task(id: game.id) {
            // The screen covers every app: whatever happens to the launch, it never stays up for good.
            try? await Task.sleep(nanoseconds: UInt64(Self.ceiling * 1_000_000_000))
            if !Task.isCancelled { finish() }
        }
    }

    private var art: some View {
        GeometryReader { geo in
            if let hero {
                LaunchArt(image: hero, moves: settings.launchMotion && !reduceMotion)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
            }
            SeleneTheme.artShade.opacity(shadeOpacity)
        }
    }

    @ViewBuilder private var centrePiece: some View {
        switch settings.launchStyle {
        case .artOnly:
            EmptyView()
        case .artAndLogo, .logoOnBlack:
            if let logo {
                // Selene's size: at most half the width and 38% of the height; the view adds room for the shadow.
                let size = LaunchLogo.fitted(logo.size, in: CGSize(width: canvas.u(960), height: canvas.u(410)))
                let margin = LaunchLogo.margin(shadowRadius: canvas.u(18))
                LaunchLogo(image: logo, shadowRadius: canvas.u(18), rise: canvas.u(LaunchMotion.riseDistance),
                           startsAt: appearedAt + LaunchMotion.screenFade + LaunchMotion.logoDelay,
                           reduceMotion: reduceMotion)
                    .frame(width: size.width + margin * 2, height: size.height + margin * 2)
                    .accessibilityHidden(true)
            } else {
                title
            }
        case .minimal:
            title
        }
    }

    /// Selene's hints bar, like every screen's, over the art once the wait is long.
    @ViewBuilder private var exitHint: some View {
        if exit != .none {
            SeleneHintsBar(left: exit == .button ? [HintItem(.b, "Close", action: finish)] : [],
                           right: exit == .button ? [] : [HintItem(nil, "Click to close", action: finish)])
                .transformEnvironment(\.seleneShowButtonHints) { if exit == .click { $0 = true } }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
        }
    }

    private func offerExit() {
        let next = LaunchExit.offer(elapsed: CACurrentMediaTime() - appearedAt, appActive: NSApp.isActive)
        guard next != exit, viewModel.launchOverlay?.game.id == game.id else { return }
        viewModel.launchOverlay?.offersExit = next != .none
        withAnimation(SeleneTheme.arrival) { exit = next }
    }

    private var title: some View {
        Text(game.name)
            .seleneFont(.screen, .semibold)
            .foregroundColor(SeleneTheme.artInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.stageGutter))
    }

    private func appear() {
        LaunchCoverTrace.event("Screen content appeared")
        appearedAt = CACurrentMediaTime()
        hero = GameArtLoader.shared.cachedHero(for: game)
        logo = GameArtLoader.shared.cachedLogo(for: game)
        withAnimation(SeleneTheme.settle(LaunchMotion.screenFade)) { shown = true }
        if state.isReady { finish() }
    }

    private func finish() {
        guard !leaving, !blackout else { return }
        withAnimation(SeleneTheme.ease(SeleneTokens.Motion.shake)) { blackout = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(SeleneTheme.arrival) { leaving = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if viewModel.launchOverlay?.game.id == game.id {
                    viewModel.dismissLaunchOverlay()
                }
            }
        }
    }

    @MainActor
    private func loadArt() async {
        let metadata = store.storeMetadata[game.id]
        if hero == nil, showsArt {
            let loaded = await GameArtLoader.shared.hero(
                for: game, metadata: metadata, artwork: artwork, personalizations: viewModel.personalizations)
            withAnimation(SeleneTheme.arrival) { hero = loaded }
        }
        if logo == nil, settings.launchStyle != .minimal, settings.launchStyle != .artOnly {
            let loaded = await GameArtLoader.shared.logo(
                for: game, metadata: metadata, artwork: artwork, personalizations: viewModel.personalizations)
            // The logo comes in by itself (`LaunchLogo`).
            logo = loaded
        }
    }
}
