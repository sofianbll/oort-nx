import SwiftUI
import NXLibraryCore
import ArcanePorting

/// What a selected card shows under the row: headline (28 SemiBold), body
/// (19, ink82), its numbers, and the "A" action. Activity adds this week's
/// total, seven day bars and the top games.
struct SpotlightCardInfoView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.nxAppLocale) private var locale

    let card: SpotlightCard
    let gameCount: Int
    let installedCount: Int
    let poolLabel: String
    let activity: ActivitySummary
    let topGames: [PortedGame]
    let focusedTop: Int?
    let artwork: ArtworkStore
    let onTopGame: (Int) -> Void
    /// Nil hides the section; an empty history has its own visible state.
    var recentBuilds: [(game: PortedGame, date: Date)]? = nil
    /// The Mods card: working mods found so far and the games they are for.
    var modCounts: (mods: Int, games: Int, looking: Bool)? = nil

    /// Monday first, whatever the locale (matches `Activity.summary`).
    private static var dayLetters: [String] {
        let formatter = DateFormatter()
        formatter.locale = L10n.context.formatLocale
        let days = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return Array(days.dropFirst()) + [days[0]]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .seleneFont(.heading, .semibold)
                .foregroundColor(SeleneTheme.ink)
            Text(about)
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink82)
                .padding(.top, canvas.u(SeleneTokens.Space.compact))
            detail
                .padding(.top, canvas.u(SeleneTokens.Space.titleGap))
            if let action {
                actionChip(action)
                    .padding(.top, canvas.u(SeleneTokens.Space.titleGap))
            }
        }
        .frame(width: canvas.u(900), alignment: .leading)
        .oortShadow(.text)
    }

    private var headline: String {
        switch card {
        case .collection: return "Collection"
        case .surprise: return "Surprise me"
        case .activity: return L10n.text("Activity")
        case .mods: return L10n.text("Mods")
        case .addGame: return L10n.text("Add a game")
        case .inbox: return L10n.text("Inbox")
        }
    }

    private var about: String {
        switch card {
        case .collection: return L10n.text("Every game in your library, in one row.")
        case .surprise: return L10n.text("Can't decide? Pick a game for me.")
        case .activity: return L10n.text("Open your profile and see what you played.")
        case .mods: return L10n.text("Mods that work with your games, from GameBanana.")
        case .addGame: return L10n.text("Build a game from your own dumps.")
        case .inbox: return L10n.text("Incoming files are ready to review.")
        }
    }

    private var action: String? {
        switch card {
        case .collection: return "Open"
        case .surprise: return "Pick"
        // Activity and Mods have no button here: the hint in the corner says it once.
        case .activity, .mods: return nil
        case .addGame: return L10n.text("Add")
        case .inbox: return L10n.text("Open")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch card {
        case .collection:
            HStack(spacing: canvas.u(SeleneTokens.Space.large)) {
                stat(L10n.text("GAMES"), "\(gameCount)")
                divider
                stat(L10n.text("INSTALLED"), "\(installedCount)")
            }
        case .surprise:
            stat(L10n.text("PICKS FROM"), poolLabel)
        case .activity:
            activityDetail
        case .mods:
            if let counts = modCounts, counts.mods > 0 {
                HStack(spacing: canvas.u(SeleneTokens.Space.large)) {
                    stat("MODS", "\(counts.mods)")
                    divider
                    stat(L10n.text("FOR"), counts.games == 1 ? L10n.text("1 game") : L10n.format("%@ games", [String(describing: counts.games)]))
                }
            } else {
                stat("MODS", modCounts?.looking == false ? L10n.text("None yet") : L10n.text("Looking…"))
            }
        case .addGame, .inbox:
            EmptyView()
        }
    }

    private var activityDetail: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.control)) {
            HStack(alignment: .bottom, spacing: canvas.u(SeleneTokens.Space.group)) {
                stat(L10n.text("THIS WEEK"), Self.duration(activity.thisWeek))
                bars
            }
            if !topGames.isEmpty {
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                    activityHeading("MOST PLAYED")
                    HStack(spacing: canvas.u(SeleneTokens.Space.line)) {
                        ForEach(Array(topGames.enumerated()), id: \.element.id) { index, game in
                            activityTile(game, focused: focusedTop == index)
                                .onTapGesture { onTopGame(index) }
                        }
                    }
                    .padding(canvas.u(SeleneTokens.Space.tight))
                    .padding(canvas.u(-SeleneTokens.Space.tight))
                }
            }
            if let recentBuilds {
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                    activityHeading("Recently built")
                    if recentBuilds.isEmpty {
                        Text(L10n.text("No completed builds yet."))
                            .seleneFont(.text)
                            .foregroundStyle(SeleneTheme.ink75)
                    } else {
                        HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.line)) {
                            ForEach(recentBuilds, id: \.game.id) { item in
                                buildTile(item.game, date: item.date)
                            }
                        }
                    }
                }
            }
        }
    }

    private func activityHeading(_ title: String) -> some View {
        Text(L10n.text(title))
            .textCase(.uppercase)
            .seleneFont(.text, .semibold)
            .foregroundStyle(SeleneTheme.ink60)
            .accessibilityAddTraits(.isHeader)
    }

    private func buildTile(_ game: PortedGame, date: Date) -> some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.tight)) {
            activityTile(game, focused: false)
            Text(date.formatted(.dateTime.day().month(.abbreviated).locale(locale.formatLocale)))
                .seleneFont(.text)
                .foregroundStyle(SeleneTheme.ink75)
                .lineLimit(1)
        }
        .frame(width: canvas.u(SeleneTokens.Space.chromeGutter))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityValue(date.formatted(.dateTime.day().month().year().locale(locale.formatLocale)))
        .help(game.name)
    }

    private var bars: some View {
        let peak = max(activity.perDay.max() ?? 0, 1)
        let days = Self.dayLetters
        return HStack(alignment: .bottom, spacing: canvas.u(SeleneTokens.Space.small)) {
            ForEach(0..<7, id: \.self) { day in
                let value = day < activity.perDay.count ? activity.perDay[day] : 0
                VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                    RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.cover), style: .continuous)
                        .fill(value > 0 ? SeleneTheme.focus : SeleneTheme.ink15)
                        .frame(width: canvas.u(22), height: canvas.u(value > 0 ? max(6, 56 * value / peak) : 4))
                    Text(days[day]).seleneFont(.badge, .semibold).foregroundColor(SeleneTheme.ink60)
                }
            }
        }
        .frame(height: canvas.u(80), alignment: .bottom)
    }

    private func activityTile(_ game: PortedGame, focused: Bool) -> some View {
        let side = canvas.u(SeleneTokens.Space.chromeGutter)
        let shape = RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.row), style: .continuous)
        return SpotlightTileArtwork(game: game, side: side,
                                    artwork: artwork)
            .clipShape(shape)
            .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
            .oortRing(focused, radius: canvas.u(SeleneTokens.Radius.row), gap: canvas.u(SeleneTokens.Space.hairline))
            .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
            .animation(reduceMotion ? nil : SeleneTheme.quick, value: focused)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
            Text(L10n.text(label)).seleneFont(.badge, .semibold).foregroundColor(SeleneTheme.ink60)
            Text(value).seleneFont(.row, .semibold).foregroundColor(SeleneTheme.ink)
        }
    }

    private var divider: some View {
        Rectangle().fill(SeleneTheme.ink25).frame(width: max(1, canvas.u(1)), height: canvas.u(36))
    }

    private func actionChip(_ label: String) -> some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            SelenePromptBadge(button: .a)
            Text(L10n.text(label)).seleneFont(.text).foregroundColor(SeleneTheme.ink90)
        }
    }

    /// "0 min", "42 min", "3 h 20 min".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        if minutes < 60 { return L10n.format("%@ min", [String(describing: minutes)]) }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : L10n.format("%@ h %@ min", [String(describing: minutes / 60), String(describing: rest)])
    }
}

/// The card's Y menu: Move, Hide card.
struct SpotlightCardMenu: View {
    @Environment(\.seleneCanvas) private var canvas

    static var rows: [(title: String, subtitle: String, icon: MaterialIcon)] { [
        ("Move", L10n.text("Change its place on Spotlight"), .swap),
        (L10n.text("Hide card"), L10n.text("Bring it back in Settings"), .hidden)
    ] }

    let card: SpotlightCard
    let focusedIndex: Int
    let onFocus: (Int) -> Void
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
            Text(L10n.text(card.title)).seleneFont(.heading, .semibold).foregroundColor(SeleneTheme.ink)
            VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    let focused = index == focusedIndex
                    HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                        MaterialIconView(row.icon, size: 28)
                        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                            Text(row.title).seleneFont(.row, .semibold)
                            Text(row.subtitle).seleneFont(.text)
                                .foregroundColor(focused ? SeleneTheme.onFocus.opacity(SeleneTokens.Alpha.heavy) : SeleneTheme.ink60)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(focused ? SeleneTheme.onFocus : SeleneTheme.ink)
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.panel))
                    .frame(height: canvas.u(68))
                    .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous)
                        .fill(focused ? SeleneTheme.focus.opacity(SeleneTokens.Alpha.near) : Color.clear))
                    .contentShape(Rectangle())
                    .seleneHover { onFocus(index) }
                    .onTapGesture { onFocus(index); onChoose(index) }
                }
            }
        }
        .padding(canvas.u(SeleneTokens.Space.large))
        .frame(width: canvas.u(560))
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.modal), floats: true)
        .accessibilityElement(children: .contain)
    }
}
