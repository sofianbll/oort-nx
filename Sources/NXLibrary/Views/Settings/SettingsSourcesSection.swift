import SwiftUI
import AppKit
import NXLibraryCore

@MainActor
struct SettingsSourcesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: SettingsEditor
    @EnvironmentObject private var sources: CatalogSourcesModel
    @Environment(\.nxAppLocale) private var localization
    let onOpenIntegrations: () -> Void
    let onActions: ([SettingsRowAction]) -> Void

    private var staged: SteamSourceChoice? {
        let choice = settings.settings.launcherChoices.steamSource
        return choice == settings.store.settings.launcherChoices.steamSource ? nil : choice
    }
    private var enabled: Bool { staged?.enabled ?? sources.configuration.isEnabled }
    private var root: URL { staged?.root ?? sources.discoveryRoot }
    private var hidden: [CatalogGame] { viewModel.catalogGames.filter { $0.integration == .steam && $0.isHidden } }
    private var review: [CatalogGame] {
        viewModel.catalogGames.filter { !$0.isHidden && $0.steamGame?.needsReview == true }
    }
    private var statusText: String {
        switch sources.status {
        case .disabled: return L10n.text("Enable Steam to find its installed Mac games.", context: localization)
        case .idle: return L10n.text("Ready to check Steam.", context: localization)
        case .scanning: return L10n.text("Checking Steam libraries…", context: localization)
        case .ready: return L10n.count("%lld Steam installations found", sources.observedGameCount, context: localization)
        case .partial: return L10n.text("Some installations could not be checked. Your library has been kept.", context: localization)
        case .cancelled: return L10n.text("Scan stopped. Refresh when you are ready.", context: localization)
        case .failed: return L10n.text("Steam could not be refreshed. Your library has been kept.", context: localization)
        }
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
            SeleneToggleRow("Steam", subtitle: "Find installed native Mac games in your Steam libraries.",
                            info: "Your Steam files stay where they are. Disabling this source keeps its games and personal choices.",
                            platform: .steam,
                            isOn: Binding(get: { enabled }, set: { stage(enabled: $0, root: root) }))
            SeleneButtonRow("Refresh Steam", subtitle: statusText,
                            buttonTitle: sources.status == .scanning ? "Cancel" : "Refresh") {
                if sources.status == .scanning { sources.cancel() } else { sources.refresh() }
            }.disabled(!sources.configuration.isEnabled && sources.status != .failed)
            SeleneValueRow("Steam folder", subtitle: "Choose the Steam folder containing steamapps.",
                           value: root.path, actionTitle: "Change", action: chooseFolder)
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
                        Button(L10n.text("Reveal", context: localization)) { reveal(game) }.buttonStyle(.plain).foregroundColor(SeleneTheme.glyph)
                    }
                }
            }
            if !hidden.isEmpty {
                SettingsSubheading("Hidden Steam games")
                ForEach(hidden) { game in
                    SeleneRow(game.name, id: "hidden-\(game.id)", subtitle: "Hidden from the library", verbatimTitle: true) {
                        Button(L10n.text("Show", context: localization)) { viewModel.setCatalogHidden(false, game: game) }
                            .buttonStyle(.plain).foregroundColor(SeleneTheme.glyph)
                    }
                }
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: sources.status) { publishActions() }
        .onChange(of: sources.configuration) { publishActions() }
        .onChange(of: viewModel.catalogGames) { publishActions() }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = root
        panel.message = L10n.text("Choose the Steam folder containing steamapps.", context: localization)
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let root = chosen.resolvingSymlinksInPath().standardizedFileURL
        let apps = root.appendingPathComponent("steamapps").resolvingSymlinksInPath().standardizedFileURL
        var directory: ObjCBool = false
        guard apps.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: apps.path, isDirectory: &directory), directory.boolValue else {
            viewModel.showSettingsNotice(title: L10n.text("Steam folder", context: localization), message: L10n.text("Choose the Steam folder containing steamapps.", context: localization))
            return
        }
        stage(enabled: enabled, root: root)
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
            .init(id: "steamSource", title: "Steam") { stage(enabled: !enabled, root: root) },
            .init(id: "steamRefresh", title: "Refresh Steam", isEnabled: sources.configuration.isEnabled || sources.status == .failed) {
                if sources.status == .scanning { sources.cancel() } else { sources.refresh() }
            },
            .init(id: "steamFolder", title: "Steam folder", activate: chooseFolder),
            .init(id: "steamInBackground", title: "Keep Steam in the background") { settings.settings.steamInBackground.toggle() }
        ]
        rows += review.map { game in .init(id: "review-\(game.id)", title: game.name, rowID: "review-\(game.id)") { reveal(game) } }
        rows += hidden.map { game in .init(id: "hidden-\(game.id)", title: game.name, rowID: "hidden-\(game.id)") { viewModel.setCatalogHidden(false, game: game) } }
        onActions(rows)
    }
}
