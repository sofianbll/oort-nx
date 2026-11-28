import SwiftUI
import OortLibrary

/// One stat in the row: a label over a value, or the platform (icon and name).
struct SeleneStat: Identifiable {
    enum Value {
        case text(String)
        case platform(String)
        case nextendo(String)
    }

    let label: String
    let value: Value

    var id: String { label }

    static func text(_ label: String, _ value: String) -> SeleneStat {
        SeleneStat(label: label, value: .text(value))
    }

    static func platform(_ console: String) -> SeleneStat { SeleneStat(label: L10n.text("PLATFORM"), value: .platform(console)) }
}

/// Selene's at-a-glance stats line, with a 1u rule between items. Spotlight and
/// Collection use the default order and 26 either side of each rule; Details
/// passes its own items and a 28 gap. The caller places it.
struct SeleneStatsRow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.onlinePlayersByTitle) private var onlinePlayers
    @Environment(\.onlinePlayersDisplay) private var onlineDisplay
    @Environment(\.nxAppLocale) private var localization

    let items: [SeleneStat]
    /// The selected game, whose online players join the row when the player chose that place.
    var onlineTitleID: String? = nil
    var onlinePlace: OnlinePlayersDisplay.Place = .selectedGame
    /// Space either side of each rule, in Selene units.
    var gap: CGFloat = 26

    /// PLAYTIME · LAST PLAYED · PLATFORM · RELEASED (Spotlight, Collection).
    init(presentation: LibraryPresentation, onlineTitleID: String? = nil) {
        var items = [
            SeleneStat.text(L10n.text("PLAYTIME"), presentation.playtime),
            SeleneStat.text(L10n.text("LAST PLAYED"), presentation.lastPlayed),
            SeleneStat.platform(presentation.console)
        ]
        if let year = presentation.releaseYear {
            items.append(SeleneStat.text(L10n.text("RELEASED"), year))
        }
        self.items = items
        self.onlineTitleID = onlineTitleID
    }

    init(items: [SeleneStat], gap: CGFloat = 26, onlineTitleID: String? = nil,
         onlinePlace: OnlinePlayersDisplay.Place = .selectedGame) {
        self.items = items
        self.gap = gap
        self.onlineTitleID = onlineTitleID
        self.onlinePlace = onlinePlace
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { divider }
                stat(item)
            }
            if let count = onlineDisplay.count(for: onlineTitleID, in: onlinePlayers, at: onlinePlace) {
                divider
                stat(.init(label: "Multiplayer",
                           value: .nextendo(OnlinePlayersDisplay.label(for: count, context: localization))))
            }
        }
        .fixedSize()
        .oortShadow(.text)
    }

    private func stat(_ item: SeleneStat) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
            // Line boxes of Selene's Segoe UI 12 / 21 (16 and 28), so the strip lands 34 below.
            Text(L10n.text(item.label))
                .seleneFont(.badge, .semibold)
                .foregroundColor(SeleneTheme.ink82)
                .frame(height: canvas.u(16), alignment: .leading)
            Group {
                switch item.value {
                case .text(let text):
                    value(text)
                case .nextendo(let text):
                    HStack(spacing: canvas.u(SeleneTokens.Space.hairline)) {
                        SeleneStatusMark(color: SeleneTheme.statusOK, pulses: false)
                        value(text)
                    }
                case .platform(let console):
                    if let platform = PlatformKind(rawValue: console) {
                        PlatformLabel(platform).foregroundStyle(SeleneTheme.ink)
                    } else {
                        value(console)
                    }
                }
            }
            .frame(minHeight: canvas.u(28))
        }
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String) -> some View {
        Text(text).seleneFont(.row, .semibold).foregroundColor(SeleneTheme.ink)
    }

    /// 1u ink25 rule, inset 4 top and bottom.
    private var divider: some View {
        Rectangle()
            .fill(SeleneTheme.ink25)
            .frame(width: max(1, canvas.u(1)))
            .padding(.vertical, canvas.u(SeleneTokens.Space.hairline))
            .padding(.horizontal, canvas.u(gap))
    }
}
