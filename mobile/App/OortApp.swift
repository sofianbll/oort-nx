// Adapted from NX2Apple frontend-ios/Shell/App/ShellApp.swift at a79d397 (MIT, Copyright (c) 2026 seedds, jhaizhou, LNPANDY and NX2Apple contributors).
// Oort NX's screens and sounds replace its library. The memory purge, which makes iOS close other apps, runs only when a game's
// settings name DM_MEM_PURGE_MB. Nothing is signed on the device.
import GameController
import OortMobile
import ShellHost
import ShellModel
import SwiftUI
import UIKit

/// The real launcher. The process becomes the game, so `launch` returns only on a failure to start.
struct EngineGameLauncher: GameLauncher {
    enum Failure: LocalizedError {
        case engine(String)
        var errorDescription: String? { if case .engine(let text) = self { return text }; return nil }
    }

    @MainActor func launch(_ game: LaunchableGame) async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let bundleURL = Bundle.main.bundleURL
        let envFile = try? String(contentsOf: documents.appendingPathComponent("env.txt"), encoding: .utf8)
        let plan = EngineLaunchPlan.make(game: game, appResources: Bundle.main.resourceURL ?? bundleURL, documents: documents, envFileText: envFile)
        let executable = plan.frameworkExecutable
        if let refusal = await Task.detached(priority: .userInitiated, operation: { OortSigning.refusal(executable) }).value {
            throw Failure.engine(refusal)
        }
        try plan.createFolders()
        if let limit = plan.environment["DM_MEM_PURGE_MB"].flatMap({ Int32($0.trimmingCharacters(in: .whitespaces)) }), limit > 0 {
            await Task.detached(priority: .userInitiated) { dm_shell_purge_memory(limit) }.value
        }
        _ = ShellRuntimeBridge.cheatFuseSession.beginSession(titleID: game.titleID, cheatsFolder: plan.gameDirectory.appendingPathComponent("cheats", isDirectory: true),
                                                             buildID: CheatFuseGuard.buildID(frameworkURL: game.frameworkURL))
        let pairs = plan.environment.sorted { $0.key < $1.key }
        let failure = withCStrings(pairs.map(\.key)) { keys in
            withCStrings(pairs.map(\.value)) { values in
                withCStrings(plan.arguments) { argv in
                    dm_shell_start_game(keys, values, Int32(pairs.count), argv, Int32(plan.arguments.count),
                                        plan.frameworkExecutable.path, plan.imageMarker, plan.logURL.path, plan.workingDirectory.path, game.titleID)
                }
            }
        }
        if let failure {
            ShellRuntimeBridge.cheatFuseSession.abortBeforeRun()
            throw Failure.engine(OortLaunchWords.why(String(cString: failure)))
        }
        dm_shell_present_game()
    }
}

/// Who may have signed a game that was added after the app was installed.
enum OortSigning {
    nonisolated static func refusal(_ executable: URL) -> String? {
        #if targetEnvironment(simulator)
        return nil
        #else
        return FrameworkSignature.preflightExternal(executable: executable, appBundleURL: Bundle.main.bundleURL,
                                                    hostTeamID: ProvisioningProfile.bundledTeamIdentifier(),
                                                    hostCertSHA1: ProvisioningProfile.bundledSigningCertificateSHA1(),
                                                    allowsHotLoading: ProvisioningProfile.bundledAllowsHotFrameworkLoading())
        #endif
    }
    nonisolated static var allowsAddedGames: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return ProvisioningProfile.bundledAllowsHotFrameworkLoading()
        #endif
    }
}

/// `strdup`ed copies for the C call, freed after it (the engine copies what it keeps).
private func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>) -> R) -> R {
    let copies: [UnsafePointer<CChar>?] = strings.map { UnsafePointer(strdup($0)) }
    defer { copies.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
    return copies.withUnsafeBufferPointer { body($0.baseAddress!) }
}

/// The app's root controller, for ShellMain.m's scene delegate.
@objc(ShellLibrary) final class ShellLibrary: NSObject {
    @MainActor private static weak var activeModel: ShellHostModel?
    @MainActor private static var pendingOpenURL: URL?

    @MainActor @objc static func gameWillPause() { activeModel?.pauseActiveSession() }
    @MainActor @objc static func gameDidCheckpoint() { activeModel?.checkpointActiveSession() }
    @MainActor @objc static func gameDidResume() { activeModel?.resumeActiveSession() }
    @MainActor @objc static func gameDidEnd() { activeModel?.endActiveSession() }

    @MainActor @objc(makeControllerWithInitialURL:) static func makeController(initialURL: URL?) -> UIViewController {
        let info = Bundle.main.infoDictionary ?? [:]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        Task.detached(priority: .utility) { ShellHostBeacon.write(to: documents) }
        let hotRoot = ShellHostConfig.defaultHotFrameworksRoot()
        let config = ShellHostConfig(
            gamesRoot: Bundle.main.privateFrameworksURL ?? Bundle.main.bundleURL.appendingPathComponent("Frameworks", isDirectory: true),
            appDataRoot: ShellHostConfig.defaultAppDataRoot(),
            hotFrameworksRoot: hotRoot,
            // The shader chain the host was compiled with: a framework built for another one needs an app update.
            environment: HostEnvironment(chain: (info["DMChain"] as? String).map { "b-" + $0 }),
            updateURL: URL(string: "https://github.com/sofianbll/oort-nx/releases"),
            activeRunningGameID: { dm_shell_active_game_id().map { String(cString: $0) } },
            requestStopRunningGame: { dm_shell_request_stop_game() },
            supportsHotFrameworkLoading: { OortSigning.allowsAddedGames })
        let model = ShellHostModel(config: config, launcher: EngineGameLauncher(), picker: DocumentFolderPicker(), cheatPicker: DocumentCheatFilePicker())
        activeModel = model
        model.startControllers()
        let url = initialURL ?? pendingOpenURL
        pendingOpenURL = nil
        if let url { _ = model.handleDeepLink(url) }
        let host = UIHostingController(rootView: OortRootView(model: model, sounds: OortSounds(defaults: model.shellSettings.defaults), importRoot: hotRoot,
                                                              checkSigner: { OortSigning.refusal($0) }))
        host.view.backgroundColor = .black
        // The controller drives Oort NX's own focus, not the system's: a press never counts twice. Set on the view, not in
        // SwiftUI: handlesGameControllerEvents over the whole app took the navigation bar's touches on a phone on its side.
        let controllers = GCEventInteraction()
        controllers.handledEventTypes = .gamepad
        host.view.addInteraction(controllers)
        return host
    }

    @MainActor @objc(handleOpenURL:) static func handleOpenURL(_ url: URL) -> Bool {
        if let activeModel { return activeModel.handleDeepLink(url) }
        guard DeepLinkRouter.isLaunchURL(url) else { return false }
        pendingOpenURL = url
        return true
    }
}

/// What ShellMain.m needs from Swift: the words of the disconnect pause, and the end of a game's cheat guard.
@objc(ShellRuntimeBridge) final class ShellRuntimeBridge: NSObject {
    static let cheatFuseSession = CheatFuseSession()
    @objc static func controllerDisconnectTitle() -> String { ControllerDisconnectOverlayStrings.localized().title }
    @objc static func controllerDisconnectMessage() -> String { ControllerDisconnectOverlayStrings.localized().message }
    @objc static func controllerDisconnectResumeTitle() -> String { ControllerDisconnectOverlayStrings.localized().resumeTitle }
    @objc static func didReturnToLibrary() { cheatFuseSession.endSessionCleanly() }
}
