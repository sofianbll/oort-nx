import Foundation
import NXLibraryCore

/// How the last porting of a game ended when it did not succeed. Saved with the
/// game, so the home still shows it after a relaunch; a successful porting clears it.
public enum PortingFailure: String, Codable, Equatable {
    case failed
    case cancelled
}

/// The small time line under the porting pills.
public enum PortingETA {
    /// Shaders: the engine's ETA plus what the final stages took last time on this
    /// Mac, or the shaders' part alone. Finishing: what is left of last time.
    /// Nothing before the shaders.
    public static func text(_ progress: PortingProgress, lastFinishingSeconds: Double?,
                            context: AppLocale = L10n.context, compact: Bool = false) -> String? {
        func estimate(_ key: String, _ seconds: Double) -> String? {
            guard seconds.isFinite, abs(seconds) < Double(Int.max) else { return nil }
            return L10n.format(compact ? "~%@" : key, [duration(seconds, context: context)], context: context)
        }
        if progress.isUpdatingShaderCache { return compact ? nil : L10n.text("Updating shader cache", context: context) }
        switch progress.phase {
        case .shaders:
            guard let eta = progress.shaderETA else { return nil }
            if let last = lastFinishingSeconds { return estimate("About %@ left", eta + last) }
            return estimate("Shaders: about %@", eta)
        case .finishing:
            // Prewarm has no reliable counter and can dwarf an older build's
            // finishing time. Keep the activity visible without reusing that ETA.
            if progress.stageName == PortingProgress.prewarmStageName {
                return compact ? nil : L10n.text("Preparing the first launch", context: context)
            }
            if let eta = progress.finishingETA { return estimate("Pipelines: about %@", eta) }
            guard let last = lastFinishingSeconds else { return compact ? nil : L10n.text("Finishing up", context: context) }
            return estimate("About %@ left", max(0, last - progress.finishingElapsed))
        case .preparing, .done, .failed:
            return nil
        }
    }

    /// Stage time in the Porting list: seconds under a minute, m:ss under an hour, h:mm:ss from an hour on.
    public static func elapsed(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func minutes(_ seconds: Double) -> Int {
        max(1, Int((seconds / 60).rounded()))
    }

    static func duration(_ seconds: Double, context: AppLocale) -> String {
        let total = minutes(seconds)
        let hours = total / 60
        let mins = total % 60
        func number(_ value: Int) -> String { value.formatted(.number.locale(context.formatLocale)) }
        if hours == 0 { return L10n.format("%@ min", [number(mins)], context: context) }
        if mins == 0 { return L10n.format("%@ hr", [number(hours)], context: context) }
        return L10n.format("%@ hr %@ min", [number(hours), number(mins)], context: context)
    }
}

/// Engine stage names are identifiers in progress and logs, not display copy.
public enum BuildStageCopy {
    public static func title(_ stage: String, context: AppLocale = L10n.context) -> String {
        let key: String
        switch stage {
        case "", "Preparing build": key = "Preparing"
        case "decompress NSZ": key = "Decompressing NSZ"
        case "build ID lookup", "survey: RomFS manifest", "survey: code modules", "survey: imports vs host hooks",
             "heap check", "address regions": key = "Checking game files"
        case "rewrite": key = "Preparing game code"
        case "NRO capture", "GLSLC capture", "UE shader decode", "JIT capture", "shader split":
            key = "Preparing shaders"
        case PortingProgress.shaderStageName, "iOS shaders", "Vulkan shaders", "GL shaders": key = "Compiling shaders"
        case "Mac host": key = "Building Mac runtime"
        case "Nextendo game patch", "Nextendo services": key = "Configuring Nextendo"
        case "Pipeline prebuild": key = "Building pipelines"
        case PortingProgress.pipelineArchiveStageName: key = "Archiving pipelines"
        case PortingProgress.prewarmStageName: key = "Preparing the first launch"
        case "Mac app", "app build", "IPA pack": key = "Building the app"
        case "prepare Xcode": key = "Preparing Xcode"
        case "Build completed": key = "Ready to play"
        case "Installation failed", PendingInstall.stageName: key = stage
        default:
            if stage.hasPrefix("extract ") || stage.hasPrefix("unpack ") { key = "Extracting game files" }
            else if stage.hasPrefix("pack ") { key = "Packing game files" }
            else if stage.hasPrefix("check ") { key = "Checking game files" }
            else if stage.hasSuffix(" shader capture") { key = "Preparing shaders" }
            else { key = "Porting" }
        }
        return L10n.text(key, context: context)
    }
}

/// What a game's art tile shows.
public enum PortingTileLook: Equatable {
    case transfer(Double)
    case normal
    /// The app plays normally, and the files needed to rebuild with the selected engine are available.
    case engineUpdate
    /// Black and white, blurred, a thin "step/count" bar with the stage and its step in small type.
    case preparing(step: Int, count: Int, title: String, detail: String)
    /// Colour risen to this fraction, the percentage in the middle.
    case filling(Double)
    /// One gesture from playing keeps its colours: the app is in the cloud, or the game files are here.
    case toDownload, toBuild
    /// Only the game files are in the cloud: download, then build. Softened.
    case toDownloadFiles
    /// Nothing here, and the cloud has not answered yet: softened, no verdict.
    case unchecked
    /// Neither here nor in the cloud: black and white.
    case missing
    /// A Steam game Steam is still installing: black and white, the download glyph and "Downloading".
    case downloading

    /// A catalog game's tile outside porting: downloading while Steam installs it.
    public static func make(catalog game: CatalogGame) -> PortingTileLook {
        game.steamGame?.isDownloading == true ? .downloading : .normal
    }

    /// A game at rest. Nil in the cloud means it has not been checked.
    public static func resting(playable: Bool, appInCloud: Bool?, filesHere: Bool, filesInCloud: Bool?,
                               engineIsOlder: Bool = false) -> PortingTileLook {
        if playable { return engineIsOlder && (filesHere || filesInCloud == true) ? .engineUpdate : .normal }
        if appInCloud == true { return .toDownload }
        if filesHere { return .toBuild }
        if filesInCloud == true { return .toDownloadFiles }
        return appInCloud == nil || filesInCloud == nil ? .unchecked : .missing
    }

    public var isAtRest: Bool {
        switch self {
        case .normal, .engineUpdate, .toDownload, .toBuild, .toDownloadFiles, .unchecked, .missing: return true
        case .transfer, .preparing, .filling, .downloading: return false
        }
    }

    public static func make(game: PortedGame, portingGameID: UUID?, progress: PortingProgress?,
                            resting: PortingTileLook) -> PortingTileLook {
        if game.id == portingGameID, let progress {
            switch progress.phase {
            case .preparing:
                let title = progress.stageName.prefix(1).uppercased() + progress.stageName.dropFirst()
                return .preparing(step: progress.step, count: progress.count, title: title, detail: progress.stepName)
            case .shaders, .finishing: return .filling(progress.overall)
            case .done, .failed: break
            }
        }
        return resting
    }
}

/// The pills under the game's title on Spotlight and Details.
public enum PortingPills: Equatable {
    /// Play (or Build), Options, Favorite.
    case normal
    /// Cancel replaces only the primary action; Options, Cloud and Favorite keep their indices.
    case queued
    /// One "Porting" pill.
    case porting
    /// Try again, Open log, Delete.
    case failed(PortingFailure)
    /// The normal pills over a working app, with a small "last porting failed" line.
    case normalAfterFailure(PortingFailure)
    /// Keep the entry and its options, with a disabled primary action and a short reason.
    case unavailable(GameUnavailableReason)

    public static func make(game: PortedGame, portingGameID: UUID?, queued: Bool = false) -> PortingPills {
        if game.id == portingGameID { return .porting }
        if queued { return .queued }
        if let reason = GameResourceState.unavailableReason(for: game) { return .unavailable(reason) }
        guard let failure = game.portingFailure else { return .normal }
        return game.isPlayableLocally ? .normalAfterFailure(failure) : .failed(failure)
    }

    public var count: Int { self == .porting ? 1 : 3 }

    public func cancelsQueuedBuild(at index: Int) -> Bool { self == .queued && index == 0 }

    /// Play and Options keep their positions. On special porting rows, Cloud follows their last action.
    public var detailsCloudIndex: Int {
        switch self {
        case .porting, .failed: return count
        case .normal, .queued, .normalAfterFailure, .unavailable: return 2
        }
    }

    public func detailsPresentation(cloudOnly: Bool) -> Self {
        if cloudOnly, case .failed(let failure) = self { return .normalAfterFailure(failure) }
        return self
    }

    public var unavailableReason: GameUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}
