import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// A catalog link and a handoff to macOS. No process, save, or session observation.
@MainActor final class MacShortcutAdapter: PlayConnector {
    typealias Opener = @MainActor (URL, @escaping @MainActor (Bool) -> Void) -> Void

    let source = CatalogIntegration.macShortcut
    private unowned let app: AppViewModel
    private let open: Opener
    private var opening = false

    init(app: AppViewModel, open: Opener? = nil) {
        self.app = app
        self.open = open ?? Self.openWithWorkspace
    }

    var canEdit: Bool { !app.playProfile.blocksPlay && !app.playProfile.isGuest }

    func availability(of target: PlayTarget) -> PlayAvailability {
        guard target.installationAvailability == .available else { return target.installationAvailability }
        guard let shortcut = target.game.macShortcut else { return .unavailable(.invalidGame) }
        return shortcut.verifiedURL() == nil ? .unavailable(.installationMissing) : .available
    }

    func play(_ target: PlayTarget, profile: PlayProfile, observe: PlayObserver?) -> PlayResult {
        guard !profile.blocksPlay, profile == app.playProfile else { return .refused(.profileLocked) }
        guard !profile.isGuest else {
            app.showSettingsNotice(title: "Mac app shortcut", message: L10n.text("Switch to a regular profile to open Mac apps from the library."))
            return .refused(.guestUnsupported)
        }
        guard !opening, app.launchingGameId == nil, app.launchOverlay == nil else { return .refused(.launchInProgress) }
        guard target.installationAvailability != .unavailable(.sourceDisabled) else { return .refused(.sourceDisabled) }
        guard let shortcut = app.visibleCatalogGames.first(where: { $0.id == target.game.id })?.macShortcut else {
            return .refused(.missingTarget)
        }
        guard let url = shortcut.verifiedURL() else {
            app.showSettingsNotice(title: "Mac app not found",
                                   message: L10n.text("The app has moved or no longer matches this tile. Choose the original app again."),
                                   actionTitle: "Locate the app…", cancelTitle: "Cancel", primaryFirst: true) { [weak self] in
                guard self?.app.playProfile == profile else { return }
                self?.chooseApp(relinking: shortcut)
            }
            return .refused(.installationMissing)
        }
        opening = true
        open(url) { [weak self] handedOff in
            guard let self else { return }
            self.opening = false
            if !handedOff, self.app.playProfile == profile {
                self.app.showSettingsNotice(title: "Could not open the Mac app",
                                            message: L10n.text("macOS did not accept the request. The app was not changed."))
            }
            observe?(.result(handedOff ? .accepted(.handedOff) : .refused(.handoffRejected)))
        }
        return .accepted(.pending)
    }

    private static func openWithWorkspace(_ url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            let accepted = application != nil && error == nil
            Task { @MainActor in completion(accepted) }
        }
    }

    func chooseApp(relinking shortcut: MacShortcutRecord? = nil) {
        guard canEdit else { return }
        let profile = app.playProfile
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = L10n.text(shortcut == nil ? "Add" : "Choose")
        panel.message = L10n.text(shortcut == nil ? "Choose an app to add a tile. The app stays where it is."
                                                  : "Choose the original app at its new location.")
        guard panel.runModal() == .OK, let url = panel.url, profile == app.playProfile else { return }
        if let shortcut { relink(shortcut.id, at: url) } else { add(at: url) }
    }

    func acceptDrop(_ urls: [URL]) -> Bool {
        guard canEdit, urls.count == 1, let url = urls.first, url.isFileURL,
              url.pathExtension.lowercased() == "app" else { return false }
        return add(at: url)
    }

    @discardableResult func add(at url: URL) -> Bool {
        updateCatalog { try app.catalogRepository.addMacShortcut(at: url) }
    }

    func relink(_ id: UUID, at url: URL) {
        updateCatalog { try app.catalogRepository.relinkMacShortcut(id: id, at: url) }
    }

    func remove(_ id: UUID) {
        updateCatalog { try app.catalogRepository.removeMacShortcut(id: id) }
    }

    @discardableResult private func updateCatalog(_ change: () throws -> CatalogDocument) -> Bool {
        guard canEdit else { return false }
        do {
            app.applyCatalog(try change())
            return true
        }
        catch let error as MacShortcutError {
            let message: String
            switch error {
            case .invalidApplication: message = "Choose a valid Mac app (.app)."
            case .differentApplication: message = "This is not the app linked to this tile. Choose the original app."
            case .alreadyLinked: message = "That location is already linked to another tile."
            }
            app.showSettingsNotice(title: "Mac app shortcut", message: L10n.text(message))
        } catch { app.reportCatalogFailure(error) }
        return false
    }

    func showTileOptions(_ game: CatalogGame) {
        guard canEdit, game.macShortcut != nil else { return }
        let profile = app.playProfile
        let key = game.personalizationKey
        let picks = ArtworkPicks.shared
        let remove: (title: String, run: () -> Void) = ("Remove tile…", { [weak self] in
            guard let self, self.app.playProfile == profile else { return }
            self.app.showSettingsNotice(title: "Remove this tile?",
                                        message: L10n.text("The tile is removed from the library. The app stays where it is."),
                                        actionTitle: "Remove tile", cancelTitle: "Cancel") { [weak self] in
                guard self?.app.playProfile == profile else { return }
                self?.remove(game.id)
            }
        })
        app.showSettingsNotice(title: "Tile options", message: game.name, actionTitle: "Choose image…",
                               cancelTitle: "Back", alternatives: [remove], primaryFirst: true) { [weak self] in
            guard let self, self.app.playProfile == profile else { return }
            do {
                guard let data = try ChangeArtworkView.chooseArtworkFile(slot: .cover, name: game.name),
                      self.app.playProfile == profile,
                      self.app.catalogGames.contains(where: { $0.id == game.id }) else { return }
                try picks.save(data, titleID: key, slot: .cover)
            } catch {
                self.app.showSettingsNotice(title: "Mac app shortcut", message: error.localizedDescription)
            }
        }
    }
}
