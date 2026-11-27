import Foundation
import OortLibrary

public enum WorkspaceMode: Equatable {
    case folder(URL)
    case staged
}

public struct Workspace: Equatable {
    public var directory: URL
    public var buildCache: URL
    public var links: [URL]

    public init(directory: URL, buildCache: URL, links: [URL]) {
        self.directory = directory
        self.buildCache = buildCache
        self.links = links
    }
}

public final class WorkspaceManager {
    private let root: URL
    private let fm: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fm = fileManager
    }

    public func makeWorkspace(for game: DetectedGame, mode: WorkspaceMode, createCache: Bool = true) throws -> Workspace {
        let planned = plannedWorkspace(for: game, mode: mode)
        let dir = planned.directory
        let cache = planned.buildCache
        switch mode {
        case .folder:
            if createCache { try fm.createDirectory(at: cache, withIntermediateDirectories: true) }
            return planned
        case .staged:
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let volume = try? dir.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            let caseSensitive = volume?.volumeSupportsCaseSensitiveNames == true
            var staged: [(relative: String, source: URL)] = []
            var seen: [String: URL] = [:]
            for source in game.allSources {
                let relative: String
                if source.layout == .extracted {
                    switch source.kind {
                    case .base: relative = "base"
                    case .update:
                        guard let version = source.version, version > 0 else { throw EngineSourceError.invalidDump("invalid update version") }
                        relative = "updates/\(version)"
                    case .dlc: relative = String(format: "dlc/%016llX/0/romfs", source.titleId)
                    case .unknown: throw EngineSourceError.invalidDump("unknown content")
                    }
                } else { relative = source.url.lastPathComponent }
                let key = caseSensitive ? relative : relative.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
                let resolved = source.url.resolvingSymlinksInPath()
                if let previous = seen[key] {
                    guard previous.path == resolved.path else {
                        throw CocoaError(.fileWriteFileExists, userInfo: [
                            NSLocalizedDescriptionKey: L10n.text("Two sources have the same name. Rename one or choose a different file.")
                        ])
                    }
                    continue
                }
                seen[key] = resolved
                staged.append((relative, source.url))
            }
            // Only links owned by this workspace are replaced. Never walk a link
            // into the original source tree, and leave build-cache contents alone.
            if let contents = fm.enumerator(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                var oldLinks: [URL] = []
                for case let entry as URL in contents {
                    if entry.resolvingSymlinksInPath() == cache.resolvingSymlinksInPath() { contents.skipDescendants(); continue }
                    if entry.lastPathComponent.hasPrefix(".arcane-cloud-"),
                       entry.deletingLastPathComponent().resolvingSymlinksInPath() == dir.resolvingSymlinksInPath() {
                        contents.skipDescendants()
                        continue
                    }
                    if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                        contents.skipDescendants()
                        oldLinks.append(entry)
                    }
                }
                for entry in oldLinks { try fm.removeItem(at: entry) }
                for entry in oldLinks {
                    var parent = entry.deletingLastPathComponent()
                    while parent.resolvingSymlinksInPath() != dir.resolvingSymlinksInPath(),
                          parent.resolvingSymlinksInPath().path.hasPrefix(dir.resolvingSymlinksInPath().path + "/"),
                          (try? fm.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
                        try fm.removeItem(at: parent)
                        parent.deleteLastPathComponent()
                    }
                }
            }
            var links: [URL] = []
            for (relative, source) in staged {
                let link = dir.appendingPathComponent(relative)
                try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: link.path)
                    || (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
                    guard (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil else {
                        throw CocoaError(.fileWriteFileExists)
                    }
                    try fm.removeItem(at: link)
                }
                try fm.createSymbolicLink(at: link, withDestinationURL: source)
                links.append(link)
            }
            if createCache { try fm.createDirectory(at: cache, withIntermediateDirectories: true) }
            return Workspace(directory: dir, buildCache: cache, links: links)
        }
    }

    /// Registers the expected locations without creating a workspace or cache.
    public func plannedWorkspace(for game: DetectedGame, mode: WorkspaceMode) -> Workspace {
        switch mode {
        case .folder(let directory): return adoptExistingWorkspace(for: game, folder: directory)
        case .staged:
            return adoptExistingWorkspace(for: game, folder: root.appendingPathComponent(String(format: "%016llX", game.baseTitleId)))
        }
    }

    /// A workspace that already exists beside the sources can be adopted
    /// without touching its build cache, which is what makes rebuilds fast.
    public func adoptExistingWorkspace(for game: DetectedGame, folder: URL) -> Workspace {
        let cache = folder.appendingPathComponent(cacheName(for: game))
        return Workspace(directory: folder, buildCache: cache, links: [])
    }

    public func brokenLinks(in workspace: URL) -> [URL] {
        guard let items = try? fm.contentsOfDirectory(
            at: workspace, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return [] }
        return items.compactMap { item -> URL? in
            guard let destination = try? fm.destinationOfSymbolicLink(atPath: item.path) else {
                return nil
            }
            let target = URL(fileURLWithPath: destination,
                             relativeTo: item.deletingLastPathComponent()).standardizedFileURL
            guard !fm.fileExists(atPath: target.path) else { return nil }
            // contentsOfDirectory may hand back /private/var while the workspace
            // URL is /var; keep the caller's spelling so comparisons match.
            return workspace.appendingPathComponent(item.lastPathComponent)
        }
    }

    private func cacheName(for game: DetectedGame) -> String {
        String(format: "%016llX_build", game.baseTitleId)
    }
}
