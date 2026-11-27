import AppKit
import OortLibrary
import NxnativeAdapter

/// Copy diagnostics: what an issue needs, scrubbed by `DiagnosticsReport` (no key values, no
/// environment, the home folder as `~`).
extension AppViewModel {
    /// The game's Cheats line needs git's answer about its engine, asked off the main thread before the report is read.
    func copyDiagnostics() {
        Task { @MainActor in
            if let game = diagnosticsGame { await cheats.prepare(for: game) }
            let developerDir = setup.resolvedDeveloperDir()
            let engine = setup.engineAdapter(developerDir: developerDir, keys: setup.keysDirectory)
            let snapshot = await Task.detached { engine.workshop() }.value
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(DiagnosticsReport.markdown(diagnosticsInputs(snapshot, developerDir: developerDir)), forType: .string)
            SoundEffectService.shared.play(.success)
        }
    }

    /// The game the report is about: the last build's, else the one in front.
    private var diagnosticsGame: PortedGame? {
        guard let id = lastBuildGameID ?? frontGameID else { return nil }
        return libraryGames.first { $0.id == id }
    }

    private func diagnosticsInputs(_ workshop: Workshop, developerDir: URL) -> DiagnosticsReport.Inputs {
        var i = DiagnosticsReport.Inputs()
        let info = Bundle.main.infoDictionary
        i.appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let executable = Bundle.main.executableURL ?? Bundle.main.bundleURL
        i.buildDate = (try? executable.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.formatted(date: .abbreviated, time: .omitted)
        i.bundleID = Bundle.main.bundleIdentifier ?? "?"
        i.macOS = ProcessInfo.processInfo.operatingSystemVersionString
        i.chip = Self.sysctlString("machdep.cpu.brand_string") ?? "?"
        i.pinnedCommit = workshop.versions.reference
        i.newestEngine = setup.newestEngineChoice.map { "\($0.commit) (\(NewestEngineCopy.ahead($0.aheadBy)))" }
        i.engineHead = workshop.versions.selected.value.map { String($0.prefix(7)) }
        i.xcodePath = developerDir.path
        i.xcodeVersion = setup.environmentStatus?.xcodeVersion
        i.metalFound = setup.environmentStatus?.metalVersion
        i.metalCertified = ToolchainRequirements.current.metalAssets.keys.sorted().joined(separator: ", ")
        i.untestedOverride = setup.allowUntestedToolchain
        let tools = setup.environmentStatus?.tools ?? []
        i.python = setup.engineToolchain.python.path
        i.setupRows = tools.map { ($0.name, $0.ok) }
        i.keysImported = workshop.localKeys != .required
        i.hasHeaderKey = workshop.localKeys.applicationGenerations != nil
        i.keyGenerations = workshop.localKeys.applicationGenerations ?? 0
        if let game = diagnosticsGame {
            let failure = game.portingFailure.map { failure in
                failure == .cancelled ? "cancelled" : "failed (\(game.portingFailureReason?.kind.rawValue ?? "unknown"))"
            }
            i.game = (game.name, game.titleId, game.isPlayableLocally, game.lastBuild?.toolchainVerified,
                      failure ?? (game.lastBuild != nil ? "succeeded" : nil))
            i.cheats = cheats.cheatDiagnostics(for: game)
        }
        i.deadWorkspaceLinks = LibraryPaths.deadWorkspaceLinks(in: core)
        i.lastCommand = porting.lastPortingCommand
        let logURL = buildLogURL ?? (lastBuildGameID.flatMap { id in libraryGames.first { $0.id == id } }
            .flatMap { logURL(for: $0) })
        if let logURL, let text = try? String(contentsOf: logURL, encoding: .utf8) {
            i.log = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(60).map(String.init)
        } else {
            i.log = logs.suffix(60).map(\.message)
        }
        let keyPath = setup.managedKeysURL.path
        i.lastCommand = i.lastCommand.map { $0 == keyPath ? "<private keys>" : $0 }
        i.log = i.log.map { $0.replacingOccurrences(of: keyPath, with: "<private keys>") }
        return i
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
