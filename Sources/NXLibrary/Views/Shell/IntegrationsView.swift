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
            HStack(spacing: canvas.u(12)) {
                Image(systemName: "link")
                    .seleneFont(.row)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: canvas.u(2)) {
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
            .overlay(Capsule().strokeBorder(SeleneTheme.ink15, lineWidth: 1))
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
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    @AccessibilityFocusState(for: .voiceOver) private var accessibilityFocus: IntegrationID?
    let overview: IntegrationOverview
    @ObservedObject var router: AppRouter
    var showsHints = true

    private func text(_ key: String) -> String { L10n.text(key, context: locale) }

    var body: some View {
        let rows = overview.rows
        OortPage(title: text("Integrations"), preset: .legacyBackdrop,
                 scrollFocus: router.integrationFocus, initialFocus: rows.first?.id,
                 restoreScroll: router.isReturningFromBack,
                 back: showsHints ? HintItem(.b, text("Back"), action: router.back) : nil,
                 confirm: showsHints ? HintItem(.a, text("Open")) { handle(.confirm) } : nil) {
            ForEach(rows) { row($0).id($0.id) }
            comingLater
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxIntegrationsAction)) { note in
            guard router.route == .integrations, let action = note.object as? GamepadAction else { return }
            handle(action)
        }
        .onAppear { accessibilityFocus = router.integrationFocus }
    }

    private var comingLater: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            Text(text("Coming later")).seleneFont(.row, .semibold)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: canvas.u(220)), alignment: .leading)],
                      alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                ForEach(PlatformKind.upcoming, id: \.self) { platform in
                    PlatformLabel(platform, preset: .listing)
                }
            }
            .foregroundStyle(SeleneTheme.ink75)
        }
        .padding(canvas.u(SeleneTokens.Space.titleGap))
    }

    private func row(_ row: IntegrationRow) -> some View {
        let focus = router.integrationFocus == row.id
        let color: Color = switch row.emphasis {
        case .attention: SeleneTheme.untested
        case .working: SeleneTheme.statusCloud
        case .neutral: SeleneTheme.ink75
        }
        return VStack(alignment: .leading, spacing: canvas.u(9)) {
            HStack(alignment: .top, spacing: canvas.u(12)) {
                Group {
                    switch row.id {
                    case .switchGames: PlatformLabel(.switch1, title: text(row.name))
                    case .steam: PlatformLabel(.steam)
                    case .drive: PlatformLabel(.drive)
                    case .nextendo: PlatformLabel(.nextendo, title: text(row.name))
                    case .images: PlatformLabel(.images, title: text(row.name))
                    case .saves: PlatformLabel(.saves, title: text(row.name))
                    }
                }
                .accessibilityAddTraits(.isHeader)
                Spacer()
                SeleneStatusDot(text: text(row.status), color: color, labelColor: SeleneTheme.ink90)
            }
            Text(text(row.purpose)).seleneFont(.text)
            VStack(alignment: .leading, spacing: canvas.u(4)) {
                access("Reads: %@", row.reads)
                access("Writes: %@", row.writes)
                access("Sends: %@", row.sends)
            }
            .foregroundStyle(SeleneTheme.ink82)
            SelenePillButton(title: row.action, minWidth: 0, height: 42, titleSize: .text,
                             horizontalPadding: 16, focused: focus, scalesOnFocus: false) {
                overview.open(row.id, in: router)
            }
            .accessibilityHint(text(row.name))
            .accessibilityAddTraits(focus ? .isSelected : [])
            .accessibilityFocused($accessibilityFocus, equals: row.id)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(canvas.u(SeleneTokens.Space.panel))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeleneTheme.glass, in: RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.rowRadius)))
        .overlay {
            RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.rowRadius))
                .strokeBorder(focus ? SeleneTheme.focus : SeleneTheme.ink15, lineWidth: focus ? 2 : 1)
                .allowsHitTesting(false)
        }
    }

    private func access(_ key: String, _ value: String) -> some View {
        Text(L10n.format(key, [text(value)], context: locale)).seleneFont(.text)
    }
}
