import AppKit
import Combine
import CoreText
import SwiftUI
import NXLibraryCore
import ArcanePorting

@main enum SettingsConfirmationProbe {
    static let remotes = try! JSONDecoder().decode([RcloneRemote].self,
        from: Data(#"[{"name":"fixture","type":"drive","source":"file"}]"#.utf8))
    static var disconnects = 0
    static var pin: String?
    static var pickedEngine: URL?
    static var availableDriveTool: URL? = URL(fileURLWithPath: "/fixture/rclone")
    static var downloadCalls = 0
    static var finishDownload: CheckedContinuation<Void, Never>?

    @MainActor static func installTool(progress: (Double) -> Void) async throws {
        downloadCalls += 1
        progress(0.42)
        await withCheckedContinuation { finishDownload = $0 }
        try Task.checkCancellation()
        throw RcloneDownload.Failure.network
    }

    static func disconnect(_ tool: URL, _ name: String) throws {
        precondition(tool.path == "/fixture/rclone" && name == "fixture")
        disconnects += 1
    }

    struct Input {
        @ObservedObject var viewModel: AppViewModel
    }

    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let font = URL(fileURLWithPath: CommandLine.arguments[2])
        NSApplication.shared.setActivationPolicy(.prohibited)
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        let locale = AppLocale(language: .french, region: "FR")
        L10n.setContext(locale)
        let root = AppData.supportRoot.appendingPathComponent("settings-confirmation-probe", isDirectory: true)
        let settings = AppSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        func makeModel() -> AppViewModel {
            AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: root)))
        }
        let vm = makeModel()
        let model = vm.cloudLibrary
        model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: nil)
        let input = Input(viewModel: vm)

        func render<V: View>(_ name: String, _ view: V, height: CGFloat = 690) throws {
            let renderer = ImageRenderer(content: view
                .frame(width: 1140, height: height)
                .background(Color(red: 0.09, green: 0.13, blue: 0.20))
                .environment(\.nxAppLocale, locale)
                .environment(\.seleneButtonNames, .xbox)
                .environment(\.colorScheme, .dark)
                .environment(\.seleneCanvas, SeleneCanvas(size: .init(width: 1920, height: 1080)))
                .environment(\.seleneReduceMotion, true))
            let image = renderer.cgImage!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: output.appendingPathComponent("confirm-\(name)-fr.png"))
        }

        func confirm(_ name: String, _ open: () -> Void, count: () -> Int) throws {
            let before = count()
            open()
            let notice = vm.settingsNotice!
            precondition(vm.settingsNoticeFocus == notice.cancelIndex && count() == before, name)
            let frenchLine = [
                "cloud-off": "cessera d’utiliser", "cloud-on": "utilisera de nouveau",
                "cloud-disconnect": "connexion locale", "reference-unfollow": "aucun fichier ne sera supprimé",
                "network-vpn": "le réglage VPN", "network-default": "aux prochains lancements",
                "network-local-mode": "privilégieront le mode", "network-adapter": "réglage d’adaptateur",
            ][name]
            if let frenchLine { precondition(notice.message.contains(frenchLine), notice.message) }
            try render(name, input.settingsNoticeOverlay(notice))
            input.settingsNoticeInput(.navigateLeft)
            precondition(vm.settingsNoticeFocus == 0 && count() == before, name)
            input.settingsNoticeInput(.navigateRight)
            input.settingsNoticeInput(.confirm) // A / Return on Cancel
            precondition(vm.settingsNotice == nil && count() == before, name)
            open()
            input.settingsNoticeInput(.cancel) // B / Esc / dismiss
            precondition(vm.settingsNotice == nil && count() == before, name)
            open()
            input.settingsNoticeInput(.navigateLeft)
            input.settingsNoticeInput(.confirm)
            input.settingsNoticeInput(.confirm)
            precondition(vm.settingsNotice == nil, name)
        }

        var cloudWrites = 0
        let cloudObserver = model.$preference.dropFirst().sink { _ in cloudWrites += 1 }
        let cloud = SettingsCloudLibrarySection(viewModel: vm, model: model, settings: settings,
            advanced: .constant(true), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
        try confirm("cloud-off", { cloud.setEnabled(false) }, count: { cloudWrites })
        precondition(!model.preference.enabled && cloudWrites == 1)
        try confirm("cloud-on", { cloud.setEnabled(true) }, count: { cloudWrites })
        precondition(model.preference.enabled && cloudWrites == 2)

        var closed = 0
        let follow = CloudReferenceDialog(viewModel: vm, onClose: { closed += 1 }).screenDraft("1-test-reference")
        try render("reference-follow", follow)
        follow.onClose()
        precondition(closed == 1 && model.preference.referenceFolder == nil && cloudWrites == 2)
        follow.save()
        precondition(closed == 2 && model.preference.referenceFolder == "1-test-reference" && cloudWrites == 3)
        try confirm("reference-unfollow", cloud.unfollow, count: { cloudWrites })
        precondition(model.preference.referenceFolder == nil && cloudWrites == 4)

        let library = CloudSetupAssistant(viewModel: vm, model: model, entry: .library, onClose: { closed += 1 })
            .screenFolder("Autre bibliothèque")
        try render("cloud-library-folder", library, height: 1020)
        // The verified step's Cancel goes back to the folder list, not to activation.
        library.cancel()
        precondition(model.preference.root == "Games" && cloudWrites == 4)
        CloudSetupAssistant(viewModel: vm, model: model, entry: .library, onClose: { closed += 1 })
            .screenFolder("Autre bibliothèque").primary()
        precondition(model.preference.root == "Autre bibliothèque" && cloudWrites == 5 && closed == 3)
        let sources = CloudSetupAssistant(viewModel: vm, model: model, entry: .sources, onClose: { closed += 1 })
            .screenFolder("Autres sources")
        try render("cloud-game-files-folder", sources, height: 1020)
        sources.cancel()
        precondition(model.preference.sourcesRootOverride == nil && cloudWrites == 5 && closed == 4)
        CloudSetupAssistant(viewModel: vm, model: model, entry: .sources, onClose: { closed += 1 })
            .screenFolder("Autres sources").primary()
        precondition(model.preference.sourcesRootOverride == "Autres sources" && cloudWrites == 6 && closed == 5)

        try confirm("cloud-disconnect", cloud.confirmDisconnect, count: { disconnects })
        for _ in 0..<20 where model.isChangingConnection { await Task.yield() }
        precondition(disconnects == 1 && model.preference.remote == nil && cloudWrites == 7)

        // Upgrade from the embedded helper: do not touch the preference or retry automatically after Cancel.
        AppData.preferences.set("fixture:Games", forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(true, forKey: CloudLibraryPreference.enabledKey)
        AppData.preferences.removeObject(forKey: CloudLibraryPreference.toolChoiceKey)
        AppData.preferences.removeObject(forKey: CloudLibraryPreference.toolOfferKey)
        let queue = AppData.supportRoot.appendingPathComponent("cloud-transfer-queue.json")
        try FileManager.default.createDirectory(at: AppData.supportRoot, withIntermediateDirectories: true)
        let entries = try JSONEncoder().encode([CloudTransferQueue.Entry(id: UUID(), action: .restore(.app),
            token: UUID(), storage: "fixture:Games")])
        try entries.write(to: queue)
        availableDriveTool = nil
        let upgraded = makeModel()
        let migration = upgraded.cloudLibrary
        let upgradeInput = Input(viewModel: upgraded)
        let drive = SettingsCloudLibrarySection(viewModel: upgraded, model: migration, settings: settings,
            advanced: .constant(false), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
        let saved = migration.preference
        precondition(migration.needsDriveToolChoice && migration.archive == nil)
        let portable = root.appendingPathComponent("portable/rclone")
        try FileManager.default.createDirectory(at: portable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: portable)
        try Data().write(to: portable.deletingLastPathComponent().appendingPathComponent("rclone.conf"))
        precondition(!migration.canChooseDriveTool(portable))
        migration.chooseExecutable(portable)
        precondition(migration.chosenExecutable == nil && migration.archive == nil)
        upgraded.offerDriveUpgrade()
        let consent = upgraded.settingsNotice!
        precondition(upgraded.settingsNoticeFocus == consent.cancelIndex && consent.message.contains("licence MIT")
                     && consent.message.contains(RcloneDownload.host) && downloadCalls == 0)
        try render("drive-download", upgradeInput.settingsNoticeOverlay(consent))
        upgradeInput.settingsNoticeInput(.confirm)
        precondition(upgraded.settingsNotice == nil && migration.archive == nil && migration.preference == saved)
        let reopenedCloud = makeModel()
        reopenedCloud.offerDriveUpgrade()
        precondition(reopenedCloud.settingsNotice == nil && reopenedCloud.cloudLibrary.needsDriveToolChoice)

        upgraded.prepareDriveTool {}
        upgradeInput.settingsNoticeInput(.navigateLeft)
        upgradeInput.settingsNoticeInput(.confirm)
        for _ in 0..<100 where finishDownload == nil { await Task.yield() }
        precondition(downloadCalls == 1 && migration.archive == nil && migration.driveToolProgress == 0.42)
        try render("drive-progress", drive, height: 950)
        finishDownload?.resume()
        finishDownload = nil
        await migration.driveToolTask?.value
        precondition(migration.driveToolFailure == .network && migration.archive == nil && migration.preference == saved)
        try render("drive-failure", drive, height: 950)
        availableDriveTool = URL(fileURLWithPath: "/fixture/rclone")
        upgraded.prepareDriveTool {}
        precondition(upgraded.settingsNoticeFocus == upgraded.settingsNotice?.cancelIndex && migration.archive == nil)
        upgradeInput.settingsNoticeInput(.navigateLeft)
        upgradeInput.settingsNoticeInput(.confirm)
        let unchangedQueue = try Data(contentsOf: queue)
        precondition(!migration.needsDriveToolChoice && migration.archive != nil && migration.preference == saved
                     && !migration.hasRestoredQueue && downloadCalls == 1 && unchangedQueue == entries)
        let installed = AppData.supportRoot.appendingPathComponent("DriveTools/rclone-\(RcloneDownload.version)", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: installed.appendingPathComponent("rclone"))
        try Data().write(to: installed.appendingPathComponent("oort-install"))
        migration.configure(remote: "fixture", root: "Games", enabled: false, sourcesRoot: nil)
        precondition(migration.canTrashDriveTool)
        try render("drive-settings", VStack(spacing: 8) { drive.advancedRows }, height: 570)
        drive.confirmTrashTool()
        let trash = upgraded.settingsNotice!
        precondition(upgraded.settingsNoticeFocus == trash.cancelIndex)
        try render("drive-trash", upgradeInput.settingsNoticeOverlay(trash))
        upgradeInput.settingsNoticeInput(.cancel)
        precondition(migration.canTrashDriveTool)
        migration.chooseExecutable(installed.appendingPathComponent("rclone"))
        precondition(!migration.canTrashDriveTool)

        let setup = vm.setup
        let engineFolder = root.appendingPathComponent("Engine", isDirectory: true)
        let scripts = engineFolder.appendingPathComponent("scripts", isDirectory: true)
        let toolchain = engineFolder.appendingPathComponent("dm/gfx/tools", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: toolchain, withIntermediateDirectories: true)
        try Data().write(to: scripts.appendingPathComponent("build_ipa_from_nsp.py"))
        try Data("metal_macosx\t32023.922\n".utf8).write(to: toolchain.appendingPathComponent("dmsh_chain.lock"))
        @discardableResult func git(_ args: String...) throws -> String {
            let result = try SystemCommandRunner().run(URL(fileURLWithPath: "/usr/bin/git"),
                ["-C", engineFolder.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@users.noreply.github.com",
                 "-c", "commit.gpgsign=false"] + args, environment: nil, currentDirectory: nil)
            precondition(result.status == 0, result.stderr)
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try git("init", "-q", "-b", "main")
        try git("add", ".")
        try git("commit", "-qm", "Tested")
        let pin = try git("rev-parse", "HEAD")
        Self.pin = pin
        try git("commit", "-qm", "Newest", "--allow-empty")
        let main = try git("rev-parse", "HEAD")
        try git("commit", "-qm", "Updated", "--allow-empty")
        let update = try git("rev-parse", "HEAD")
        try git("remote", "add", "origin", ".")
        try git("checkout", "--quiet", "--detach", pin)
        var engineActions: [SettingsRowAction] = []
        let engine = SettingsEngineSection(viewModel: vm, setup: setup, settings: settings, onActions: { engineActions = $0 })
        func pressEngine(_ id: String, _ button: Int = 0) {
            engine.publishActions()
            engineActions.first { $0.id == id }!.press(button: button)
        }
        var engineWrites = 0
        let engineObserver = setup.$nxnativePath.dropFirst().sink { _ in engineWrites += 1 }
        pressEngine("repo") // Native picker returned Cancel.
        precondition(engineWrites == 0)
        pickedEngine = engineFolder
        pressEngine("repo")
        pickedEngine = nil
        precondition(engineWrites == 1 && setup.nxnativePath == engineFolder.path && vm.pinnedEngineCommit == pin)
        setup.compatibilityReport = .init(ok: false, checks: [])
        var overrideWrites = 0
        let overrideObserver = setup.$allowUntestedToolchain.dropFirst().sink { _ in overrideWrites += 1 }
        try confirm("toolchain-on", { pressEngine("override") }, count: { overrideWrites })
        precondition(setup.allowUntestedToolchain && overrideWrites == 1)
        try confirm("toolchain-off", { pressEngine("override") }, count: { overrideWrites })
        precondition(!setup.allowUntestedToolchain && overrideWrites == 2)

        func offer(_ commit: String, count: Int) {
            setup.upstreamState = .loaded(.init(repository: "fixture", status: "ahead", baseCommit: pin, upstreamCommit: commit,
                aheadBy: count, behindBy: 0, totalCommits: count, commits: [],
                compareURL: URL(string: "https://example.invalid")!, checkedAt: .now))
        }
        func waitForSwitch() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while setup.isSwitchingEngine && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(15)) }
            precondition(!setup.isSwitchingEngine && setup.newestEngineProblem == nil, setup.newestEngineProblem ?? "Switch timed out")
        }
        var switches = 0
        let switchObserver = setup.$isSwitchingEngine.dropFirst().filter { $0 }.sink { _ in switches += 1 }
        offer(main, count: 1)
        pressEngine("newest")
        input.settingsNoticeInput(.cancel)
        let cancelledHead = try git("rev-parse", "HEAD")
        precondition(cancelledHead == pin && switches == 0 && makeModel().setup.newestEngineChoice == nil)
        try confirm("engine-newest", { pressEngine("newest") }, count: { switches })
        try await waitForSwitch()
        let newestHead = try git("rev-parse", "HEAD")
        let reopened = makeModel()
        precondition(switches == 1 && newestHead == main && reopened.setup.newestEngineChoice?.commit == main && reopened.setup.allowUntestedToolchain)
        offer(update, count: 2)
        try confirm("engine-update", { pressEngine("newest") }, count: { switches })
        try await waitForSwitch()
        let updatedHead = try git("rev-parse", "HEAD")
        precondition(switches == 2 && updatedHead == update && makeModel().setup.newestEngineChoice?.commit == update)
        // An outstanding offer leaves Back to tested at the secondary button.
        offer(main, count: 1)
        try confirm("engine-tested", { pressEngine("newest", 1) }, count: { switches })
        try await waitForSwitch()
        let testedHead = try git("rev-parse", "HEAD")
        precondition(switches == 3 && testedHead == pin && makeModel().setup.newestEngineChoice == nil && !setup.allowUntestedToolchain)

        var networkActions: [SettingsRowAction] = []
        let network = SettingsAPISection(viewModel: vm, settings: settings, showsMultiplayer: true,
            supportsNextendo: true, advanced: .constant(true), onActions: { networkActions = $0 })
        network.publishActions()
        settings.settings.multiplayerAdapter = "oldAdapter"
        var networkWrites = 0
        let networkObserver = settings.$settings.dropFirst().sink { _ in networkWrites += 1 }
        func pressNetwork(_ id: String) { networkActions.first { $0.id == id }!.press(button: 0) }
        try confirm("network-vpn", { pressNetwork("multiplayerVPN") }, count: { networkWrites })
        precondition(networkWrites == 1 && settings.settings.multiplayerVPN == .zeroTier && settings.settings.multiplayerAdapter == nil)
        try confirm("network-default", { pressNetwork("multiplayerDefault") }, count: { networkWrites })
        precondition(networkWrites == 2 && settings.settings.multiplayerDefault == .local)
        try confirm("network-local-mode", { pressNetwork("multiplayerLocalMode") }, count: { networkWrites })
        precondition(networkWrites == 3 && settings.settings.multiplayerLocalMode == .lan)
        try confirm("network-adapter", { networkActions.first { $0.id == "multiplayerAdapter" }!.cycle!(1) }, count: { networkWrites })
        precondition(networkWrites == 4 && settings.settings.multiplayerAdapter == "feth3971")

        let client = NextendoClientDialog(settings: settings, onClose: { closed += 1 }).screenDraft("fixture-nextendo")
        try render("nextendo-client", client)
        client.onClose()
        precondition(closed == 6 && networkWrites == 4 && settings.settings.nextendoClientID == nil)
        client.save()
        precondition(closed == 7 && networkWrites == 5 && settings.settings.nextendoClientID == "fixture-nextendo")

        let page = SettingsView(initialSection: .multiplayer, viewModel: vm, settings: settings,
                                router: AppRouter(), artwork: ArtworkStore())
        try confirm("network-reset", page.resetSection, count: { networkWrites })
        precondition(networkWrites == 6 && SettingsReset.reset(.multiplayer, in: settings.settings) == settings.settings
            && settings.settings.nextendoClientID == "fixture-nextendo")
        withExtendedLifetime((cloudObserver, engineObserver, overrideObserver, switchObserver, networkObserver)) {}
        print("Settings confirmation probe: cancel and single apply checked for cloud, engine and multiplayer.")
    }
}
