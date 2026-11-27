import AppKit
import SwiftUI
import OortLibrary
import ArcanePorting

/// Holds the session card: the latest ended session waits until Arcane is in front, shows 1.8 s later for 8 s,
/// then leaves. A newer session replaces one still waiting or showing.
@MainActor
final class SessionCardPresenter: ObservableObject {
    static let delay: UInt64 = 1_800_000_000
    static let hold: UInt64 = 8_000_000_000

    @Published private(set) var shown: SessionSummary?
    @Published private(set) var achievementNames: [String] = []
    private var pendingAchievements: [String] = []
    private var achievementTask: Task<Void, Never>?
    private var pending: SessionSummary?
    private var task: Task<Void, Never>?
    private let isActive: @MainActor () -> Bool

    init(isActive: @escaping @MainActor () -> Bool = { @MainActor in NSApp?.isActive == true }) {
        self.isActive = isActive
    }

    /// A game closed; `enabled` is the Session card switch.
    func ended(_ summary: SessionSummary?, enabled: Bool) {
        guard enabled, let summary else { return }
        pending = summary
        if isActive() { schedule() }
    }

    /// Arcane came forward: a waiting card shows.
    func becameActive() {
        if pending != nil { schedule() }
        if !pendingAchievements.isEmpty { scheduleAchievements() }
    }

    func unlocked(_ names: [String]) {
        pendingAchievements.append(contentsOf: names)
        if isActive() { scheduleAchievements() }
    }

    func profileDidChange() {
        clear()
        achievementTask?.cancel()
        pendingAchievements = []
        achievementNames = []
    }

    private func scheduleAchievements() {
        achievementTask?.cancel()
        achievementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.delay)
            guard let self, !Task.isCancelled, self.isActive() else { return }
            self.achievementNames = self.pendingAchievements
            self.pendingAchievements = []
            try? await Task.sleep(nanoseconds: Self.hold)
            guard !Task.isCancelled else { return }
            self.achievementNames = []
        }
    }

    /// The switch went off: nothing waiting or showing stays.
    func clear() {
        task?.cancel()
        task = nil
        pending = nil
        shown = nil
    }

    private func schedule() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.delay)
            guard let self, !Task.isCancelled, self.isActive(), let summary = self.pending else { return }
            self.pending = nil
            self.shown = summary
            SoundEffectService.shared.play(.success)
            try? await Task.sleep(nanoseconds: Self.hold)
            guard !Task.isCancelled else { return }
            self.shown = nil
        }
    }
}

struct AchievementUnlockToast: View {
    let names: [String]

    var body: some View {
        NoticeToast(symbol: "trophy.fill", title: L10n.count("%lld achievements unlocked", names.count),
                    text: names.formatted(.list(type: .and).locale(L10n.context.formatLocale)))
    }
}

/// What a refresh of the library does and what came of it; the activity center keeps it afterwards.
struct LibraryRefreshToast: View {
    @Environment(\.nxAppLocale) private var localization
    let refresh: LibraryRefresh

    var body: some View {
        let state = LibraryRefreshModel.title(refresh, context: localization)
        let detail = LibraryRefreshModel.detail(refresh, context: localization)
        // What is missing takes every line of the card; its state becomes the title.
        let incomplete = refresh.outcome == .incomplete
        let text = incomplete ? detail ?? state : [state, detail].compactMap { $0 }.joined(separator: " · ")
        NoticeToast(symbol: symbol, title: incomplete ? state : L10n.text("Library refresh", context: localization), text: text)
            .onAppear { AccessibilityNotification.Announcement(text).post() }
            .onChange(of: refresh.outcome) { AccessibilityNotification.Announcement(text).post() }
    }

    private var symbol: String {
        switch refresh.outcome {
        case .running: return "arrow.triangle.2.circlepath"
        case .upToDate, .changed: return "checkmark.circle"
        case .incomplete: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        }
    }
}

private struct NoticeToast: View {
    @Environment(\.seleneCanvas) private var canvas
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.control)) {
            Image(systemName: symbol)
                .font(.system(size: canvas.u(SeleneTokens.Text.heading.rawValue), weight: .semibold))
                .foregroundColor(SeleneTheme.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                Text(title)
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                Text(text)
                    .seleneFont(.row, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.large))
        .frame(width: canvas.u(640), height: canvas.u(128))
        .background(Color(hex: ThemeStore.shared.palette.glass, opacity: 0.96),
                    in: RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge)))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge)).strokeBorder(SeleneTheme.ink15))
        .oortShadow(.floating)
        .accessibilityElement(children: .combine)
    }
}

/// Selene's session card: "Session ended", the game's name and this session · total on the left, the logo on the
/// right, the game's art faint behind. 640 × 128 units, top right; it takes no input.
struct SessionCardView: View {
    @Environment(\.catalogPersonalizations) private var personalizations
    @Environment(\.seleneCanvas) private var canvas
    let summary: SessionSummary
    let game: PlayedGame?
    let metadata: NintendoStoreMetadata?
    let artwork: ArtworkStore

    @State private var hero: NSImage?
    @State private var logo: NSImage?

    var body: some View {
        ZStack(alignment: .leading) {
            if let hero {
                Image(nsImage: hero)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: canvas.u(640), height: canvas.u(128))
                    .clipped()
                    .opacity(SeleneTokens.Alpha.half)
                    // Faint on the right, gone under the words on the left.
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.15),
                                                 .init(color: .black, location: 0.85)],
                                         startPoint: .leading, endPoint: .trailing))
            }
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.text("Session ended"))
                        .seleneFont(.text)
                        .foregroundColor(SeleneTheme.ink75)
                    Text(summary.gameName)
                        .seleneFont(.row, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, canvas.u(SeleneTokens.Space.seam))
                        .padding(.bottom, canvas.u(SeleneTokens.Space.compact))
                    HStack(alignment: .lastTextBaseline, spacing: canvas.u(SeleneTokens.Space.small)) {
                        figure(summary.thisSession, L10n.text("this session"))
                        Text("·")
                            .seleneFont(.text)
                            .foregroundColor(SeleneTheme.ink75)
                        figure(summary.total, L10n.text("total"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: canvas.u(170), maxHeight: canvas.u(88))
                        .oortShadow(.text)
                        .padding(.trailing, canvas.u(SeleneTokens.Space.hairline))
                }
            }
            .padding(.leading, canvas.u(SeleneTokens.Space.panel))
            .padding(.trailing, canvas.u(SeleneTokens.Space.control))
            // Words wider than the card are cut at its right edge, never pushed past its left one.
            .frame(width: canvas.u(640), alignment: .leading)
        }
        .frame(width: canvas.u(640), height: canvas.u(128))
        .background(Color(hex: ThemeStore.shared.palette.glass, opacity: 0.92))
        .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous)
            .strokeBorder(SeleneTheme.ink.opacity(SeleneTokens.Alpha.soft), lineWidth: max(1, canvas.u(1))))
        .oortShadow(.floating)
        .environment(\.seleneMinimumFont, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("Session ended, %@: %@ this session, %@ total", [String(describing: summary.gameName), String(describing: summary.thisSession.replacingOccurrences(of: "<1m", with: L10n.text("under a minute"))), String(describing: summary.total.replacingOccurrences(of: "<1m", with: L10n.text("under a minute")))]))
        .task(id: summary.id) { await loadArt() }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(value)
                .seleneFont(.row, .semibold)
                .foregroundColor(SeleneTheme.ink)
            Text(L10n.text(label))
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink75)
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// The art the game's pages already loaded, else the same lookups they use.
    @MainActor
    private func loadArt() async {
        guard let game else { return }
        hero = GameArtLoader.shared.cachedHero(for: game)
        logo = GameArtLoader.shared.cachedLogo(for: game)
        if hero == nil {
            let loaded = await GameArtLoader.shared.hero(for: game, metadata: metadata, artwork: artwork, personalizations: personalizations)
            withAnimation(SeleneTheme.arrival) { hero = loaded }
        }
        if logo == nil {
            let loaded = await GameArtLoader.shared.logo(for: game, metadata: metadata, artwork: artwork, personalizations: personalizations)
            withAnimation(SeleneTheme.arrival) { logo = loaded }
        }
    }
}

/// The session card's place on the screen: 112 units from the top, 28 from the right, sliding in from the right with a
/// fade as Selene's cards do. It never takes clicks or focus.
struct SessionCardLayer: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject var presenter: SessionCardPresenter
    var refresh: LibraryRefreshModel? = nil
    /// The ended session's game, nxnative or Steam.
    let game: (UUID) -> PlayedGame?
    let metadata: [UUID: NintendoStoreMetadata]
    let artwork: ArtworkStore

    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: canvas.u(40)))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if !presenter.achievementNames.isEmpty {
                AchievementUnlockToast(names: presenter.achievementNames)
                    .transition(arrival)
            } else if let summary = presenter.shown {
                SessionCardView(summary: summary,
                                game: game(summary.gameID),
                                metadata: metadata[summary.gameID],
                                artwork: artwork)
                    .id(summary.id)
                    .transition(arrival)
            } else if let refresh, refresh.announces, let current = refresh.current {
                LibraryRefreshToast(refresh: current)
                    .transition(arrival)
            }
        }
        .padding(.top, canvas.u(SeleneTokens.Space.toastTop))
        .padding(.trailing, canvas.u(SeleneTokens.Space.feature))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .animation(Motion.toast(reduceMotion), value: presenter.shown?.id)
        .animation(Motion.toast(reduceMotion), value: presenter.achievementNames)
        .animation(Motion.toast(reduceMotion), value: refresh?.announces)
    }
}
