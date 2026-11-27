import Foundation
import OortLibrary

/// Reads a game's `mods` folder: which subfolders there are, where each one's RomFS tree is, and the files in it.
/// A mod's RomFS is what the engine's `DM_ROMFS_OVERLAY` reads before the game's own (dm/host/hle_fs.c).
public enum ModFolderScanner {
    public enum OnlineContent: Equatable, Sendable { case visual, data, uncertain }

    public static func onlineContent(under romfs: URL) -> OnlineContent {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var uncertain = false
        var hasVisual = false
        guard let walker = FileManager.default.enumerator(at: romfs, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, _ in uncertain = true; return false }) else { return .uncertain }
        for case let url as URL in walker {
            if url.lastPathComponent == ".DS_Store" { continue }
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink == false else {
                uncertain = true
                continue
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { uncertain = true; continue }
            switch url.pathExtension.lowercased() {
            case "bntx", "dds", "ktx", "ktx2", "astc", "bfres":
                hasVisual = true
            case "byml", "byaml", "bgyml", "json", "csv", "yaml", "yml", "xml", "lua", "bin", "trpfd":
                return .data
            default:
                uncertain = true
            }
        }
        return hasVisual && !uncertain ? .visual : .uncertain
    }

    /// The mod's RomFS tree: `<folder>/romfs`, else the Atmosphère layouts `<folder>/atmosphere/contents/<TID>/romfs`
    /// and `<folder>/contents/<TID>/romfs` (title ID in either case). A real directory, never a symlink, so an overlay
    /// path cannot lead out of the mods folder.
    public static func romfs(in folder: URL, titleID: String) -> URL? {
        let ids = [titleID.uppercased(), titleID.lowercased()]
        let candidates = [folder.appendingPathComponent("romfs")]
            + ids.map { folder.appendingPathComponent("atmosphere/contents/\($0)/romfs") }
            + ids.map { folder.appendingPathComponent("contents/\($0)/romfs") }
        return candidates.first(where: isRealDirectory)
    }

    /// The mods folder's visible entries, sorted by name: subfolders and stray files (an archive not unzipped yet, which
    /// is then shown as not a mod). Hidden entries and symlinks are left out.
    public static func entries(in modsFolder: URL) -> [URL] {
        ((try? listedEntries(in: modsFolder)) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false }
    }

    /// A caller removing records needs a complete listing. Read failures cannot stand for missing mods.
    static func checkedEntries(in modsFolder: URL) throws -> [URL] {
        try listedEntries(in: modsFolder).filter { entry in
            guard let isLink = try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink else {
                throw CocoaError(.fileReadUnknown)
            }
            return !isLink
        }
    }

    private static func listedEntries(in modsFolder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: modsFolder, includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                    options: .skipsHiddenFiles)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every file under a RomFS tree, as a path relative to it, in its exact case (RomFS paths are case-sensitive).
    /// Hidden files (Finder's `.DS_Store`) are left out: the game never reads them.
    public static func files(under romfs: URL) -> Set<String> {
        let base = romfs.resolvingSymlinksInPath().standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: romfs, includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: .skipsHiddenFiles) else { return [] }
        var found: Set<String> = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            found.insert(String(path.dropFirst(base.count + 1)))
        }
        return found
    }

    static func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}
