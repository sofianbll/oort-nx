import AppKit
import NXLibraryCore
import ArcanePorting

/// What the home shows of the porting: the tile look, the pills and the time line.
extension AppViewModel {
    /// The game being ported now, if any.
    var portingGameID: UUID? { isBuilding ? currentBuildGameID : nil }

    func portingTileLook(_ game: PortedGame) -> PortingTileLook {
        PortingTileLook.make(game: game, portingGameID: portingGameID, progress: portingProgress,
                             resting: restingTileLook(game))
    }

    private func restingTileLook(_ game: PortedGame) -> PortingTileLook {
        let state = cloudLibrary.states[game.id]
        func inCloud(_ item: CloudLibraryItem, expected: Bool) -> Bool? {
            guard cloudLibrary.archive != nil else { return false }
            switch state?.copy(item) {
            case .cloudOnly: return true
            case .notInCloud: return false
            default: return expected ? true : cloudLibrary.catalogChecked ? false : nil
            }
        }
        // An imported title is only listed because its app is in the cloud.
        let older = installedVersions[game.id]?.isOlder == true
        let playable = game.isPlayableLocally
        let filesInCloud = playable ? older && engineUpdateFilesInCloud(for: game) : inCloud(.sources, expected: false)
        return .resting(playable: playable, appInCloud: inCloud(.app, expected: game.cloudImportPending == true),
                        filesHere: gamesWithFilesHere.contains(game.id),
                        filesInCloud: filesInCloud, engineIsOlder: older)
    }

    func engineDetail(for game: PortedGame) -> String {
        let version = installedVersions[game.id] ?? .unknown
        return version.detail(filesAvailable: gamesWithFilesHere.contains(game.id) || engineUpdateFilesInCloud(for: game))
    }

    private func engineUpdateFilesInCloud(for game: PortedGame) -> Bool {
        guard cloudLibrary.archive != nil, let state = cloudLibrary.states[game.id] else { return false }
        if state.referenceSources != nil { return true } // The reference lookup verifies every required file.
        guard let sources = state.sources ?? state.sourceAvailability, !sources.files.isEmpty,
              Set(sources.files.map(\.url)) == Set(game.sources.map(\.url)) else { return false }
        // Availability can be mixed: files already here need not also have a remote copy.
        return sources.files.allSatisfy { file in
            file.state != .newerOnThisMac && (file.localBytes != nil || file.state == .cloudOnly)
        }
    }

    func portingPills(_ game: PortedGame) -> PortingPills {
        let pills = PortingPills.make(game: game, portingGameID: portingGameID, queued: buildQueue.contains(game.id))
        if pills == .unavailable(.sourcesMissing), canCheckCloudSources(for: game) { return .normal }
        return pills
    }

    /// "About 8 min left" under the Porting pill; nil before the shaders.
    var portingETAText: String? {
        guard isBuilding, let portingProgress else { return nil }
        return PortingETA.text(portingProgress, lastFinishingSeconds: porting.lastPortingFinishSeconds)
    }
}
