import SwiftUI
import NXLibraryCore
import ArcanePorting

extension EnvironmentValues {
    @Entry var integrationBar: AnyView? = nil
}

/// Observe the owners directly; the same throwaway projection feeds the home bar and the page.
struct IntegrationSurface: View {
    @ObservedObject var router: AppRouter
    @ObservedObject var sources: CatalogSourcesModel
    @ObservedObject var app: AppViewModel
    @ObservedObject var setup: SetupModel
    @ObservedObject var cloud: CloudLibraryModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var igdb: IGDBSettings
    let nextendo: NextendoSettings?
    let isBar: Bool

    var body: some View {
        if let nextendo {
            IntegrationAccountSurface(account: nextendo, show: surface)
        } else {
            surface(.noLocalProfile)
        }
    }

    private func surface(_ account: IntegrationOverview.Account) -> some View {
        let data = overview(account)
        return Group {
            if isBar {
                IntegrationBar(rows: data.rows, focused: router.integrationBarFocused, open: router.openIntegrations)
            } else {
                IntegrationsView(overview: data, router: router)
            }
        }
    }

    private func overview(_ account: IntegrationOverview.Account) -> IntegrationOverview {
        var data = IntegrationOverview()
        if setup.isCheckingEnvironment { data.engine = .checking }
        else if setup.isNxnativeValid {
            data.engine = (setup.compatibilityReport != nil && !setup.canPassToolchainGate)
                || setup.environmentStatus?.canBuild == false ? .blocked : .detected
        }
        data.steam = sources.status
        data.steamGameCount = sources.observedGameCount
        data.hasMacShortcuts = app.catalogGames.contains { $0.macShortcut != nil }
        if cloud.preference.remote == nil { data.drive = .notConfigured }
        else if !cloud.preference.enabled { data.drive = .off }
        else if cloud.active != nil || cloud.libraryMove != nil { data.drive = .transferring }
        else if cloud.queuePause != nil { data.drive = .paused }
        else if cloud.importTask != nil || cloud.isChangingConnection { data.drive = .checking }
        else if cloud.connectionCheck?.failure != nil || cloud.checkFailure != nil { data.drive = .failed }
        else if cloud.connectionCheck != nil { data.drive = .checked }
        else { data.drive = .unchecked }
        data.nextendo = account
        data.steamGridDB = app.hasSteamGridDBKey
        data.igdb = igdb.isConfigured
        data.saves = settings.settings.cloudSaves
        return data
    }
}

private struct IntegrationAccountSurface<Content: View>: View {
    @ObservedObject var account: NextendoSettings
    let show: (IntegrationOverview.Account) -> Content

    var body: some View { show(status) }

    private var status: IntegrationOverview.Account {
        if account.isBusy { return .checking }
        return switch account.status {
        case .signedOut: account.failure == nil ? .unchecked : .unavailable
        case .signedIn: .connected
        case .expired: .expired
        case .unavailable: .unavailable
        }
    }
}

struct IntegrationBar: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    @AccessibilityFocusState(for: .voiceOver) private var accessibilityFocus: Bool
    let rows: [IntegrationRow]
    let focused: Bool
    let open: () -> Void

    private var summary: IntegrationRow? {
        rows.first { $0.emphasis == .attention } ?? rows.first { $0.emphasis == .working }
            ?? rows.first { $0.id == .steam }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                Image(systemName: "link")
                    .seleneFont(.row)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                    Text(L10n.text("Integrations", context: locale)).seleneFont(.row, .semibold)
                    if let summary {
                        Text(L10n.text(summary.status, context: locale))
                            .seleneFont(.text)
                            .foregroundStyle(focused ? SeleneTheme.onFocus : SeleneTheme.ink82)
                    }
                }
                Image(systemName: "chevron.right").seleneFont(.text).accessibilityHidden(true)
            }
            .lineLimit(1)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.control))
            .padding(.vertical, canvas.u(SeleneTokens.Space.compact))
            .foregroundStyle(focused ? SeleneTheme.onFocus : SeleneTheme.ink)
            .background(focused ? SeleneTheme.focus : SeleneTheme.glassSolid, in: Capsule())
            .overlay(Capsule().strokeBorder(SeleneTheme.ink15, lineWidth: SeleneTokens.Space.thinStroke))
            .frame(maxWidth: canvas.u(385), alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("Integrations", context: locale))
        .accessibilityValue(summary.map {
            "\(L10n.text($0.name, context: locale)): \(L10n.text($0.status, context: locale))"
        } ?? "")
        .accessibilityAddTraits(focused ? .isSelected : [])
        .accessibilityFocused($accessibilityFocus)
        .onChange(of: focused, initial: true) { _, focused in
            if focused { accessibilityFocus = true }
        }
    }
}

struct IntegrationsView: View {
    @Environment(\.nxAppLocale) private var locale
    @AccessibilityFocusState(for: .voiceOver) private var accessibilityFocus: IntegrationID?
    let overview: IntegrationOverview
    @ObservedObject var router: AppRouter
    var showsHints = true

    private func text(_ key: String) -> String { L10n.text(key, context: locale) }

    var body: some View {
        Group {
            if let id = router.integrationDetail {
                detail(overview.row(id))
            } else {
                let rows = overview.rows
                OortPage(title: text("Integrations"), scrollFocus: router.integrationFocus,
                         initialFocus: rows.first?.id, restoreScroll: router.isReturningFromBack,
                         back: backHint, confirm: confirmHint("Open")) {
                    OortSection(title: text("Games")) {
                        ForEach(rows.filter { $0.id.isGameSource }) { summary($0) }
                        OortReadout(text: text("Coming later") + ": " + PlatformKind.upcoming.map {
                            text($0.rawValue)
                        }.joined(separator: " · "), preset: .quiet)
                    }
                    OortSection(title: text("Integration services")) {
                        ForEach(rows.filter { !$0.id.isGameSource }) { summary($0) }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxIntegrationsAction)) { note in
            guard router.route == .integrations, let action = note.object as? GamepadAction else { return }
            handle(action)
        }
        .onChange(of: router.integrationDetail, initial: true) { _, detail in
            accessibilityFocus = detail ?? router.integrationFocus
        }
    }

    private var backHint: HintItem? {
        showsHints ? HintItem(.b, text("Back"), action: router.backFromIntegration) : nil
    }

    private func confirmHint(_ title: String) -> HintItem? {
        showsHints ? HintItem(.a, text(title)) { handle(.confirm) } : nil
    }

    private func summary(_ row: IntegrationRow) -> some View {
        OortRow(title: text(row.name), platform: platform(row.id), status: text(row.status),
                focused: router.integrationFocus == row.id, tone: tone(row),
                preset: .navigation(label: text("Details")) { router.showIntegrationDetail(row.id) })
            .id(row.id)
            .accessibilityFocused($accessibilityFocus, equals: row.id)
    }

    private func detail(_ row: IntegrationRow) -> some View {
        OortPage<IntegrationID, _>(title: text(row.name), back: backHint, confirm: confirmHint("Open")) {
            OortCard {
                OortStatus(text: text(row.status), tone: tone(row))
                OortReadout(text: text(row.purpose))
                ForEach([("Reads: %@", row.reads), ("Writes: %@", row.writes), ("Sends: %@", row.sends)], id: \.0) { key, value in
                    OortReadout(text: L10n.format(key, [text(value)], context: locale))
                }
            }
            OortButton(title: row.action, focused: true, preset: .compact) {
                overview.open(row.id, in: router)
            }
            .accessibilityFocused($accessibilityFocus, equals: row.id)
        }
    }

    private func platform(_ id: IntegrationID) -> PlatformKind {
        switch id {
        case .switchGames: .switch1
        case .steam: .steam
        case .macApps: .mac
        case .drive: .drive
        case .nextendo: .nextendo
        case .images: .images
        case .saves: .saves
        }
    }

    private func tone(_ row: IntegrationRow) -> OortStatus.Tone {
        switch row.emphasis {
        case .attention: .attention
        case .working: .working
        case .neutral: .neutral
        }
    }
}
