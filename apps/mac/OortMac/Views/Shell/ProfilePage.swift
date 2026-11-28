import SwiftUI
import Combine
import OortLibrary
import NxnativeAdapter

extension Notification.Name {
    static let nxProfileCardsSaveFailed = Self("NXProfileCardsSaveFailed")
}

struct ProfilePage: View {
    enum Focus: Hashable {
        case edit, change, account, lock, card(ProfilePageCard), game(ProfilePageCard, UUID), achievement(UUID, String)
    }

    let profile: LocalProfile
    @ObservedObject var viewModel: AppViewModel
    var history: PlaySessionStore
    let artwork: ArtworkStore
    let nextendo: NextendoSettings?
    var router: AppRouter
    @Binding var focus: Focus?
    var isGuest = false
    let onSwitch: () -> Void
    private func onEdit() { router.openSettings(.profileIdentity) }
    private func onAccount() {
        showFriends = false
        router.openSettings(.profileNextendo)
    }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.nxAppLocale) private var locale
    @Environment(\.seleneBackdropStyle) private var backdrop
    @ObservedObject private var theme = ThemeStore.shared
    @State private var accountRevision = false
    @State private var frames: [Focus: CGRect] = [:]
    @State private var achievement: AchievementEntry?
    @State private var achievementScreen: AchievementsScreenModel?
    @State private var showFriends = false
    @State private var friendIndex = 0

    private struct AchievementEntry {
        let game: CatalogGame
        let summary: AchievementSummary
    }

    private struct PageData {
        let now: Date
        let activity: [UUID: CarriedPlaytime]
        let week: ActivitySummary
        let games: [CatalogGame]
        let achievements: [AchievementEntry]

        func games(for card: ProfilePageCard) -> [CatalogGame] {
            card.games(in: games, activity: activity, week: week, now: now)
        }
    }

    private struct Frames: PreferenceKey {
        static let defaultValue: [Focus: CGRect] = [:]
        static func reduce(value: inout [Focus: CGRect], nextValue: () -> [Focus: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
        }
    }

    private var account: NextendoAccountSnapshot? {
        nextendo?.status == .signedIn ? nextendo?.account : nil
    }

    private var cards: [ProfilePageCard] {
        (profile.pageCards ?? .init()).visible(hasAccount: account != nil)
    }

    private var pageData: PageData {
        let now = Date.now
        let games = viewModel.visibleCatalogGames
        return .init(now: now, activity: history.profileActivity(at: now),
                     week: Activity.summary(sessions: history.sessions, now: now, calendar: .current),
                     games: games, achievements: games.compactMap { game in
            guard let native = game.nxnativeGame,
                  let summary = viewModel.localAchievementSummary(for: native, profile: profile.id) else { return nil }
            return .init(game: game, summary: summary)
        })
    }

    private var style: SeleneBackdropStyle {
        var style = backdrop
        if let url = theme.wallpaper(for: profile.look.wallpaper)?.url, profile.look.wallpaper != nil {
            style.wallpaperURL = url
            style.sizing = profile.look.sizing
        }
        return style
    }

    private var gap: CGFloat { canvas.u(SeleneTokens.Space.large) }
    private var layoutScale: CGFloat {
        max(SeleneTokens.Text.badge.rawValue / SeleneTokens.Text.text.rawValue,
            canvas.size.height / SeleneCanvas.design.height)
    }
    private var radius: CGFloat { canvas.u(SeleneTokens.Radius.card) }
    private var defaultFocus: Focus { isGuest ? .change : .edit }
    private var ownsPage: Bool { !viewModel.profileOwnsInput && !router.isMenuPresented && !viewModel.isGameOptionsOpen }

    var body: some View {
        let _ = accountRevision
        let data = pageData
        let most = data.games(for: .mostPlayed).first
        ZStack(alignment: .bottom) {
            SeleneBackdrop(still: true)
                .environment(\.seleneBackdropStyle, style)
            if let most { heroArt(most) }
            page(data, most: most)
                .seleneOverlayOwnership(!showFriends && achievementScreen == nil)
            if showFriends { friendsDetail(data) }
            if let achievement, let screen = achievementScreen {
                achievementDetail(achievement, screen)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(SeleneTheme.ink)
        .environment(\.seleneMinimumFont, SeleneTokens.Text.badge.rawValue)
        .animation(Motion.screen(reduceMotion), value: achievementScreen != nil)
        .animation(Motion.overlay(reduceMotion), value: showFriends)
        .onChange(of: achievementScreen != nil) { _, open in router.isScreenshotViewerOpen = open }
        .onDisappear { if achievementScreen != nil { router.isScreenshotViewerOpen = false } }
        .onReceive(nextendo?.objectWillChange.map { true }.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { _ in
            accountRevision.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxProfileInput)) { note in
            guard ownsPage, router.route == .profile, let action = note.object as? GamepadAction else { return }
            handle(action, data: data)
        }
        .onChange(of: nextendo?.status) { if nextendo?.status != .signedIn { showFriends = false } }
    }

    private func page(_ data: PageData, most: CatalogGame?) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let inset = min(canvas.u(SeleneTokens.Space.stageGutter),
                                geometry.size.width * SeleneTokens.Space.stageGutter / SeleneCanvas.design.width)
                let width = max(0, geometry.size.width - inset * 2)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: gap) {
                            hero(data, most: most, width: width)
                            sections(data, width: width)
                        }
                        .padding(.horizontal, inset)
                        .padding(.vertical, gap)
                        .coordinateSpace(.named("profile-page"))
                    }
                    .onChange(of: focus, initial: true) { _, next in
                        if let next { withAnimation(Motion.focus(reduceMotion)) { proxy.scrollTo(next) } }
                        else { focus = defaultFocus }
                    }
                    .onPreferenceChange(Frames.self) { current in
                        let initial = frames.isEmpty
                        frames = current
                        if let focus, !current.isEmpty {
                            if current[focus] == nil { self.focus = defaultFocus }
                            else if initial { proxy.scrollTo(focus) }
                        }
                    }
                }
            }
            if ownsPage && !showFriends && achievementScreen == nil {
                SeleneHintsBar(left: [HintItem(.b, "Back", action: router.back)],
                               right: [HintItem(.lb, "Previous") { handle(.tabPrevious, data: data) },
                                       HintItem(.rb, "Next") { handle(.tabNext, data: data) }]
                               + (isGuest ? [] : [HintItem(.y, "Edit profile", action: onEdit)])
                               + [HintItem(.menu, "Menu", hold: "Hold: Profile page") { router.isMenuPresented = true }]
                               + [HintItem(.a, "Open", action: { activate(focus ?? defaultFocus, data: data) })])
            }
        }
    }

    private func heroArt(_ game: CatalogGame) -> some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, canvas.stageSize.width * 3 / 4)
            gameArt(game, showsFallback: false)
                .frame(width: width, height: width * SeleneCanvas.design.height / SeleneCanvas.design.width)
                .opacity(SeleneTokens.Effect.deepVeil)
                .mask {
                    LinearGradient(colors: [.clear, .white, .white], startPoint: .leading, endPoint: .trailing)
                        .mask { LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func hero(_ data: PageData, most: CatalogGame?, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: canvas.u(SeleneTokens.Space.section)) {
                ProfilePortrait(profile: profile, size: SeleneTokens.Space.stageGutter + SeleneTokens.Space.section, ring: true)
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                    metadata(L10n.text("My profile"))
                    Text(profile.name).seleneFont(.hero, .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let account, profile.sharesPresence, nextendo?.presenceShared == true {
                        SeleneStatusDot(text: L10n.text("Nextendo connected") + " · " + account.name,
                                        color: SeleneTheme.statusOK, labelColor: SeleneTheme.ink90)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, canvas.u(SeleneTokens.Space.line))
            .oortArtShadow(canvas.u(SeleneTokens.Space.compact), strength: 1, color: SeleneTheme.scrim)
            // One line of four while it fits, two rows of two otherwise: a value never breaks.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.group)) { stats(data) }
                VStack(alignment: .leading, spacing: gap) {
                    let all = statValues(data)
                    ForEach(Array(stride(from: 0, to: all.count, by: 2)), id: \.self) { row in
                        HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.group)) {
                            ForEach(all[row..<min(row + 2, all.count)], id: \.0) { stat($0.0, $0.1) }
                        }
                    }
                }
            }
            .oortArtShadow(canvas.u(SeleneTokens.Space.compact), strength: 1, color: SeleneTheme.scrim)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: gap) {
                    HStack(spacing: canvas.u(SeleneTokens.Space.medium)) { pills(data) }
                        .fixedSize()
                    Spacer(minLength: 0)
                    mostPlayedLabel(most, data: data).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: gap) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: canvas.u(SeleneTokens.Space.small)) { pills(data) }
                        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small)) { pills(data) }
                    }
                    mostPlayedLabel(most, data: data)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.top, canvas.u(SeleneTokens.Space.section))
        .padding(.bottom, canvas.u(SeleneTokens.Space.section))
    }

    private func statValues(_ data: PageData) -> [(String, String)] {
        [("Playtime", LibraryPresentation.duration(data.activity.values.reduce(0) { $0 + $1.duration })),
         ("This week", LibraryPresentation.duration(data.week.thisWeek)),
         ("Games", data.games.count.formatted(.number.locale(locale.formatLocale)))]
        + (profile.createdAt.map { [("Member since", $0.formatted(.dateTime.month(.abbreviated).year().locale(locale.formatLocale)))] } ?? [])
    }

    @ViewBuilder private func stats(_ data: PageData) -> some View {
        ForEach(statValues(data), id: \.0) { stat($0.0, $0.1) }
    }

    @ViewBuilder private func mostPlayedLabel(_ game: CatalogGame?, data: PageData) -> some View {
        if let game, let played = data.activity[game.id] {
            VStack(alignment: .trailing, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                metadata(L10n.text("Most played game"))
                Text(game.name).seleneFont(.heading, .semibold)
                Text(LibraryPresentation.duration(played.duration)).seleneFont(.row)
            }
            .multilineTextAlignment(.trailing)
            .oortArtShadow(canvas.u(SeleneTokens.Space.compact), strength: 1, color: SeleneTheme.scrim)
        }
    }

    @ViewBuilder private func pills(_ data: PageData) -> some View {
        if !isGuest { pill("Edit profile", icon: .edit, id: .edit, data: data) }
        pill("Switch profile", icon: .swap, id: .change, data: data)
        if nextendo != nil { pill("Nextendo settings", icon: .settings, id: .account, data: data) }
        if !isGuest { pill("Profile lock", icon: .lock, id: .lock, data: data) }
    }

    /// The same key as "See all": one focus look on the whole page.
    private func pill(_ title: String, icon: MaterialIcon, id: Focus, data: PageData) -> some View {
        SelenePillButton(title: title, icon: icon, iconSize: SeleneTokens.Space.control, minWidth: 0,
                         height: SeleneTokens.Space.actionPillHeight, horizontalPadding: SeleneTokens.Space.feature,
                         focused: focus == id, scalesOnFocus: false) {
            focus = id
            activate(id, data: data)
        }
        .modifier(FocusTarget(id: id))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
            metadata(L10n.text(title))
            Text(value).seleneFont(.heading, .semibold).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func metadata(_ text: String) -> some View {
        Text(text).seleneFont(.text, .medium).foregroundStyle(SeleneTheme.ink75)
    }

    @ViewBuilder private func sections(_ data: PageData, width: CGFloat) -> some View {
        if let index = cards.firstIndex(of: .friends),
           let units = ProfilePageCards.friendsColumnWidth(available: width / layoutScale) {
            let narrow = units * layoutScale
            let left = Array(cards.filter { $0 != .friends }.prefix(max(1, index)))
            let rest = cards.filter { $0 != .friends && !left.contains($0) }
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    ForEach(left) { section($0, data: data, width: width - narrow - gap) }
                }
                .frame(maxWidth: .infinity)
                section(.friends, data: data, width: narrow).frame(width: narrow)
            }
            ForEach(rest) { section($0, data: data, width: width) }
        } else {
            ForEach(cards) { section($0, data: data, width: width) }
        }
    }

    private func section(_ card: ProfilePageCard, data: PageData, width: CGFloat) -> some View {
        let units = width / layoutScale
        let gameColumns = ProfilePageCards.columns(width: units)
        // Progress and both unlocks fit side by side before three landscape covers do.
        let count = card == .achievements && units >= SeleneTokens.Space.transferMeasure + SeleneTokens.Space.stageGutter * 2
            ? max(3, gameColumns) : gameColumns
        let tileWidth = max(0, (width - gap * CGFloat(count - 1)) / CGFloat(count))
        let items = data.games(for: card)
        let empty = isEmpty(card, items: items, data: data)
        return VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small)) {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                Text(L10n.text(card.title)).seleneFont(.heading, .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                let target = Focus.card(card)
                // "See all" leads somewhere only when the card has something to show.
                if !empty { SelenePillButton(title: "See all", icon: .chevron, iconSize: SeleneTokens.Space.control,
                                 minWidth: 0, height: SeleneTokens.Space.group, horizontalPadding: SeleneTokens.Space.medium,
                                 focused: focus == target, scalesOnFocus: false) {
                    focus = target
                    activate(target, data: data)
                }
                .accessibilityHint(L10n.text(card.title))
                .modifier(FocusTarget(id: target)) }
            }
            switch card {
            case .friends:
                friendsList(data: data, limit: 4)
            case .achievements:
                achievements(data, columns: count, tileWidth: tileWidth)
            case .week:
                if empty { self.empty("No playtime this week.") } else { week(data) }
            default:
                if empty {
                    self.empty(card == .neverPlayed ? "No games in this view." : "Play a game and it shows up here.")
                } else {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(items.prefix(count)) { game in
                            tile(game, card: card, data: data, width: tileWidth)
                        }
                    }
                }
            }
        }
    }

    private func isEmpty(_ card: ProfilePageCard, items: [CatalogGame], data: PageData) -> Bool {
        switch card {
        case .friends: false
        case .achievements: data.achievements.allSatisfy { $0.summary.total == 0 }
        case .week: data.week.thisWeek <= 0
        default: items.isEmpty
        }
    }

    private func tile(_ game: CatalogGame, card: ProfilePageCard, data: PageData, width: CGFloat) -> some View {
        let selected = focus == .game(card, game.id)
        let height = width * SeleneCanvas.design.height / SeleneCanvas.design.width
            + (card == .recent ? canvas.u(SeleneTokens.Space.small) : 0)
        return button(.game(card, game.id), data: data, radius: radius, showsRowRing: false) {
            Rectangle().fill(SeleneTheme.glass)
                .frame(width: width, height: height)
                .overlay {
                    gameArt(game)
                    LinearGradient(colors: [.clear, SeleneTheme.scrim], startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    if let activity = data.activity[game.id] {
                        Label(LibraryPresentation.duration(activity.duration), systemImage: "clock")
                            .seleneFont(.text, .semibold)
                            .padding(canvas.u(SeleneTokens.Space.compact))
                            .oortPanel(radius: canvas.u(SeleneTokens.Radius.hint), raised: true)
                            .padding(canvas.u(SeleneTokens.Space.small))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                        if let date = data.activity[game.id]?.lastPlayed {
                            metadata(date.formatted(.dateTime.day().month(.abbreviated).locale(locale.formatLocale)))
                        }
                        Text(game.name).seleneFont(.row, .semibold).lineLimit(2)
                    }
                    .padding(canvas.u(SeleneTokens.Space.medium))
                }
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(SeleneTheme.ink15) }
        }
        .modifier(TileFocus(focused: selected, radius: SeleneTokens.Radius.card,
                            scale: (SeleneTokens.Space.stageGutter + SeleneTokens.Space.compact) / SeleneTokens.Space.stageGutter))
        .zIndex(selected ? 1 : 0)
        .accessibilityLabel(game.name)
        .accessibilityValue(data.activity[game.id].map { LibraryPresentation.duration($0.duration) } ?? "")
    }

    private func week(_ data: PageData) -> some View {
        let peak = max(1, data.week.perDay.max() ?? 0)
        let formatter = DateFormatter()
        formatter.locale = locale.formatLocale
        let labels = formatter.shortStandaloneWeekdaySymbols ?? []
        return HStack(alignment: .bottom, spacing: canvas.u(SeleneTokens.Space.compact)) {
            ForEach(data.week.perDay.indices, id: \.self) { index in
                let day = labels.count == data.week.perDay.count ? labels[(index + 1) % labels.count] : ""
                let duration = data.week.perDay[index]
                VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                    // Written, so a controller or a glance reads it without hovering.
                    Text(duration > 0 ? LibraryPresentation.duration(duration) : " ")
                        .seleneFont(.text, .semibold).monospacedDigit().lineLimit(1)
                    RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.cover))
                        .fill(duration > 0 ? SeleneTheme.focus : SeleneTheme.ink25)
                        .frame(width: canvas.u(SeleneTokens.Space.group),
                               height: canvas.u(max(SeleneTokens.Space.hairline, SeleneTokens.Space.chromeGutter * duration / peak)))
                    Text(day).seleneFont(.text).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day)
                .accessibilityValue(LibraryPresentation.duration(duration))
                .help(LibraryPresentation.duration(duration))
            }
        }
        .padding(gap)
        .oortPanel(radius: radius)
    }

    @ViewBuilder private func achievements(_ data: PageData, columns count: Int, tileWidth: CGFloat) -> some View {
        let total = data.achievements.reduce(0) { $0 + $1.summary.total }
        let unlocked = data.achievements.reduce(0) { $0 + $1.summary.unlocked }
        if total == 0 {
            empty("No local achievements available.")
        } else {
            let recent = data.achievements.flatMap { entry in entry.summary.rows(.unlocked).map { (entry.game, $0) } }
                .sorted { ($0.1.unlockedAt ?? .distantPast) > ($1.1.unlockedAt ?? .distantPast) }
                .prefix(2)
            let progress = achievementProgress(unlocked: unlocked, total: total)
            let unlocks = ForEach(Array(recent.enumerated()), id: \.offset) { _, item in
                achievementTile(item.1, game: item.0, data: data).frame(width: tileWidth)
            }
            if count >= 3 {
                HStack(alignment: .top, spacing: gap) {
                    progress.frame(width: tileWidth)
                    unlocks
                }
            } else {
                progress
                if count == 2 {
                    HStack(alignment: .top, spacing: gap) { unlocks }
                } else {
                    unlocks
                }
            }
        }
    }

    private func achievementProgress(unlocked: Int, total: Int) -> some View {
        achievementSurface {
            metadata(L10n.text("Overall progress"))
            HStack(alignment: .firstTextBaseline, spacing: canvas.u(SeleneTokens.Space.compact)) {
                Text(unlocked, format: .number).seleneFont(.screen, .semibold)
                Text("/ \(total.formatted(.number.locale(locale.formatLocale)))").seleneFont(.heading)
                    .foregroundStyle(SeleneTheme.ink60)
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            OortMeter(share: Double(unlocked) / Double(total), height: SeleneTokens.Space.compact,
                                   track: SeleneTheme.ink25, fill: SeleneTheme.statusCloud)
        }
    }

    private func achievementTile(_ row: AchievementRow, game: CatalogGame, data: PageData) -> some View {
        button(.achievement(game.id, row.id), data: data, radius: radius) {
            achievementSurface {
                HStack(spacing: canvas.u(SeleneTokens.Space.control)) {
                    Image(systemName: row.icon ?? "trophy")
                        .seleneFont(.heading)
                        .frame(width: canvas.u(SeleneTokens.Space.chromeGutter),
                               height: canvas.u(SeleneTokens.Space.chromeGutter))
                        .background(SeleneTheme.statusCloud.opacity(SeleneTokens.Effect.panelVeil),
                                    in: RoundedRectangle(cornerRadius: radius))
                        .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(SeleneTheme.ink25) }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                        Text(row.name).seleneFont(.row, .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.description).seleneFont(.text).foregroundStyle(SeleneTheme.ink75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let date = row.unlockedAt {
                    metadata(L10n.format("Unlocked on %@", [
                        date.formatted(.dateTime.day().month(.abbreviated).locale(locale.formatLocale))
                    ]))
                }
            }
        }
    }

    private func achievementSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small), content: content)
            .padding(gap)
            .frame(maxWidth: .infinity, minHeight: canvas.u(SeleneTokens.Space.stageGutter + SeleneTokens.Space.section),
                   alignment: .topLeading)
            .oortPanel(radius: radius)
    }

    private func friendText(_ friend: NextendoAccountSnapshot.Friend) -> String {
        switch friend.presence {
        case .offline: return L10n.text("Offline")
        case .online: return L10n.text("Online")
        case .playing: return friend.game ?? L10n.text("Playing")
        }
    }

    @ViewBuilder private func friendsList(data: PageData, limit: Int? = nil) -> some View {
        if let friends = account?.friends {
            if friends.isEmpty {
                empty("No friends yet.")
            } else {
                surface {
                    let displayed = friends.prefix(limit ?? friends.count)
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, friend in
                        if index > 0 { Divider().overlay(SeleneTheme.ink15).accessibilityHidden(true) }
                        friendRow(friend, games: data.games)
                            .seleneRowFocus(limit == nil && friendIndex == index, radius: radius)
                            .id(index)
                    }
                }
            }
        } else {
            empty("Friends list unavailable.")
        }
    }

    private func friendRow(_ friend: NextendoAccountSnapshot.Friend, games: [CatalogGame]) -> some View {
        let diameter = canvas.u(SeleneTokens.Space.group)
        let color: Color = switch friend.presence {
        case .offline: SeleneTheme.ink60
        case .online: SeleneTheme.statusOK
        case .playing: SeleneTheme.statusCloud
        }
        return HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
            ZStack {
                Circle().strokeBorder(color).background(SeleneTheme.ink15, in: Circle())
                Text(String(friend.name.prefix(1))).seleneFont(.row, .semibold)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                Text(friend.name).seleneFont(.row, .semibold).lineLimit(1)
                SeleneStatusDot(text: friendText(friend), color: color).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            if friend.presence == .playing, let id = friend.gameID,
               let game = games.first(where: { $0.nxnativeGame?.titleId?.caseInsensitiveCompare(id) == .orderedSame }) {
                gameArt(game)
                    .frame(width: canvas.u(SeleneTokens.Space.chromeGutter + SeleneTokens.Space.small),
                           height: canvas.u(SeleneTokens.Space.group))
                    .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.cover)))
            }
        }
        .padding(.vertical, canvas.u(SeleneTokens.Space.tight))
        .accessibilityElement(children: .combine)
    }

    private func friendsDetail(_ data: PageData) -> some View {
        VStack(spacing: gap) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: gap) {
                        Text(L10n.text("Friends")).seleneFont(.screen, .semibold).accessibilityAddTraits(.isHeader)
                        friendsList(data: data)
                    }
                    .frame(maxWidth: canvas.u(SeleneTokens.Space.transferMeasure))
                    .padding(gap)
                }
                .onChange(of: friendIndex) {
                    withAnimation(Motion.focus(reduceMotion)) { proxy.scrollTo(friendIndex) }
                }
            }
            SeleneHintsBar(left: [HintItem(.b, "Back", action: { showFriends = false })],
                           right: [HintItem(.lb, "Previous") { handle(.tabPrevious, data: data) },
                                   HintItem(.rb, "Next") { handle(.tabNext, data: data) },
                                   HintItem(.a, "Nextendo settings", action: onAccount)])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeleneTheme.scrim)
        .transition(.opacity)
    }

    private func gameArt(_ game: CatalogGame, showsFallback: Bool = true) -> some View {
        ProfileGameArt(game: game, artwork: artwork, metadata: viewModel.store.storeMetadata[game.id],
                       showsFallback: showsFallback)
    }

    private func achievementDetail(_ entry: AchievementEntry, _ screen: AchievementsScreenModel) -> some View {
        AchievementsScreen(model: screen, game: entry.game, summary: entry.summary, art: nil,
                           onFilter: { screen.setFilter($0, summary: entry.summary) },
                           onShiftFilter: { screen.shiftFilter(by: $0, summary: entry.summary) },
                           onCycleOrder: {}, onFocus: { index in
            if screen.state.index == index { _ = screen.openDetail() } else { screen.focus(index) }
        }, onOpen: { _ = screen.openDetail() }, onCloseDetail: screen.closeDetail,
                           onClose: { achievementScreen = nil })
    }

    private func empty(_ title: String) -> some View {
        surface { Text(L10n.text(title)).seleneFont(.text).foregroundStyle(SeleneTheme.ink75) }
    }

    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small), content: content)
            .padding(canvas.u(SeleneTokens.Space.panel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .oortPanel(radius: radius)
    }

    private func button<Content: View>(_ id: Focus, data: PageData, radius: CGFloat, showsRowRing: Bool = true,
                                       @ViewBuilder content: () -> Content) -> some View {
        Button {
            focus = id
            activate(id, data: data)
        } label: {
            content().contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .seleneRowFocus(showsRowRing && focus == id, radius: radius)
        .modifier(FocusTarget(id: id))
    }

    private struct FocusTarget: ViewModifier {
        let id: Focus

        func body(content: Content) -> some View {
            content.background {
                GeometryReader { geometry in
                    Color.clear.preference(key: Frames.self, value: [id: geometry.frame(in: .named("profile-page"))])
                }
            }
            .id(id)
        }
    }

    private func activate(_ id: Focus, data: PageData) {
        switch id {
        case .edit: onEdit()
        case .change: onSwitch()
        case .account: onAccount()
        case .lock: router.openSettings(.profileSecurity, rowID: "profileLock")
        case .card(.friends):
            friendIndex = 0
            showFriends = account != nil
        case .card(.achievements): openAchievements(data.achievements.max {
            ($0.summary.lastUnlockedAt ?? .distantPast) < ($1.summary.lastUnlockedAt ?? .distantPast)
        })
        case .achievement(let id, let row): openAchievements(data.achievements.first { $0.game.id == id }, row: row)
        case .card(let card):
            router.navigate(to: .profileCollection(card))
        case .game(_, let id):
            guard let game = data.games.first(where: { $0.id == id }) else { return }
            if game.nxnativeGame != nil { router.showDetail(id) }
            else {
                router.openSpotlightDetails(id, returningTo: viewModel.spotlight.selectedKey)
            }
        }
    }

    private func openAchievements(_ entry: AchievementEntry?, row: String? = nil) {
        guard let entry else { return }
        let ids = entry.summary.rows(.all).map(\.id)
        let screen = AchievementsScreenModel(ids: ids)
        if let row, let index = ids.firstIndex(of: row) { screen.focus(index); _ = screen.openDetail() }
        achievement = entry
        achievementScreen = screen
    }

    private func handle(_ action: GamepadAction, data: PageData) {
        if let achievement, let screen = achievementScreen {
            guard action != .contextAction else { return }
            if screen.handle(action, summary: achievement.summary) == .close { achievementScreen = nil }
            return
        }
        if showFriends {
            if action == .cancel { showFriends = false }
            if action == .confirm { onAccount() }
            switch action {
            case .navigateUp, .navigateDown, .tabPrevious, .tabNext:
                let delta = action == .navigateUp || action == .tabPrevious ? -1 : 1
                let next = min(max(0, friendIndex + delta), max(0, (account?.friends?.count ?? 0) - 1))
                if friendIndex != next { friendIndex = next; SoundEffectService.shared.play(.focus) }
            default: break
            }
            return
        }
        let current = focus ?? defaultFocus
        switch action {
        case .cancel: router.back()
        case .confirm: activate(current, data: data)
        case .menu: router.isMenuPresented = true
        case .menuHold: router.openSettings(.profileCards)
        case .contextAction where !isGuest: focus = .edit; onEdit()
        case .jumpToStart, .jumpToEnd:
            let ordered = frames.sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }.map(\.key)
            if let next = action == .jumpToStart ? ordered.first : ordered.last, next != current {
                focus = next
                SoundEffectService.shared.play(.focus)
            }
        case .tabNext, .tabPrevious:
            let ordered = frames.sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }.map(\.key)
            guard let index = ordered.firstIndex(of: current) else { return }
            let next = index + (action == .tabNext ? 1 : -1)
            if ordered.indices.contains(next) {
                focus = ordered[next]
                SoundEffectService.shared.play(.focus)
            }
        case .navigateUp, .navigateDown, .navigateLeft, .navigateRight:
            guard let origin = frames[current] else { focus = defaultFocus; return }
            let vertical = action == .navigateUp || action == .navigateDown
            let forward = action == .navigateDown || action == .navigateRight
            let direction: CGFloat = forward ? 1 : -1
            func candidates(inRow: Bool) -> [(Focus, CGFloat, CGFloat)] {
                frames.compactMap { id, rect -> (Focus, CGFloat, CGFloat)? in
                    let primary = vertical ? rect.midY - origin.midY : rect.midX - origin.midX
                    let secondary = vertical ? rect.midX - origin.midX : rect.midY - origin.midY
                    guard primary * direction > canvas.u(SeleneTokens.Space.compact) else { return nil }
                    if inRow && !rect.intersects(CGRect(x: rect.minX, y: origin.minY, width: rect.width, height: origin.height)) { return nil }
                    return (id, abs(primary), abs(secondary))
                }
            }
            // Sideways stays in the row first; a column beside it (Friends) is still reached.
            let found = vertical ? candidates(inRow: false) : candidates(inRow: true).isEmpty
                ? candidates(inRow: false).map { ($0.0, $0.2, $0.1) } : candidates(inRow: true)
            if let next = found.min(by: { ($0.1, $0.2) < ($1.1, $1.2) })?.0 {
                focus = next
                SoundEffectService.shared.play(.focus)
            }
        default: break
        }
    }
}

private struct ProfileGameArt: View {
    let game: CatalogGame
    let artwork: ArtworkStore
    let metadata: NintendoStoreMetadata?
    var showsFallback = true
    @Environment(\.catalogPersonalizations) private var personalizations
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var image: NSImage?

    private var played: PlayedGame { game.nxnativeGame.map(PlayedGame.nxnative) ?? .steam(game) }

    var body: some View {
        Color.clear.overlay {
            if let art = image ?? GameArtLoader.shared.cachedHero(for: played) {
                Image(nsImage: art).resizable().scaledToFill()
            } else if showsFallback, let game = game.nxnativeGame {
                Image(nsImage: GameIconProvider.icon(for: game)).resizable().scaledToFit()
            } else if showsFallback {
                Image(systemName: "gamecontroller").seleneFont(.hero).foregroundStyle(SeleneTheme.ink25)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: game.id) {
            image = nil
            let art = await GameArtLoader.shared.hero(for: played, metadata: metadata, artwork: artwork,
                                                      personalizations: personalizations)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.detailArt(reduceMotion)) { image = art }
        }
    }
}
