import Foundation

extension CatalogIntegration {
    public static let macShortcut = Self(rawValue: "macShortcut")
}

public enum MacShortcutError: Error, Equatable {
    case invalidApplication, differentApplication, alreadyLinked
}

/// A reference to an app explicitly chosen on this Mac, not a managed installation.
public struct MacShortcutRecord: CatalogSourceRecord, Sendable {
    public static let integration = CatalogIntegration.macShortcut
    public let id: UUID
    public let name: String
    public let bundleIdentifier: String
    public internal(set) var url: URL
    public var isFavorite = false
    public var isHidden = false

    var key: String { "mac-\(id.uuidString.lowercased())" }

    public func validateRecord(personalizationKey: String) throws {
        guard personalizationKey == key, url.isFileURL, (url.host(percentEncoded: false) ?? "").isEmpty,
              url.path.hasPrefix("/"), url.pathExtension.lowercased() == "app",
              url.standardized.path == url.path, !bundleIdentifier.isEmpty else {
            throw CatalogModelError.invalidRecord
        }
    }

    public func presence(sourceEnabled: Bool) -> CatalogRecordPresence {
        // This is the chosen reference, not live proof the app still exists. Play rechecks it at the OS boundary.
        .init(requiresReview: false, isDownloading: false, isListedNormally: sourceEnabled && !isHidden,
              launchTarget: nil, installations: [
                  .init(id: key, contentURL: url, applicationURL: url, executableURL: nil,
                        bundleIdentifier: bundleIdentifier, availability: .available, size: .unknown)
              ])
    }

    public var isInstalledForLibrary: Bool { FileManager.default.fileExists(atPath: url.path) }
    public var librarySearchTerms: [String] { [bundleIdentifier, url.deletingPathExtension().lastPathComponent] }
}

extension CatalogGame {
    public var macShortcut: MacShortcutRecord? { record as? MacShortcutRecord }
}
