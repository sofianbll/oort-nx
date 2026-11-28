import SwiftUI
import AppKit
import OortLibrary

@MainActor
struct SettingsSourcesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: SettingsEditor
    @Environment(CatalogSourcesModel.self) private var sources
    @Environment(\.nxAppLocale) private var localization
    let onOpenIntegrations: () -> Void
    let onActions: ([SettingsRowAction]) -> Void

    private var staged: SteamSourceChoice? {
        let choice = settings.settings.launcherChoices.steamSource
        return choice == settings.store.settings.launcherChoices.steamSource ? nil : choice
    }
    private var root: URL { staged?.root ?? sources.discoveryRoot }
    /// Steam's rows, decided once (NXLibraryCore/Steam/SteamSourceEntries.swift) for the drawing and for the focus.
    private var steam: SteamSourceEntries.MacRows {
        SteamSourceEntries.mac(applied: sources.configuration.isEnabled, staged: staged?.enabled, status: sources.status,
                               found: sources.observedGameCount, root: root.path)
    }
    private var hidden: [CatalogGame] { viewModel.catalogGames.filter { $0.integration == .steam && $0.isHidden } }
    private var review: [CatalogGame] {
        viewModel.catalogGames.filter { !$0.isHidden && $0.steamGame?.needsReview == true }
    }
    var body: some View {
        OortSettingsGroup {
            SeleneButtonRow("All integrations", id: "integrations",
                            subtitle: "See what each one reads, writes and sends.",
                            buttonTitle: "Open", action: onOpenIntegrations)
            SeleneButtonRow("Mac apps", id: "macShortcutAdd",
                            subtitle: "Add a shortcut to an app on this Mac. The app stays where it is.",
                            platform: .mac,
                            buttonTitle: "Add an app…") { viewModel.macShortcuts.chooseApp() }
                .disabled(!viewModel.macShortcuts.canEdit)
            ForEach(steam.all, id: \.id, content: row)
            SettingsSubheading("Play")
            SeleneToggleRow("Keep Steam in the background",
                            subtitle: "Steam starts quietly when possible and comes forward if it needs you.",
                            info: "When Play opens Steam, it starts quietly. The waiting screen stays visible while the game starts. Steam comes forward if it needs input or the game takes too long.",
                            isOn: $settings.settings.steamInBackground)
            if let error = sources.errorMessage {
                Text(error).seleneFont(.text).foregroundColor(SeleneTheme.danger)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(SeleneTokens.Space.large)
            }
            if sources.reviewCount > 0 {
                Text(L10n.count("%lld Steam games need review", sources.reviewCount, context: localization))
                    .seleneFont(.text).foregroundColor(SeleneTheme.ink).padding(.vertical, SeleneTokens.Space.gap)
            }
            if !review.isEmpty {
                SettingsSubheading("Review installations")
                Text(L10n.text("Check these installations in Steam, then refresh this source. Only recognized native Mac games appear in the library.", context: localization))
                    .seleneFont(.text).foregroundColor(SeleneTheme.ink).fixedSize(horizontal: false, vertical: true)
                ForEach(review) { game in
                    SeleneRow(game.name, id: "review-\(game.id)", subtitle: "Needs review", verbatimTitle: true) {
                        Button(L10n.text("Reveal", context: localization)) { reveal(game) }.buttonStyle(OortPressStyle()).foregroundColor(SeleneTheme.glyph)
                    }
                }
            }
            if !hidden.isEmpty {
                SettingsSubheading("Hidden Steam games")
                ForEach(hidden) { game in
                    SeleneRow(game.name, id: "hidden-\(game.id)", subtitle: "Hidden from the library", verbatimTitle: true) {
                        Button(L10n.text("Show", context: localization)) { viewModel.setCatalogHidden(false, game: game) }
                            .buttonStyle(OortPressStyle()).foregroundColor(SeleneTheme.glyph)
                    }
                }
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: sources.status) { publishActions() }
        .onChange(of: sources.configuration) { publishActions() }
        .onChange(of: viewModel.catalogGames) { publishActions() }
    }
    /// The Selene row of each kind of entry: what it says and what A asks are the entry's.
    @ViewBuilder private func row(_ entry: IntegrationEntry) -> some View {
        switch entry.control {
        case .toggle(let checked):
            SeleneToggleRow(entry.title.key, subtitle: entry.about?.key, info: entry.info?.key,
                            platform: entry.icon.flatMap(PlatformKind.init(rawValue:)),
                            isOn: Binding(get: { checked }, set: { _ in ask(entry) }))
        case .button(let button):
            SeleneButtonRow(entry.title.key, subtitle: entry.about.map(words), buttonTitle: button.key) { ask(entry) }
                .disabled(entry.request == nil)
        case .value(let value, let button):
            SeleneValueRow(entry.title.key, subtitle: entry.about?.key, value: value, actionTitle: button.key) { ask(entry) }
        case .row, .open:
            EmptyView()  // Steam's Mac rows are a switch, a button and a value (IntegrationEntryTests).
        }
    }
    private func words(_ words: IntegrationWords) -> String {
        words.count.map { L10n.count(words.key, $0, context: localization) } ?? L10n.text(words.key, context: localization)
    }
    /// A asks what the row says when it is pressed, the choice waiting in the draft included.
    private func ask(_ entry: IntegrationEntry) {
        if let request = steam.all.first(where: { $0.id == entry.id })?.request { perform(request) }
    }
    /// Each request goes to its owner: the draft for the choice, the source for its reading, the picker for the folder.
    private func perform(_ request: IntegrationRequest) {
        switch request {
        case .steam(let enabled): stage(enabled: enabled, root: root)
        case .refreshSteam: sources.refresh()
        case .cancelSteamRefresh: sources.cancel()
        case .chooseSteamFolder: chooseFolder()
        case .readSteamAgain, .online, .clearOnline: break
        }
    }
    /// The picker and its refusal say what the folder row says.
    private var folderWords: (title: String, message: String) {
        (L10n.text(steam.folder.title.key, context: localization), steam.folder.about.map { L10n.text($0.key, context: localization) } ?? "")
    }
    private func chooseFolder() {
        OortFilePickerPresentation.open(.folder, title: folderWords.title, message: folderWords.message,
                                        startingAt: root) { urls in
            if let chosen = urls.first { use(chosen) }
        }
    }
    private func use(_ chosen: URL) {
        let root = chosen.resolvingSymlinksInPath().standardizedFileURL
        let apps = root.appendingPathComponent("steamapps").resolvingSymlinksInPath().standardizedFileURL
        var directory: ObjCBool = false
        guard apps.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: apps.path, isDirectory: &directory), directory.boolValue else {
            viewModel.showSettingsNotice(title: folderWords.title, message: folderWords.message)
            return
        }
        stage(enabled: steam.source.checked == true, root: root)
    }
    private func stage(enabled: Bool, root: URL) {
        if enabled == sources.configuration.isEnabled && root == sources.discoveryRoot {
            settings.settings.launcherChoices.steamSource = settings.store.settings.launcherChoices.steamSource
        } else {
            settings.settings.launcherChoices.steamSource = .init(enabled: enabled, root: root,
                replaces: staged.map(\.replaces) ?? viewModel.catalogSnapshot.source(.steam)?.generation,
                generation: staged?.generation ?? UUID())
        }
    }
    private func reveal(_ game: CatalogGame) {
        guard let location = game.steamGame?.installations.first?.contentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([location])
    }
    private func publishActions() {
        var rows: [SettingsRowAction] = [
            .init(id: "integrations", title: "All integrations", rowID: "integrations", activate: onOpenIntegrations),
            .init(id: "macShortcutAdd", title: "Add an app…", rowID: "macShortcutAdd",
                  isEnabled: viewModel.macShortcuts.canEdit) { viewModel.macShortcuts.chooseApp() },
        ] + steam.all.map { SettingsRowAction($0, ask: ask) } + [
            .init(id: "steamInBackground", title: "Keep Steam in the background") { settings.settings.steamInBackground.toggle() }
        ]
        rows += review.map { game in .init(id: "review-\(game.id)", title: game.name, rowID: "review-\(game.id)") { reveal(game) } }
        rows += hidden.map { game in .init(id: "hidden-\(game.id)", title: game.name, rowID: "hidden-\(game.id)") { viewModel.setCatalogHidden(false, game: game) } }
        onActions(rows)
    }
}
