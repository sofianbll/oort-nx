import Foundation

/// A folder in a game's `mods` or `code-mods` folder.
public struct LocalMod: Equatable, Sendable {
    /// The folder's name: the mod's identity across both folders.
    public let folderName: String
    public let folder: URL
    /// The RomFS tree the engine overlays, if any.
    public let romfs: URL?
    /// The ExeFS patch tree passed to the engine at build time, if any.
    public let exefs: URL?
    public var isMod: Bool { romfs != nil || exefs != nil }
    package var isCodeMod: Bool { exefs != nil }
    public var isOn: Bool

    public init(folderName: String, folder: URL, romfs: URL?, exefs: URL? = nil, isOn: Bool) {
        self.folderName = folderName
        self.folder = folder
        self.romfs = romfs
        self.exefs = exefs
        self.isOn = isOn
    }
}
