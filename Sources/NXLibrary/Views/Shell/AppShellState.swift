import Foundation
import NXLibraryCore

/// Prepared before the shell enters SwiftUI's view graph. Model startup can
/// update AppKit and shared observable services; it must not run during a view's
/// StateObject creation while the prepared shell enters the view graph.
@MainActor
final class AppShellState {
    let settings: AppSettingsStore
    let viewModel: AppViewModel
    let router: AppRouter
    let sources: CatalogSourcesModel
    let profiles: LocalProfileStore
    let igdb = IGDBSettings.shared
    /// The Mods card keeps its prepared cover across navigation; Spotlight observes it only while visible.
    let modStoreHost = ModStoreHost()
    /// "Welcome to Arcane" is up from the first frame, so the library never shows before it. Decided before save recovery starts; what it raises opens above.
    let opensWithWelcome: Bool

    init(settings: AppSettingsStore, catalog: CatalogDocument, repository: CatalogRepository) {
        self.settings = settings
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let profiles = LocalProfileStore(settings: settings.settings,
                                         name: name.isEmpty ? L10n.text("Player") : String(name.prefix(32)))
        self.profiles = profiles
        let startup = settings.settings.profileStartup
        let needsPicker = profiles.needsStartupPicker(startup)
        if profiles.active != nil, startup != startup.available(in: profiles.profiles) {
            settings.settings.profileStartup = .ask
        }
        if let look = profiles.active?.look, look != .init(settings.settings) {
            look.apply(to: &settings.settings)
        }
        AppDelegate.settingsStore = settings
        AppLocalization.shared.configure(settings.settings)
        ThemeStore.shared.apply(id: settings.settings.colorThemeID)
        let model = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository, localProfiles: profiles)
        viewModel = model
        AppDelegate.cloudLibrary = model.cloudLibrary
        AppDelegate.activityOwner = model
        AppDelegate.showCloudQuit = { [weak model] in
            guard let model, !model.cloudQuitRequested else { return }
            model.dismissLaunchOverlay()
            model.cloudQuitRequested = true
        }
        AppDelegate.isBusy = { [weak model] in
            guard let model else { return false }
            return model.isBuilding || model.isUpdatingApp || model.hasActiveSaveOperations
        }
        sources = CatalogSourcesModel(repository: repository, initialConfiguration: catalog.source(.steam) ?? .init(integration: .steam)) { [weak model] document in
            model?.applyCatalog(document)
        }
        let router = AppRouter(settings: settings)
        router.setInitialRoute(AppRouter.initialRoute(for: settings.settings.startOn, last: settings.settings.lastHome))
        self.router = router
        opensWithWelcome = ArcaneWelcome.shouldShow(setupCompleted: model.setupCompleted,
                                                    shown: settings.settings.welcomeArcaneShown,
                                                    hasPendingRecovery: false)
        model.isWelcomeOpen = opensWithWelcome
        model.profileOwnsInput = needsPicker
    }
}
