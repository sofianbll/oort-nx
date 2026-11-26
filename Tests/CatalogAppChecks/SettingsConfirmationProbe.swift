import AppKit
import Combine
import CoreText
import SwiftUI
import Vision
import NXLibraryCore
import ArcanePorting

@main enum SettingsConfirmationProbe {
    static let remotes = try! JSONDecoder().decode([RcloneRemote].self,
        from: Data(#"[{"name":"fixture","type":"drive","source":"file"}]"#.utf8))
    static var disconnects = 0
    static var pin: String?
    static var pickedEngine: URL?
    nonisolated(unsafe) static var pickedRclone: URL?
    static var availableDriveTool: URL? = URL(fileURLWithPath: "/fixture/rclone")
    static var scopeTool: URL?
    static var scopeAccount = "Account_ID"
    static var scopeLibraryID = "Library_ID"
    static var scopeSourcesID: String? = "Initial_ROMs_ID"
    static var scopeOffline = false
    static var downloadCalls = 0
    static var finishDownload: CheckedContinuation<Void, Never>?

    @MainActor static func installTool(progress: (Double) -> Void) async throws {
        downloadCalls += 1
        progress(0.42)
        await withCheckedContinuation { finishDownload = $0 }
        try Task.checkCancellation()
        throw RcloneDownload.Failure.network
    }

    static var account: RcloneAccount?
    static var kept: [Bool] = []
    nonisolated(unsafe) static let choices = MemorySavedChoices()

    static func disconnect(_ tool: URL, _ name: String, keepingClient: Bool) throws {
        kept.append(keepingClient)
        precondition(tool.path == "/fixture/rclone" && name == "fixture")
        disconnects += 1
    }

    static func scopeBackend(remote: String, root: String, tool: URL) -> RcloneStorageBackend {
        scopeTool = tool
        return RcloneStorageBackend(remote: remote, root: root) { _, args, _ in
            precondition(args.contains("--drive-shared-with-me=false"))
            switch args.first {
            case "about":
                if scopeOffline { return .init(status: 1, stdout: "", stderr: "network is unreachable") }
                return .init(status: 0, stdout: "{}", stderr: "'root_folder_id = \(scopeAccount)' - save this in the config to speed up startup")
            case "lsjson" where args.contains("--stat"):
                return .init(status: 0, stdout: #"{"IsDir":true}"#, stderr: "")
            case "lsjson" where args.contains("--dirs-only"):
                let json: String
                if args.contains("--drive-root-folder-id=\(scopeLibraryID)") {
                    let gameFiles = scopeSourcesID.map { #"{"Name":"GameFiles","ID":"\#($0)","IsDir":true},"# } ?? ""
                    json = "[" + gameFiles + #"{"Name":"Switch","ID":"Switch_ID","IsDir":true}]"#
                } else if args.contains("--drive-root-folder-id=Switch_ID") {
                    json = scopeSourcesID.map { #"[{"Name":"Jeux","ID":"\#($0)","IsDir":true}]"# } ?? "[]"
                } else {
                    json = #"[{"Name":"Games","ID":"\#(scopeLibraryID)","IsDir":true},{"Name":"Autre bibliothèque","ID":"Other_ID","IsDir":true},{"Name":"Autres sources","ID":"ROMs_ID","IsDir":true}]"#
                }
                return .init(status: 0, stdout: json, stderr: "")
            default: preconditionFailure("Unexpected fixture command: \(args)")
            }
        }
    }

    struct Input {
        @ObservedObject var viewModel: AppViewModel
    }

    @MainActor static func checkDriveScope(settings: AppSettingsStore, makeModel: () -> AppViewModel) async throws {
        let roms = "Games/Switch/Jeux"
        let prefs = AppData.preferences
        let keys = ["NXLibrary_CloudDriveScope", "NXLibrary_CloudSourcesBinding", "NXLibrary_CloudLastKnownAvailability",
                    CloudLibraryPreference.referenceFolderKey, CloudLibraryPreference.toolOfferKey]
        let initial = (keys + [CloudLibraryPreference.storageKey, CloudLibraryPreference.enabledKey,
                              CloudLibraryPreference.toolChoiceKey, CloudLibraryPreference.sourcesRootKey])
            .map { ($0, prefs.object(forKey: $0)) }
        defer { for (key, value) in initial { prefs.set(value, forKey: key) } }
        func seed(_ explicit: Bool, migrating: Bool = false) {
            for key in keys { prefs.removeObject(forKey: key) }
            prefs.set("fixture:Games", forKey: CloudLibraryPreference.storageKey)
            prefs.set(true, forKey: CloudLibraryPreference.enabledKey)
            prefs.set(!migrating, forKey: CloudLibraryPreference.toolChoiceKey)
            prefs.set(explicit ? roms : nil, forKey: CloudLibraryPreference.sourcesRootKey)
            scopeSourcesID = "Initial_ROMs_ID"
            scopeAccount = "Account_ID"
            scopeLibraryID = "Library_ID"
            scopeOffline = false
        }
        var failures: [String] = []
        func check(_ ok: Bool, _ message: String) {
            if !ok { failures.append(message) }
        }
        for explicit in [true, false] {
            seed(explicit)
            let original = makeModel().cloudLibrary
            if explicit {
                original.chooseSourcesRoot(roms)
            }
            await original.scopeTask?.value
            precondition(original.driveScope?.sources?.id == "Initial_ROMs_ID")
            scopeSourcesID = nil
            original.setReferenceFolder("TemporaryRef")
            await original.scopeTask?.value
            precondition(original.driveScope?.sources == nil)
            scopeSourcesID = "Replacement_ROMs_ID"
            let replaced = makeModel().cloudLibrary
            await replaced.scopeTask?.value
            check(replaced.sourceArchive == nil && replaced.sourcesNeedConfirmation, "N3: replacement accepted (explicit=\(explicit))")
            scopeSourcesID = "Initial_ROMs_ID"
            let restored = makeModel().cloudLibrary
            await restored.scopeTask?.value
            check(restored.sourceArchive == nil && restored.sourcesNeedConfirmation, "N3: mismatch forgotten after restart")
            restored.chooseSourcesRoot(explicit ? roms : nil)
            await restored.scopeTask?.value
            check(restored.sourceArchive != nil && !restored.sourcesNeedConfirmation, "N3: a fresh choice cannot enable the valid folder")
        }

        seed(false)
        scopeOffline = true
        let offline = makeModel()
        let model = offline.cloudLibrary
        await model.scopeTask?.value
        precondition(model.connectionCheck?.failure == .offline && model.archive == nil)
        var actions: [SettingsRowAction] = []
        let settingsView = SettingsCloudLibrarySection(viewModel: offline, model: model, settings: SettingsEditor(settings),
            advanced: .constant(true), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { actions = $0 })
        settingsView.publishActions()
        scopeOffline = false
        if let retry = actions.first(where: { $0.id == "cloudRecovery" }), retry.isEnabled {
            retry.press(button: 0)
            let deadline = ContinuousClock.now + .seconds(3)
            while model.archive == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(15)) }
        }
        check(model.archive != nil && model.connectionCheck?.failure == nil && model.importTask == nil,
              "N12: Retry cannot recover the scope without importing")
        if model.archive == nil {
            model.setReferenceFolder("TemporaryRef")
            await model.scopeTask?.value
        }
        precondition(model.driveScope?.account == "Account_ID")
        scopeAccount = "Replacement_Account_ID"
        model.connectionCheck = nil
        settingsView.test()
        let deadline = ContinuousClock.now + .seconds(3)
        while model.connectionCheck == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(15)) }
        check(model.connectionCheck?.failure == .scopeChanged && model.archive == nil, "N12: Test connection accepted a replacement account")
        scopeAccount = "Account_ID"
        scopeLibraryID = "Replacement_Library_ID"
        model.connectionCheck = nil
        settingsView.test()
        let folderDeadline = ContinuousClock.now + .seconds(3)
        while model.connectionCheck == nil && ContinuousClock.now < folderDeadline { try await Task.sleep(for: .milliseconds(15)) }
        check(model.connectionCheck?.failure == .scopeChanged && model.archive == nil, "N12: Test connection accepted a replacement folder")

        seed(true, migrating: true)
        let upgraded = makeModel()
        let migration = upgraded.cloudLibrary
        let input = Input(viewModel: upgraded)
        upgraded.prepareDriveTool {}
        let consent = upgraded.settingsNotice!
        check(consent.message.contains(roms), "N13: the existing-tool consent does not show the saved ROM path")
        input.settingsNoticeInput(.confirm)
        check(migration.needsDriveToolChoice && migration.preference.sourcesRootOverride == roms && migration.sourceArchive == nil,
              "N13: Cancel changed the ROM selection")
        scopeOffline = true
        upgraded.prepareDriveTool {}
        input.settingsNoticeInput(.navigateRight)
        input.settingsNoticeInput(.confirm)
        await migration.scopeTask?.value
        check(migration.connectionCheck?.failure == .offline && migration.sourceArchive == nil
              && migration.preference.sourcesRootOverride == roms
              && prefs.object(forKey: "NXLibrary_CloudSourcesBinding") == nil, "N13: migration approved an unverified ROM folder")
        scopeOffline = false
        await migration.checkDriveScope()?.value
        let restarted = makeModel().cloudLibrary
        await restarted.scopeTask?.value
        check(migration.driveScope?.sources?.id == "Initial_ROMs_ID" && restarted.sourceArchive != nil
            && !restarted.sourcesNeedConfirmation, "N13: a second consent is needed to use the saved ROM path")
        precondition(failures.isEmpty, failures.joined(separator: "; "))
        print("Drive scope regressions passed: N3/N12/N13")
    }

    @MainActor static func main() async throws {
        let fixtureHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!, isDirectory: true)
            .resolvingSymlinksInPath().path
        precondition(URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path == fixtureHome
            && AppData.profile.home.resolvingSymlinksInPath().path == fixtureHome,
            "The settings probe cannot run outside its temporary home")
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let font = URL(fileURLWithPath: CommandLine.arguments[2])
        NSApplication.shared.setActivationPolicy(.prohibited)
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        let locale = AppLocale(language: .french, region: "FR")
        L10n.setContext(locale)
        let root = AppData.supportRoot.appendingPathComponent("settings-confirmation-probe", isDirectory: true)
        let settings = AppSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        settings.settings.soundVolume = 0
        SoundEffectService.shared.bind(to: settings)
        func makeModel() -> AppViewModel {
            AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: root)))
        }
        if ProcessInfo.processInfo.environment["OORT_CAPTURE_ATTENTIONS"] == "1" {
            try checkAttentions(vm: makeModel(), settings: settings, output: output, locale: locale, capturesOnly: true)
            return
        }
        let toolVM = makeModel()
        let tool = SettingsCloudLibrarySection(viewModel: toolVM, model: toolVM.cloudLibrary,
            settings: SettingsEditor(settings), advanced: .constant(true), onEdit: {}, onEditLibrary: {},
            onEditSources: {}, onActions: { _ in })
        let fm = FileManager.default
        let bin = root.appendingPathComponent("bin"), cellar = root.appendingPathComponent("Cellar")
        for folder in [bin, cellar] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        let stable = bin.appendingPathComponent("rclone")
        let v1 = cellar.appendingPathComponent("rclone-1"), v2 = cellar.appendingPathComponent("rclone-2")
        for version in [v1, v2] {
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: version)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: version.path)
        }
        try fm.createSymbolicLink(at: stable, withDestinationURL: v1)
        let defaults = AppData.preferences
        let keys = [CloudLibraryPreference.executableKey, CloudLibraryPreference.toolChoiceKey]
        let prior = keys.map { defaults.object(forKey: $0) }
        pickedRclone = stable
        tool.chooseTool()
        pickedRclone = nil
        try fm.removeItem(at: stable)
        try fm.removeItem(at: v1)
        try fm.createSymbolicLink(at: stable, withDestinationURL: v2)
        precondition(makeModel().cloudLibrary.resolvedDriveTool == stable, "explicit rclone must survive a versioned-link upgrade")
        for (key, value) in zip(keys, prior) { defaults.set(value, forKey: key) }
        print("Explicit rclone link survives upgrade")
        if ProcessInfo.processInfo.environment["OORT_SETTINGS_DRAFT_ONLY"] != "1" {
            try await checkDriveScope(settings: settings, makeModel: makeModel)
            if ProcessInfo.processInfo.environment["OORT_SCOPE_ONLY"] == "1" { return }
        }
        // Unfollow compares the displayed catalog revision with the on-disk revision.
        let repository = CatalogRepository(store: .init(directory: root))
        let catalog = try repository.load()
        let vm = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository)
        vm.applyCatalog(catalog) // This harness disables catalog application in the initializer.
        if ProcessInfo.processInfo.environment["OORT_ATTENTIONS_ONLY"] == "1" {
            try await checkNoticeHold()
            try checkAttentions(vm: vm, settings: settings, output: output, locale: locale)
            return
        }
        let router = AppRouter()
        router.openSettings(.look)
        let dialogHost = SettingsView(initialSection: .look, viewModel: vm, settings: settings, router: router, artwork: ArtworkStore())
        for (cloud, pin) in [(true, false), (false, true), (false, false)] {
            dialogHost.screenReportDialog(cloud: cloud, pin: pin)
            router.isPalettePresented = true
            precondition(router.isPalettePresented == !(cloud || pin), "Settings dialogs own the palette input")
        }
        try checkDraft(vm: vm, settings: settings, output: output, locale: locale)
        try checkNavigation(vm: vm, settings: settings, output: output, locale: locale, size: .init(width: 1440, height: 810), suffix: "fr")
        try checkNavigation(vm: vm, settings: settings, output: output, locale: locale, size: .init(width: 840, height: 810), suffix: "etroit-fr")
        try checkNavigation(vm: vm, settings: settings, output: output, locale: .init(language: .english, region: "US"),
                            size: .init(width: 1440, height: 810), suffix: "en")
        try checkGameSettings(vm: vm, settings: settings, output: output)
        try await checkHeroArt()
        if ProcessInfo.processInfo.environment["OORT_SETTINGS_DRAFT_ONLY"] == "1" { return }
        let model = vm.cloudLibrary
        model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: nil)
        let input = Input(viewModel: vm)

        func render<V: View>(_ name: String, _ view: V, height: CGFloat = 690, context: AppLocale? = nil) throws {
            let renderer = ImageRenderer(content: view
                .frame(width: 1140, height: height)
                .background(Color(red: 0.09, green: 0.13, blue: 0.20))
                .environment(\.nxAppLocale, context ?? locale)
                .environment(\.seleneButtonNames, .xbox)
                .environment(\.colorScheme, .dark)
                .environment(\.seleneCanvas, SeleneCanvas(size: .init(width: 1920, height: 1080)))
                .environment(\.seleneReduceMotion, true))
            let image = renderer.cgImage!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: output.appendingPathComponent("confirm-\(name)-\(context?.language.rawValue ?? "fr").png"))
        }

        for language in [locale, AppLocale(language: .english, region: "US")] {
            L10n.setContext(language)
            vm.alertMessage = DevelopmentStartup.libraryMoveNotice(removal: true, pendingBuild: true)
            input.presentLegacyNotice()
            try render("previous-library", input.settingsNoticeOverlay(vm.settingsNotice!), context: language)
            input.settingsNoticeInput(.cancel)
        }
        L10n.setContext(locale)

        func confirm(_ name: String, _ open: () -> Void, count: () -> Int) throws {
            // Cancel on the left in the dialogs that follow the agreed order, on the right in the others.
            func toAction() { input.settingsNoticeInput(vm.settingsNotice!.cancelFirst ? .navigateRight : .navigateLeft) }
            func toCancel() { input.settingsNoticeInput(vm.settingsNotice!.cancelFirst ? .navigateLeft : .navigateRight) }
            let before = count()
            open()
            let notice = vm.settingsNotice!
            precondition(vm.settingsNoticeFocus == notice.cancelIndex && count() == before, name)
            let frenchLine = [
                "cloud-disconnect": "connexion locale", "reference-unfollow": "aucun fichier ne sera supprimé",
                "network-vpn": "le réglage VPN", "network-default": "aux prochains lancements",
                "network-local-mode": "privilégieront le mode", "network-adapter": "réglage d’adaptateur",
            ][name]
            if let frenchLine { precondition(notice.message.contains(frenchLine), notice.message) }
            try render(name, input.settingsNoticeOverlay(notice))
            let action: GamepadAction = notice.cancelIndex == 0 ? .navigateRight : .navigateLeft
            let back: GamepadAction = notice.cancelIndex == 0 ? .navigateLeft : .navigateRight
            input.settingsNoticeInput(action)
            precondition(vm.settingsNoticeFocus != notice.cancelIndex && count() == before, name)
            input.settingsNoticeInput(back)
            input.settingsNoticeInput(.confirm) // A / Return on Cancel
            precondition(vm.settingsNotice == nil && count() == before, name)
            open()
            input.settingsNoticeInput(.cancel) // B / Esc / dismiss
            precondition(vm.settingsNotice == nil && count() == before, name)
            open()
            input.settingsNoticeInput(action)
            input.settingsNoticeInput(.confirm)
            input.settingsNoticeInput(.confirm)
            precondition(vm.settingsNotice == nil, name)
        }

        var cloudWrites = 0
        let cloudObserver = model.$preference.dropFirst().sink { _ in cloudWrites += 1 }
        let cloud = SettingsCloudLibrarySection(viewModel: vm, model: model, settings: SettingsEditor(settings),
            advanced: .constant(true), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
        settings.beginDraft(fields: SettingsDraftFields.fields(profiles: nil, languages: vm.availableLanguages, cloudEnabled: true))
        cloud.setEnabled(false)
        precondition(model.preference.enabled && cloudWrites == 0 && settings.editingSettings.launcherChoices.cloudActivation?.enabled == false)
        try settings.commitDraft()
        model.useSettingsActivation(settings.settings.launcherChoices.cloudActivation)
        precondition(!model.preference.enabled && cloudWrites == 1)
        cloud.setEnabled(true)
        precondition(!model.preference.enabled && cloudWrites == 1 && settings.editingSettings.launcherChoices.cloudActivation?.enabled == true)
        try settings.commitDraft()
        model.useSettingsActivation(settings.settings.launcherChoices.cloudActivation)
        precondition(model.preference.enabled && cloudWrites == 2)
        settings.endDraft()

        var closed = 0
        let follow = CloudReferenceDialog(viewModel: vm, onClose: { closed += 1 }).screenDraft("1-test-reference")
        try render("reference-follow", follow)
        follow.onClose()
        precondition(closed == 1 && model.preference.referenceFolder == nil && cloudWrites == 2)
        follow.save()
        precondition(closed == 2 && model.preference.referenceFolder == "1-test-reference" && cloudWrites == 3)
        try confirm("reference-unfollow", cloud.unfollow, count: { cloudWrites })
        let unfollowDeadline = ContinuousClock.now + .seconds(10)
        while model.isChangingConnection && ContinuousClock.now < unfollowDeadline {
            try await Task.sleep(for: .milliseconds(15))
        }
        precondition(!model.isChangingConnection && model.preference.referenceFolder == nil && cloudWrites == 4,
                     "Reference unfollow did not finish: \(vm.settingsNotice?.message ?? "no error reported")")

        let library = CloudSetupAssistant(viewModel: vm, model: model, entry: .library, onClose: { closed += 1 })
            .screenFolder("Autre bibliothèque")
        try render("cloud-library-folder", library, height: 1020)
        // The verified step's Cancel goes back to the folder list, not to activation.
        library.cancel()
        precondition(model.preference.root == "Games" && cloudWrites == 4)
        CloudSetupAssistant(viewModel: vm, model: model, entry: .library, onClose: { closed += 1 })
            .screenFolder("Autre bibliothèque").primary()
        precondition(model.preference.root == "Autre bibliothèque" && cloudWrites == 5 && closed == 3)
        precondition(vm.settingsNotice == nil && vm.librarySelection.query.filter == .cloud, "Finished setup opens the cloud shelf")
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
        precondition(kept == [false] && model.keptConnection == nil)

        // The client is there: Erase has its own role and keeping the ID and secret takes initial focus.
        func section() -> SettingsCloudLibrarySection {
            SettingsCloudLibrarySection(viewModel: vm, model: model, settings: SettingsEditor(settings),
                advanced: .constant(true), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
        }
        func settle() async { for _ in 0..<20 where model.isChangingConnection { await Task.yield() } }
        account = RcloneAccount(hasClient: true, isSignedIn: true)
        model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: nil)
        section().confirmDisconnect()
        let question = vm.settingsNotice!
        precondition(question.choices == ["Erase everything", "Cancel", "Disconnect and keep the ID and secret"]
                     && question.role(at: 0) == .destructive && question.cancelIndex == 1
                     && vm.settingsNoticeFocus == 2)
        precondition(question.choiceDetails["Disconnect and keep the ID and secret"]?.contains("Seule la connexion Google") == true
                     && question.choiceDetails["Erase everything"]?.contains("l’ID et le secret") == true)
        try render("cloud-disconnect-choice", input.settingsNoticeOverlay(question))
        input.settingsNoticeInput(.navigateLeft)
        precondition(vm.settingsNoticeFocus == question.cancelIndex)
        input.settingsNoticeInput(.confirm)
        precondition(kept == [false] && model.preference.remote == "fixture")
        section().confirmDisconnect()
        input.settingsNoticeInput(.cancel)
        precondition(kept == [false] && model.preference.remote == "fixture")
        section().confirmDisconnect()
        input.settingsNoticeInput(.confirm)
        await settle()
        precondition(kept == [false, true] && model.preference.remote == nil && model.keptConnection == "fixture")
        account = RcloneAccount(hasClient: true, isSignedIn: false)
        try render("cloud-kept-client", section().advancedRows.frame(width: 1060).padding(40), height: 700)
        try confirm("cloud-erase-kept", section().confirmEraseKept, count: { kept.count })
        await settle()
        precondition(kept == [false, true, false] && model.keptConnection == nil)
        account = RcloneAccount(hasClient: true, isSignedIn: true)
        model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: nil)
        section().confirmDisconnect()
        input.settingsNoticeInput(.navigateLeft)
        input.settingsNoticeInput(.navigateUp)
        precondition(vm.settingsNoticeFocus == 0)
        input.settingsNoticeInput(.confirm)
        await settle()
        precondition(kept.last == false && model.preference.remote == nil && model.keptConnection == nil)
        account = nil

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
        let drive = SettingsCloudLibrarySection(viewModel: upgraded, model: migration, settings: SettingsEditor(settings),
            advanced: .constant(false), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
        let saved = migration.preference
        precondition(migration.needsDriveToolChoice && migration.archive == nil)
        precondition(drive.referenceStatus == L10n.text("Connection status unavailable"))
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
                     && consent.message.contains(RcloneDownload.host) && consent.message.contains("ton propre Google Drive")
                     && consent.message.contains("rien n’est envoyé à Oort NX") && downloadCalls == 0)
        try render("drive-download", upgradeInput.settingsNoticeOverlay(consent))
        upgradeInput.settingsNoticeInput(.confirm)
        precondition(upgraded.settingsNotice == nil && migration.archive == nil && migration.preference == saved)
        let reopenedCloud = makeModel()
        reopenedCloud.offerDriveUpgrade()
        precondition(reopenedCloud.settingsNotice == nil && reopenedCloud.cloudLibrary.needsDriveToolChoice)

        upgraded.prepareDriveTool {}
        upgradeInput.settingsNoticeInput(.navigateRight)
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
        upgradeInput.settingsNoticeInput(.navigateRight)
        upgradeInput.settingsNoticeInput(.confirm)
        await migration.scopeTask?.value
        let unchangedQueue = try Data(contentsOf: queue)
        precondition(!migration.needsDriveToolChoice && migration.archive != nil && migration.preference == saved
                     && !migration.hasRestoredQueue && downloadCalls == 1 && unchangedQueue == entries,
                     "Approved tool did not bind the original library: \(String(describing: migration.connectionCheck?.failure))")
        let installed = AppData.supportRoot.appendingPathComponent("DriveTools/rclone-\(RcloneDownload.version)", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let managed = installed.appendingPathComponent("rclone")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: managed)
        try Data().write(to: installed.appendingPathComponent("oort-install"))
        migration.setReferenceFolder("1-test-reference")
        migration.chooseSourcesRoot("Autres sources")
        await migration.scopeTask?.value
        precondition(scopeTool == managed && migration.archive != nil && migration.referenceArchive != nil
                     && migration.driveScope?.reference == "1-test-reference"
                     && migration.driveScope?.sources?.id == "ROMs_ID" && migration.sourceArchive != nil)
        migration.configure(remote: "fixture", root: "Autre bibliothèque", enabled: true, sourcesRoot: "Autres sources")
        await migration.scopeTask?.value
        precondition(migration.driveScope?.library.id == "Other_ID"
                     && migration.sourcesNeedConfirmation && migration.sourceArchive == nil)
        migration.configure(remote: "fixture", root: "Games", enabled: false, sourcesRoot: nil)
        precondition(migration.canTrashDriveTool)
        try render("drive-settings", VStack(spacing: 8) { drive.advancedRows }, height: 570)
        drive.confirmTrashTool()
        let trash = upgraded.settingsNotice!
        precondition(upgraded.settingsNoticeFocus == trash.cancelIndex)
        try render("drive-trash", upgradeInput.settingsNoticeOverlay(trash))
        upgradeInput.settingsNoticeInput(.cancel)
        precondition(migration.canTrashDriveTool)
        migration.chooseExecutable(managed)
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
        let engine = SettingsEngineSection(viewModel: vm, setup: setup, settings: SettingsEditor(settings), onActions: { engineActions = $0 })
        func pressEngine(_ id: String, _ button: Int = 0) {
            engine.publishActions()
            engineActions.first { $0.id == id }!.press(button: button)
        }
        var engineWrites = 0
        let engineObserver = setup.$nxnativePath.dropFirst().sink { _ in engineWrites += 1 }
        settings.beginDraft(fields: SettingsDraftFields.fields(profiles: nil, languages: vm.availableLanguages))
        pressEngine("repo") // Native picker returned Cancel.
        precondition(engineWrites == 0)
        pickedEngine = engineFolder
        pressEngine("repo")
        pickedEngine = nil
        let enginePath = engineFolder.standardizedFileURL.path
        precondition(engineWrites == 0 && settings.editingSettings.launcherChoices.enginePath == enginePath)
        try settings.commitDraft()
        setup.useSavedEnginePath(settings.settings.launcherChoices.enginePath!)
        precondition(engineWrites == 1 && setup.nxnativePath == enginePath && vm.pinnedEngineCommit == pin)
        setup.compatibilityReport = .init(ok: false, checks: [])
        settings.beginDraft(fields: SettingsDraftFields.fields(profiles: nil, languages: vm.availableLanguages))
        var overrideWrites = 0
        let overrideObserver = settings.$settings.map(\.toolchainOverride).removeDuplicates().dropFirst()
            .sink { _ in overrideWrites += 1 }
        pressEngine("override")
        precondition(!setup.allowUntestedToolchain && overrideWrites == 0 && settings.editingSettings.toolchainOverride == true)
        try settings.commitDraft()
        precondition(setup.allowUntestedToolchain && overrideWrites == 1)
        pressEngine("override")
        precondition(setup.allowUntestedToolchain && overrideWrites == 1 && settings.editingSettings.toolchainOverride == false)
        try settings.commitDraft()
        precondition(!setup.allowUntestedToolchain && overrideWrites == 2)
        settings.endDraft()

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
        let editor = SettingsEditor(settings)
        settings.settings.multiplayerAdapter = "oldAdapter"
        settings.beginDraft(fields: SettingsDraftFields.fields(profiles: nil, languages: vm.availableLanguages))
        let network = SettingsAPISection(viewModel: vm, settings: editor, showsMultiplayer: true,
            supportsNextendo: true, advanced: .constant(true), onActions: { networkActions = $0 })
        network.publishActions()
        var networkWrites = 0
        let networkObserver = settings.$settings.dropFirst().sink { _ in networkWrites += 1 }
        func pressNetwork(_ id: String) { networkActions.first { $0.id == id }!.press(button: 0) }
        pressNetwork("multiplayerVPN")
        precondition(editor.settings.multiplayerVPN == .zeroTier && editor.settings.multiplayerAdapter == nil)
        pressNetwork("multiplayerDefault")
        pressNetwork("multiplayerLocalMode")
        networkActions.first { $0.id == "multiplayerAdapter" }!.cycle!(1)
        precondition(editor.settings.multiplayerDefault == .local && editor.settings.multiplayerLocalMode == .lan
            && editor.settings.multiplayerAdapter == "feth3971" && vm.settingsNotice == nil && networkWrites == 0)

        let client = NextendoClientDialog(settings: editor, onClose: { closed += 1 }).screenDraft("fixture-nextendo")
        try render("nextendo-client", client)
        client.onClose()
        precondition(closed == 6 && networkWrites == 0 && editor.settings.nextendoClientID == nil)
        client.save()
        precondition(closed == 7 && networkWrites == 0 && editor.settings.nextendoClientID == "fixture-nextendo")

        let page = SettingsView(initialSection: .multiplayer, viewModel: vm, settings: settings,
                                router: AppRouter(), artwork: ArtworkStore())
        page.resetSection(.multiplayer)
        precondition(networkWrites == 0 && SettingsReset.reset(.multiplayer, in: editor.settings) == editor.settings)
        try settings.commitDraft()
        precondition(networkWrites == 1 && SettingsReset.reset(.multiplayer, in: settings.settings) == settings.settings
            && settings.settings.nextendoClientID == "fixture-nextendo")
        withExtendedLifetime((cloudObserver, engineObserver, overrideObserver, switchObserver, networkObserver)) {}
        print("Settings: independent cloud and engine actions; multiplayer writes only once, at Save.")
    }

    @MainActor private static func checkDraft(vm: AppViewModel, settings: AppSettingsStore,
                                               output: URL, locale: AppLocale) throws {
        let backdrop = output.appendingPathComponent("wallpaper-fixture.png")
        let wallpaper = ImageRenderer(content: LinearGradient(colors: [.mint, .cyan, .orange],
            startPoint: .topLeading, endPoint: .bottomTrailing).frame(width: 1920, height: 1080))
        let bitmap = NSBitmapImageRep(cgImage: wallpaper.cgImage!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: backdrop)
        settings.settings.wallpaperID = try ThemeStore.shared.importWallpaper(from: backdrop)
        settings.settings.cloudSaves = .iCloudDrive
        settings.settings.cloudSavesPickedFolder = AppData.profile.home
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/nxnative Saves").path
        precondition(CloudSaves.displayPath(settings.settings.cloudSavesPickedFolder) == "iCloud Drive › nxnative Saves")
        let router = AppRouter(settings: settings)
        router.hasPendingSettings = { settings.draft?.hasChanges == true }
        router.openSettings(.cloudSaves)
        let art = ArtworkStore()
        let style = SeleneBackdropStyle(palette: ThemeStore.shared.palette,
            wallpaperURL: ThemeStore.shared.wallpaper(for: settings.settings.wallpaperID)?.url,
            sizing: .fill, animated: false, brightness: .bright)
        precondition(style.wallpaperURL != nil)
        let size = CGSize(width: 1920, height: 1080)
        let host = NSHostingView(rootView: SettingsView(initialSection: .cloudSaves, viewModel: vm,
                                                         settings: settings, router: router, artwork: art)
            .environment(\.nxAppLocale, locale)
            .environment(\.colorScheme, .dark)
            .environment(\.seleneButtonNames, .nintendo)
            .environment(\.seleneReduceMotion, true)
            .environment(\.seleneBackdropStyle, style)
            .seleneCanvasRoot(zoom: CGFloat(Double(ProcessInfo.processInfo.environment["OORT_ZOOM"] ?? "") ?? 1)))
        host.frame.size = size
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; settings.endDraft() }
        window.layoutIfNeeded()
        func settle() {
            for _ in 0..<8 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                host.layoutSubtreeIfNeeded()
            }
        }
        func capture(_ name: String) throws {
            settle()
            precondition(!window.isVisible)
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            host.cacheDisplay(in: host.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        func send(_ action: GamepadAction) {
            let input: Notification.Name = router.settingsDecision == nil ? .nxSettingsGamepadAction : .nxSettingsDecisionInput
            NotificationCenter.default.post(name: input, object: action)
            settle()
        }
        try capture("01-reglages-sauvegardes")
        let original = try Data(contentsOf: settings.fileURL)
        let section = SettingsCloudSavesSection(settings: SettingsEditor(settings), onActions: { _ in })
        section.stepChoice(1)
        settings.editingSettings.multiplayerDefault = .local
        settings.editingSettings.interfaceSounds = false
        let stillSaved = try Data(contentsOf: settings.fileURL)
        precondition(stillSaved == original && settings.settings.cloudSaves == .iCloudDrive)
        send(.tabPrevious)
        send(.tabNext)
        precondition(settings.draft?.changes.count == 3, "Moving between sections must keep the draft")
        send(.confirm)
        try capture("02-reglages-brouillon")
        router.back()
        precondition(router.settingsDecision == .leave && router.route == .settings(.cloudSaves))
        try capture("03-reglages-demande-enregistrement")
        send(.confirm) // default = Keep editing
        precondition(router.settingsDecision == nil && settings.draft?.hasChanges == true && router.route == .settings(.cloudSaves))
        send(.contextAction) // Y: save without leaving
        precondition(router.settingsDecision == .save)
        send(.navigateRight) // Save, last on the right
        send(.confirm)
        precondition(router.settingsDecision == nil && settings.draft?.hasChanges == false && router.route == .settings(.cloudSaves))
        precondition(AppSettingsStore(fileURL: settings.fileURL).settings.multiplayerDefault == .local)
        settings.editingSettings.multiplayerDefault = .online
        var quit = false
        precondition(router.requestSettingsDeparture { quit = true })
        settle()
        send(.navigateLeft)
        send(.confirm) // discard, then resume quit
        precondition(quit && settings.editingSettings.multiplayerDefault == .local)
        settings.settings.multiplayerDefault = .offline
        settings.settings.interfaceSounds = true
        print("Settings draft: live row, one exit dialog, default Keep editing, Y and verified save, discard before quit.")
    }

    @MainActor private static func checkNavigation(vm: AppViewModel, settings: AppSettingsStore,
            output: URL, locale: AppLocale, size: CGSize, suffix: String) throws {
        let previousLocale = L10n.context
        L10n.setContext(locale)
        defer { L10n.setContext(previousLocale) }
        let router = AppRouter(settings: settings)
        router.hasPendingSettings = { settings.draft?.hasChanges == true }
        router.openSettings(.cloudSaves) // Switch is the previous category.
        let style = SeleneBackdropStyle(palette: ThemeStore.shared.palette,
            wallpaperURL: ThemeStore.shared.wallpaper(for: settings.settings.wallpaperID)?.url,
            sizing: .fill, animated: false, brightness: .bright)
        precondition(style.wallpaperURL != nil)
        let sources = CatalogSourcesModel(
            repository: CatalogRepository(store: .init(directory: output.appendingPathComponent("catalog-\(suffix)"))),
            initialConfiguration: .init(integration: .steam)) { _ in }
        let host = NSHostingView(rootView: SettingsView(initialSection: .cloudSaves, viewModel: vm,
                settings: settings, router: router, artwork: ArtworkStore())
            .environmentObject(sources)
            .environmentObject(AppUpdater())
            .environment(\.nxAppLocale, locale)
            .environment(\.colorScheme, .dark)
            .environment(\.seleneButtonNames, .nintendo)
            .environment(\.seleneReduceMotion, true)
            .environment(\.seleneBackdropStyle, style)
            .seleneCanvasRoot(zoom: CGFloat(Double(ProcessInfo.processInfo.environment["OORT_ZOOM"] ?? "") ?? 1)))
        host.frame.size = size
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; settings.endDraft() }
        window.layoutIfNeeded()
        func settle() {
            for _ in 0..<8 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.016))
                host.layoutSubtreeIfNeeded()
            }
        }
        func send(_ action: GamepadAction) {
            NotificationCenter.default.post(name: .nxSettingsGamepadAction, object: action)
            settle()
        }
        func capture(_ name: String) throws {
            precondition(!window.isVisible)
            let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: image)
            try image.representation(using: .png, properties: [:])!
                .write(to: output.appendingPathComponent("\(name)-\(suffix).png"))
        }
        settle()
        settings.editingSettings.reduceMotion.toggle()
        send(.tabPrevious)
        send(.confirm)
        try capture("navigation-01-switch")
        // The four subjects are the page; Engine is the first and already in focus.
        send(.confirm)
        try capture("navigation-02-engine")
        send(.cancel)
        precondition(router.settingsDecision == nil)
        try capture("navigation-03-back")
        send(.cancel)
        precondition(router.settingsDecision == nil)
        // Every category, for a look at the whole: the sidebar returns to where it was.
        for index in 0..<SettingsPage.stops.count {
            send(.tabNext)
            settle()
            try capture(String(format: "page-%02d", index))
        }
        send(.cancel)
        precondition(router.settingsDecision == .leave && settings.draft?.hasChanges == true,
                     "Back must leave the subject, then the rows, then ask about the draft")
        print("Settings navigation: category → subject → restored row → sidebar → draft exit (\(suffix)).")
    }

    /// Spotlight shows a Switch game's art only when it recognises it as that game's.
    @MainActor private static func checkHeroArt() async throws {
        let app = AppData.profile.home.appendingPathComponent("Art Fixture.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("hero.png"))
        let game = PortedGame(name: "Art Fixture", url: app, platform: .macApp, sizeBytes: 0, modificationDate: .now,
                              bundleId: "test.oort.art", titleId: "010000000000F013")
        let art = SeleneHeroArt()
        await art.loadHero(game: game, current: { game.id }, metadata: nil, artwork: ArtworkStore(),
                           personalizations: .empty, settle: 0, keepsWithoutGame: true)
        precondition(art.image != nil && art.shows(game.id) && !art.shows(UUID()), "Art loaded under \(art.key) is not recognised")
        print("Game art: a Switch game's background is recognised as its own.")
    }

    @MainActor private static func checkGameSettings(vm: AppViewModel, settings: AppSettingsStore, output: URL) throws {
        let root = AppData.profile.home
        let app = root.appendingPathComponent("Navigation Fixture.app")
        let dm = app.appendingPathComponent("Contents/Resources/dm")
        let title = "010000000000F012"
        let envFolder = root.appendingPathComponent("Library/Application Support/nxnative/\(title)")
        let env = envFolder.appendingPathComponent("env.txt")
        let source = Data("DM_DYNAMIC_RESOLUTION=1\nNAVIGATION_FIXTURE_ONLY=read-only\n".utf8)
        try FileManager.default.createDirectory(at: dm, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: envFolder, withIntermediateDirectories: true)
        try source.write(to: env)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.oort.navigation", "DMSettings": []]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let metadata = """
        {"game":"Navigation Fixture","settings":[
          {"env":"DM_DYNAMIC_RESOLUTION","kind":"toggle","section":"Picture","label":"Dynamic resolution","default":"0","on":"1","off":"0"},
          {"env":"DM_SOUND_FIXTURE","kind":"toggle","section":"Sound","label":"Fixture effect","default":"0","on":"1","off":"0"}
        ]}
        """
        try Data(metadata.utf8).write(to: dm.appendingPathComponent("launcher.json"))
        let game = PortedGame(name: "Navigation Fixture", url: app, platform: .macApp, sizeBytes: 0,
                              modificationDate: .now, bundleId: "test.oort.navigation", titleId: title)
        precondition(vm.runtimeSettings.settingsSnapshot(for: game)?.fixed.contains("DM_DYNAMIC_RESOLUTION") == true)
        let wallpaper = ThemeStore.shared.wallpaper(for: settings.settings.wallpaperID)?.url
        precondition(wallpaper != nil)
        let style = SeleneBackdropStyle(palette: ThemeStore.shared.palette, wallpaperURL: wallpaper,
                                       sizing: .fill, animated: false, brightness: .bright)
        func withHost<V: View>(_ view: V, size: CGSize, locale: AppLocale,
                               check: (() -> Void, (String) throws -> String) throws -> Void) throws {
            let oldLocale = L10n.context
            L10n.setContext(locale)
            defer { L10n.setContext(oldLocale) }
            let host = NSHostingView(rootView: ZStack { SeleneBackdrop(still: true); view }
                .environment(\.nxAppLocale, locale)
                .environment(\.colorScheme, .dark)
                .environment(\.seleneButtonNames, .nintendo)
                .environment(\.seleneReduceMotion, true)
                .environment(\.seleneBackdropStyle, style)
                .seleneCanvasRoot(zoom: CGFloat(Double(ProcessInfo.processInfo.environment["OORT_ZOOM"] ?? "") ?? 1)))
            host.frame.size = size
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            window.layoutIfNeeded()
            func settle() {
                for _ in 0..<8 {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.016))
                    host.layoutSubtreeIfNeeded()
                }
            }
            settle()
            try check(settle) { name in
                precondition(!window.isVisible)
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!
                    .write(to: output.appendingPathComponent("\(name).png"))
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = [locale.language == .french ? "fr-FR" : "en-US"]
                try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
                return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
            }
        }
        func send(_ action: GamepadAction, settle: () -> Void) {
            NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: action)
            settle()
        }
        for (size, locale, name) in [(CGSize(width: 1440, height: 810), L10n.context, "fr"),
            (.init(width: 840, height: 810), L10n.context, "etroit-fr"),
            (.init(width: 1440, height: 810), AppLocale(language: .english, region: "US"), "en")] {
            vm.gameForSettingsSheet = game
            try withHost(GameOptionsView(viewModel: vm, game: game, origin: .details,
                           onClose: {}, onShowBuild: {}, onMove: {}), size: size, locale: locale) { settle, capture in
                _ = try capture("panneau-court-\(name)")
                for _ in 0..<12 { send(.navigateDown, settle: settle) } // All settings, the last row
                send(.confirm, settle: settle)
                send(.navigateDown, settle: settle) // Picture
                let image = try capture("jeu-image-\(name)")
                let fixedLabel = L10n.text("Set in env.txt")
                precondition(image.localizedCaseInsensitiveContains(fixedLabel), "Missing \(fixedLabel): \(image)")
                send(.confirm, settle: settle)
                send(.confirm, settle: settle) // The fixed row does not write.
                precondition(try! Data(contentsOf: env) == source)
                send(.cancel, settle: settle)
                send(.cancel, settle: settle)
                let quick = try capture("jeu-panneau-\(name)")
                precondition(quick.localizedCaseInsensitiveContains(L10n.text("All settings")), quick)
            }
            vm.gameForSettingsSheet = nil
        }
        let steam = CatalogGame(steam: .init(appID: 2147483000, name: "Steam Fixture"))
        vm.steamOptionsGame = steam
        try withHost(SteamOptionsView(viewModel: vm, game: steam, origin: .details, onClose: {}, onMove: {}),
                     size: .init(width: 1440, height: 810), locale: L10n.context) { settle, capture in
            send(.navigateDown, settle: settle)
            send(.confirm, settle: settle)
            let image = try capture("jeu-steam-fr")
            precondition(image.contains("Steam Fixture") && image.contains("Fiche et images"), image)
        }
        vm.steamOptionsGame = nil
        print("Game settings: quick panel ↔ full screen, fixed env.txt, Switch and Steam.")
    }
}
