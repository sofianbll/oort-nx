import Foundation
import OortLibrary

/// One RomFS tree, one ExeFS patch tree, or both side by side.
public enum ModSupport {
    public struct Layout: Equatable, Sendable {
        public let romfs: String?
        public let exefs: String?
    }

    /// The actual paths up to each tree, keeping the archive's spelling. Top-level cheats are ignored.
    public static func layout(in paths: [String], titleID: String) throws -> Layout {
        var romfs = Set<String>(), exefs = Set<String>()
        for path in paths {
            let parts = path.split(separator: "/").filter { $0 != "." }.map(String.init)
            guard let first = parts.first else { continue }
            guard !path.hasPrefix("/"), !parts.contains("..") else { throw ModInstallError.unsafe }
            let lower = parts.map { $0.lowercased() }
            guard !lower.contains("main.npdm") else { throw ModInstallError.unsupportedLayout }
            guard lower[0] != "cheats" else { continue }
            guard !lower.contains("exefs_patches") else {
                throw ModInstallError.unsupportedLayout
            }
            let index = lower.firstIndex { $0 == "romfs" || $0 == "exefs" }
            let prefix = index.map { lower.prefix($0) } ?? lower[...]
            for component in prefix where component.utf8.count == 16 && UInt64(component, radix: 16) != nil {
                guard component.caseInsensitiveCompare(titleID) == .orderedSame else { throw ModInstallError.unsupportedLayout }
            }
            if let contents = prefix.firstIndex(of: "contents"), prefix.indices.contains(contents + 1),
               prefix[contents + 1].caseInsensitiveCompare(titleID) != .orderedSame {
                throw ModInstallError.unsupportedLayout
            }
            guard let index else {
                if isPatch(first) || isPatch(parts.last ?? "") { throw ModInstallError.unsupportedLayout }
                continue
            }
            let root = parts[...index].joined(separator: "/")
            let suffix = parts.dropFirst(index + 1)
            let hasPatch = lower.contains(where: isPatch)
            if lower[index] == "romfs" {
                guard !hasPatch, !suffix.contains(where: { $0.lowercased() == "exefs" }) else {
                    throw ModInstallError.unsupportedLayout
                }
                romfs.insert(root)
            } else if !suffix.isEmpty, !suffix.contains(where: { $0.hasPrefix(".") }) {
                guard !suffix.contains(where: { $0.lowercased() == "romfs" }),
                      !parts[index...].contains(where: { $0.rangeOfCharacter(from: patchSeparators) != nil }) else {
                    throw ModInstallError.unsupportedLayout
                }
                if !path.hasSuffix("/") {
                    guard let name = suffix.last, isPatch(name) else { throw ModInstallError.unsupportedLayout }
                    exefs.insert(root)
                }
            }
        }
        guard romfs.count <= 1, exefs.count <= 1 else { throw ModInstallError.unsupportedLayout }
        if let resources = romfs.first, let code = exefs.first,
           resources.split(separator: "/").dropLast() != code.split(separator: "/").dropLast() {
            throw ModInstallError.unsupportedLayout
        }
        guard !romfs.isEmpty || !exefs.isEmpty else { throw ModInstallError.noRomFS }
        return Layout(romfs: romfs.first, exefs: exefs.first)
    }

    public static func isVisible(_ summary: GameBananaModSummary) -> Bool {
        !summary.isObsolete && !summary.hasContentRatings
    }

    public static func isVisible(_ profile: GameBananaModProfile) -> Bool {
        !profile.isObsolete && !profile.isPrivate && !profile.isWithheld && !profile.isTrashed
            && profile.contentRatings.isEmpty && !ModRequirements.needsTool(profile.requirements)
    }

    static let patchSeparators = CharacterSet(charactersIn: ":\t\n\r")

    static func isPatch(_ component: String) -> Bool {
        let name = component.lowercased()
        return name.hasSuffix(".pchtxt") || name.hasSuffix(".ips")
    }
}

/// What a mod's GameBanana Requirements mean here. They are free text, so only clear cases are acted on: a loader or
/// a PC tool the engine cannot run hides the mod (it would install and then not work, or break the game, as exlaunch
/// mods do); notes about a modded Switch or an emulator are left out; everything else (game versions, other mods) is
/// shown in the mod's panel for the player to judge.
public enum ModRequirements {
    /// Loaders and tools: exlaunch-based loaders, Smash's Skyline/ARCropolis, mod managers and mergers that must run
    /// on the game first, and ReShade, which hooks a PC emulator's renderer.
    static let tools = ["exlaunch", "skyline", "arcropolis", "mod loader", "modloader", "mod manager", "tkmm",
                        "recomp", "reshade"]
    static let optionalWords = ["optional", "preferred", "recommended", "not required"]
    static let platformWords = ["hacked", "modded", "emulator", "yuzu", "ryujinx", "atmosphere", "sdcard", "sd card",
                                "cfw", "homebrew"]
    static let platformNames: Set<String> = ["computer", "pc"]

    public static func needsTool(_ requirements: [GameBananaRequirement]) -> Bool {
        requirements.contains { requirement in
            let name = requirement.name.lowercased()
            return !requirement.isOptional && !optionalWords.contains(where: name.contains)
                && tools.contains(where: name.contains)
        }
    }

    public static func shown(_ requirements: [GameBananaRequirement]) -> [GameBananaRequirement] {
        requirements.filter { requirement in
            let name = requirement.name.lowercased()
            return !platformNames.contains(name) && !platformWords.contains(where: name.contains)
        }
    }
}

/// A mod's folder name in the game's mods folder: safe for `DM_ROMFS_OVERLAY` (no `:`), a single path component,
/// visible in Finder, and unique (APFS is case-insensitive by default).
public enum ModFolderName {
    public static let maxLength = 80

    public static func make(from modName: String, modID: Int, existing: Set<String>) -> String {
        let unsafe = CharacterSet(charactersIn: ":/\\").union(.controlCharacters).union(.newlines)
        var name = String(String.UnicodeScalarView(modName.unicodeScalars.map { unsafe.contains($0) ? " " : $0 }))
        name = name.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        while name.hasPrefix(".") || name.hasPrefix(" ") { name.removeFirst() }
        name = String(name.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Mod \(modID)" }

        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)".lowercased()) { number += 1 }
        return "\(name) \(number)"
    }
}
