import Foundation

/// Interface sound cues. The raw value is the Selene file name without `.wav`.
public enum SoundCue: String, CaseIterable {
    case move = "navigation"
    case select = "activation"
    case back = "CloseAdditionalView"
    case openPanel = "OpenPanel"
    case gameStarting = "GameStarting"
    case gameReady = "GameReady"
    case alert = "Alert"
    case success = "Success"
    case key = "Key"
    case boot = "Boot"

    /// The bundled MIT cue used when neither an import nor a bundled file exists.
    public var fallback: SoundCue? {
        switch self {
        case .select, .openPanel, .gameStarting, .gameReady: return .success
        case .back, .alert: return .key
        case .move, .success, .key, .boot: return nil
        }
    }
}

/// Finds the file for a cue: imported Selene sound, then bundled sound, then the fallback cue.
public struct SoundCueResolver {
    public let importedSounds: URL?
    public let bundledSounds: URL?
    private let fileManager: FileManager

    public init(importedSounds: URL?, bundledSounds: URL?, fileManager: FileManager = .default) {
        self.importedSounds = importedSounds
        self.bundledSounds = bundledSounds
        self.fileManager = fileManager
    }

    public func url(for cue: SoundCue) -> URL? {
        for folder in [importedSounds, bundledSounds].compactMap({ $0 }) {
            let url = folder.appendingPathComponent("\(cue.rawValue).wav")
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return cue.fallback.flatMap(url(for:))
    }
}
