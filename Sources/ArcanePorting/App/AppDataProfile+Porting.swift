import Foundation
import NXLibraryCore

extension AppDataProfile {
    /// The profile's own temporary folder, plus folders beside Game apps for an unmigrated stable profile.
    public func automaticStagingFolders(appFolders: [URL]) -> [URL] {
        // shortcut: shared staging is not swept after a move until scratch folders can identify their owner.
        let shared = !isDevelopment && !LibraryMove.moved(supportRoot)
        return BuildScratch.tempFolders(core: supportRoot, appFolders: shared ? appFolders : [])
            .filter { !LibraryMove.contains($0, in: legacySupportRoot) }
    }
}
