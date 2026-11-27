import Foundation
import OortLibrary

/// Shared by build review, disk checks and installation. Resolving a path never moves an app.
public enum GameAppDestination {
    /// A new user may accept ~/Applications without a picker. Never recreate a remembered destination.
    public static func prepareInitialFolder(_ folder: URL, hasExplicitChoice: Bool,
                                            home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let initial = home.appendingPathComponent("Applications")
        guard !hasExplicitChoice, folder.standardizedFileURL.path == initial.standardizedFileURL.path,
              !FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    public static func url(for game: PortedGame, in folder: URL) -> URL {
        if game.status != .notBuilt, game.canDeleteAppBundle(),
           FileManager.default.fileExists(atPath: game.url.path) {
            return game.url
        }
        return url(name: game.name, titleId: game.titleId, in: folder)
    }

    public static func url(name: String, titleId: String?, in folder: URL, reusingExisting: Bool = true,
                           reservedNames: Set<String> = []) -> URL {
        let fm = FileManager.default
        let base = appName(name)
        let title = titleId.flatMap(ImportService.normalizedTitleId)
        func usable(_ url: URL) -> Bool {
            guard !reservedNames.contains(url.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()) else { return false }
            if reusingExisting {
                return !fm.fileExists(atPath: url.path) || (title != nil && titleID(at: url) == title)
            }
            return !fm.fileExists(atPath: url.path) && (try? fm.destinationOfSymbolicLink(atPath: url.path)) == nil
        }
        let preferred = folder.appendingPathComponent(base + ".app")
        if usable(preferred) { return preferred }
        let stem = title.map { "\(base) (\($0))" } ?? base
        var candidate = folder.appendingPathComponent(stem + ".app")
        var number = 2
        while !usable(candidate) {
            candidate = folder.appendingPathComponent("\(stem) \(number).app")
            number += 1
        }
        return candidate
    }

    /// Check before starting the engine. In particular, never recreate a disconnected destination.
    public static func folderProblem(at folder: URL, fileManager fm: FileManager = .default) -> String? {
        var isDirectory: ObjCBool = false
        guard folder.isFileURL, folder.standardizedFileURL.path != "/",
              fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fm.isReadableFile(atPath: folder.path), fm.isExecutableFile(atPath: folder.path) else {
            return L10n.text("The Game apps folder is unavailable. Reconnect it or choose another in Settings → Porting → Game folders.")
        }
        guard fm.isWritableFile(atPath: folder.path) else {
            return L10n.format("The app folder is read-only: %@. Allow writing here before building.", [String(describing: folder.path)])
        }
        return nil
    }

    private static func appName(_ name: String) -> String {
        let value = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Game" : value
    }

    private static func titleID(at app: URL) -> String? {
        ImportService.info(at: app).flatMap(ImportService.titleID(in:))
    }
}
