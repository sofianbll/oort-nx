import Foundation
import CryptoKit
import OortLibrary

public enum ModInstallError: Error, Equatable {
    case notAllowed, download, damaged, unreadable, unsafe, noRomFS, unsupportedLayout, noSpace
    case writeFailed(String)

    public var message: String {
        switch self {
        case .notAllowed: return L10n.text("Quit the game to install mods.")
        case .download: return L10n.text("The download didn't finish.")
        case .damaged: return L10n.text("The download was damaged. Try again.")
        case .unreadable: return L10n.text("This archive can't be opened.")
        case .unsafe: return L10n.text("This archive has files outside its folder, so it wasn't installed.")
        case .noRomFS: return L10n.text("This archive needs a romfs folder or an exefs folder with patches.")
        case .unsupportedLayout:
            return L10n.text("Use one mod for this game, with romfs and exefs side by side if it has both. Replacement code files aren't supported.")
        case .noSpace: return L10n.text("There isn't enough space to install this mod.")
        // The reason stays out of the sentence: the player gets plain words, not a system error.
        case .writeFailed: return L10n.text("The mod couldn't be copied into the game's folder. Try again.")
        }
    }
}

public enum ModInstallResult: Equatable, Sendable {
    /// Installed and on.
    case on(String)
    /// An update of a mod the player had turned off: it stays off.
    case off(String)
    /// Installed, but the overlay line is full, so it stays off.
    case installedOff(String)

    public var folderName: String {
        switch self { case .on(let name), .off(let name), .installedOff(let name): return name }
    }

    /// The sentence to show, if any.
    public var message: String? {
        if case .installedOff = self { return L10n.text("Installed, but too many mods are on. Turn one off first.") }
        return nil
    }
}

/// Installs a downloaded GameBanana file into the game's mods folder: verify size and MD5, list the archive with the
/// system `bsdtar`, refuse absolute or `..` paths, find the single RomFS root, unpack into a hidden staging folder
/// inside the mods folder, refuse links, then hand the RomFS tree to `ModStore.adopt`. The staging folder is
/// removed whatever happens; the downloaded archive belongs to the caller.
public struct ModInstaller {
    public let store: ModStore
    private let runner: CommandRunning
    private let bsdtar: URL
    private let freeSpace: (URL) -> Int64?
    private let now: () -> Date

    public init(store: ModStore, runner: CommandRunning = SystemCommandRunner(),
                bsdtar: URL = URL(fileURLWithPath: "/usr/bin/bsdtar"),
                freeSpace: @escaping (URL) -> Int64? = ModInstaller.availableCapacity,
                now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.runner = runner
        self.bsdtar = bsdtar
        self.freeSpace = freeSpace
        self.now = now
    }

    /// Free space on the volume of `url` (or its nearest existing parent), for important use.
    public static func availableCapacity(_ url: URL) -> Int64? {
        VolumeSpace.free(at: url)
    }

    /// Size first, then the MD5 GameBanana publishes (any case).
    public static func verify(_ archive: URL, file: GameBananaFile) throws {
        let size = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        guard size == file.size else { throw ModInstallError.damaged }
        guard let handle = try? FileHandle(forReadingFrom: archive) else { throw ModInstallError.damaged }
        defer { try? handle.close() }
        var md5 = Insecure.MD5()
        try? handle.forEachChunk { md5.update(data: $0) }
        let digest = md5.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == file.md5.lowercased() else { throw ModInstallError.damaged }
    }

    public func install(archive: URL, file: GameBananaFile, mod: AvailableMod) throws -> ModInstallResult {
        guard store.isWritable else { throw ModInstallError.notAllowed }
        try Self.verify(archive, file: file)
        if let free = freeSpace(store.modsFolder), free < 3 * file.size { throw ModInstallError.noSpace }

        let listing = try tar(["-tf", archive.path])
        let layout = try ModSupport.layout(in: listing.split(separator: "\n").map(String.init), titleID: store.titleID)
        // Links of any kind are refused before anything is unpacked: bsdtar -tv starts a symlink's line with `l` and
        // ends a hard link's with `link to <target>`.
        let verbose = try tar(["-tvf", archive.path]).split(separator: "\n")
        guard verbose.allSatisfy({ ($0.hasPrefix("-") || $0.hasPrefix("d")) && !$0.contains(" link to ") }) else {
            throw ModInstallError.unsafe
        }

        let fm = FileManager.default
        let staging = store.modsFolder.appendingPathComponent(".installing-\(UUID().uuidString)")
        do { try fm.createDirectory(at: staging, withIntermediateDirectories: true) }
        catch { throw ModInstallError.writeFailed(error.localizedDescription) }
        defer { try? fm.removeItem(at: staging) }

        _ = try tar(["-xf", archive.path, "-C", staging.path])
        if Self.containsSymlink(staging) { throw ModInstallError.unsafe }
        let romfs = layout.romfs.map { staging.appendingPathComponent($0) }
        let exefs = layout.exefs.map { staging.appendingPathComponent($0) }
        guard [romfs, exefs].compactMap({ $0 }).allSatisfy(ModFolderScanner.isRealDirectory) else { throw ModInstallError.unsupportedLayout }

        let isUpdate = store.gameBananaRecords()[mod.id] != nil
        let record = ModRecord(folderName: mod.name, isOn: false, gameBananaModID: mod.id, gameBananaFileID: file.id,
                               md5: file.md5.lowercased(), installedAt: now())
        let local: LocalMod
        do {
            local = try store.adopt(romfs: romfs, exefs: exefs, name: mod.name, record: record)
        } catch ModStoreError.notAllowed {
            throw ModInstallError.notAllowed
        } catch ModStoreError.invalidCodeMod {
            throw ModInstallError.unsupportedLayout
        } catch let ModStoreError.writeFailed(reason) {
            throw ModInstallError.writeFailed(reason)
        } catch {
            throw ModInstallError.writeFailed(error.localizedDescription)
        }
        if local.isOn { return .on(local.folderName) }
        return isUpdate ? .off(local.folderName) : .installedOff(local.folderName)
    }

    private func tar(_ arguments: [String]) throws -> String {
        let result: CommandResult
        do { result = try runner.run(bsdtar, arguments, environment: nil, currentDirectory: nil) }
        catch { throw ModInstallError.unreadable }
        guard result.status == 0 else { throw ModInstallError.unreadable }
        return result.stdout
    }

    private static func containsSymlink(_ folder: URL) -> Bool {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            return true
        }
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return true
        }
        return false
    }
}
