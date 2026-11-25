// From NX2Apple frontend-ios/Sources/ShellHost/GameBannerStore.swift at a79d397 (MIT, Copyright (c) 2026 seedds, jhaizhou, LNPANDY and NX2Apple contributors). Changes: mobile/PROVENANCE.md.
import CoreGraphics
import Foundation
import ImageIO
import ShellModel
import UniformTypeIdentifiers

/// Manages writable per-game 16:9 banners under `<Documents>/Banners/<TitleID>/`:
/// - `custom.jpg`: user-cropped custom cover (highest priority)
/// - `auto.jpg`: automatically backfilled official 16:9 banner for legacy bundles lacking `banner.<ext>`
public enum GameBannerStore {
    public static let customFileName = "custom.jpg"
    public static let autoFileName = "auto.jpg"
    public static let maxRemoteBytes = 16 * 1024 * 1024
    public enum StoreError: Error, Equatable {
        case invalidTitleID
        case invalidImageData
    }

    public struct Resolution: Equatable, Sendable {
        /// Banner URLs in priority order (`custom.jpg`, bundled `entry.bannerURL`, `auto.jpg`).
        public var candidates: [URL]
        /// True when a user-saved `custom.jpg` exists on disk for this game.
        public var hasCustomCover: Bool

        public var primaryURL: URL? { candidates.first }
    }

    /// Normalizes a game title ID into a safe single directory component, rejecting traversal characters.
    public static func sanitizedTitleID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return nil }
        if trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains(":") || trimmed.contains("..") {
            return nil
        }
        if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return nil
        }
        return trimmed.uppercased()
    }

    public static func gameDirectory(for titleID: String, bannersRoot: URL) -> URL? {
        guard let safe = sanitizedTitleID(titleID) else { return nil }
        return bannersRoot.appendingPathComponent(safe, isDirectory: true)
    }

    public static func customBannerURL(for titleID: String, bannersRoot: URL) -> URL? {
        gameDirectory(for: titleID, bannersRoot: bannersRoot)?.appendingPathComponent(customFileName, isDirectory: false)
    }

    public static func autoBannerURL(for titleID: String, bannersRoot: URL) -> URL? {
        gameDirectory(for: titleID, bannersRoot: bannersRoot)?.appendingPathComponent(autoFileName, isDirectory: false)
    }

    public static func hasCustomBanner(for titleID: String, bannersRoot: URL, fileManager fm: FileManager = .default) -> Bool {
        guard let url = customBannerURL(for: titleID, bannersRoot: bannersRoot) else { return false }
        return isNonEmptyRegularFile(url, fileManager: fm)
    }

    public static func hasAutoBanner(for titleID: String, bannersRoot: URL, fileManager fm: FileManager = .default) -> Bool {
        guard let url = autoBannerURL(for: titleID, bannersRoot: bannersRoot) else { return false }
        return isNonEmptyRegularFile(url, fileManager: fm)
    }

    /// Resolves banner priority:
    /// 1) `<bannersRoot>/<TitleID>/custom.jpg`
    /// 2) `entry.bannerURL` (`.framework/banner.<ext>`)
    /// 3) `<bannersRoot>/<TitleID>/auto.jpg`
    /// (4th level fallback to `entry.iconURL` happens in `ShellUI` when `GameTile.banner == nil`.)
    public static func resolve(for entry: CatalogueEntry, bannersRoot: URL, fileManager fm: FileManager = .default) -> Resolution {
        var candidates: [URL] = []
        var hasCustom = false

        if let custom = customBannerURL(for: entry.id, bannersRoot: bannersRoot),
           isNonEmptyRegularFile(custom, fileManager: fm) {
            candidates.append(custom)
            hasCustom = true
        }
        if let bundled = entry.bannerURL, isNonEmptyRegularFile(bundled, fileManager: fm) {
            candidates.append(bundled)
        }
        if let auto = autoBannerURL(for: entry.id, bannersRoot: bannersRoot),
           isNonEmptyRegularFile(auto, fileManager: fm) {
            candidates.append(auto)
        }
        return Resolution(candidates: candidates, hasCustomCover: hasCustom)
    }

    /// Validates and atomically writes `custom.jpg`, excluding `bannersRoot` from iCloud backup.
    @discardableResult
    public static func saveCustomBanner(
        _ data: Data,
        for titleID: String,
        bannersRoot: URL,
        fileManager fm: FileManager = .default
    ) throws -> URL {
        guard let target = customBannerURL(for: titleID, bannersRoot: bannersRoot) else {
            throw StoreError.invalidTitleID
        }
        return try writeValidatedBanner(data, to: target, bannersRoot: bannersRoot, fileManager: fm)
    }

    /// Validates and atomically writes `auto.jpg`, excluding `bannersRoot` from iCloud backup.
    @discardableResult
    public static func saveAutoBanner(
        _ data: Data,
        for titleID: String,
        bannersRoot: URL,
        fileManager fm: FileManager = .default
    ) throws -> URL {
        guard let target = autoBannerURL(for: titleID, bannersRoot: bannersRoot) else {
            throw StoreError.invalidTitleID
        }
        return try writeValidatedBanner(data, to: target, bannersRoot: bannersRoot, fileManager: fm)
    }

    /// Deletes `<bannersRoot>/<TitleID>/custom.jpg` if present and returns its URL for cache invalidation.
    @discardableResult
    public static func removeCustomBanner(
        for titleID: String,
        bannersRoot: URL,
        fileManager fm: FileManager = .default
    ) -> URL? {
        guard let target = customBannerURL(for: titleID, bannersRoot: bannersRoot) else { return nil }
        if fm.fileExists(atPath: target.path) {
            try? fm.removeItem(at: target)
        }
        return target
    }

    /// Single-point 720p banner fallback URL for any valid 16-hex Switch title ID.
    /// Returns pixel dimensions when `data` is a bounded, decodable image with a recognized magic header.
    public static func imagePixelSize(_ data: Data, maxBytes: Int = maxRemoteBytes) -> (width: Int, height: Int)? {
        guard data.count >= 12, data.count <= maxBytes else { return nil }
        let bytes = [UInt8](data.prefix(12))
        let isJPEG = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
        let isPNG = bytes.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let isWebP = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50
        let isHEIF = bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70
        guard isJPEG || isPNG || isWebP || isHEIF else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0 else { return nil }
        return (image.width, image.height)
    }

    public static func isValidLandscapeImageData(_ data: Data, maxBytes: Int = maxRemoteBytes) -> Bool {
        guard let size = imagePixelSize(data, maxBytes: maxBytes) else { return false }
        return size.width > size.height
    }

    /// Returns JPEG bytes matching `auto.jpg`: preserves valid JPEG bytes verbatim and transcodes PNG/WebP/HEIF via ImageIO.
    public static func normalizedJPEGData(_ data: Data, quality: CGFloat = 0.92, maxBytes: Int = maxRemoteBytes) -> Data? {
        guard imagePixelSize(data, maxBytes: maxBytes) != nil else { return nil }
        let bytes = [UInt8](data.prefix(3))
        if bytes.count == 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return data
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest), out.length > 0 else { return nil }
        return out as Data
    }

    private static func writeValidatedBanner(
        _ data: Data,
        to target: URL,
        bannersRoot: URL,
        fileManager fm: FileManager
    ) throws -> URL {
        guard !data.isEmpty, Artwork(id: "validate", data: data) != nil else {
            throw StoreError.invalidImageData
        }
        let dir = target.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        BackupExclusion.exclude(bannersRoot)
        try data.write(to: target, options: .atomic)
        BackupExclusion.exclude(target)
        return target
    }

    private static func isNonEmptyRegularFile(_ url: URL, fileManager fm: FileManager) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              size > 0 else {
            return false
        }
        return true
    }
}
