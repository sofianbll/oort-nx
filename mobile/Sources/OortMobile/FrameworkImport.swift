import Foundation
import ShellHost

/// Copies a game built on the Mac (`DmGame<title ID>.framework`) from Files into `Documents/Frameworks`, after reading what it is.
enum FrameworkImport {
    enum Failure: LocalizedError, Equatable {
        case notAGame, unreadable(String), foreignFiles, wrongSigner(String), noSpace, copy
        var errorDescription: String? {
            switch self {
            case .notAGame: Oort.text("This is not a game built for Oort NX. Pick a folder that ends in .framework.")
            case .unreadable(let why): why
            case .foreignFiles: Oort.text("This game has links to files outside its folder. Build it again on your Mac.")
            case .wrongSigner(let why): why
            case .noSpace: Oort.text("There is not enough free space on this device.")
            case .copy: Oort.text("The game could not be copied. Nothing was changed.")
            }
        }
    }

    /// `check` refuses a game another team signed (nil: accepted). Returns the title ID.
    @discardableResult
    static func run(_ source: URL, into root: URL, freeSpace: (URL) -> Int64? = Self.freeSpace,
                    check: (URL) -> String?) throws -> String {
        let fm = FileManager.default
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard source.pathExtension == "framework",
              let data = try? Data(contentsOf: source.appendingPathComponent("game.manifest.json"), options: .mappedIfSafe) else { throw Failure.notAGame }
        let manifest: GameManifest
        do { manifest = try GameManifest.parse(data) } catch { throw Failure.unreadable(error.localizedDescription) }
        let name = "DmGame\(manifest.titleID.uppercased()).framework"
        guard manifest.titleID.count == 16, manifest.titleID.allSatisfy(\.isHexDigit), manifest.framework == name,
              !manifest.frameworkExecutable.contains("/"),
              fm.isReadableFile(atPath: source.appendingPathComponent(manifest.frameworkExecutable).path) else { throw Failure.notAGame }
        var size: Int64 = 0
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .fileSizeKey]
        guard let files = fm.enumerator(at: source, includingPropertiesForKeys: keys) else { throw Failure.notAGame }
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { throw Failure.foreignFiles }
            size += Int64(values.fileSize ?? 0)
        }
        if let refusal = check(source.appendingPathComponent(manifest.frameworkExecutable)) { throw Failure.wrongSigner(refusal) }
        if let free = freeSpace(root), free < size + 64 << 20 { throw Failure.noSpace }
        let target = root.appendingPathComponent(name, isDirectory: true)
        // Copied beside, then swapped: a stopped copy never leaves half a game.
        let staging = root.deletingLastPathComponent().appendingPathComponent(".oort-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: staging)
            if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: staging) }
            else { try fm.moveItem(at: staging, to: target) }
        } catch { throw Failure.copy }
        BackupExclusion.exclude(target)
        return manifest.titleID
    }

    static func freeSpace(_ url: URL) -> Int64? {
        try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
}
