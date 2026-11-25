@_exported import OortCore

public typealias LauncherSetting = GameLauncherSetting

extension GameProblem {
    /// The short line in the player's language: the cause's own, unless the problem came with other words.
    var spokenReason: String { reason == cause.words ? cause.label : reason }
}
