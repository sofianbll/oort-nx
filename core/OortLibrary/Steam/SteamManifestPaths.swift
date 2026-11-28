import Foundation

/// Which file events under Steam's folders can change the library. `SteamManifestWatcher` (the Mac app, FSEvents)
/// asks it; nothing is read, only the paths are compared.
public enum SteamManifestPaths {
    /// An event that may change the library. With `dropped` (the system lost events under `path` and asks for a
    /// rescan of it), only a drop at a `steamapps` folder or above counts: one inside `downloading/` or `common/`
    /// says nothing about the manifests, and a long download could otherwise rescan every batch.
    public static func isRelevant(_ path: String, dropped: Bool, libraries: [String], root: String?) -> Bool {
        guard dropped else { return isRelevant(path, libraries: libraries, root: root) }
        let folder = path.hasSuffix("/") ? String(path.dropLast()) : path
        return libraries.contains { library in
            let steamapps = library + "/steamapps"
            return steamapps == folder || steamapps.hasPrefix(folder + "/")
        }
    }

    /// `<library>/steamapps/appmanifest_<digits>.acf`, or the root's `steamapps/libraryfolders.vdf`.
    public static func isRelevant(_ path: String, libraries: [String], root: String?) -> Bool {
        if let root, path == root + "/steamapps/libraryfolders.vdf" { return true }
        for library in libraries {
            let prefix = library + "/steamapps/"
            guard path.hasPrefix(prefix) else { continue }
            let name = path.dropFirst(prefix.count)
            guard name.hasPrefix("appmanifest_"), name.hasSuffix(".acf") else { return false }
            let digits = name.dropFirst("appmanifest_".count).dropLast(".acf".count)
            return !digits.isEmpty && digits.utf8.allSatisfy { (48...57).contains($0) }
        }
        return false
    }
}
