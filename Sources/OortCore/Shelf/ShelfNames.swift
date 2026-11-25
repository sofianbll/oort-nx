import Foundation

/// The rules every name read from a source goes through. They are the Mac's (`CloudDriveFolders.validName`, `titleID(in:)`,
/// `CloudArtifactFiles.validate`), tightened for a folder somebody else may have written into.
public enum ShelfNames {
    static let linkSuffix = ".rclonelink"
    static let keyNames: Set<String> = ["prod.keys", "title.keys", "dev.keys", "keys.txt"]

    public static func isTitleID(_ text: String) -> Bool {
        text.utf8.count == 16 && text.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) }
    }

    /// `Name [0100…]` or `0100…`, capitals only.
    public static func titleID(inFolder folder: String) -> String? {
        guard isPlain(folder), !folder.contains("/") else { return nil }
        let title = folder.hasSuffix("]") ? String(folder.dropLast().suffix(16)) : folder
        guard isTitleID(title), folder == title || folder.hasSuffix(" [\(title)]") else { return nil }
        return title
    }

    /// What to show for a game folder. A name is text from outside: it never carries a line break or a direction mark.
    public static func displayName(_ text: String, titleID: String) -> String {
        let suffix = " [\(titleID)]"
        let name = text.hasSuffix(suffix) ? String(text.dropLast(suffix.count)) : text
        let clean = String(String.UnicodeScalarView(name.unicodeScalars.filter { !isControl($0) }))
            .trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? titleID : String(clean.unicodeScalars.prefix(120).map(Character.init))
    }

    /// Two names a disk could take for the same one.
    static func folded(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// A relative path that stays inside its folder on every system, with no name a system gives a meaning to.
    public static func isSafePath(_ path: String) -> Bool {
        guard isPlain(path), (1...1024).contains(path.utf8.count) else { return false }
        let parts = path.components(separatedBy: "/")
        guard parts.count <= 16, parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.count <= 255 && !part.hasPrefix(".") && !part.hasSuffix(".") && !part.hasSuffix(" ")
                && !part.hasPrefix(" ") && !keyNames.contains(part.lowercased()) && !part.lowercased().hasSuffix(linkSuffix)
        }) else { return false }
        // Saves never travel with a build.
        return !parts[0].lowercased().hasPrefix("save")
    }

    /// Letters a folder tree can hold everywhere: no backslash, colon, control or direction mark, no `.` or `..` part.
    static func isPlain(_ path: String) -> Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !path.contains("\\") && !path.contains(":")
            && !path.unicodeScalars.contains(where: isControl)
            && !path.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }

    static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0..<0x20, 0x7F..<0xA0, 0x200B...0x200F, 0x2028...0x202E, 0x2060...0x206F, 0xFEFF: true
        default: false
        }
    }

    static func isHex(_ text: String, count: Int) -> Bool {
        text.utf8.count == count && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// `0001790000000000-<64 hex>.json` as the Mac names its manifests: 16 digits of milliseconds, then the content's SHA-256.
    static func manifestName(_ name: String, suffix: String = ".json") -> (stamp: Int64, sha256: String)? {
        guard name.hasSuffix(suffix) else { return nil }
        let parts = name.dropLast(suffix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].utf8.count == 16, parts[0].utf8.allSatisfy({ (48...57).contains($0) }),
              let stamp = Int64(parts[0]), isHex(String(parts[1]), count: 64) else { return nil }
        return (stamp, String(parts[1]))
    }

    /// One JSON string, escaped the way the Mac's encoder does it, so both sides hash the same bytes.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Dotted numbers, missing parts count as zero. Nil when it is not a version.
    static func compareVersions(_ a: String, _ b: String) -> Int? {
        func parts(_ text: String) -> [Int]? {
            let items = text.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...4).contains(items.count) else { return nil }
            let numbers = items.compactMap { $0.utf8.count <= 6 && $0.utf8.allSatisfy { (48...57).contains($0) } ? Int($0) : nil }
            return numbers.count == items.count ? numbers : nil
        }
        guard let left = parts(a), let right = parts(b) else { return nil }
        for index in 0..<4 {
            let l = index < left.count ? left[index] : 0, r = index < right.count ? right[index] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }
}

extension ShelfNode {
    /// The only child with this exact name and kind. A name that a disk could confuse with another one is refused.
    static func only(_ name: String, kind: Kind, in nodes: [ShelfNode]) throws -> ShelfNode? {
        let matches = nodes.filter { ShelfNames.folded($0.name) == ShelfNames.folded(name) }
        guard let match = matches.first else { return nil }
        guard matches.count == 1, match.name.utf8.elementsEqual(name.utf8), match.kind == kind else { throw ShelfError.ambiguous }
        return match
    }
}
