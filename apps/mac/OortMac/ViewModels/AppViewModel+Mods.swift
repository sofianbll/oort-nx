import AppKit
import OortLibrary
import ArcanePorting

/// Mods: the game's RomFS and ExeFS folders, their order and on/off state, and the RomFS overlay the game reads.
extension AppViewModel {
    /// Nil when the game's app has no valid title ID.
    func modStore(for game: PortedGame) -> ModStore? {
        guard let titleID = CheatLocator.titleID(appURL: game.url, fallback: game.titleId) else { return nil }
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ModStore(supportFolder: support.appendingPathComponent("nxnative/\(titleID)"),
                        recordsFile: AppData.supportRoot.appendingPathComponent("mods/\(titleID).json"),
                        titleID: titleID,
                        canWrite: { RunningGameMonitor.runningApplication(for: game) == nil },
                        trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                        allowsAutomaticMaintenance: !AppData.profile.isDevelopment)
    }

    func modsRowValue(for game: PortedGame) -> String {
        guard let store = modStore(for: game) else { return L10n.text("None") }
        if store.codeModsNeedRebuild(app: game.url, build: game.lastBuild) { return L10n.text("Rebuild") }
        let mods = store.mods()
        return ModStore.rowValue(on: mods.filter(\.isOn).count, total: mods.count)
    }

    /// Runs a change; nil when it worked, otherwise the sentence to show.
    func performModChange(_ change: () throws -> Void) -> String? {
        do {
            try change()
            return nil
        } catch let error as ModStoreError {
            return Self.modMessage(error)
        } catch {
            return "The mods could not be saved: \(error.localizedDescription)"
        }
    }

    nonisolated static func modMessage(_ error: ModStoreError) -> String {
        switch error {
        case .notAllowed: return "Quit the game to change its mods."
        case .notAMod: return L10n.text("Not a mod: needs romfs or exefs patches.")
        case .colonInName(let name): return "Rename the folder \(name): its name can't contain ':'."
        case .overlayTooLong: return "Too many mods are on for one game. Turn one off first."
        case .invalidCodeMod(let name):
            return L10n.format("%@ needs an exefs folder with .pchtxt or .ips files only, without links.", [name])
        case .duplicateFolderName(let name):
            return L10n.format("File and code mods both use the folder name %@. Rename one folder.", [name])
        case .writeFailed(let reason): return "The mods could not be saved: \(reason)"
        }
    }
}
