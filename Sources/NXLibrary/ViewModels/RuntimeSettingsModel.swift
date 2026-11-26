import Foundation
import NXLibraryCore
import ArcanePorting

/// A built game's saved choices for its next launch, as Game options and More settings show them: reading, writing,
/// restoring the new-game defaults and which settings the build supports. It keeps no state: the game's files are the
/// truth (`NXNativeGameSettings`, or env.txt for a build from before saved choices). It reaches the rest of Arcane
/// only through `app`: the log, the notice and the new-game defaults.
final class RuntimeSettingsModel {
    /// The coordinator: log, notices and the player's settings.
    unowned let app: AppViewModel

    init(app: AppViewModel) {
        self.app = app
    }

    func loadRuntimeConfig(for game: PortedGame) -> GameRuntimeConfig {
        gameSettings(for: game)?.runtimeConfig() ?? GameRuntimeConfig.load(for: game)
    }

    /// The game's saved-choices store, or nil for a build from before saved choices (env.txt).
    func gameSettings(for game: PortedGame) -> NXNativeGameSettings? {
        NXNativeGameSettings.forGame(game)
    }

    func settingsSnapshot(for game: PortedGame) -> GameSettingsSnapshot? {
        gameSettings(for: game)?.snapshot()
    }

    /// One saved choice; false (with a notice) when it could not be kept.
    @discardableResult func setGameSetting(_ env: String, to value: String, for game: PortedGame) -> Bool {
        guard let settings = gameSettings(for: game) else { return false }
        do {
            try settings.set(env, to: value)
            app.tips.settingChanged(for: game.id, enabled: app.settingsStore?.settings.showsTips ?? false)
            return true
        } catch {
            settingsNotSaved(game, error)
            return false
        }
    }

    func setMultiplayerMode(_ mode: MultiplayerMode, for game: PortedGame) {
        guard let settings = gameSettings(for: game) else { return }
        do { try settings.setMultiplayerMode(mode) }
        catch { settingsNotSaved(game, error) }
    }

    /// Use new game defaults: every setting to the build's default, then Arcane's new-game defaults.
    func restoreGameDefaults(for game: PortedGame) {
        guard let settings = gameSettings(for: game) else { return }
        do {
            try settings.resetAll()
            let base = settings.runtimeConfig()
            try settings.apply(app.settingsStore?.settings.gameDefaults ?? GameRuntimeConfig(), changedFrom: base)
        } catch {
            settingsNotSaved(game, error)
        }
    }

    /// The other games with saved choices, and what each would take from this one.
    func copyTargets(for game: PortedGame) -> [CopySettingsPanel.Target] {
        guard let source = settingsSnapshot(for: game) else { return [] }
        return app.libraryGames.compactMap { other in
            guard other.id != game.id, let snapshot = settingsSnapshot(for: other) else { return nil }
            return .init(game: other, copy: GameSettingsCopy(from: source, to: snapshot))
        }
    }

    func copyPlan(from game: PortedGame, to other: PortedGame) -> GameSettingsCopy? {
        guard let source = settingsSnapshot(for: game), let target = settingsSnapshot(for: other) else { return nil }
        return GameSettingsCopy(from: source, to: target)
    }

    func copySettings(_ copy: GameSettingsCopy, to other: PortedGame) -> Bool {
        guard !copy.changes.isEmpty, let settings = gameSettings(for: other) else { return false }
        let before = settings.savedChoices()
        do { try settings.apply(copy) }
        catch {
            settingsNotSaved(other, error)
            return false
        }
        let written = settings.savedChoices()
        app.undoOffers.offer(L10n.format("Settings copied to %@", [other.name])) { [weak self] in
            guard let self, let game = self.app.libraryGames.first(where: { $0.id == other.id }),
                  let settings = self.gameSettings(for: game) else { return }
            let current = settings.savedChoices()
            let unchanged = Set(copy.changes.map(\.env).filter { current[$0] == written[$0] })
            do { try settings.restore(before, only: unchanged) }
            catch { self.settingsNotSaved(game, error); return }
            NotificationCenter.default.post(name: .nxGameSettingsRestored, object: game.id)
        }
        NotificationCenter.default.post(name: .nxGameSettingsRestored, object: other.id)
        return true
    }

    /// Puts this game's choices back exactly as they are now, whatever changes them next.
    func wayBack(for game: PortedGame) -> () -> Void {
        let saved = gameSettings(for: game)?.savedChoices()
        let config = saved == nil ? GameRuntimeConfig.load(for: game) : nil
        let key = game.titleId?.uppercased()
        let display = key.flatMap { app.settingsStore?.settings.gameDisplayOverrides[$0] }
        return { [weak self] in
            guard let self, self.app.libraryGames.contains(where: { $0.id == game.id }) else { return }
            if let saved {
                do { try self.gameSettings(for: game)?.restore(saved) }
                catch { self.settingsNotSaved(game, error); return }
            } else if let config { self.saveRuntimeConfig(config, for: game) }
            if let key { self.app.settingsStore?.settings.gameDisplayOverrides[key] = display }
            NotificationCenter.default.post(name: .nxGameSettingsRestored, object: game.id)
        }
    }

    private func settingsNotSaved(_ game: PortedGame, _ error: Error) {
        app.logs.append(LogEntry(level: .error, message: L10n.format("Could not save settings for %@: %@", [String(describing: game.name), String(describing: error.localizedDescription)])))
        app.showSettingsNotice(title: L10n.text("Options not saved"), message: L10n.text("Your game options could not be saved. Try again."))
    }

    func supportsSetting(_ env: String, for game: PortedGame) -> Bool {
        LauncherSettingsReader.supports(env, for: game.url)
    }

    @discardableResult func saveRuntimeConfig(_ config: GameRuntimeConfig, for game: PortedGame) -> Bool {
        do {
            try config.save(for: game)
            app.logs.append(LogEntry(level: .success, message: L10n.format("Saved settings for %@", [String(describing: game.name)])))
            return true
        } catch {
            app.logs.append(LogEntry(level: .error, message: L10n.format("Could not save settings for %@: %@", [String(describing: game.name), String(describing: error.localizedDescription)])))
            app.showSettingsNotice(title: L10n.text("Options not saved"), message: L10n.text("Your game options could not be saved. Try again.")) { [weak self] in
                self?.saveRuntimeConfig(config, for: game)
            }
            return false
        }
    }
}
