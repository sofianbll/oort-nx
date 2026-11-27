import Foundation
import OortLibrary

/// Installed builds can differ from the selected checkout. Read their packer's DMCommit and use the checkout
/// only as a Git object database. Cache the answers on this actor, off SwiftUI's main actor.
public actor InstalledEngineCapabilities {
    public static let shared = InstalledEngineCapabilities()

    private static let homeMenuCommit = "4a2a3426defd5326c270d48341cbb77d23ed75cf"
    private static let trpfdCommit = "2aaaa33b5969815bd8692b4a1af42e78b06869d4"
    static let trpfdTitleID = "0100F43008C44000"

    private let runner: any CommandRunning & Sendable
    private var engineFolder = ""
    private var ancestry: EngineAncestry?
    private var trpfdProfiles: [String: Bool] = [:]

    public init(runner: any CommandRunning & Sendable = SystemCommandRunner()) {
        self.runner = runner
    }

    public func supportsHomeMenu(in app: URL, engineFolder: String) async -> Bool {
        let known = await engineCommit(in: app, engineFolder: engineFolder, containing: Self.homeMenuCommit) != nil
        return HomeMenu.supported(by: app, knownEngine: known)
    }

    public func gameOverlay(in app: URL) -> GameOverlayLaunch {
        GameOverlayLaunch(app: app)
    }

    public func supportsGameDisplay(in app: URL) -> Bool {
        // Read the installed host, so a backport or an imported app needs no Git history.
        let host = try? Data(contentsOf: HomeMenu.hostExecutable(in: app), options: [.mappedIfSafe])
        return host?.range(of: Data("\(GameDisplay.key)\0".utf8)) != nil
    }

    public func mergesTrpfd(in app: URL, engineFolder: String, gameData: URL,
                            environment: [String: String] = NSWorkspaceLauncher.inheritedGameEnvironment()) async -> Bool {
        // Only the Z-A profile is supported. Unknown metadata must not hide warnings.
        guard CheatLocator.titleID(appURL: app, fallback: nil) == Self.trpfdTitleID,
              let commit = await engineCommit(in: app, engineFolder: engineFolder, containing: Self.trpfdCommit),
              self.engineFolder == engineFolder,
              trpfdProfileIsEnabled(at: commit) else { return false }
        let key = "DM_TRPFD_MERGE"
        if let value = environment[key] { return value != "0" }
        for file in [gameData.appendingPathComponent("env.txt"),
                     app.appendingPathComponent("Contents/Resources/dm/env.txt")] {
            if let text = try? String(contentsOf: file, encoding: .utf8),
               let setting = CheatLocator.envLines(text).first(where: { $0.0 == key }) {
                return setting.1 != "0"
            }
        }
        return true
    }

    private func engineCommit(in app: URL, engineFolder: String, containing feature: String) async -> String? {
        guard !engineFolder.isEmpty, let commit = MacNXNative.embeddedStamp(in: app) else { return nil }
        if self.engineFolder != engineFolder {
            self.engineFolder = engineFolder
            ancestry = EngineAncestry(runner: runner, engineFolder: URL(fileURLWithPath: engineFolder))
            trpfdProfiles.removeAll()
        }
        return await ancestry?.answer(feature, in: commit) == true ? commit : nil
    }

    private func trpfdProfileIsEnabled(at commit: String) -> Bool {
        if let known = trpfdProfiles[commit] { return known }
        let profile = "\(commit):dm/games/\(Self.trpfdTitleID)/game.tsv"
        guard let result = try? runner.run(URL(fileURLWithPath: "/usr/bin/git"),
                                          ["-C", engineFolder, "show", profile],
                                          environment: nil, currentDirectory: nil),
              result.status == 0 else { return false }
        let flag = result.stdout.split(whereSeparator: \.isNewline)
            .lazy.map { $0.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } }
            .first { $0.first == "trpfd_merge" }
        let enabled = flag == ["trpfd_merge", "on"]
        trpfdProfiles[commit] = enabled
        return enabled
    }
}
