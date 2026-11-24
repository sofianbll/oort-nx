import AppKit
import Combine
import SwiftUI
import NXLibraryCore
import ArcanePorting

enum SettingsConfirmationProbe {
    static let remotes = try! JSONDecoder().decode([RcloneRemote].self,
        from: Data(#"[{"name":"fixture","type":"drive","source":"file"}]"#.utf8))
    static var disconnects = 0
    static var switches: [String] = []
    static var pickedEngine: URL?

    static func disconnect(_ tool: URL, _ name: String) throws {
        precondition(tool.path == "/fixture/rclone" && name == "fixture")
        disconnects += 1
    }

    struct Input {
        @ObservedObject var viewModel: AppViewModel
    }

    @MainActor static func run(_ output: URL) async throws {
        let root = AppData.supportRoot.appendingPathComponent("settings-confirmation-probe", isDirectory: true)
        let settings = AppSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: root)))
        let model = vm.cloudLibrary
        let input = Input(viewModel: vm)
        let locale = AppLocale(language: .french, region: "FR")
        let previousLocale = L10n.context
        L10n.setContext(locale)
        defer { L10n.setContext(previousLocale) }

        func render<V: View>(_ name: String, _ view: V, height: CGFloat = 690) throws {
            try CloudScreenProbe.render("confirm-\(name)-fr", output,
                view.environment(\.nxAppLocale, locale).environment(\.seleneButtonNames, .xbox),
                size: .init(width: 1140, height: height))
        }

        func confirm(_ name: String, _ open: () -> Void, count: () -> Int) throws {
            let before = count()
            open()
            let notice = vm.settingsNotice!
            precondition(vm.settingsNoticeFocus == notice.cancelIndex && count() == before, name)
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
            .screenFolder("Other library")
        try render("cloud-library-folder", library, height: 1020)
        // The verified step's Cancel goes back to the folder list, not to activation.
        library.cancel()
        precondition(model.preference.root == "Games" && cloudWrites == 4)
        CloudSetupAssistant(viewModel: vm, model: model, entry: .library, onClose: { closed += 1 })
            .screenFolder("Other library").primary()
        precondition(model.preference.root == "Other library" && cloudWrites == 5 && closed == 3)
        let sources = CloudSetupAssistant(viewModel: vm, model: model, entry: .sources, onClose: { closed += 1 })
            .screenFolder("Other sources")
        try render("cloud-game-files-folder", sources, height: 1020)
        sources.cancel()
        precondition(model.preference.sourcesRootOverride == nil && cloudWrites == 5 && closed == 4)
        CloudSetupAssistant(viewModel: vm, model: model, entry: .sources, onClose: { closed += 1 })
            .screenFolder("Other sources").primary()
        precondition(model.preference.sourcesRootOverride == "Other sources" && cloudWrites == 6 && closed == 5)

        try confirm("cloud-disconnect", cloud.confirmDisconnect, count: { disconnects })
        for _ in 0..<20 where model.isChangingConnection { await Task.yield() }
        precondition(disconnects == 1 && model.preference.remote == nil && cloudWrites == 7)

        let setup = vm.setup
        let engineFolder = root.appendingPathComponent("Engine", isDirectory: true)
        let scripts = engineFolder.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: engineFolder.appendingPathComponent("dm"), withIntermediateDirectories: true)
        try Data().write(to: scripts.appendingPathComponent("build_ipa_from_nsp.py"))
        let pin = vm.pinnedEngineCommit
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

        let main = String(repeating: "e", count: 40)
        setup.upstreamState = .loaded(.init(repository: "fixture", status: "ahead", baseCommit: pin, upstreamCommit: main,
            aheadBy: 2, behindBy: 0, totalCommits: 2, commits: [],
            compareURL: URL(string: "https://example.invalid")!, checkedAt: .now))
        try confirm("engine-newest", { pressEngine("newest") }, count: { switches.count })
        precondition(switches == ["useNewestEngine"])
        setup.newestEngineChoice = .init(commit: String(repeating: "d", count: 40), aheadBy: 1, turnedOnOverride: true)
        try confirm("engine-update", { pressEngine("newest") }, count: { switches.count })
        try confirm("engine-tested", { pressEngine("newest", 1) }, count: { switches.count })
        precondition(switches == ["useNewestEngine", "useNewestEngine", "useTestedEngine"] && vm.pinnedEngineCommit == pin)

        var networkActions: [SettingsRowAction] = []
        ScreenVPN.connected = true
        defer { ScreenVPN.connected = false }
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
        withExtendedLifetime((cloudObserver, engineObserver, overrideObserver, networkObserver)) {}
        print("Settings confirmation probe: cancel and single apply checked for cloud, engine and multiplayer.")
    }
}
