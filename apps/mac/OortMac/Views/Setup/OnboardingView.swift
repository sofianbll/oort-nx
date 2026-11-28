import AppKit
import NxnativeAdapter
import SwiftUI
import OortLibrary

struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    var settings: AppSettingsStore
    var profiles: LocalProfileStore
    @ObservedObject var sources: CatalogSourcesModel
    @ObservedObject private var controller = GameControllerService.shared
    let finish: () -> Void
    let openSettings: (SettingsSection) -> Void

    @State private var focus = "continue"
    @State private var inventory: OnboardingInventory?
    @State private var scanID = UUID()
    @State private var error: String?
    @State private var exclusions = Set(AppData.preferences.stringArray(forKey: AppViewModel.StorageKeys.onboardingExclusions) ?? [])

    private var page: FirstRunSetup.Page { viewModel.firstRunSetup.page }
    private var step: Int { (FirstRunSetup.Page.tour.firstIndex(of: page) ?? 0) + 1 }
    private var title: String {
        switch page {
        case .welcome: return "Welcome to Oort NX"
        case .controller: return "Your controller"
        case .profile: return "Your local profile"
        case .localGames: return "Games on this Mac"
        case .services: return "Optional services"
        default: return "Look and sound"
        }
    }
    private var detail: String {
        switch page {
        case .welcome: return "Play games already on your Mac. No account is required."
        case .controller: return "Connect a controller in macOS, or continue with your keyboard and mouse."
        case .profile: return "Your profile keeps your play history and preferences on this Mac."
        case .localGames: return "Add the checked games without moving their files or starting a build."
        case .services: return "Set up only what you want. You can do this later in Settings."
        default: return "Choose how the library looks and sounds. You can change it anytime."
        }
    }
    private var nextTitle: String {
        if page == .localGames, inventory == nil { return "Continue without waiting" }
        if page == .services { return "Later" }
        if page == .look { return "Open library" }
        return "Continue"
    }

    var body: some View {
        OnboardingScreen(title: L10n.text(title), detail: L10n.text(detail),
                         progress: "\(step) / \(FirstRunSetup.Page.tour.count)",
                         rows: rows, message: error ?? status, focus: $focus,
                         primary: (nextTitle, advance), secondary: page == .welcome ? ("Skip setup", finish) : ("Back", back),
                         backSkips: page == .welcome)
            .task(id: scanID) {
                guard page == .localGames else { return }
                await scan()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nxSetupCheckGamepadAction)) { note in
                guard let action = note.object as? GamepadAction, viewModel.isGuidedSetupOpen,
                      NSApp.modalWindow == nil else { return }
                switch action {
                case .navigateUp: move(-1)
                case .navigateDown: move(1)
                case .navigateLeft: horizontal(-1)
                case .navigateRight: horizontal(1)
                case .confirm: activate()
                case .cancel: back()
                default: break
                }
            }
    }

    private func move(_ delta: Int) {
        // The foot is one line, Back then Continue: from the rows, Down reaches Continue.
        let foot = ["back", "continue"]
        let targets = rows.filter { $0.action != nil }.map(\.id)
        let next: String?
        if foot.contains(focus) { next = delta < 0 ? targets.last : nil }
        else if let index = targets.firstIndex(of: focus) {
            next = targets.indices.contains(index + delta) ? targets[index + delta] : delta > 0 ? foot.last : nil
        } else { next = nil }
        guard let next else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    private func horizontal(_ delta: Int) {
        if let row = rows.first(where: { $0.id == focus }), let cycle = row.cycle { cycle(delta) }
        else if delta > 0, focus == "back" { focus = "continue" }
        else if delta < 0, focus == "continue" { focus = "back" }
    }

    private func activate() {
        if focus == "continue" { advance() }
        else if focus == "back" { if page == .welcome { finish() } else { back() } }
        else { rows.first { $0.id == focus }?.action?() }
    }

    private func advance() {
        if page == .localGames, inventory == nil {
            finish()
            return
        }
        if page == .localGames, let inventory {
            let picked = inventory.entries.filter { !exclusions.contains($0.id) && !$0.alreadyInLibrary }.compactMap(\.game)
            if !picked.isEmpty {
                do { viewModel.applyCatalog(try viewModel.catalogRepository.mergeNXNative(scanned: picked, enableSource: true)) }
                catch {
                    self.error = error.localizedDescription
                    return
                }
            }
        }
        SoundEffectService.shared.play(.click)
        if !viewModel.moveOnboarding(1) { finish() }
    }

    /// On the first page there is nothing to go back to: only the Skip setup button leaves the assistant.
    private func back() {
        if viewModel.moveOnboarding(-1) { SoundEffectService.shared.play(.back) }
    }

    private var status: String? {
        guard page == .localGames else { return nil }
        guard let inventory else { return L10n.text("Looking at your Mac…") }
        if inventory.incomplete { return L10n.text("Some folders could not be read. Check the folders or continue.") }
        if inventory.entries.isEmpty { return L10n.text("No games found") }
        return nil
    }

    private var rows: [OnboardingScreen.Row] {
        switch page {
        case .welcome:
            return [.init("language", L10n.text("App language"), "", .language,
                          .text(settings.settings.appLanguage.nativeName),
                          cycle: changeLanguage, action: { changeLanguage(1) })]
        case .controller:
            return [.init("controller", controller.isGamepadConnected ? controller.activeControllerName : L10n.text("No Gamepad Connected"),
                          L10n.text(controller.isGamepadConnected ? "Controller recognised" : "Keyboard and mouse are ready"),
                          .gamepad, controller.isGamepadConnected ? .text("✓") : .none)]
        case .profile:
            return [.init("profile", profiles.active?.name ?? L10n.text("Player"), L10n.text("Local profile"),
                          .person, .text(L10n.text("Edit")), action: { openSettings(.profileIdentity) })]
        case .localGames: return gameRows
        case .services: return serviceRows
        case .look:
            let theme = SelenePaletteCatalog.resolve(settings.settings.colorThemeID, in: ThemeStore.shared.palettes)
            return [
                .init("theme", L10n.text("Color theme"), "", .palette, .text(theme.name),
                      cycle: changeTheme, action: { changeTheme(1) }),
                .init("sound", L10n.text("Interface sounds"), "", .volume, .toggle(settings.settings.interfaceSounds),
                      action: { settings.settings.interfaceSounds.toggle(); SoundEffectService.shared.play(.click) })
            ]
        default: return []
        }
    }

    private var gameRows: [OnboardingScreen.Row] {
        [
            .init("files", L10n.text(GameFoldersCopy.sourcesTitle),
                  GameFoldersCopy.sourcesContents, .folder,
                  note: viewModel.porting.gameFilesFolder?.lastPathComponent ?? L10n.text("No folder selected"),
                  badges: GameFoldersCopy.sourceBadges,
                  action: { pickFolder(apps: false) }),
            .init("apps", L10n.text(GameFoldersCopy.appsTitle), GameFoldersCopy.appsContents, .folder,
                  note: viewModel.gameAppsFolder.lastPathComponent,
                  badges: GameFoldersCopy.appBadges, action: { pickFolder(apps: true) }),
            .init("keys", L10n.text(GameFoldersCopy.keysTitle), GameFoldersCopy.keysContents, .key,
                  badges: GameFoldersCopy.keyBadges, action: { viewModel.setup.selectProdKeysFile() })
        ] + (inventory?.entries.map { entry in
            let label = entry.alreadyInLibrary ? "Already in your library" :
                entry.isApp ? "Ready to play" : entry.game == nil ? "Identify later in Add Game" : "Game files · build later"
            let canAdd = entry.game != nil && !entry.alreadyInLibrary
            return .init(entry.id, entry.name, L10n.text(label), entry.isApp ? .gamepad : .folder,
                         canAdd ? .toggle(!exclusions.contains(entry.id)) : entry.alreadyInLibrary ? .text("✓") : .none,
                         action: canAdd ? {
                if !exclusions.insert(entry.id).inserted { exclusions.remove(entry.id) }
                AppData.preferences.set(Array(exclusions), forKey: AppViewModel.StorageKeys.onboardingExclusions)
            } : nil)
        } ?? [])
    }

    private var serviceRows: [OnboardingScreen.Row] {
        [
            service("drive", "Google Drive", "Connect your cloud library.", .cloud, .cloudLibrary),
            service("nextendo", "Nextendo", "Connect an account for online play.", .gamepad, .profileNextendo),
            service("steam", "Steam", "Read your installed Mac games from Steam.", .store, .sources),
            service("saves", "Save copies", "Choose if and where to sync ported-game saves.", .sync, .cloudSaves)
        ]
    }

    private func service(_ id: String, _ name: String, _ subtitle: String, _ icon: MaterialIcon,
                         _ section: SettingsSection) -> OnboardingScreen.Row {
        let enabled: Bool
        switch section {
        case .sources: enabled = sources.configuration.isEnabled
        case .cloudLibrary: enabled = viewModel.cloudLibrary.archive != nil
        case .profileNextendo: enabled = viewModel.profileNextendo?.status == .signedIn
        case .cloudSaves: enabled = settings.settings.cloudSaves != .off
        default: enabled = false
        }
        return .init(id, L10n.text(name), L10n.text(subtitle), icon, .text(L10n.text(enabled ? "Enabled" : "Later")),
                     action: { openSettings(section) })
    }

    private func changeLanguage(_ delta: Int) {
        let languages = AppLanguage.allCases
        guard let index = languages.firstIndex(of: settings.settings.appLanguage) else { return }
        settings.settings.appLanguage = languages[(index + delta + languages.count) % languages.count]
    }

    private func changeTheme(_ delta: Int) {
        let themes = SelenePaletteCatalog.pickerOrder(ThemeStore.shared.palettes)
        guard !themes.isEmpty else { return }
        let index = themes.firstIndex { $0.id == settings.settings.colorThemeID } ?? 0
        let next = themes[(index + delta + themes.count) % themes.count].id
        settings.settings.colorThemeID = next
        ThemeStore.shared.apply(id: next)
    }

    private func pickFolder(apps: Bool) {
        OortFilePickerPresentation.open(.folder, title: L10n.text(apps ? GameFoldersCopy.appsTitle : GameFoldersCopy.sourcesTitle),
            message: apps ? GameFoldersCopy.appsPickerMessage
                : GameFoldersCopy.sourcesPickerMessage(extractedFolders: viewModel.setup.engineSourceCapabilities.extractedFolders),
            startingAt: apps ? viewModel.gameAppsFolder : viewModel.porting.gameFilesFolder,
            canCreateDirectories: true) { urls in
            guard let folder = urls.first, folder.standardizedFileURL.path != "/" else { return }
            if apps { viewModel.libraryFolder = folder }
            else { AppData.preferences.set(folder.path, forKey: AppViewModel.StorageKeys.savedGameFolder) }
            inventory = nil
            error = nil
            scanID = UUID()
        }
    }

    @MainActor private func scan() async {
        let apps = viewModel.gameAppsFolder
        let homeApps = AppData.profile.home.appendingPathComponent("Applications", isDirectory: true)
        let systemApps = AppData.profile.isDevelopment ? [] : FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        let fallbackRoots = ([homeApps] + systemApps).filter { FileManager.default.fileExists(atPath: $0.path) }
        let custom = AppData.preferences.string(forKey: AppViewModel.StorageKeys.savedLibraryFolder) != nil
        let directories = (custom ? [apps] : []) + fallbackRoots
        let files = viewModel.porting.gameFilesFolder
        let existing = viewModel.libraryGames
        let worker = Task.detached(priority: .userInitiated) {
            OnboardingInventory.read(apps: directories, files: files, existing: existing, cancelled: { Task.isCancelled })
        }
        let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        if !Task.isCancelled { inventory = result }
    }
}
