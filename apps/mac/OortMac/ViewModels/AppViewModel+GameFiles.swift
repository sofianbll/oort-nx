import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// A game's files: removing its sources, deleting it, the file pickers and its porting log.
extension AppViewModel {
    /// A human-readable summary for the destructive source-removal confirmation.
    func sourceRemovalSummary(for game: PortedGame) -> String {
        let fm = FileManager.default
        let existingSources = game.sources.filter {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: $0.url.path, isDirectory: &isDir) && !isDir.boolValue
        }
        let sourceBytes = existingSources.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let workspaceBytes: Int64
        if let path = game.workspacePath {
            let workspace = URL(fileURLWithPath: path).standardizedFileURL
            workspaceBytes = BuildScratch.isManaged(workspace, core: core)
                ? directorySize(workspace) : 0
        } else {
            workspaceBytes = 0
        }

        var parts: [String] = []
        if !existingSources.isEmpty {
            parts.append(L10n.count("%lld original source files (%@)", existingSources.count, arguments: [Self.formatBytes(sourceBytes)]))
        }
        if workspaceBytes > 0 {
            parts.append(L10n.format("Build cache (%@)", [Self.formatBytes(workspaceBytes)]))
        }
        let target = parts.isEmpty ? L10n.text("Remaining build data") : parts.joined(separator: ", ")
        return L10n.format("Move to Trash: %@. The installed app, saves and logs stay. Rebuilds will be disabled until you attach the sources again.", [target])
    }

    func removeSources(for game: PortedGame) {
        guard !isBuilding, !isUpdatingApp, !isCleaningStorage, !isCheckingCloudBuild, !cloudLibrary.isWorking else {
            alertMessage = L10n.text("Wait for the current build, storage operation or app update to finish.")
            return
        }
        let fm = FileManager.default
        let current: CatalogDocument
        do { current = try catalogRepository.load() }
        catch { reportCatalogFailure(error); return }
        guard var updated = current.nxnativeGames.first(where: { $0.id == game.id }),
              updated.sources == game.sources, updated.workspacePath == game.workspacePath, updated.url == game.url else {
            alertMessage = L10n.format("Could not load the library entry for %@.", [game.name])
            return
        }
        guard let release = removalLease(for: updated) else { return }
        defer { release() }

        let appPath = resolvedRemovalPath(updated.url)
        let otherGames = current.nxnativeGames.filter { $0.id != game.id }
        var removedBytes: Int64 = 0
        var failures: [String] = []
        var sources = [URL]()

        for source in updated.sources {
            let url = source.url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                failures.append(L10n.format("%@ is a folder", [url.lastPathComponent]))
                continue
            }
            let resolved = resolvedRemovalPath(url)
            if resolved == appPath || resolved.hasPrefix(appPath + "/") {
                failures.append(L10n.format("%@ is inside the app", [url.lastPathComponent]))
                continue
            }
            let shared = otherGames.contains { other in
                other.sources.contains { candidate in
                    resolvedRemovalPath(candidate.url) == resolved ||
                    ((try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier).map { id in
                        id.isEqual((try? candidate.url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier) ?? nil)
                    } ?? false)
                }
            }
            if shared {
                failures.append(L10n.format("%@ is also used by another library entry", [url.lastPathComponent]))
                continue
            }
            sources.append(url)
            removedBytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init) ?? source.sizeBytes
        }

        var files = sources
        var removedWorkspace = false
        if let path = updated.workspacePath, failures.isEmpty {
            let workspace = URL(fileURLWithPath: path).standardizedFileURL
            if BuildScratch.isManaged(workspace, core: core),
               fm.fileExists(atPath: workspace.path),
               workspaceCanBeTrashed(workspace, protecting: current.nxnativeGames, owner: updated) {
                files.append(workspace)
                removedWorkspace = true
            }
        }

        updated.sources.removeAll { sources.contains($0.url.standardizedFileURL) }
        if removedWorkspace {
            updated.workspacePath = nil
            updated.buildCachePath = nil
        }
        if updated.sources.isEmpty {
            updated.status = .builtSourcesMissing
        }
        do {
            applyCatalog(try catalogRepository.removeNXNativeFiles(id: game.id, from: current, files: files,
                keeping: updated) {
                guard RunningGameMonitor.runningApplication(for: updated) == nil else { throw CatalogRemovalFailure.gameBusy }
            })
        } catch {
            let message = L10n.format("Could not remove the original game files. %@", [error.localizedDescription])
            alertMessage = message
            logs.append(LogEntry(level: .error, message: message))
            return
        }
        let removed = L10n.count("Removed %lld source files (%@).", sources.count, arguments: [Self.formatBytes(removedBytes)])
            + (removedWorkspace ? " " + L10n.text("The build cache was also removed.") : "")
        if failures.isEmpty {
            logs.append(LogEntry(level: .success,
                                 message: L10n.format("%@ The installed app and saves were kept.", [String(describing: removed)])))
            alertMessage = L10n.format("%@ The installed app and saves were kept. Rebuilds stay disabled until you attach the sources again.", [removed])
        } else {
            let detail = failures.joined(separator: "; ")
            logs.append(LogEntry(level: .warning,
                                 message: L10n.format("%@ Some items were kept: %@", [String(describing: removed), String(describing: detail)])))
            alertMessage = L10n.format("%@ Some items were kept: %@", [removed, detail])
        }
    }

    private func resolvedRemovalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func removalLease(for game: PortedGame) -> (() -> Void)? {
        if game.titleId != nil, let release = acquireSaveInstallLease(for: game) { return release }
        if game.titleId == nil, RunningGameMonitor.runningApplication(for: game) == nil { return {} }
        alertMessage = CatalogRemovalFailure.gameBusy.localizedDescription
        return nil
    }

    private func workspaceCanBeTrashed(_ workspace: URL, protecting games: [PortedGame], owner: PortedGame) -> Bool {
        let path = resolvedRemovalPath(workspace)
        return games.allSatisfy { game in
            let otherWorkspace = game.id == owner.id ? nil : game.workspacePath.map { URL(fileURLWithPath: $0) }
            return ([game.url] + game.sources.map(\.url) + [otherWorkspace].compactMap { $0 }).allSatisfy {
                let protected = resolvedRemovalPath($0)
                return protected != path && !protected.hasPrefix(path + "/")
            }
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init) ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    static func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(L10n.context.formatLocale))
    }

    func deletePortedGame(_ game: PortedGame) {
        guard !isBuilding, !isUpdatingApp, !isCleaningStorage, !isCheckingCloudBuild, !cloudLibrary.isWorking else {
            alertMessage = L10n.text("Wait for the current build, storage operation or app update to finish.")
            return
        }
        do {
            let catalog = try catalogRepository.load()
            let games = catalog.nxnativeGames
            guard let current = games.first(where: { $0.id == game.id }),
                  current.url == game.url, current.workspacePath == game.workspacePath, current.sources == game.sources,
                  workspaceCanBeTrashed(game.url, protecting: games.filter { $0.id != game.id }, owner: current) else {
                alertMessage = L10n.format("Could not load the library entry for %@.", [game.name])
                return
            }
            guard let release = removalLease(for: current) else { return }
            defer { release() }
            let appPath = resolvedRemovalPath(current.url)
            let deleteBundle = current.canDeleteAppBundle() && !current.sources.contains {
                let path = resolvedRemovalPath($0.url)
                return path == appPath || path.hasPrefix(appPath + "/")
            }
            var files = deleteBundle && FileManager.default.fileExists(atPath: game.url.path) ? [game.url] : []

            // Remove only the app-owned staged workspace. A folder-mode game's
            // workspace is the user's source folder and must never be touched.
            var removedWorkspace = false
            if let path = game.workspacePath {
                let workspace = URL(fileURLWithPath: path).standardizedFileURL
                if BuildScratch.isManaged(workspace, core: core),
                   FileManager.default.fileExists(atPath: workspace.path),
                   workspaceCanBeTrashed(workspace, protecting: games, owner: current) {
                    files.append(workspace)
                    removedWorkspace = true
                }
            }

            applyCatalog(try catalogRepository.removeNXNativeFiles(id: game.id, from: catalog, files: files, keeping: nil) {
                guard RunningGameMonitor.runningApplication(for: current) == nil else { throw CatalogRemovalFailure.gameBusy }
            })
            if deleteBundle {
                logs.append(LogEntry(level: .warning,
                    message: L10n.format("Game app deleted: %@%@", [String(describing: game.name), String(describing: removedWorkspace ? "; staged workspace removed" : "")])))
            } else {
                logs.append(LogEntry(level: .warning,
                    message: L10n.format("Removed %@ from the library; its source folders were left in place.", [String(describing: game.name)])))
            }
        } catch {
            let message = L10n.format("Failed to delete game: %@", [String(describing: error.localizedDescription)])
            alertMessage = message
            logs.append(LogEntry(level: .error, message: message))
        }
    }

    // MARK: - File Pickers

    func selectRyujinxFolder() {
        guard !isBuilding, !isUpdatingApp else { return }
        OortFilePickerPresentation.open(.folder, title: L10n.text("Ryujinx folder"),
                                        message: L10n.text("Select your Ryujinx folder to automatically locate prod.keys.")) { [weak self] urls in
            guard let self, let url = urls.first, !isBuilding, !isUpdatingApp else { return }
            setup.detectEnvironment(customRyujinxDir: url.path)
        }
    }

    func logURL(for game: PortedGame) -> URL? {
        if let path = game.lastBuild?.logPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        guard let titleId = game.titleId, !titleId.isEmpty else { return nil }
        return launchService.logURL(for: titleId)
    }

    func revealLog(for game: PortedGame) {
        guard let url = logURL(for: game) else {
            logs.append(LogEntry(level: .warning, message: L10n.format("No log path is known for %@.", [String(describing: game.name)])))
            return
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
            logs.append(LogEntry(level: .info,
                                 message: L10n.format("No log yet for %@; opened the log folder.", [String(describing: game.name)])))
        }
    }
}
