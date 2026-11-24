import Foundation

/// Browses directory metadata only. Selection does not open a file or follow a symlink.
public enum FileBrowser {
    public static let gameExtensions = ["nsp", "xci", "nsz", "xcz", "nup"]

    public enum Choice: Equatable, Sendable {
        case folder, gameFiles(allowFolder: Bool), keys

        public var allowsFolder: Bool { self == .folder || self == .gameFiles(allowFolder: true) }
        public func accepts(_ name: String) -> Bool {
            switch self {
            case .folder: return false
            case .keys: return name.lowercased() == "prod.keys"
            case .gameFiles: return FileBrowser.gameExtensions.contains((name as NSString).pathExtension.lowercased())
            }
        }
    }

    public struct Entry: Equatable, Identifiable, Sendable {
        public let url: URL
        public let isFolder: Bool
        public let isHidden: Bool
        public let size: Int?
        public var id: URL { url }
        public var name: String { url.lastPathComponent }
    }

    public struct Place: Equatable, Identifiable, Sendable {
        public enum Kind: Sendable { case home, games, downloads, desktop, documents, disk, recent }
        public let url: URL
        public let kind: Kind
        public var id: URL { url }
    }

    public enum Failure: Error, Equatable, Sendable { case denied, unavailable, link }

    /// Home child names come from a listing of Home; discovering a place does not enter it.
    public static func places(home: URL, homeChildren: Set<String>, disks: [URL], recent: [URL]) -> [Place] {
        var seen: Set<String> = []
        let paths: [(URL, Place.Kind)] = [(home, .home)] +
            [("Games", Place.Kind.games), ("Downloads", .downloads), ("Desktop", .desktop), ("Documents", .documents)]
                .filter { homeChildren.contains($0.0) }.map { (home.appendingPathComponent($0.0, isDirectory: true), $0.1) } +
            disks.map { ($0, .disk) } + recent.map { ($0, .recent) }
        return paths.compactMap { url, kind in
            let url = url.standardizedFileURL
            return seen.insert(url.path).inserted ? Place(url: url, kind: kind) : nil
        }
    }

    public static func parent(of url: URL, home: URL) -> URL? {
        guard url.standardizedFileURL.path != home.standardizedFileURL.path, url.path != "/" else { return nil }
        return url.deletingLastPathComponent()
    }

    public static func visible(_ entries: [Entry], query: String, showHidden: Bool) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { (showHidden || !$0.isHidden) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
    }

    public static func list(_ folder: URL, choice: Choice) async throws -> [Entry] {
        let worker = Task.detached(priority: .userInitiated) { try read(folder, choice: choice) }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func read(_ folder: URL, choice: Choice) throws -> [Entry] {
        let manager = FileManager.default
        do {
            // Check each component in order, not the link's target. /tmp and /var are macOS aliases
            // for /private/tmp and /private/var; normalize those system roots only.
            let path = folder.standardizedFileURL.path
            let systemAlias = ["/tmp", "/var", "/etc"].contains { path == $0 || path.hasPrefix($0 + "/") }
            let physicalPath = systemAlias ? "/private" + path : path
            var component = URL(fileURLWithPath: "/", isDirectory: true)
            for name in physicalPath.split(separator: "/") {
                try Task.checkCancellation()
                component.appendPathComponent(String(name))
                if try manager.attributesOfItem(atPath: component.path)[.type] as? FileAttributeType == .typeSymbolicLink {
                    throw Failure.link
                }
            }
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey, .fileSizeKey]
            let urls = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))
            return try urls.compactMap { url -> Entry? in
                try Task.checkCancellation()
                let name = url.lastPathComponent
                guard !name.hasPrefix("._"), let values = try? url.resourceValues(forKeys: keys),
                      values.isSymbolicLink != true else { return nil }
                let directory = values.isDirectory == true && values.isPackage != true
                guard directory || (values.isRegularFile == true && choice.accepts(name)) else { return nil }
                return Entry(url: url, isFolder: directory, isHidden: values.isHidden == true || name.hasPrefix("."),
                             size: directory ? nil : values.fileSize)
            }.sorted {
                if $0.isFolder != $1.isFolder { return $0.isFolder }
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.name < $1.name : order == .orderedAscending
            }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain {
            throw error.code == NSFileReadNoPermissionError ? Failure.denied : Failure.unavailable
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain {
            throw error.code == Int(EACCES) || error.code == Int(EPERM) ? Failure.denied : Failure.unavailable
        }
    }
}
