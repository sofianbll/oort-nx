import Foundation

public enum SeleneImportError: Error, Equatable, LocalizedError {
    case notASeleneFolder

    public var errorDescription: String? {
        L10n.text("That folder is not a Selene checkout. Pick the folder that contains theme/theme.yaml.")
    }
}

public struct SeleneImportReport: Equatable {
    public var copied: [String]
    public var missing: [String]

    public init(copied: [String] = [], missing: [String] = []) {
        self.copied = copied
        self.missing = missing
    }
}

/// Copies Selene's optional sounds and wallpapers from a checkout the user owns into
/// Arcane's support folder. Nothing from Selene ships in the repository except the
/// MIT sounds and public-domain wallpapers already bundled.
public struct SeleneImporter {
    public static let soundFiles = ["OpenPanel", "LoginSelect", "GameStarting", "GameReady",
                                    "activation", "CloseAdditionalView", "Alert"]

    public static var defaultDestination: URL {
        AppData.supportRoot.appendingPathComponent("SeleneImports")
    }

    public let destination: URL
    private let fileManager: FileManager

    public init(destination: URL = SeleneImporter.defaultDestination, fileManager: FileManager = .default) {
        self.destination = destination
        self.fileManager = fileManager
    }

    public func importFrom(seleneRoot: URL) throws -> SeleneImportReport {
        let theme = seleneRoot.appendingPathComponent("theme")
        guard fileManager.fileExists(atPath: theme.appendingPathComponent("theme.yaml").path) else {
            throw SeleneImportError.notASeleneFolder
        }
        var report = SeleneImportReport()

        let audio = theme.appendingPathComponent("Audio")
        for name in Self.soundFiles {
            let relative = L10n.format("Sounds/%@.wav", [String(describing: name)])
            let source = audio.appendingPathComponent("\(name).wav")
            if fileManager.fileExists(atPath: source.path) {
                try copy(source, to: relative)
                report.copied.append(relative)
            } else {
                report.missing.append(relative)
            }
        }

        let wallpapers = theme.appendingPathComponent("Wallpapers")
        let themes = (try? fileManager.contentsOfDirectory(at: wallpapers, includingPropertiesForKeys: [.isDirectoryKey],
                                                           options: [.skipsHiddenFiles])) ?? []
        for folder in themes.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles])) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let relative = L10n.format("Wallpapers/%@/%@", [String(describing: folder.lastPathComponent), String(describing: file.lastPathComponent)])
                try copy(file, to: relative)
                report.copied.append(relative)
            }
        }
        return report
    }

    private func copy(_ source: URL, to relative: String) throws {
        let target = destination.appendingPathComponent(relative)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.copyItem(at: source, to: target)
    }
}
