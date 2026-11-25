// From NX2Apple frontend-ios/Sources/ShellHost/HostText.swift at a79d397 (MIT, Copyright (c) 2026 seedds, jhaizhou, LNPANDY and NX2Apple contributors). Changes: mobile/PROVENANCE.md.
import Foundation
import ShellModel

/// The host layer's own words, from `Resources/Localizable.xcstrings` (English source, like ShellUI). The catalog is generated from
/// `frontend/l10n/*.json` (`ios.host.*`) by `tools/l10n_shell_catalogs.py`: change a text there, not in the catalog.
func hostText(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: HostStrings.bundle)
}

enum HostStrings {
    /// Visual QA renders one language's `.lproj` whatever the Mac's language is, as `ShellStrings.captureBundle` does. Nil in the app.
    nonisolated(unsafe) static var captureBundle: Bundle?
    static var bundle: Bundle { captureBundle ?? .module }
}

extension ProblemCause {
    /// The short state label, which says the same thing as `message`.
    public var label: String {
        switch self {
        case .manifestMissing: hostText("Game manifest missing")
        case .manifestDamaged: hostText("Can't read this game")
        case .manifestUnsupported: hostText("Manifest not supported")
        case .settingsMissing: hostText("Settings list missing")
        case .settingsDamaged: hostText("Settings list damaged")
        case .settingsUnsupported: hostText("Settings list not supported")
        case .codeMissing: hostText("Game code missing")
        case .filesDamaged: hostText("Game files damaged")
        }
    }

    /// What happened and what to do, for the player. The technical message stays in `GameProblem.detail`.
    public var message: String {
        switch self {
        case .manifestMissing: hostText("This game's manifest is missing. Rebuild the game in the launcher on your Mac.")
        case .manifestDamaged: hostText("This game's manifest is damaged. Rebuild the game in the launcher on your Mac.")
        case .manifestUnsupported, .settingsUnsupported:
            hostText("This game was built for a different version of this app. Update the app or rebuild the game in the launcher on your Mac.")
        case .settingsMissing: hostText("This game's settings list is missing. Rebuild the game in the launcher on your Mac.")
        case .settingsDamaged: hostText("This game's settings list is damaged. Rebuild the game in the launcher on your Mac.")
        case .codeMissing: hostText("The game's code is missing from this app. Rebuild and reinstall it.")
        case .filesDamaged: hostText("This game's files are damaged. Rebuild the game in the launcher on your Mac.")
        }
    }
}

extension GameProblem {
    /// The broken state a tile shows: the short reason, the player's sentence and the technical message.
    public var state: GameState { .broken(reason: spokenReason, detail: cause.message, technical: detail) }
}

/// Maps known English C launch errors from `ShellMain.m` to localized `ShellHost` catalog strings.
public func localizeEngineLaunchError(_ raw: String) -> String {
    switch raw {
    case "This game was updated while the app was open. Close and reopen the app to load the new build.":
        return hostText("This game was updated while the app was open. Close and reopen the app to load the new build.")
    case "A game is already running.":
        return hostText("A game is already running.")
    case "The game's start arguments are incomplete.":
        return hostText("The game's start arguments are incomplete.")
    case "This game's framework in Documents/Frameworks is unsigned. Install the game again from Oort NX.":
        return hostText("This game's framework in Documents/Frameworks is unsigned. Reinstall it with the same signing team from Oort NX.")
    case "iOS refused the code signature of this game's framework. Install the game again from Oort NX.":
        return hostText("iOS refused the code signature of this game's framework. Reinstall it with the same signing team from Oort NX.")
    case FrameworkSignature.unsupportedHotFrameworkSigningMessage:
        return hostText("This app signature does not support loading games from Documents/Frameworks. Reinstall the app from Oort NX on your computer.")
    case FrameworkSignature.certMismatchHotFrameworkMessage:
        return hostText("Could not load the game framework because the signing certificate does not match this app. Reinstall the app from your computer.")
    default:
        if raw.contains("file system sandbox blocked mmap")
            || raw.contains("sandbox blocked mmap")
            || raw.hasPrefix("The game's code could not be loaded:") {
            return hostText("Could not load the game framework because the signing certificate does not match this app. Reinstall the app from your computer.")
        }
        return raw
    }
}

/// Localized copy for the iOS in-game controller disconnect auto-pause overlay.
public struct ControllerDisconnectOverlayStrings: Equatable, Sendable {
    public let title: String
    public let message: String
    public let resumeTitle: String

    public static func localized() -> ControllerDisconnectOverlayStrings {
        ControllerDisconnectOverlayStrings(
            title: hostText("Controller Disconnected"),
            message: hostText("Game paused. Reconnect your controller or tap Resume to continue with touch controls."),
            resumeTitle: hostText("Resume")
        )
    }
}
