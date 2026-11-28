import SwiftUI
import OortLibrary
import NxnativeAdapter

extension EnvironmentValues {
    @Entry var integrationBar: AnyView? = nil
}

/// Observe the owners directly and say what they observe as the core's facts; the same facts feed the home bar and
/// the page.
struct IntegrationSurface: View {
    var router: AppRouter
    var sources: CatalogSourcesModel
    @ObservedObject var app: AppViewModel
    @ObservedObject var setup: SetupModel
    @ObservedObject var cloud: CloudLibraryModel
    var settings: AppSettingsStore
    @ObservedObject var igdb: IGDBSettings
    let nextendo: NextendoSettings?
    let isBar: Bool
    @StateObject private var question = ScreenQuestion()

    var body: some View {
        if let nextendo {
            IntegrationAccountSurface(account: nextendo, show: surface)
        } else {
            surface(.noLocalProfile)
        }
    }

    private func surface(_ account: IntegrationFacts.Account) -> some View {
        let data = facts(account)
        return Group {
            if isBar {
                IntegrationBar(rows: data.rows, focused: router.integrationBarFocused, open: router.openIntegrations)
            } else {
                IntegrationsPage(facts: data, router: router, question: question, toggle: toggle)
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

    private func facts(_ account: IntegrationFacts.Account) -> IntegrationFacts {
        var data = IntegrationOverview.mac
        if setup.isCheckingEnvironment { data.engine = .checking }
        else if setup.isNxnativeValid {
            data.engine = (setup.compatibilityReport != nil && !setup.canPassToolchainGate)
                || setup.environmentStatus?.canBuild == false ? .blocked : .detected
        }
        data.engineCommit = setup.versions.selected.value
        data.expectedEngineCommit = setup.versions.expected
        data.keys = IntegrationOverview.keys(setup.localKeyStatus)
        data.xcodeVersion = setup.environmentStatus?.xcodeVersion
        data.metalVersion = setup.environmentStatus?.metalVersion
        data.buildBlock = IntegrationOverview.buildBlock(setup.compatibilityReport, canPass: setup.canPassToolchainGate,
                                                         canBuild: setup.environmentStatus?.canBuild)
        data.appleToolsTested = setup.compatibilityReport.map { $0.metal == .same }
        data.hasSwitchGames = app.visibleCatalogGames.contains { $0.integration == .nxnative && !$0.isHidden }
        data.steam = IntegrationOverview.steam(sources)
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
        data.saves = IntegrationOverview.saves(settings.settings.cloudSaves)
        return data
    }
}

private struct IntegrationAccountSurface<Content: View>: View {
    @ObservedObject var account: NextendoSettings
    let show: (IntegrationFacts.Account) -> Content

    var body: some View { show(status) }

    private var status: IntegrationFacts.Account {
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

/// Settings › Integrations on the Mac: the core's screens (IntegrationScreen) drawn by ScreenView, their focus kept by
/// the router, their intents done by the Mac's effects table.
struct IntegrationsPage: View {
    let facts: IntegrationFacts
    var router: AppRouter
    @ObservedObject var question: ScreenQuestion
    var showsHints = true
    /// Asks the owner for the other state of an entry's switch; false when the owner refuses (a settings draft waits).
    var toggle: (IntegrationID) -> Bool = { _ in false }

    var screen: Screen {
        router.integrationDetail.flatMap { IntegrationScreen.detail($0, facts) } ?? IntegrationScreen.list(facts)
    }

    /// The list keeps its focused entry, the detail its focused node: both in the router, so B comes back to them.
    private var focus: Binding<String?> {
        router.integrationDetail == nil
            ? Binding(get: { router.integrationFocus?.rawValue }, set: { router.integrationFocus = $0.flatMap(IntegrationID.init(rawValue:)) })
            : Binding(get: { router.integrationAction }, set: { router.integrationAction = $0 })
    }

    private var view: ScreenView {
        ScreenView(screen: screen, focus: focus, question: question,
                   restoreScroll: router.integrationDetail == nil && router.isReturningFromBack, showsHints: showsHints,
                   platform: Self.platform, perform: perform)
    }

    var body: some View {
        view.onReceive(NotificationCenter.default.publisher(for: .nxIntegrationsAction)) { note in
            guard router.route == .integrations, let action = note.object as? GamepadAction else { return }
            handle(action)
        }
    }

    func handle(_ action: GamepadAction) { view.handle(action) }

    /// The Mac's effect of each intent, complete for IntegrationTarget: the targets the Mac does not offer are refused.
    func perform(_ intent: Screen.Intent) -> ScreenOutcome {
        switch intent {
        case .open(let id):
            guard let id = IntegrationID(rawValue: id), facts.row(id) != nil else { return .refused(nil) }
            router.showIntegrationDetail(id)
            if router.integrationDetail != id { return .refused(nil) }
        case .back:
            router.backFromIntegration()
        case .toggle(let id):
            guard let id = IntegrationID(rawValue: id), facts.row(id)?.switchOn != nil, toggle(id) else { return .refused(nil) }
        case .owner(let target):
            guard let target = IntegrationTarget(rawValue: target), let id = router.integrationDetail else { return .refused(nil) }
            switch target {
            case .settings: if !IntegrationOverview.open(id, facts, in: router) { return .refused(nil) }
            case .switchGames: router.browseIntegrationLibrary(.nxnative)
            case .steamGames: router.browseIntegrationLibrary(.steam)
            case .programs, .clearOnline: return .refused(nil)
            }
        }
        return .done
    }

    /// The Mac's picture of each entry, by its identity: the Mac keeps its PlatformKind table.
    static func platform(_ icon: String) -> PlatformKind? {
        switch IntegrationID(rawValue: icon) {
        case .switchGames?: .switch1
        case .steam?: .steam
        case .macApps?: .mac
        case .drive?: .drive
        case .nextendo?: .nextendo
        case .images?: .images
        case .saves?: .saves
        case .programs?, .online?, nil: nil
        }
    }
}
