import NXLibraryCore

public enum GameStatus: String, Codable, Equatable, Sendable {
    case notBuilt, building, built, builtSourcesMissing
    case failed, cancelled, needsRebuild, appMissing
}
