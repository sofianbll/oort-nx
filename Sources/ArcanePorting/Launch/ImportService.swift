import Darwin
import Foundation
import NXLibraryCore

public struct ImportedApp: Identifiable, Equatable {
    public var id: String { titleId ?? bundleId ?? appURL.path }
    public var name: String
    public var version: String?
    public var titleId: String?
    public var bundleId: String?
    public var appURL: URL
    public var sizeBytes: Int64
    public var modificationDate: Date

    public init(name: String, version: String?, titleId: String?,
                bundleId: String?, appURL: URL, sizeBytes: Int64,
                modificationDate: Date) {
        self.name = name
        self.version = version
        self.titleId = titleId
        self.bundleId = bundleId
        self.appURL = appURL
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
    }
}

public final class ImportService {
    private let fm: FileManager
    private let sizeCache: AppSizeCache
    private let maximumDepth: Int
    private let maximumDirectories: Int
    public private(set) var scanWarnings: [String] = []

    /// Without a cache, sizes are remembered for the life of this service only.
    public init(fileManager: FileManager = .default, sizeCache: AppSizeCache? = nil,
                maximumDepth: Int = 6, maximumDirectories: Int = 4000) {
        self.fm = fileManager
        self.sizeCache = sizeCache ?? AppSizeCache(file: nil)
        self.maximumDepth = max(0, maximumDepth)
        self.maximumDirectories = max(1, maximumDirectories)
    }

    public func scan(directories: [URL], measureSize: Bool = true,
                     cancelled: () -> Bool = { false }) -> [ImportedApp] {
        scan(directories: directories, matchingTitle: nil, measureSize: measureSize, cancelled: cancelled)
    }

    private func scan(directories: [URL], matchingTitle: String?, measureSize: Bool = true,
                      cancelled: () -> Bool = { false }) -> [ImportedApp] {
        var apps: [ImportedApp] = []
        scanWarnings = []
        var queue: [(url: URL, depth: Int)] = []
        var visited: Set<String> = []
        var appPaths: Set<String> = []

        func warn(_ message: String) {
            if scanWarnings.count < 5, !scanWarnings.contains(message) { scanWarnings.append(message) }
        }
        func enqueue(_ url: URL, depth: Int) {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard !visited.contains(canonical) else { return }
            guard queue.count < maximumDirectories else {
                warn("Search stopped at \(maximumDirectories) folders. Choose a Game apps folder closer to your games.")
                return
            }
            visited.insert(canonical)
            queue.append((url, depth))
        }
        defer {
            sizeCache.retain(apps.map(\.appURL))
            sizeCache.save()
        }
        for directory in directories { enqueue(directory, depth: 0) }
        var next = 0
        while next < queue.count, !cancelled() {
            let (directory, depth) = queue[next]
            next += 1
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
                                                  .contentModificationDateKey],
                    options: [.skipsHiddenFiles])
            } catch {
                warn("Cannot read \(directory.path). Check folder access or choose another Game apps folder. (\(error.localizedDescription))")
                continue
            }
            for item in items.sorted(by: { $0.path < $1.path }) {
                if cancelled() { break }
                if item.pathExtension.lowercased() != "app" {
                    if let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                       values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true {
                        if depth < maximumDepth { enqueue(item, depth: depth + 1) }
                        else { warn("Some subfolders are more than \(maximumDepth) levels deep. Choose their parent as Game apps to scan them.") }
                    }
                    continue
                }
                // An app is a boundary, including an unrecognised app. Never discover its nested helpers.
                let canonical = item.resolvingSymlinksInPath().standardizedFileURL.path
                guard appPaths.insert(canonical).inserted else { continue }
                if let info = Self.info(at: item), var app = Self.observation(at: item, info: info, bytes: 0),
                   matchingTitle == nil || matchingTitle == app.titleId {
                    if measureSize, matchingTitle == nil { app.sizeBytes = size(of: item, date: app.modificationDate) }
                    apps.append(app)
                }
            }
        }
        return apps.sorted {
            if $0.modificationDate == $1.modificationDate { return $0.appURL.path < $1.appURL.path }
            return $0.modificationDate > $1.modificationDate
        }
    }

    /// Select one observation per title before merging it into the persisted catalog.
    public func appsForLibrary(scanned: [ImportedApp], existing: [PortedGame]) -> [ImportedApp] {
        var preferred: [String: String] = [:]
        for game in existing {
            if game.cloudImportPending != true, let title = game.titleId, game.url.pathExtension.lowercased() == "app",
               fm.fileExists(atPath: game.url.path) {
                preferred[title.uppercased()] = game.url.resolvingSymlinksInPath().standardizedFileURL.path
            }
        }
        var selected: [String: ImportedApp] = [:]
        // scan() is newest first. A known installed path takes precedence over another copy.
        for app in scanned {
            let key = app.id.uppercased()
            if let path = preferred[key], app.appURL.resolvingSymlinksInPath().standardizedFileURL.path != path {
                continue
            }
            if selected[key] == nil { selected[key] = app }
        }
        return selected.values.sorted {
            if $0.modificationDate == $1.modificationDate { return $0.appURL.path < $1.appURL.path }
            return $0.modificationDate > $1.modificationDate
        }
    }

    public func makeGame(from app: ImportedApp) -> PortedGame {
        var game = PortedGame(
            name: app.name, url: app.appURL, platform: .macApp,
            sizeBytes: app.sizeBytes, modificationDate: app.modificationDate,
            bundleId: app.bundleId,
            titleId: app.titleId.flatMap(Self.normalizedTitleId),
            versionString: app.version
        )
        game.status = .builtSourcesMissing
        game.toolchain = ToolchainInfo(
            verified: false,
            note: "Imported build; build record unavailable"
        )
        game.settings = GameRuntimeConfig()
        return game
    }

    static func normalizedTitleId(_ value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("0x") { text.removeFirst(2) }
        guard text.count == 16,
              text.allSatisfy({ $0.isHexDigit }) else { return nil }
        return text.uppercased()
    }

    static func titleID(in info: [String: Any]) -> String? {
        let bundleID = info["CFBundleIdentifier"] as? String
        guard bundleID != AppDataProfile.identifier, bundleID != AppDataProfile.legacyIdentifier else { return nil }
        let suffix = bundleID?.hasPrefix("org.nxnative.") == true
            ? bundleID?.split(separator: ".").last.map(String.init) : nil
        return [info["DMTitleID"] as? String, suffix].compactMap { $0 }.compactMap(normalizedTitleId).first
    }

    static func info(at app: URL) -> [String: Any]? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? SaveFiles.readRegular(plist, limit: 1_048_576),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return object
    }

    static func verifiedIdentity(of app: URL, titleID: String? = nil) throws -> [String: Any] {
        guard app.isFileURL, app.pathExtension.lowercased() == "app",
              let info = info(at: app), let found = self.titleID(in: info), SaveLocation.validID(found),
              titleID == nil || found == titleID else { throw CloudArchiveError.invalidApp }
        return info
    }

    private static func observation(at url: URL, info: [String: Any], bytes: Int64) -> ImportedApp? {
        guard let titleID = titleID(in: info) else { return nil }
        return .init(name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                        ?? url.deletingPathExtension().lastPathComponent,
                     version: info["CFBundleShortVersionString"] as? String, titleId: titleID,
                     bundleId: info["CFBundleIdentifier"] as? String, appURL: url, sizeBytes: bytes,
                     modificationDate: (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                         .contentModificationDate) ?? .distantPast)
    }

    public struct Adoption {
        public let app: ImportedApp
        public let existing: PortedGame?
        public let destination: URL
        public var conflicts: Bool { existing != nil || discovered }
        fileprivate let discovered: Bool
        fileprivate let previous: String?
        fileprivate let volume: stat
    }

    /// A hidden copy on the destination volume, ready for a single atomic publish.
    public struct StagedAdoption {
        public let plan: Adoption
        public let app: ImportedApp
        public let contentUnverified: Bool
        fileprivate let incoming: URL
    }

    public func prepareAdoption(from url: URL, into folder: URL, existing: [PortedGame]) throws -> Adoption {
        guard url.isFileURL, folder.isFileURL else { throw CloudArchiveError.invalidApp }
        let source = url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent, isDirectory: true)
        let folder = folder.resolvingSymlinksInPath().standardizedFileURL
        if let problem = GameAppDestination.folderProblem(at: folder) {
            throw BuildInstallError.replaceFailed(problem)
        }
        // This identity only plans the destination and confirmation; trust the staged copy below.
        let info = try Self.verifiedIdentity(of: source)
        guard let app = Self.observation(at: source, info: info, bytes: 0), let title = app.titleId,
              try CloudArchiveInventory.node(at: source).st_mode & S_IFMT == S_IFDIR else {
            throw CloudArchiveError.invalidApp
        }
        let known = existing.first { $0.titleId?.caseInsensitiveCompare(title) == .orderedSame }
        let discovered = scan(directories: [folder], matchingTitle: title)
        let registered = known?.canDeleteAppBundle() == true ? known?.url : nil
        let protected = existing.flatMap { game in
            game.sources.map(\.url) + [game.workspacePath.map { URL(fileURLWithPath: $0) }].compactMap { $0 }
        }.map { $0.resolvingSymlinksInPath().path }
        let previousURL = ([registered].compactMap { $0 } + discovered.map(\.appURL)).first { candidate in
            let path = candidate.resolvingSymlinksInPath().path
            return path.hasPrefix(folder.path + "/") && path.caseInsensitiveCompare(source.path) != .orderedSame &&
                !source.path.hasPrefix(path + "/") && !protected.contains { $0 == path || $0.hasPrefix(path + "/") } &&
                Self.info(at: candidate).flatMap(Self.titleID(in:)) == title
        }.map {
            $0.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent($0.lastPathComponent)
        }
        let target = previousURL ?? GameAppDestination.url(name: app.name, titleId: title, in: folder, reusingExisting: false)
        let destination = URL(fileURLWithPath: target.path, isDirectory: true)
        guard !destination.path.hasPrefix(source.path + "/") else { throw CloudArchiveError.unsafePath }
        let previous = try previousURL.map(Self.adoptionSignature)
        let volume = try CloudArchiveInventory.node(at: destination.deletingLastPathComponent())
        return .init(app: app, existing: known, destination: destination, discovered: !discovered.isEmpty,
                     previous: previous, volume: volume)
    }

    public func stageAdoption(_ plan: Adoption, replacing: Bool, archive: CloudGameArchive? = nil,
                              capacity: (URL) -> Int64? = {
                                  (try? FileManager.default.attributesOfFileSystem(forPath: $0.path)[.systemFreeSize] as? NSNumber)?.int64Value
                              }) async throws -> StagedAdoption {
        guard !plan.conflicts || replacing else { throw CloudArchiveError.confirmationRequired }
        let source = plan.app.appURL
        let initial = try CloudArchiveInventory.signature(source, kind: .app)
        guard !initial.hasExcludedFiles else { throw CloudArchiveError.excludedFiles }
        let parent = plan.destination.deletingLastPathComponent()
        try Self.checkAdoptionVolume(plan)
        let overhead = Int64(initial.entries.count) * 16_384 + 1_048_576
        guard let free = capacity(parent), free >= overhead, initial.bytes <= free - overhead else {
            throw CloudArchiveError.insufficientSpace
        }
        let stage = parent.appendingPathComponent(".arcane-adopt-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let incoming = stage.appendingPathComponent(plan.destination.lastPathComponent)
        do {
            try fm.copyItem(at: source, to: incoming)
            let copied = try CloudArchiveInventory.signature(incoming, kind: .app)
            guard copied.entries == initial.entries, !copied.hasExcludedFiles,
                  try CloudArchiveInventory.signature(source, kind: .app).sha256 == initial.sha256 else {
                throw CloudArchiveError.localChanged
            }
            try Self.repairAdoptionCopy(incoming, entries: copied.entries)
            let info = try Self.verifiedIdentity(of: incoming, titleID: plan.app.titleId)
            var contentUnverified = false
            if try BuildOutputInstaller.checkSignature(incoming).status != 0 {
                guard let title = plan.app.titleId else { throw CloudArchiveError.invalidApp }
                let manifests = try await archive?.adoptionManifests(titleID: title) ?? []
                if manifests.isEmpty {
                    contentUnverified = true
                } else {
                    let snapshot = try CloudArchiveInventory.signature(incoming, kind: .app)
                    let actual = try CloudArtifactFiles.entries(at: incoming, snapshot: snapshot, excludingSignatures: true)
                    let matches = manifests.contains { manifest in
                        guard let files = manifest.artifacts.first(where: { $0.kind == .app })?.files else { return false }
                        let expected = files.entries.filter { !CloudArtifactFiles.isSignaturePath($0.relative) }
                        return actual == expected.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
                    }
                    guard matches else { throw CloudArchiveError.unknownAppContents }
                    guard try CloudArchiveInventory.signature(incoming, kind: .app).sha256 == snapshot.sha256 else {
                        throw CloudArchiveError.localChanged
                    }
                }
                try Task.checkCancellation()
                try BuildOutputInstaller.signAdHoc(incoming)
            }
            let bytes = try CloudArchiveInventory.signature(incoming, kind: .app).bytes
            guard var app = Self.observation(at: incoming, info: info, bytes: bytes) else { throw CloudArchiveError.invalidApp }
            app.name = plan.app.name
            app.appURL = plan.destination
            return .init(plan: plan, app: app, contentUnverified: contentUnverified, incoming: incoming)
        } catch {
            try? fm.removeItem(at: stage)
            throw error
        }
    }

    static func repairAdoptionCopy(_ app: URL, entries: [CloudArchiveInventory.Entry]) throws {
        let fm = FileManager.default
        var types = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.type) })
        let names = Set(types.keys.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        for entry in entries where entry.type == "F" && entry.path.hasSuffix(CloudArtifactFiles.linkSuffix) {
            let relative = String(entry.path.dropLast(CloudArtifactFiles.linkSuffix.count))
            guard SaveFiles.validRelative(relative), !CloudArchiveInventory.isExcluded(relative, .app),
                  !names.contains(relative.precomposedStringWithCanonicalMapping.lowercased()) else {
                throw CloudArchiveError.unsafePath
            }
            let sidecar = app.appendingPathComponent(entry.path)
            try CloudArtifactFiles.restoreLink(sidecar, to: app.appendingPathComponent(relative), relative: relative, kind: .app)
            try fm.removeItem(at: sidecar)
        }
        for entry in entries {
            try Task.checkCancellation()
            let restoredLink = entry.type == "F" && entry.path.hasSuffix(CloudArtifactFiles.linkSuffix)
            var path = restoredLink ? String(entry.path.dropLast(CloudArtifactFiles.linkSuffix.count)) : entry.path
            let url = path.isEmpty ? app : app.appendingPathComponent(path)
            if removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0, errno != ENOATTR && errno != ENOTSUP {
                throw CloudArchiveError.invalidApp
            }
            if restoredLink { continue }
            // Drive's browser ZIP can add .xml to the outer seal as well as the nested seals.
            if entry.type == "F", url.lastPathComponent == "CodeResources.xml",
               url.deletingLastPathComponent().lastPathComponent == "_CodeSignature" {
                let seal = url.deletingPathExtension()
                if !SaveFiles.exists(seal) {
                    try fm.moveItem(at: url, to: seal)
                    types.removeValue(forKey: path)
                    path = String(path.dropLast(".xml".count))
                    types[path] = "F"
                }
            }
            if entry.type == "F", entry.path.hasPrefix("Contents/MacOS/"),
               entry.path.split(separator: "/").count == 3, entry.mode & 0o100 == 0,
               chmod(url.path, mode_t(entry.mode | 0o111)) != 0 {
                throw CloudArchiveError.invalidApp
            }
            let parts = path.split(separator: "/")
            if entry.type == "F", parts.count == 6, parts[0] == "Contents", parts[1] == "PlugIns",
               parts[2].hasSuffix(".bundle"), parts[3] == "Contents", parts[4] == "_CodeSignature",
               parts[5] == "CodeResources" {
                let signature = String(path.dropLast("CodeResources".count)) + "CodeSignature"
                if types[signature] == nil {
                    try Data().write(to: app.appendingPathComponent(signature), options: .withoutOverwriting)
                }
            }
        }

        // Use the outer seal to distinguish flattened links from legitimate independent resources.
        // Only accept the relative layout emitted by nxnative's packer; codesign still verifies the seal and targets.
        let sealPath = "Contents/_CodeSignature/CodeResources"
        guard types[sealPath] == "F",
              let data = try? SaveFiles.readRegular(app.appendingPathComponent(sealPath), limit: 32 * 1_048_576),
              let seal = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let files = seal["files2"] as? [String: [String: Any]] else { return }
        for (path, entry) in files {
            guard path.hasPrefix("Resources/"), SaveFiles.validRelative(path),
                  let link = entry["symlink"] as? String else { continue }
            let relative = "Contents/" + path
            let url = app.appendingPathComponent(relative)
            let parent = relative.split(separator: "/").dropLast().joined(separator: "/")
            let depth = path.split(separator: "/").count - 1
            let parts = link.split(separator: "/")
            guard parts.count > depth + 1, parts[depth] == "PlugIns", parts[depth + 1].hasSuffix(".bundle"),
                  types[parent] == "D", types[relative] != "L", types[relative + CloudArtifactFiles.linkSuffix] != "F"
            else { continue }
            let target = "PlugIns/\(parts[depth + 1])/Contents/" + path
            guard link == String(repeating: "../", count: depth) + target,
                  let targetType = types["Contents/" + target], targetType == "F" || targetType == "D" else { continue }
            try SaveFiles.safePath(url.deletingLastPathComponent())
            try SaveFiles.safePath(app.appendingPathComponent("Contents/" + target))
            if types[relative] != nil { try fm.removeItem(at: url) }
            try fm.createSymbolicLink(atPath: url.path, withDestinationPath: link)
        }
    }

    /// Roll back the rename if the catalog cannot record the verified copy.
    public func publishAdoption(_ staged: StagedAdoption, record: (ImportedApp) throws -> Void) throws {
        let plan = staged.plan
        try Self.checkAdoptionVolume(plan)
        let current: String?
        do { current = try Self.adoptionSignature(plan.destination) }
        catch CloudArchiveError.localMissing { current = nil }
        guard current == plan.previous else { throw CloudArchiveError.localChanged }
        let replace = current != nil
        try BuildInstallIO().publish(staged.incoming, plan.destination, replace)
        do { try record(staged.app) }
        catch {
            // Do not remove the staging bundle if the rollback itself fails.
            guard (try? BuildInstallIO().publish(plan.destination, staged.incoming, replace)) != nil else {
                throw CloudArchiveError.installFailed
            }
            throw error
        }
    }

    private static func adoptionSignature(_ bundle: URL) throws -> String {
        let snapshot = try CloudArchiveInventory.signature(bundle, kind: .app)
        guard !snapshot.hasExcludedFiles else { throw CloudArchiveError.excludedFiles }
        return snapshot.sha256
    }

    private static func checkAdoptionVolume(_ plan: Adoption) throws {
        let parent = plan.destination.deletingLastPathComponent()
        try SaveFiles.safePath(parent)
        let volume = try CloudArchiveInventory.node(at: parent)
        guard volume.st_dev == plan.volume.st_dev, volume.st_ino == plan.volume.st_ino else {
            throw CloudArchiveError.localChanged
        }
    }

    public func cleanupAdoption(_ staged: StagedAdoption, published: Bool) {
        if published && staged.plan.previous != nil {
            // Keep the original in staging if the destination volume has no Trash.
            guard (try? fm.trashItem(at: staged.incoming, resultingItemURL: nil)) != nil else { return }
        }
        try? fm.removeItem(at: staged.incoming.deletingLastPathComponent())
    }

    /// The remembered size while the app's date is unchanged, else measured. Each new size is saved at once,
    /// so quitting during a long first scan keeps the apps already measured.
    private func size(of app: URL, date: Date) -> Int64 {
        if let known = sizeCache.size(for: app, date: date) { return known }
        let measured = DirectorySize.bytes(at: app)
        sizeCache.set(measured, for: app, date: date)
        sizeCache.save()
        return measured
    }
}
