import Foundation
import NXLibraryCore

/// Drive folders chosen in the assistant, the latest first, for each connection on this Mac.
enum CloudRecentFolders {
    static let preferenceKey = "NXLibrary_CloudRecentFolders"
    static let limit = 5

    static func load(for remote: String?) -> [String] {
        guard let remote, let saved = AppData.preferences.dictionary(forKey: preferenceKey)?[remote] as? [String] else { return [] }
        return saved.filter(CloudLibraryPreference.validRoot).prefix(limit).map { $0 }
    }

    static func add(_ path: String, for remote: String?) {
        guard let remote, CloudLibraryPreference.validRoot(path) else { return }
        var all = AppData.preferences.dictionary(forKey: preferenceKey) ?? [:]
        all[remote] = ([path] + load(for: remote).filter { $0 != path }).prefix(limit).map { $0 }
        AppData.preferences.set(all, forKey: preferenceKey)
    }
}
