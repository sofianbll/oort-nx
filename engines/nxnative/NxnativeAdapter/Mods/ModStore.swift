import Foundation
import CryptoKit
import OortLibrary

/// What Arcane remembers about one mod of a game, in the game's records file (list order = overlay order).
public struct ModRecord: Codable, Equatable, Sendable {
    public var folderName: String
    public var isOn: Bool
    public var gameBananaModID: Int?
    public var gameBananaFileID: Int?
    public var md5: String?
    public var installedAt: Date?
    /// Legacy records without this field may own an entry in the RomFS overlay.
    var codeOnly: Bool?

    public init(folderName: String, isOn: Bool, gameBananaModID: Int? = nil, gameBananaFileID: Int? = nil,
                md5: String? = nil, installedAt: Date? = nil) {
        self.folderName = folderName
        self.isOn = isOn
        self.gameBananaModID = gameBananaModID
        self.gameBananaFileID = gameBananaFileID
        self.md5 = md5
        self.installedAt = installedAt
    }
}

/// Two mods that are on and change at least one same file; `upper` comes first in the overlay and wins.
public struct ModConflict: Equatable, Sendable {
    public let upper: String
    public let lower: String

    public init(upper: String, lower: String) {
        self.upper = upper
        self.lower = lower
    }

    public var message: String { L10n.format("%1$@ and %2$@ change the same files: %1$@ takes priority.", [upper, lower]) }
}

public enum ModStoreError: Error, Equatable {
    /// The game is running: its launcher read the overlay at start and the mods stay as they are until it quits.
    case notAllowed
    /// The folder holds neither a RomFS tree nor ExeFS patches.
    case notAMod(String)
    /// `:` separates `DM_ROMFS_OVERLAY`'s folders, so a folder name with one cannot be on.
    case colonInName(String)
    /// The active mods' paths would not fit the launcher's line (`overlayLimit`).
    case overlayTooLong
    case invalidCodeMod(String)
    case duplicateFolderName(String)
    case writeFailed(String)
}

/// A game's RomFS and ExeFS mods share one ordered record. RomFS applies through `DM_ROMFS_OVERLAY` on Play;
/// ExeFS builds use a snapshot of enabled patches; Play can switch the built group on or off together.
/// Every change requires `canWrite`, and removed mods go to the Trash.
public struct ModStore: Sendable {
    /// The Mac launcher reads `env.txt` lines into a 4096-byte buffer: `DM_ROMFS_OVERLAY=` (17) + value + newline
    /// must fit in 4095 (dm/mac/launcher.c `env_file`); the host keeps the value in `overlay[4096]`.
    public static let overlayLimit = 4077
    public static let overlayKey = "DM_ROMFS_OVERLAY"

    public let supportFolder: URL
    public let recordsFile: URL
    public let titleID: String
    private let canWrite: @Sendable () -> Bool
    private let allowsAutomaticMaintenance: Bool
    private let trash: @Sendable (URL) throws -> Void

    public init(supportFolder: URL, recordsFile: URL, titleID: String,
                canWrite: @escaping @Sendable () -> Bool, trash: @escaping @Sendable (URL) throws -> Void, allowsAutomaticMaintenance: Bool = true) {
        self.supportFolder = supportFolder
        self.recordsFile = recordsFile
        self.titleID = titleID.uppercased()
        self.canWrite = canWrite
        self.allowsAutomaticMaintenance = allowsAutomaticMaintenance
        self.trash = trash
    }

    /// The Mods row's value: "None" without mods, "Off" when none is on, otherwise "<n> on".
    public static func rowValue(on: Int, total: Int) -> String {
        total == 0 ? L10n.text("None") : on == 0 ? L10n.text("Off") : L10n.format("%@ on", [String(on)])
    }

    public var modsFolder: URL { supportFolder.appendingPathComponent("mods") }
    public var codeModsFolder: URL { supportFolder.appendingPathComponent("code-mods") }
    public var envFile: URL { supportFolder.appendingPathComponent("env.txt") }

    // MARK: - Reading

    /// Recorded mods in their order (only those whose folder exists), then folders without a record, off, by name.
    public func mods() -> [LocalMod] {
        mods(entries: entries, records: loadRecords())
    }

    private var entries: [URL] {
        (ModFolderScanner.entries(in: modsFolder) + ModFolderScanner.entries(in: codeModsFolder))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func checkedEntries(in folder: URL) throws -> [URL] {
        do {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnknown) }
            return try ModFolderScanner.checkedEntries(in: folder)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
    }

    private func checkedEntries() throws -> [URL] {
        let files = try checkedEntries(in: modsFolder)
        let code = try checkedEntries(in: codeModsFolder)
        let names = Set(files.map(\.lastPathComponent))
        if let duplicate = code.map(\.lastPathComponent).filter({ names.contains($0) }).min() {
            throw ModStoreError.duplicateFolderName(duplicate)
        }
        return files + code
    }

    private func mods(entries: [URL], records: [ModRecord]) -> [LocalMod] {
        let folders = Dictionary(entries.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        let recorded = records.filter { folders[$0.folderName] != nil }
        let known = Set(recorded.map(\.folderName))
        let list = recorded.compactMap { record in folders[record.folderName].map { mod($0, on: record.isOn) } }
            + folders.keys.sorted().filter { !known.contains($0) }.compactMap { folders[$0].map { mod($0, on: false) } }
        return allowsAutomaticMaintenance ? list : readingLiveOverlay(list)
    }

    /// A copied record orders metadata; the actual game's overlay determines what is active.
    /// Reading a separate profile must neither write the overlay nor display stale enabled states.
    private func readingLiveOverlay(_ list: [LocalMod]) -> [LocalMod] {
        guard list.contains(where: { $0.romfs != nil }),
              let text = try? String(contentsOf: envFile, encoding: .utf8) else { return list }
        let value = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix(Self.overlayKey + "=") }
            .map { String($0.dropFirst(Self.overlayKey.count + 1)) } ?? ""
        let paths = value.split(separator: ":").map { URL(fileURLWithPath: String($0)).standardizedFileURL.resolvingSymlinksInPath().path }
        var order: [String: Int] = [:]
        for (index, path) in paths.enumerated() where order[path] == nil { order[path] = index }
        var observed: [(rank: Int, index: Int, item: LocalMod)] = []
        for (index, original) in list.enumerated() {
            if original.exefs != nil {
                observed.append((rank: Int.max, index: index, item: original))
                continue
            }
            var item = original
            let rank: Int? = item.romfs.flatMap { order[$0.standardizedFileURL.resolvingSymlinksInPath().path] }
            item.isOn = rank != nil
            observed.append((rank: rank ?? Int.max, index: index, item: item))
        }
        observed.sort { first, second in
            if first.rank == second.rank { return first.index < second.index }
            return first.rank < second.rank
        }
        return observed.map { $0.item }
    }

    /// The overlay value for enabled mods, top first; nil when none is on.
    public func overlayValue() -> String? { overlay(for: mods()) }

    /// The records of mods installed from GameBanana whose folder still exists, by GameBanana mod id.
    public func gameBananaRecords() -> [Int: ModRecord] {
        gameBananaRecords(entries: entries, records: loadRecords())
    }

    private func gameBananaRecords(entries: [URL], records: [ModRecord]) -> [Int: ModRecord] {
        let present = Set(entries.map(\.lastPathComponent))
        var found: [Int: ModRecord] = [:]
        for record in records where present.contains(record.folderName) {
            if let id = record.gameBananaModID, found[id] == nil { found[id] = record }
        }
        return found
    }

    /// Pairs of mods that are on and share a file, in list order. Only pass true when this game's engine guarantees
    /// it merges the Z-A descriptor; unknown or older builds must retain the warning.
    public func conflicts(mergesTrpfd: Bool = false) -> [ModConflict] {
        let on = mods().filter { $0.isOn }.compactMap { mod in
            mod.romfs.map { romfs in
                var files = ModFolderScanner.files(under: romfs)
                if mergesTrpfd && titleID == InstalledEngineCapabilities.trpfdTitleID { files.remove("arc/data.trpfd") }
                return (mod.folderName, files)
            }
        }
        var found: [ModConflict] = []
        for i in on.indices {
            for j in on.indices where j > i && !on[i].1.isDisjoint(with: on[j].1) {
                found.append(ModConflict(upper: on[i].0, lower: on[j].0))
            }
        }
        return found
    }

    /// Cleans abandoned install staging, never a previous version held for recovery.
    public func removeLeftoverInstalls() {
        guard allowsAutomaticMaintenance, canWrite() else { return }
        let fm = FileManager.default
        for root in [modsFolder, codeModsFolder] where ModFolderScanner.isRealDirectory(root) {
            for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where name.hasPrefix(".installing-") {
                try? fm.removeItem(at: root.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Changing

    public func onlineRiskMods() -> [String: ModFolderScanner.OnlineContent] {
        Dictionary(mods().compactMap { mod in
            guard mod.isOn, let romfs = mod.romfs else { return nil }
            let content = ModFolderScanner.onlineContent(under: romfs)
            return content == .visual ? nil : (mod.folderName, content)
        }, uniquingKeysWith: { first, _ in first })
    }

    public func disableOnlineRiskMods() throws {
        try change { list in
            for index in list.indices where list[index].isOn {
                if let romfs = list[index].romfs, ModFolderScanner.onlineContent(under: romfs) != .visual {
                    list[index].isOn = false
                }
            }
        }
    }

    public func setOn(_ on: Bool, folderName: String) throws {
        try change { list in
            guard let index = list.firstIndex(where: { $0.folderName == folderName }) else { return }
            if on {
                guard list[index].isMod else { throw ModStoreError.notAMod(folderName) }
                guard !folderName.contains(":") else { throw ModStoreError.colonInName(folderName) }
            }
            list[index].isOn = on
        }
    }

    /// Moves a mod within its section, leaving the other section's slots untouched.
    public func move(folderName: String, by offset: Int) throws {
        try change { list in
            guard let mod = list.first(where: { $0.folderName == folderName }) else { return }
            let slots = list.indices.filter { list[$0].isCodeMod == mod.isCodeMod }
            var section = slots.map { list[$0] }
            guard let index = section.firstIndex(where: { $0.folderName == folderName }) else { return }
            let target = min(max(index + offset, 0), section.count - 1)
            guard target != index else { return }
            section.insert(section.remove(at: index), at: target)
            for (slot, mod) in zip(slots, section) { list[slot] = mod }
        }
    }

    /// Whether changes are allowed now (the game is not running).
    public var isWritable: Bool { canWrite() }

    /// Copies a chosen folder's ExeFS patches, leaving the original alone.
    public func importCodeMod(from source: URL) throws {
        guard canWrite() else { throw ModStoreError.notAllowed }
        guard ModFolderScanner.isRealDirectory(source) else { throw ModStoreError.invalidCodeMod(source.lastPathComponent) }
        let tree = source.appendingPathComponent("exefs")
        try adopt(romfs: nil, exefs: tree, name: source.lastPathComponent, record: nil)
    }

    /// A GameBanana update keeps the name, position and switch, even if the new archive changes kind.
    @discardableResult
    func adopt(romfs: URL?, exefs: URL?, name: String, record: ModRecord?, turnOn: Bool = true) throws -> LocalMod {
        guard canWrite() else { throw ModStoreError.notAllowed }
        let fm = FileManager.default
        let entries = try checkedEntries()
        let stored = try checkedRecords()
        let previous = record?.gameBananaModID.flatMap { gameBananaRecords(entries: entries, records: stored)[$0] }
        let used = Set(entries.map(\.lastPathComponent))
        let name = previous?.folderName ?? ModFolderName.make(from: name, modID: record?.gameBananaModID ?? 0, existing: used)
        var list = mods(entries: entries, records: stored)
        let index = previous.flatMap { old in list.firstIndex { $0.folderName == old.folderName } } ?? list.endIndex
        let old = previous == nil || index == list.endIndex ? nil : list[index]
        let root = exefs == nil ? modsFolder : codeModsFolder
        let folder = root.appendingPathComponent(name)
        let staging = root.appendingPathComponent(".installing-\(UUID().uuidString)")
        let candidate = staging.appendingPathComponent("candidate")
        let backup = root.appendingPathComponent(".previous-\(UUID().uuidString)").appendingPathComponent(name)
        var keepBackup = false
        defer {
            try? fm.removeItem(at: staging)
            if !keepBackup { try? fm.removeItem(at: backup.deletingLastPathComponent()) }
        }

        var local = LocalMod(folderName: name, folder: folder,
                             romfs: romfs.map { _ in folder.appendingPathComponent("romfs") },
                             exefs: exefs.map { _ in folder.appendingPathComponent("exefs") }, isOn: old?.isOn ?? turnOn)
        guard local.isMod else { throw ModStoreError.notAMod(name) }
        if old != nil { list.remove(at: index) }
        list.insert(local, at: index)
        if let value = overlay(for: list), value.utf8.count > Self.overlayLimit {
            local.isOn = false
            list[index].isOn = false
        }
        var adopted = record
        adopted?.folderName = name
        do {
            try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
            if let exefs {
                for file in try Self.patchFiles(in: exefs, name: name) {
                    let destination = candidate.appendingPathComponent("exefs").appendingPathComponent(file.relative)
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: file.url, to: destination)
                }
            }
            if let romfs { try fm.moveItem(at: romfs, to: candidate.appendingPathComponent("romfs")) }
            guard canWrite() else { throw ModStoreError.notAllowed }
            if let old {
                try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: old.folder, to: backup)
            }
            var published = false
            do {
                try fm.moveItem(at: candidate, to: folder)
                published = true
                try save(list, previous: stored, replacing: adopted)
            } catch {
                if published { try? fm.removeItem(at: folder) }
                if let old {
                    do { try fm.moveItem(at: backup, to: old.folder) }
                    catch { keepBackup = true; throw ModStoreError.writeFailed("\(backup.path): \(error.localizedDescription)") }
                }
                throw error
            }
            if old != nil {
                // Keep the previous version if the volume's Trash is unavailable.
                do { try trash(backup) } catch {
                    keepBackup = true
                    throw ModStoreError.writeFailed("\(backup.path): \(error.localizedDescription)")
                }
            }
        } catch let error as ModStoreError {
            throw error
        } catch {
            throw ModStoreError.writeFailed(error.localizedDescription)
        }
        return local
    }

    /// Moves the mod's folder to the Trash and forgets it.
    public func remove(folderName: String) throws {
        guard canWrite() else { throw ModStoreError.notAllowed }
        let stored = try checkedRecords()
        let list = mods(entries: try checkedEntries(), records: stored)
        guard let mod = list.first(where: { $0.folderName == folderName }) else { return }
        do { try trash(mod.folder) } catch { throw ModStoreError.writeFailed(error.localizedDescription) }
        try save(list.filter { $0.folderName != folderName }, previous: stored)
    }

    /// Drops records whose folder is gone and brings the overlay line in line with the list. Does nothing while the
    /// game runs, or before Arcane has managed this game's mods (no records yet: a hand-written overlay stays). A
    /// failed read or overlong overlay leaves both the records and `env.txt` intact.
    public func sync(automatic: Bool = true) throws {
        guard !automatic || allowsAutomaticMaintenance else { return }
        guard canWrite(), FileManager.default.fileExists(atPath: recordsFile.path) else { return }
        let stored = try readRecords()
        let list = mods(entries: try checkedEntries(), records: stored)
        let value = overlay(for: list)
        if let value, value.utf8.count > Self.overlayLimit { throw ModStoreError.overlayTooLong }
        let recorded = Set(stored.map(\.folderName))
        let kept = list.filter { recorded.contains($0.folderName) }.map(\.folderName)
        if stored.contains(where: { $0.codeOnly != true }) { try writeOverlay(value) }
        if kept != stored.map(\.folderName) {
            try write(records: stored.filter { kept.contains($0.folderName) })
        }
    }

    // MARK: - Internals

    private func change(_ edit: (inout [LocalMod]) throws -> Void) throws {
        guard canWrite() else { throw ModStoreError.notAllowed }
        let stored = try checkedRecords()
        var list = mods(entries: try checkedEntries(), records: stored)
        try edit(&list)
        if let value = overlay(for: list), value.utf8.count > Self.overlayLimit { throw ModStoreError.overlayTooLong }
        try save(list, previous: stored)
    }

    /// Records the whole list (hand-installed folders get a record where they stand) and writes the overlay.
    private func save(_ list: [LocalMod], previous stored: [ModRecord], replacing: ModRecord? = nil) throws {
        var previous = Dictionary(stored.map { ($0.folderName, $0) }, uniquingKeysWith: { first, _ in first })
        if let replacing { previous[replacing.folderName] = replacing }
        let records = list.map { mod -> ModRecord in
            var record = previous[mod.folderName] ?? ModRecord(folderName: mod.folderName, isOn: false)
            record.isOn = mod.isOn
            record.codeOnly = mod.romfs == nil && mod.exefs != nil ? true : nil
            return record
        }
        let hadRecords = FileManager.default.fileExists(atPath: recordsFile.path)
        try write(records: records)
        guard stored.contains(where: { $0.codeOnly != true }) || records.contains(where: { $0.codeOnly != true }) else { return }
        do { try writeOverlay(overlay(for: list)) }
        catch {
            if hadRecords { try write(records: stored) }
            else { try FileManager.default.removeItem(at: recordsFile) }
            throw error
        }
    }

    private func mod(_ entry: URL, on: Bool) -> LocalMod {
        let name = entry.lastPathComponent
        let isCode = entry.deletingLastPathComponent().lastPathComponent == codeModsFolder.lastPathComponent
        // Foundation can enumerate `/var` as `/private/var`; keep the store's spelling in overlay paths.
        let folder = (isCode ? codeModsFolder : modsFolder).appendingPathComponent(name)
        let romfs = ModFolderScanner.romfs(in: folder, titleID: titleID)
        let tree = folder.appendingPathComponent("exefs")
        let exefs = isCode && ModFolderScanner.isRealDirectory(tree) ? tree : nil
        return LocalMod(folderName: name, folder: folder, romfs: romfs, exefs: exefs,
                        isOn: on && (romfs != nil || exefs != nil) && !name.contains(":"))
    }

    private func overlay(for list: [LocalMod]) -> String? {
        let paths = list.filter { $0.isOn }.compactMap { $0.romfs?.path }
        return paths.isEmpty ? nil : paths.joined(separator: ":")
    }

    private func writeOverlay(_ value: String?) throws {
        do { try EnvFileEditor.set(Self.overlayKey, to: value, in: envFile) }
        catch { throw ModStoreError.writeFailed(error.localizedDescription) }
    }

    private func loadRecords() -> [ModRecord] {
        (try? checkedRecords()) ?? []
    }

    private func checkedRecords() throws -> [ModRecord] {
        do { return try readRecords() }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return [] }
    }

    private func readRecords() throws -> [ModRecord] {
        try JSONDecoder().decode([ModRecord].self, from: Data(contentsOf: recordsFile))
    }

    private func write(records: [ModRecord]) throws {
        do {
            try FileManager.default.createDirectory(at: recordsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: recordsFile, options: .atomic)
        } catch {
            throw ModStoreError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Code mods at build time

    /// The parent folder is the switch name. Like hle_mods.c, use dm_code.tsv as a marker:
    /// its rows list applied patch files, not mod names, and the host does not read them.
    public static func bundledCodeMods(in app: URL) -> [String]? {
        let root = app.appendingPathComponent("Contents/Resources/dm/mods")
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter {
            !$0.hasPrefix(".") && fm.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("dm_code.tsv").path)
        }
        return names.isEmpty ? nil : names.sorted()
    }

    public func codeModsNeedRebuild(app: URL, build: BuildRecord? = nil) -> Bool {
        codeModState(app: app, build: build).needsRebuild
    }

    public func codeModsLaunchEnvironment(app: URL, build: BuildRecord? = nil, online: Bool = false) -> [String: String] {
        if online, let first = Self.bundledCodeMods(in: app)?.first { return ["DM_MODS_OFF": first] }
        guard let off = codeModState(app: app, build: build).off else { return [:] }
        return ["DM_MODS_OFF": off]
    }

    private func codeModState(app: URL, build: BuildRecord?) -> (needsRebuild: Bool, off: String?) {
        // Don't reuse a record for a moved app or an external replacement without a patched copy.
        let built = Self.bundledCodeMods(in: app) ?? (
            build?.outputPath == app.path && ModFolderScanner.isRealDirectory(app.appendingPathComponent("Contents/Resources/dm/codemods"))
                ? build?.builtCodeMods ?? [] : []
        )
        guard let selection = try? localCodeMods(),
              let selected = try? codeMods(selection.filter(\.isOn), stage: nil) else { return (true, built.first) }
        if selected.isEmpty {
            // Without a local build or selectable patches, leave a transferred bundle's defaults alone.
            return (false, build == nil && selection.isEmpty ? nil : built.first)
        }
        guard Set(selected.map(Self.codeModIdentity)) == Set(built.map(Self.codeModIdentity)) else { return (true, nil) }
        return (false, "") // Even an empty launch value takes precedence over env.txt.
    }

    private static func codeModIdentity(_ name: String) -> Substring {
        // The engine rejects overlapping patches, so changing only list order doesn't change the built code.
        let position = name.prefix(8)
        guard position.utf8.count == 8, position.utf8.allSatisfy({ (48...57).contains($0) }),
              name.dropFirst(8).first == "-" else { return name[...] }
        return name.dropFirst(9)
    }

    func enabledCodeMods() throws -> [LocalMod] {
        try localCodeMods().filter(\.isOn)
    }

    private func localCodeMods() throws -> [LocalMod] {
        let entries = try checkedEntries().filter {
            $0.deletingLastPathComponent().lastPathComponent == codeModsFolder.lastPathComponent
        }
        guard !entries.isEmpty else { return [] }
        return mods(entries: entries, records: try checkedRecords()).filter { $0.exefs != nil }
    }

    /// The engine reads child folders in name order and applies the whole set together. Prefix with the
    /// selected order and a fingerprint of the patch paths/content, which the engine preserves in its metadata.
    func codeMods(_ list: [LocalMod], stage: URL?) throws -> [String] {
        var names: [String] = []
        let fm = FileManager.default
        for (index, mod) in list.enumerated() {
            guard let tree = mod.exefs else { continue }
            let patches = try Self.patchFiles(in: tree, name: mod.folderName)
            let candidate = stage?.appendingPathComponent(".candidate")
            var hash = SHA256()
            hash.update(data: Data(mod.folderName.utf8))
            for patch in patches {
                let input: URL
                if let candidate {
                    input = candidate.appendingPathComponent("exefs").appendingPathComponent(patch.relative)
                    try fm.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: patch.url, to: input)
                } else { input = patch.url }
                var contents = SHA256()
                let handle = try FileHandle(forReadingFrom: input)
                defer { try? handle.close() }
                try handle.forEachChunk { contents.update(data: $0) }
                hash.update(data: Data(("\u{0}" + patch.relative + "\u{0}").utf8))
                hash.update(data: Data(contents.finalize()))
            }
            let digest = hash.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
            let label = String(mod.folderName.unicodeScalars.prefix(24))
            let name = String(format: "%08d", index) + "-" + digest + "-" + label
            if let stage, let candidate { try fm.moveItem(at: candidate, to: stage.appendingPathComponent(name)) }
            names.append(name)
        }
        return names
    }

    private static func patchFiles(in tree: URL, name: String) throws -> [(url: URL, relative: String)] {
        let failure = ModStoreError.invalidCodeMod(name)
        guard ModFolderScanner.isRealDirectory(tree) else { throw failure }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var walkFailed = false
        guard let walker = FileManager.default.enumerator(at: tree, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles], errorHandler: { _, _ in walkFailed = true; return false }) else { throw failure }
        let base = tree.resolvingSymlinksInPath().path + "/"
        var files: [(url: URL, relative: String)] = []
        for case let file as URL in walker {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink == false else { throw failure }
            let resolved = file.resolvingSymlinksInPath().path
            guard resolved.hasPrefix(base) else { throw failure }
            let relative = String(resolved.dropFirst(base.count))
            guard !relative.isEmpty, relative.rangeOfCharacter(from: ModSupport.patchSeparators) == nil,
                  file.lastPathComponent.lowercased() != "main.npdm" else { throw failure }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, ModSupport.isPatch(file.lastPathComponent) else { throw failure }
            files.append((file, relative))
        }
        guard !walkFailed, !files.isEmpty else { throw failure }
        return files.sorted { $0.relative < $1.relative }
    }
}
