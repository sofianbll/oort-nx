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
                IntegrationsView(overview: data, router: router, toggle: toggle)
            }
        }
    }

    /// Steam's switch, from the list: the same choice Settings › Sources saves, written as one committed field and
    /// applied by the shell as a saved choice is. Refused, with nothing written, when the catalogue changed since it was
    /// shown, when the write fails, or while a settings draft waits.
    private func toggle(_ id: IntegrationID) -> Bool {
        guard id == .steam, !router.hasPendingSettings() else { return false }
        let current = sources.configuration
        guard (try? app.catalogRepository.load().source(.steam)?.generation) == current.generation else { return false }
        var change = AppSettingsDraft(settings.settings, fields: [
            .init(SteamSourceEntries.sourceID, \.launcherChoices.steamSource) { _ in "" }
        ])
        change.values.launcherChoices.steamSource = SteamSourceEntries.flipped(current, root: sources.discoveryRoot)
        return (try? settings.commit(change)) != nil
    }

    private func overview(_ account: IntegrationOverview.Account) -> IntegrationOverview {
        var data = IntegrationOverview()
        if setup.isCheckingEnvironment { data.engine = .checking }
        else if setup.isNxnativeValid {
            data.engine = (setup.compatibilityReport != nil && !setup.canPassToolchainGate)
                || setup.environmentStatus?.canBuild == false ? .blocked : .detected
        }
        data.engineCommit = setup.versions.selected.value
        data.expectedEngineCommit = setup.versions.expected
        data.keyStatus = setup.localKeyStatus
        data.xcodeVersion = setup.environmentStatus?.xcodeVersion
        data.metalVersion = setup.environmentStatus?.metalVersion
        data.buildBlock = IntegrationOverview.buildBlock(setup.compatibilityReport, canPass: setup.canPassToolchainGate,
                                                         canBuild: setup.environmentStatus?.canBuild)
        data.appleToolsTested = setup.compatibilityReport.map { $0.metal == .same }
        data.hasSwitchGames = app.visibleCatalogGames.contains { $0.integration == .nxnative && !$0.isHidden }
        data.steam = sources.status
        data.steamEnabled = sources.configuration.isEnabled
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
        data.driveCheckDate = cloud.connectionCheck?.date
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
                        Text(L10n.text(summary.barStatus, context: locale))
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
            .background(OortKeyFace(kind: focused ? .solid : .quiet, radius: canvas.u(SeleneTokens.Radius.field), lit: focused, outlined: false))
            .frame(maxWidth: canvas.u(385), alignment: .leading)
        }
        .buttonStyle(OortPressStyle())
        .accessibilityLabel(L10n.text("Integrations", context: locale))
        .accessibilityValue(summary.map {
            "\(L10n.text($0.barName, context: locale)): \(L10n.text($0.barStatus, context: locale))"
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
    @AccessibilityFocusState(for: .voiceOver) private var accessibilityAction: IntegrationDetailAction?
    let overview: IntegrationOverview
    @ObservedObject var router: AppRouter
    var showsHints = true
    /// Asks the owner for the other state of an entry's switch; false when the owner refuses (a settings draft waits).
    var toggle: (IntegrationID) -> Bool = { _ in false }

    private func text(_ key: String) -> String { L10n.text(key, context: locale) }
    private func text(_ words: IntegrationWords) -> String { L10n.format(words.key, words.args, context: locale) }
    var catalogueFocus: IntegrationID? { router.integrationFocus ?? overview.sections.first?.entries.first?.id }

    var body: some View {
        Group {
            if let id = router.integrationDetail, let row = overview.row(id) {
                detail(row)
            } else {
                let sections = overview.sections
                OortPage(title: text("Integrations"), scrollFocus: router.integrationFocus,
                          initialFocus: sections.first?.entries.first?.id, restoreScroll: router.isReturningFromBack,
                          back: backHint, confirm: confirmHint(IntegrationCatalog.open.key), extra: switchHint) {
                    ForEach(sections) { section in
                        OortSection(title: text(section.id.title.key)) {
                            ForEach(section.entries) { summary($0) }
                            if let upcoming = section.upcoming { OortReadout(text: text(upcoming), preset: .quiet) }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxIntegrationsAction)) { note in
            guard router.route == .integrations, let action = note.object as? GamepadAction else { return }
            handle(action)
        }
        .onChange(of: router.integrationDetail, initial: true) { _, detail in
            accessibilityFocus = detail == nil ? catalogueFocus : nil
            accessibilityAction = detail.flatMap(overview.row).flatMap(detailFocus)
        }
        .onChange(of: router.integrationAction) { _, action in
            if router.integrationDetail != nil { accessibilityAction = action }
        }
    }

    private var backHint: HintItem? {
        showsHints ? HintItem(.b, text("Back"), action: router.backFromIntegration) : nil
    }

    private func confirmHint(_ title: String) -> HintItem? {
        showsHints ? HintItem(.a, text(title)) { handle(.confirm) } : nil
    }

    /// X on a row with a switch: the other state, said for the focused row.
    private var switchHint: HintItem? {
        guard showsHints, router.integrationDetail == nil, let id = catalogueFocus,
              let on = overview.row(id)?.switchOn else { return nil }
        return HintItem(.x, text(IntegrationCatalog.toggle(on: on).key)) { handle(.secondaryAction) }
    }

    private func summary(_ row: IntegrationRow) -> some View {
        OortRow(title: text(row.name), platform: platform(row.id), about: text(row.id.capabilities.key),
                status: text(row.status), focused: catalogueFocus == row.id, tone: tone(row),
                isOn: row.switchOn.map { on in Binding(get: { on }, set: { _ in flip(row.id) }) },
                preset: .navigation(label: text(IntegrationCatalog.open.key)) { router.showIntegrationDetail(row.id) })
            .id(row.id)
            .accessibilityFocused($accessibilityFocus, equals: row.id)
            .accessibilityActions {
                if let on = row.switchOn {
                    Button(text(IntegrationCatalog.toggle(on: on).key)) { flip(row.id) }
                }
            }
    }

    private func detail(_ row: IntegrationRow) -> some View {
        let action = detailFocus(row)
        return OortPage(title: text(row.name), scrollFocus: router.integrationAction, initialFocus: row.actions.last,
                        back: backHint, confirm: action.map { confirmHint(row.title(of: $0)) } ?? nil) {
            OortReadout(text: text(row.purpose), preset: .lead)
            // One box per step (IntegrationCatalog.steps): title, sentences, then its buttons under them, aligned.
            ForEach(row.steps) { step in
                OortCard(step.id.title.key) {
                    ForEach(Array(step.content.enumerated()), id: \.offset) { _, item in
                        switch item {
                        case .say(let words):
                            OortReadout(text: text(words))
                        case .words(let words):
                            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                                OortReadout(text: text(word))
                            }
                        case .status:
                            OortStatus(text: text(row.status), tone: tone(row))
                        case .date(let date):
                            OortReadout(text: L10n.format("Checked: %@", [
                                date.formatted(.dateTime.year().month().day().hour().minute().locale(locale.formatLocale))
                            ], context: locale), preset: .quiet)
                        case .access:
                            ForEach([(IntegrationCatalog.reads, row.reads), (IntegrationCatalog.writes, row.writes),
                                     (IntegrationCatalog.sends, row.sends)], id: \.0.key) { label, value in
                                OortReadout(text: L10n.format(label.key, [text(value)], context: locale))
                            }
                        case .action(let choice):
                            OortButton(title: row.title(of: choice), focused: choice == action, preset: .compact) {
                                activate(choice, for: row)
                            }
                            .accessibilityFocused($accessibilityAction, equals: choice)
                            .id(choice)
                        }
                    }
                }
            }
        }
    }

    private func platform(_ id: IntegrationID) -> PlatformKind? {
        switch id {
        case .switchGames: .switch1
        case .steam: .steam
        case .macApps: .mac
        case .drive: .drive
        case .nextendo: .nextendo
        case .images: .images
        case .saves: .saves
        case .programs, .online: nil
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
