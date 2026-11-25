import Foundation

/// What is wrong with a game that cannot run. Each system says it in the player's language.
public enum ProblemCause: String, Equatable, Sendable, CaseIterable {
    case manifestMissing, manifestDamaged, manifestUnsupported
    case settingsMissing, settingsDamaged, settingsUnsupported
    case codeMissing
    case filesDamaged

    /// The short English label.
    public var words: String {
        switch self {
        case .manifestMissing: "Game manifest missing"
        case .manifestDamaged: "Can't read this game"
        case .manifestUnsupported: "Manifest not supported"
        case .settingsMissing: "Settings list missing"
        case .settingsDamaged: "Settings list damaged"
        case .settingsUnsupported: "Settings list not supported"
        case .codeMissing: "Game code missing"
        case .filesDamaged: "Game files damaged"
        }
    }
}

/// `reason` is the short line, `detail` the technical message for a log or a Details line.
public struct GameProblem: Error, Equatable, Sendable, LocalizedError {
    public var cause: ProblemCause
    public var reason: String
    public var detail: String

    public init(cause: ProblemCause = .filesDamaged, reason: String, detail: String = "") {
        self.cause = cause
        self.reason = reason
        self.detail = detail
    }

    public var errorDescription: String? { detail.isEmpty ? reason : "\(reason): \(detail)" }
}
