import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// A catalog link and a handoff to macOS. No process, save, or session observation.
@MainActor final class MacShortcutAdapter: PlayAdapter {
    typealias Opener = @MainActor (URL, @escaping @MainActor (Bool) -> Void) -> Void

    let source = CatalogIntegration.macShortcut
    private unowned let app: AppViewModel
    private let open: Opener
    private(set) var isOpening = false

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

    func artifact(of target: PlayTarget) -> String? {
        target.game.macShortcut.flatMap { NativePlayTarget($0.url)?.artifact }
    }

    func admit(_ target: PlayTarget, profile: PlayProfile, gesture: PlayGesture) -> PlayResult {
        guard !profile.blocksPlay, profile == app.playProfile else { return .refused(.profileLocked) }
        guard !profile.isGuest else {
            app.showSettingsNotice(title: "Mac app shortcut", message: L10n.text("Switch to a regular profile to open Mac apps from the library."))
            return .refused(.guestUnsupported)
        }
        guard !isOpening, app.launchingGameId == nil, app.launchOverlay == nil else { return .refused(.launchInProgress) }
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
        guard let native = NativePlayTarget(url), native.bundleID == shortcut.bundleIdentifier
        else { return .refused(.outcomeUnknown) }
        if gesture.hasUnsettledHandoff(native.scope) { return .refused(.outcomeUnknown) }
        isOpening = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let refusal: PlayRefusal? = if let refusal = await gesture.reserve(native.scope) { refusal }
                else if self.app.playProfile != profile { .profileLocked }
                else if NativePlayTarget(url)?.artifact != native.artifact { .stale }
                else { nil }
            if let refusal {
                gesture.finish(.refused(refusal)) { [weak self] in self?.isOpening = false }
                return
            }
            self.open(native.url) { [weak self] handedOff in
                gesture.finish(handedOff ? .accepted(.handedOff) : .refused(.handoffRejected)) {
                    [weak self] in
                    self?.isOpening = false
                    if let self, !handedOff, self.app.playProfile == profile {
                        self.app.showSettingsNotice(title: "Could not open the Mac app",
                                                    message: L10n.text("macOS did not accept the request. The app was not changed."))
                    }
                }
            }
        }
        return .accepted(.pending)
    }

    private static func openWithWorkspace(_ url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        let configuration = NativePlayTarget.openConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            let accepted = application != nil && error == nil
            Task { @MainActor in completion(accepted) }
        }
    }

    func chooseApp(relinking shortcut: MacShortcutRecord? = nil) {
        guard canEdit else { return }
        let profile = app.playProfile
        OortFilePickerPresentation.open(.apps, title: L10n.text("Mac apps"),
                                        message: L10n.text(shortcut == nil ? "Choose an app to add a tile. The app stays where it is."
                                                                           : "Choose the original app at its new location."),
                                        startingAt: URL(fileURLWithPath: "/Applications", isDirectory: true)) { [weak self] urls in
            MainActor.assumeIsolated {
                guard let self, let url = urls.first, profile == self.app.playProfile else { return }
                if let shortcut { self.relink(shortcut.id, at: url) } else { self.add(at: url) }
            }
        }
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
        guard let index = app.catalogSnapshot.games.firstIndex(where: { $0.id == id }) else { return }
        let game = app.catalogSnapshot.games[index], profile = app.playProfile
        guard updateCatalog({ try app.catalogRepository.removeMacShortcut(id: id) }) else { return }
        app.undoOffers.offer(L10n.format("%@ left your library", [game.name])) { [weak self] in
            guard let self, self.app.playProfile == profile else { return }
            self.updateCatalog { try self.app.catalogRepository.restoreMacShortcut(game, at: index) }
        }
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
        // The tile comes back with Undo and the app never moves: no question first.
        let remove: (title: String, run: () -> Void) = ("Remove tile", { [weak self] in
            guard let self, self.app.playProfile == profile else { return }
            self.remove(game.id)
        })
        app.showSettingsNotice(title: "Tile options", message: game.name, actionTitle: "Choose image…",
                               cancelTitle: "Back", alternatives: [remove], primaryFirst: true, destructive: [remove.title]) { [weak self] in
            guard let self, self.app.playProfile == profile else { return }
            ChangeArtworkView.chooseArtworkFile(slot: .cover, name: game.name) { [weak self] result in
                MainActor.assumeIsolated {
                    guard let self, self.app.playProfile == profile,
                          self.app.catalogGames.contains(where: { $0.id == game.id }) else { return }
                    do { try picks.save(try result.get(), titleID: key, slot: .cover) } catch {
                        self.app.showSettingsNotice(title: "Mac app shortcut", message: error.localizedDescription)
                    }
                }
            }
        }
    }
}
