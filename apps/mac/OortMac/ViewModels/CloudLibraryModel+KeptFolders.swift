import Foundation
import OortLibrary

/// The folders to propose again when the same account signs in: kept before a connection is left, never read to decide a write.
extension CloudLibraryModel {
    @MainActor func keepFolders() {
        guard preference.remote != nil else { return }
        let folders = CloudKeptFolders(account: driveScope?.account ?? keptFolders?.account,
                                       library: preference.root.split(separator: "/").joined(separator: "/"),
                                       sources: preference.sourcesRootOverride)
        guard let data = try? JSONEncoder().encode(folders) else { return }
        AppData.preferences.set(data, forKey: CloudKeptFolders.preferenceKey)
    }

    /// Earlier versions recorded no account: their folders are proposed only when their games are found again.
    var keptFolders: CloudKeptFolders? {
        if let saved = AppData.preferences.data(forKey: CloudKeptFolders.preferenceKey)
            .flatMap({ try? JSONDecoder().decode(CloudKeptFolders.self, from: $0) }) { return saved }
        guard preference.storage != nil || preference.sourcesRootOverride != nil else { return nil }
        return CloudKeptFolders(account: driveScope?.account,
                                library: preference.root.split(separator: "/").joined(separator: "/"),
                                sources: preference.sourcesRootOverride)
    }
}
