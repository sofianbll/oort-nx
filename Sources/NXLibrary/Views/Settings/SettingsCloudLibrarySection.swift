import AppKit
import ArcanePorting
import NXLibraryCore
import SwiftUI

/// Porting → Cloud library: a locally recognised connection is not a network check.
struct SettingsCloudLibrarySection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: CloudLibraryModel
    @ObservedObject var settings: SettingsEditor
    @Binding var advanced: Bool
    let onEdit: () -> Void
    let onEditLibrary: () -> Void
    let onEditSources: () -> Void
    var onEditReference: () -> Void = {}
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.seleneFocusedRowID) private var focusedRowID
    @Environment(\.seleneFocusedButton) private var focusedButton
    @Environment(\.passiveSettingsArrival) private var passiveArrival
    @State private var tool: URL?
    @State private var version: String?
    @State private var remotes: [RcloneRemote]?
    @State private var issue: RcloneConfiguration.Failure?
    @State private var inspecting = true
    @State private var inspection = 0
    @State private var testTask: Task<Void, Never>?

    private struct Inspection: Equatable {
        let enabled: Bool
        let chosen: URL?
        let changing: Bool
        let resolved: URL?
        let attempt: Int
    }

    private var selection: CloudLibraryPreference { model.preference }
    private var hasAccount: Bool { selection.remote != nil }
    private var stagedEnabled: Bool {
        let proposal = settings.settings.launcherChoices.cloudActivation
        return proposal == settings.store.settings.launcherChoices.cloudActivation ? selection.enabled : (proposal?.enabled ?? selection.enabled)
    }
    private var connection: CloudLibraryPreference.Connection { selection.connection(in: remotes) }
    private var connected: RcloneRemote? {
        if case .connected(let remote) = connection { return remote }
        return nil
    }
    private var editable: Bool { viewModel.canConfigureCloudLibrary && testTask == nil }
    private var canPrepareTool: Bool { viewModel.canStartLibraryMove && testTask == nil }
    private var showToolRecovery: Bool {
        model.driveToolFailure != nil || (selection.enabled && selection.remote != nil && model.needsDriveTool)
    }
    private var hasKnownConnection: Bool { editable && !inspecting && connected != nil }
    private var canTest: Bool { hasKnownConnection && model.canCheckDriveScope }
    private var canImport: Bool { editable && model.archive != nil && model.importTask == nil && !viewModel.isScanningLibrary }
    private var recoveryFailure: CloudLibraryFailure? {
        if let result = model.connectionCheck { return result.failure }
        return model.checkFailure
    }
    private var canRecover: Bool {
        guard recoveryFailure?.action == .retry else { return editable }
        return model.connectionCheck?.scopeCheck == true ? editable && model.canCheckDriveScope : canImport
    }
    private var focusedToolButton: Int? { focusedRowID == "rclone" ? focusedButton : nil }
    private var canFollow: Bool { editable && model.archive != nil && (connected == nil || connected?.type == "drive") }

    private var referenceStatus: String {
        guard let result = model.referenceCheck else {
            if !selection.enabled { return text("The cloud library is turned off.") }
            if model.needsDriveTool || model.connectionCheck?.failure != nil { return text("Connection status unavailable") }
            return text("Checking…")
        }
        if let failure = result.failure {
            if failure == .folderMissing {
                return text("No access. Share this folder as Viewer with the Google account connected here.")
            }
            return text(failure.messageKey)
        }
        if result.incomplete { return text(CloudLibraryFailure.incomplete.messageKey) }
        if result.count == 0 { return text("No games found. The reference is not verified.") }
        return L10n.format("Games: %@ · Checked %@", [
            (result.count ?? 0).formatted(.number.locale(localization.formatLocale)),
            result.date.formatted(.dateTime.month().day().hour().minute().locale(localization.formatLocale)),
        ], context: localization)
    }

    private var serviceStatus: String {
        if testTask != nil { return text("Checking…") }
        if selection.remote == nil { return text("Not connected yet") }
        guard let result = model.connectionCheck else { return text("Connection not tested") }
        if result.failure != nil { return text(result.failure == .offline ? "Offline" : "Connection status unavailable") }
        return text("Connection OK")
    }

    private var lastTest: String? {
        model.lastCompleteCheck.map {
            L10n.format("Last verified: %@", [$0.formatted(.dateTime.year().month().day().hour().minute()
                .locale(localization.formatLocale))], context: localization)
        }
    }

    private var connectionStatus: CloudLibraryStatus {
        if testTask != nil { return .pending }
        if recoveryFailure != nil { return .failed }
        return model.connectionCheck == nil || selection.remote == nil ? .unknown : .synchronized
    }

    private var toolSubtitle: String {
        if let tool {
            let path = (tool.path as NSString).abbreviatingWithTildeInPath
            return version.map { "\($0) · \(path)" } ?? path
        }
        return text(inspecting ? "Checking…" : "Choose your own rclone or let Oort NX download it when you turn on Drive.")
    }

    var body: some View {
        OortSettingsGroup {
            SettingsSubheading("Your account")
            accountRows
            SettingsSubheading("Your folders")
            folderRows
            SettingsSubheading("On this Mac")
            SeleneToggleRow("Enable cloud library", subtitle: "Cloud storage for ported apps and build caches, separate from saves.",
                            isOn: Binding(get: { stagedEnabled }, set: setEnabled))
                .disabled(!editable || !hasAccount)
                .opacity(hasAccount ? 1 : SeleneTokens.Alpha.muted)
            SeleneButtonRow("Import games from the cloud", id: "cloudLibraryImport",
                            subtitle: model.importTask == nil ? nil : "Checking…", buttonTitle: "Import", action: importGames)
                .disabled(!canImport)
            if model.importTask != nil { OortMeter(share: nil, fill: CloudLibraryStatus.pending.color) }
            SeleneToggleRow("Icon next to Play", isOn: $settings.settings.showsCloudPlayIcon)
            SeleneToggleRow("Link in Details", isOn: $settings.settings.showsCloudDetailsLink)
            SeleneCycleRow("Tile badges", value: settings.settings.cloudTileBadges.titleKey, cycle: stepBadges)

            SettingsSubheading("Advanced")
            SeleneButtonRow("Tool, test and reference library", id: "cloudLibraryAdvanced",
                            buttonTitle: advanced ? "Hide" : "Show", action: toggleAdvanced)
                .accessibilityValue(text(advanced ? "Expanded" : "Collapsed"))
            if advanced { advancedRows }
        }
        .task(id: Inspection(enabled: !passiveArrival || advanced, chosen: model.chosenExecutable,
                             changing: model.isChangingConnection, resolved: model.resolvedDriveTool, attempt: inspection)) {
            guard !passiveArrival || advanced else { inspecting = false; return }
            if !model.isChangingConnection { await inspect() }
        }
        .onAppear(perform: publishActions)
        .onChange(of: [editable, canTest, canImport, canFollow, selection.referenceFolder != nil,
                      model.chosenExecutable != nil, inspecting, hasAccount, advanced]) {
            publishActions()
        }
        .onChange(of: recoveryFailure) { publishActions() }
        .onChange(of: model.sourcesNeedConfirmation) { publishActions() }
        .onChange(of: [model.connectionCheck?.scopeCheck == true, canRecover, hasKnownConnection]) { publishActions() }
        .onChange(of: model.driveToolProgress != nil) { publishActions() }
        .onChange(of: model.driveToolFailure) { publishActions() }
        .onChange(of: model.needsDriveToolChoice) { publishActions() }
        .onDisappear { testTask?.cancel() }
    }

    @ViewBuilder private var accountRows: some View {
        let provider = connected.flatMap { $0.type == "drive" ? nil : $0.type } ?? text("Google Drive")
        // The usual connection's own name says nothing to a player; a second one's does.
        SeleneRow(selection.remote.flatMap { $0 == "gdrive" ? nil : "\(provider) · \($0)" } ?? provider, id: "cloudLibraryAccount",
                  subtitle: hasAccount ? lastTest : text("You need a Google client ID. Oort helps you add it."),
                  verbatimTitle: true, verbatimSubtitle: true) {
            SeleneStatusDot(text: serviceStatus, color: connectionStatus.color)
            button(hasAccount ? "Change this" : "Sign in", action: hasAccount ? onEdit : openSetup).disabled(!editable)
        }
        if let progress = model.driveToolProgress {
            SeleneButtonRow("Preparing the connection…", id: "driveToolProgress", buttonTitle: "Cancel", action: cancelTool)
            OortMeter(share: progress, fill: CloudLibraryStatus.pending.color)
        } else if showToolRecovery {
            SeleneButtonRow(model.driveToolFailure?.messageKey ?? "The connection to Drive is not ready on this Mac yet.", id: "driveToolRecovery",
                            buttonTitle: model.driveToolFailure == nil ? "Continue" : "Retry", action: recoverTool)
                .disabled(!canPrepareTool)
        }
        if let failure = recoveryFailure {
            SeleneButtonRow(failure.messageKey, id: "cloudRecovery", buttonTitle: failure.action.titleKey, action: recover)
                .disabled(!canRecover)
        }
        if hasAccount {
            SeleneButtonRow("Disconnect", subtitle: "Removes only the local connection. Cloud files stay where they are.",
                            buttonTitle: "Disconnect", action: confirmDisconnect)
                .disabled(!hasKnownConnection)
        }
    }

    /// Both folders are there before the account is: the page never hides what the connection is for.
    @ViewBuilder private var folderRows: some View {
        folderRow("Compiled games", id: "cloudLibraryFolder", about: "What Oort uploads and downloads.",
                  path: selection.root, games: knownGames(model.lastKnown.personalApps), action: onEditLibrary)
        folderRow("Your ROMs", id: "cloudSourcesRoot", about: "The files you bring. Oort never changes them.",
                  path: selection.sourcesRootOverride ?? text("In your compiled games folder"), games: knownGames(model.lastKnown.personalFiles), action: onEditSources)
        if hasAccount, model.sourcesNeedConfirmation {
            SeleneButtonRow("Confirm your ROM folder", id: "cloudConfirmSources", subtitle: selection.sourcesRoot, verbatimSubtitle: true,
                            buttonTitle: "Choose", action: confirmSourcesFolder)
                .disabled(!editable)
        }
    }

    private func folderRow(_ title: String, id: String, about: String, path: String, games: Int?,
                           action: @escaping () -> Void) -> some View {
        SeleneRow(title, id: id, subtitle: "\(text(about))\n\(hasAccount ? path : text("Connect your account first."))",
                  verbatimSubtitle: true) {
            if hasAccount, let games { SeleneValueChip(text: L10n.count("%lld games", games, context: localization)) }
            button("Change this", action: action)
                .accessibilityLabel("\(text("Change this")) · \(text(title))")
        }
        .disabled(!editable || !hasAccount)
        .opacity(hasAccount ? 1 : SeleneTokens.Alpha.muted)
    }

    private func knownGames(_ ids: Set<UUID>) -> Int? { model.lastCompleteCheck == nil ? nil : ids.count }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(text(title), action: action)
            .buttonStyle(OortPressStyle())
            .seleneFont(.text, .semibold)
            .foregroundColor(SeleneTheme.glyph)
    }

    private var advancedRows: some View {
        Group {
            SeleneRow("rclone", subtitle: toolSubtitle, verbatimSubtitle: true) {
                SelenePillButton(title: "Choose…", minWidth: 96, height: 34, horizontalPadding: 14,
                                 focused: focusedToolButton == 0, enabled: editable, action: chooseTool)
                if model.chosenExecutable != nil {
                    SelenePillButton(title: "Automatic", minWidth: 96, height: 34, horizontalPadding: 14,
                                     focused: focusedToolButton == 1, enabled: editable, action: useAutomaticTool)
                }
                SelenePillButton(title: "Refresh", minWidth: 96, height: 34, horizontalPadding: 14,
                                 focused: focusedToolButton == (model.chosenExecutable == nil ? 1 : 2),
                                 enabled: editable && !inspecting, action: refresh)
            }
            if model.canTrashDriveTool {
                SeleneButtonRow("Oort NX’s copy of rclone", id: "driveToolOwned",
                                subtitle: "Only Oort NX’s download is moved to the Trash; other copies stay in place.",
                                buttonTitle: "Move to Trash", action: confirmTrashTool)
                    .disabled(!canPrepareTool || selection.enabled)
            }

            if let issue {
                Text(text(issue.key)).seleneFont(.text).foregroundColor(SeleneTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasAccount {
                SeleneButtonRow("Test connection", subtitle: "Lists the cloud folder without changing its files.", buttonTitle: "Test", action: test)
                    .disabled(!canTest)
                SeleneButtonRow("Reference library", id: "cloudReferenceFolder",
                                subtitle: "Follow a shared Google Drive folder in read-only mode.",
                                buttonTitle: selection.referenceFolder == nil ? "Follow" : "Edit", action: onEditReference)
                    .disabled(!canFollow)
            }
            if let folder = selection.referenceFolder, hasAccount {
                let failed = model.referenceCheck?.failure != nil
                SeleneRow(model.referenceCheck?.name ?? "\(text("Folder")) · …\(folder.suffix(6))", id: "cloudReferenceStatus",
                          subtitle: referenceStatus, verbatimTitle: true, verbatimSubtitle: true) {
                    SeleneStatusDot(text: text(failed ? "No access" : "Read only"), color: failed
                        ? CloudLibraryStatus.failed.color : model.referenceCheck == nil
                         ? CloudLibraryStatus.pending.color : model.referenceCheck?.count == 0 || model.referenceCheck?.incomplete == true
                         ? CloudLibraryStatus.unknown.color : CloudLibraryStatus.synchronized.color)
                    button("Unfollow", action: unfollow)
                        .disabled(!editable)
                        .help(text("Files on this Mac and in Drive stay in place."))
                }
            }
        }
    }

    private func toggleAdvanced() {
        withAnimation(Motion.focus(reduceMotion)) { advanced.toggle() }
    }

    private func stepBadges(_ step: Int) {
        settings.settings.cloudTileBadges = settings.settings.cloudTileBadges.stepped(step)
    }

    private func publishActions() {
        var actions: [SettingsRowAction] = [
            hasAccount ? .init(id: "cloudLibraryConnect", title: "Change Google credentials", rowID: "cloudLibraryAccount",
                               isEnabled: editable, activate: onEdit)
                : .init(id: "cloudLibrarySetup", title: "Configure cloud library", rowID: "cloudLibraryAccount",
                        isEnabled: editable, activate: openSetup),
        ]
        if model.driveToolProgress != nil {
            actions.append(.init(id: "driveToolProgress", title: "Preparing the connection…", activate: cancelTool))
        } else if showToolRecovery {
            actions.append(.init(id: "driveToolRecovery", title: "The connection to Drive is not ready on this Mac yet.", isEnabled: canPrepareTool,
                                 activate: recoverTool))
        }
        if let failure = recoveryFailure {
            actions.append(.init(id: "cloudRecovery", title: failure.messageKey, isEnabled: canRecover, activate: recover))
        }
        if hasAccount {
            actions.append(.init(id: "cloudLibraryDisconnect", title: "Disconnect", isEnabled: hasKnownConnection, activate: confirmDisconnect))
        }
        actions += [
            .init(id: "cloudLibraryFolder", title: "Compiled games", rowID: "cloudLibraryFolder",
                  isEnabled: editable && hasAccount, activate: onEditLibrary),
            .init(id: "cloudSourcesRoot", title: "Your ROMs", rowID: "cloudSourcesRoot",
                  isEnabled: editable && hasAccount, activate: onEditSources),
        ]
        if hasAccount, model.sourcesNeedConfirmation {
            actions.append(.init(id: "cloudConfirmSources", title: "Confirm your ROM folder",
                                 isEnabled: editable, activate: confirmSourcesFolder))
        }
        actions += [
            .init(id: "cloudLibraryEnabled", title: "Enable cloud library", isEnabled: editable && hasAccount) { setEnabled(!stagedEnabled) },
            .init(id: "cloudLibraryImport", title: "Import games from the cloud", isEnabled: canImport, activate: importGames),
            .init(id: "showsCloudPlayIcon", title: "Icon next to Play") { settings.settings.showsCloudPlayIcon.toggle() },
            .init(id: "showsCloudDetailsLink", title: "Link in Details") { settings.settings.showsCloudDetailsLink.toggle() },
            .value("cloudTileBadges", "Tile badges", cycle: stepBadges),
            .init(id: "cloudLibraryAdvanced", title: "Tool, test and reference library", rowID: "cloudLibraryAdvanced", activate: toggleAdvanced),
        ]
        if advanced {
            let automatic = model.chosenExecutable != nil
            actions.append(.init(id: "cloudLibraryTool", title: "rclone", isEnabled: editable,
                                 secondary: automatic ? ("Automatic", useAutomaticTool) : ("Refresh", refresh),
                                 additionalButtons: automatic ? [refresh] : [], activate: chooseTool))
            if model.canTrashDriveTool {
                actions.append(.init(id: "driveToolOwned", title: "Oort NX’s copy of rclone",
                                     isEnabled: canPrepareTool && !selection.enabled, activate: confirmTrashTool))
            }
            if hasAccount {
                actions.append(.init(id: "cloudLibraryTest", title: "Test connection", isEnabled: canTest, activate: test))
                actions.append(.init(id: "cloudReferenceFolder", title: "Reference library", rowID: "cloudReferenceFolder",
                                     isEnabled: canFollow, activate: onEditReference))
                if selection.referenceFolder != nil {
                    actions.append(.init(id: "cloudReferenceUnfollow", title: "Unfollow", rowID: "cloudReferenceStatus",
                                         isEnabled: editable, activate: unfollow))
                }
            }
        }
        onActions(actions)
    }

    private func setEnabled(_ enabled: Bool) {
        let before = selection
        guard editable, before.remote != nil, enabled != stagedEnabled else { return }
        if enabled == before.enabled {
            settings.settings.launcherChoices.cloudActivation = settings.store.settings.launcherChoices.cloudActivation
            return
        }
        if enabled && model.needsDriveTool {
            // Choosing/installing a connection tool is still an explicit action; it cannot open access through Save.
            viewModel.prepareDriveTool {
                guard editable, selection == before else { return }
                model.acceptDriveTool()
                if !model.needsDriveTool { settings.settings.launcherChoices.cloudActivation = model.activationChoice(enabled: true) }
            }
            return
        }
        settings.settings.launcherChoices.cloudActivation = model.activationChoice(enabled: enabled)
    }

    private func openSetup() { viewModel.prepareDriveTool(then: onEdit) }

    private func recoverTool() {
        let before = selection
        viewModel.prepareDriveTool {
            guard selection == before else { return }
            if before.remote == nil { onEdit() }
            else if !before.enabled {
                model.configure(remote: before.remote, root: before.root, enabled: true, sourcesRoot: before.sourcesRootOverride)
            }
        }
    }

    private func cancelTool() { model.driveToolTask?.cancel() }

    private func confirmTrashTool() {
        guard !selection.enabled, canPrepareTool else { return }
        viewModel.confirmSetting(text("Oort NX’s copy of rclone"),
            message: text("Only Oort NX’s download is moved to the Trash; other copies stay in place."),
            action: "Move to Trash") {
            viewModel.trashDriveTool()
            inspection += 1
        }
    }

    private func importGames() {
        guard canImport else { return }
        viewModel.importCloudGames(manually: true)
    }

    private func confirmSourcesFolder() {
        let before = selection
        guard editable, model.sourcesNeedConfirmation else { return }
        let keep = { selectSourcesFolder(before.sourcesRootOverride, from: before) }
        if before.sourcesRootOverride == nil {
            viewModel.confirmSetting(text("Your ROMs"),
                message: L10n.format("Are your ROMs in “%@”?", [before.sourcesRoot]),
                action: "Keep this folder", apply: keep)
            return
        }
        viewModel.confirmSetting(text("Your ROMs"),
            message: L10n.format("Are your ROMs in “%@”, or in your compiled games folder?", [before.sourcesRoot]),
            choices: [("Keep this folder", keep), ("Use default", { selectSourcesFolder(nil, from: before) })])
    }

    private func selectSourcesFolder(_ root: String?, from before: CloudLibraryPreference) {
        guard selection == before else { return }
        guard let reference = before.referenceFolder else { model.chooseSourcesRoot(root); return }
        guard let remote = before.remote, let tool = model.resolvedDriveTool else { return }
        let folder = root ?? CloudLibraryPreference(storage: before.storage, enabled: before.enabled).sourcesRoot
        let service = CloudDriveFolders(remote: remote, executable: tool, reference: reference)
        Task { @MainActor in
            do {
                try await service.verifyPersonalFolder(folder, allowMissing: true)
                guard editable, selection == before else { return }
                model.chooseSourcesRoot(root)
            } catch is CancellationError {
            } catch {
                guard selection == before else { return }
                let failure = (error as? CloudLibraryFailure) ?? .unavailable
                viewModel.showSettingsNotice(title: text("Your ROMs"), message: text(failure.messageKey))
            }
        }
    }

    private func unfollow() {
        guard editable, let reference = selection.referenceFolder else { return }
        viewModel.confirmSetting(text("Reference library"),
            message: text("Games available only from this reference will leave your library, but no files will be deleted."),
            action: "Unfollow") {
            guard editable, selection.referenceFolder == reference else { return }
            viewModel.followCloudReference(nil)
        }
    }

    private func recover() {
        guard canRecover, let failure = recoveryFailure else { return }
        let result = model.connectionCheck
        viewModel.recoverCloud(failure.action, sourceFolder: result?.onSources ?? model.checkFailureOnSources) {
            if result?.scopeCheck == true { checkScope(explicit: result?.explicit == true) }
            else { viewModel.retryCloudCheck() }
        }
    }

    private func chooseTool() {
        guard editable else { return }
        OortFilePickerPresentation.open(.tool, title: "rclone", message: text("Choose the rclone executable or use the detected one."),
                                        startingAt: tool?.deletingLastPathComponent()) { urls in
            // A package manager installs the tool as a link: the file it leads to is the one kept.
            if let chosen = urls.first { use(chosen.resolvingSymlinksInPath()) }
        }
    }

    private func use(_ chosen: URL) {
        guard editable else { return }
        guard RcloneStorageBackend.isExecutable(chosen) else { issue = .tool; return }
        guard model.canChooseDriveTool(chosen) else { issue = .portableConfiguration; return }
        model.chooseExecutable(chosen)
    }

    private func useAutomaticTool() {
        guard editable else { return }
        model.chooseExecutable(nil)
    }

    private func refresh() {
        guard editable, !inspecting else { return }
        inspection += 1
    }

    private func inspect() async {
        inspecting = true
        version = nil; remotes = nil; issue = nil
        defer { if !Task.isCancelled { inspecting = false } }
        do {
            let found = model.resolvedDriveTool
            try Task.checkCancellation()
            tool = found
            guard let found else { return }
            let config = RcloneConfiguration(executable: found)
            let detectedVersion = try await config.version()
            try Task.checkCancellation()
            version = detectedVersion
            let listed = try await config.remotes()
            try Task.checkCancellation()
            remotes = listed
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { issue = (error as? RcloneConfiguration.Failure) ?? .configuration }
        }
    }

    private func test() {
        guard canTest else { return }
        checkScope(explicit: true)
    }

    private func checkScope(explicit: Bool) {
        guard let task = model.checkDriveScope(explicit: explicit) else { return }
        testTask = Task { @MainActor in
            defer { testTask = nil }
            await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        }
    }

    private func confirmDisconnect() {
        guard hasKnownConnection, let tool, let name = connected?.name else { return }
        viewModel.confirmSetting(text("Disconnect cloud service?"),
            message: "\(name)\n\n\(text("Removes only the local connection. Cloud files stay where they are."))",
            action: "Disconnect") {
                guard hasKnownConnection, model.preference.remote == name else { return }
                model.isChangingConnection = true
                Task { @MainActor in
                    var disconnected = false
                    defer {
                        model.isChangingConnection = false
                        if disconnected && model.canTrashDriveTool { confirmTrashTool() }
                    }
                    model.keepFolders()
                    do {
                        try await RcloneConfiguration(executable: tool).disconnect(name)
                        model.configure(remote: nil, root: selection.root, enabled: false, sourcesRoot: selection.sourcesRootOverride)
                        disconnected = true
                    } catch {
                        viewModel.showSettingsNotice(title: text("Disconnect"),
                                                     message: text(RcloneConfiguration.Failure.disconnect.key))
                    }
                }
            }
    }

    private func text(_ key: String) -> String { L10n.text(key, context: localization) }
}
