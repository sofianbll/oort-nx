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
        if selection.remote == nil { return text("Not connected") }
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
            SettingsSubheading("Status")
            let provider = connected.flatMap { $0.type == "drive" ? nil : $0.type } ?? text("Google Drive")
            SeleneRow(selection.remote.map { "\(provider) · \($0)" } ?? text("Cloud service"),
                      subtitle: lastTest, verbatimTitle: true, verbatimSubtitle: true) {
                SeleneStatusDot(text: serviceStatus, color: connectionStatus.color)
            }
            if let progress = model.driveToolProgress {
                SeleneButtonRow("Downloading rclone…", id: "driveToolProgress", buttonTitle: "Cancel", action: cancelTool)
                SeleneProgressBar(progress: progress, color: CloudLibraryStatus.pending.color)
            } else if showToolRecovery {
                SeleneButtonRow(model.driveToolFailure?.messageKey ?? "Drive is waiting for rclone.", id: "driveToolRecovery",
                                buttonTitle: model.driveToolFailure == nil ? "Continue" : "Retry", action: recoverTool)
                    .disabled(!canPrepareTool)
            }
            if let failure = recoveryFailure {
                SeleneButtonRow(failure.messageKey, id: "cloudRecovery", buttonTitle: failure.action.titleKey, action: recover)
                    .disabled(!canRecover)
            }
            if selection.remote != nil {
                SeleneToggleRow("Enable cloud library", subtitle: "Cloud storage for ported apps and build caches, separate from saves.",
                                isOn: Binding(get: { stagedEnabled }, set: setEnabled))
                    .disabled(!editable)
            } else {
                SeleneButtonRow("Configure cloud library", buttonTitle: "Open", action: openSetup)
                    .disabled(!editable)
            }
            if selection.remote != nil, model.sourcesNeedConfirmation {
                SeleneButtonRow("Confirm the game files folder", id: "cloudConfirmSources", subtitle: selection.sourcesRoot, verbatimSubtitle: true,
                                buttonTitle: "Choose", action: confirmSourcesFolder)
                    .disabled(!editable)
            }

            if selection.remote != nil {
                SeleneButtonRow("Reference library", id: "cloudReferenceFolder",
                                subtitle: "Follow a shared Google Drive folder in read-only mode.",
                                buttonTitle: selection.referenceFolder == nil ? "Follow" : "Edit", action: onEditReference)
                    .disabled(!canFollow)
            }
            if let folder = selection.referenceFolder, selection.remote != nil {
                let failed = model.referenceCheck?.failure != nil
                SeleneRow(model.referenceCheck?.name ?? "\(text("Folder")) · …\(folder.suffix(6))", id: "cloudReferenceStatus",
                          subtitle: referenceStatus, verbatimTitle: true, verbatimSubtitle: true) {
                    SeleneStatusDot(text: text(failed ? "No access" : "Read only"), color: failed
                        ? CloudLibraryStatus.failed.color : model.referenceCheck == nil
                         ? CloudLibraryStatus.pending.color : model.referenceCheck?.count == 0 || model.referenceCheck?.incomplete == true
                         ? CloudLibraryStatus.unknown.color : CloudLibraryStatus.synchronized.color)
                    Button(text("Unfollow"), action: unfollow)
                        .buttonStyle(.plain)
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                        .disabled(!editable)
                        .help(text("Files on this Mac and in Drive stay in place."))
                }
            }

            SettingsSubheading("Import")
            SeleneButtonRow("Import games from the cloud", id: "cloudLibraryImport",
                            subtitle: model.importTask == nil ? nil : "Checking…", buttonTitle: "Import", action: importGames)
                .disabled(!canImport)
            if model.importTask != nil { SeleneProgressBar(progress: nil, color: CloudLibraryStatus.pending.color) }

            SettingsSubheading("Appearance")
            SeleneToggleRow("Icon next to Play", isOn: $settings.settings.showsCloudPlayIcon)
            SeleneToggleRow("Link in Details", isOn: $settings.settings.showsCloudDetailsLink)
            SeleneCycleRow("Tile badges", value: settings.settings.cloudTileBadges.titleKey, cycle: stepBadges)

            SettingsSubheading("Advanced")
            SeleneButtonRow("Folders and connection tools", buttonTitle: advanced ? "Hide" : "Show", action: toggleAdvanced)
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
                      model.chosenExecutable != nil, inspecting, selection.remote != nil, advanced]) {
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

    private var advancedRows: some View {
        Group {
            if selection.remote != nil {
                HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                    SeleneButtonRow("Library folder", id: "cloudLibraryFolder", subtitle: selection.storage,
                                    verbatimSubtitle: true, truncateSubtitleInMiddle: true, buttonTitle: "Edit", action: onEditLibrary)
                    SeleneButtonRow("Game files folder", id: "cloudSourcesRoot", subtitle: selection.sourcesStorage,
                                    verbatimSubtitle: true, truncateSubtitleInMiddle: true, buttonTitle: "Edit", action: onEditSources)
                }
                .disabled(!editable)
                SeleneButtonRow("Change Google credentials", id: "cloudLibraryConnect", buttonTitle: "Edit", action: onEdit)
                    .disabled(!editable)
            }
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

            if selection.remote != nil {
                SeleneButtonRow("Test connection", subtitle: "Lists the cloud folder without changing its files.", buttonTitle: "Test", action: test)
                    .disabled(!canTest)
                SeleneButtonRow("Disconnect", subtitle: "Removes only the local connection. Cloud files stay where they are.",
                                buttonTitle: "Disconnect", action: confirmDisconnect)
                    .disabled(!hasKnownConnection)
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
        var actions: [SettingsRowAction]
        if selection.remote != nil {
            actions = [
                .init(id: "cloudLibraryEnabled", title: "Enable cloud library", isEnabled: editable) { setEnabled(!stagedEnabled) },
                .init(id: "cloudReferenceFolder", title: "Reference library", rowID: "cloudReferenceFolder",
                      isEnabled: canFollow, activate: onEditReference),
                .init(id: "cloudLibraryImport", title: "Import games from the cloud", isEnabled: canImport, activate: importGames),
            ]
            if selection.referenceFolder != nil {
                actions.insert(.init(id: "cloudReferenceUnfollow", title: "Unfollow", rowID: "cloudReferenceStatus",
                                     isEnabled: editable, activate: unfollow),
                               at: actions.count - 1)
            }
            if model.sourcesNeedConfirmation {
                actions.insert(.init(id: "cloudConfirmSources", title: "Confirm the game files folder",
                                     isEnabled: editable, activate: confirmSourcesFolder), at: 1)
            }
            if let failure = recoveryFailure {
                actions.insert(.init(id: "cloudRecovery", title: failure.messageKey, isEnabled: canRecover, activate: recover), at: 0)
            }
        } else {
            actions = [.init(id: "cloudLibrarySetup", title: "Configure cloud library", isEnabled: editable, activate: openSetup)]
        }
        if model.driveToolProgress != nil {
            actions.insert(.init(id: "driveToolProgress", title: "Downloading rclone…", activate: cancelTool), at: 0)
        } else if showToolRecovery {
            actions.insert(.init(id: "driveToolRecovery", title: "Drive is waiting for rclone.", isEnabled: canPrepareTool,
                                 activate: recoverTool), at: 0)
        }
        actions += [
            .init(id: "showsCloudPlayIcon", title: "Icon next to Play") { settings.settings.showsCloudPlayIcon.toggle() },
            .init(id: "showsCloudDetailsLink", title: "Link in Details") { settings.settings.showsCloudDetailsLink.toggle() },
            .value("cloudTileBadges", "Tile badges", cycle: stepBadges),
            .init(id: "cloudLibraryAdvanced", title: "Folders and connection tools", activate: toggleAdvanced),
        ]
        if advanced {
            if selection.remote != nil {
                actions.append(.init(id: "cloudLibraryFolder", title: "Library folder", rowID: "cloudLibraryFolder",
                                     isEnabled: editable, activate: onEditLibrary))
                actions.append(.init(id: "cloudSourcesRoot", title: "Game files folder", rowID: "cloudSourcesRoot",
                                     isEnabled: editable, activate: onEditSources))
                actions.append(.init(id: "cloudLibraryConnect", title: "Change Google credentials", rowID: "cloudLibraryConnect",
                                     isEnabled: editable, activate: onEdit))
            }
            let automatic = model.chosenExecutable != nil
            actions.append(.init(id: "cloudLibraryTool", title: "rclone", isEnabled: editable,
                                 secondary: automatic ? ("Automatic", useAutomaticTool) : ("Refresh", refresh),
                                 additionalButtons: automatic ? [refresh] : [], activate: chooseTool))
            if model.canTrashDriveTool {
                actions.append(.init(id: "driveToolOwned", title: "Oort NX’s copy of rclone",
                                     isEnabled: canPrepareTool && !selection.enabled, activate: confirmTrashTool))
            }
            if selection.remote != nil {
                actions.append(.init(id: "cloudLibraryTest", title: "Test connection", isEnabled: canTest, activate: test))
                actions.append(.init(id: "cloudLibraryDisconnect", title: "Disconnect", isEnabled: hasKnownConnection, activate: confirmDisconnect))
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
            viewModel.confirmSetting(text("Game files folder"),
                message: L10n.format("Confirm “%@” as the game files folder for this library?", [before.sourcesRoot]),
                action: "Keep this folder", apply: keep)
            return
        }
        viewModel.confirmSetting(text("Game files folder"),
            message: L10n.format("Keep “%@” for game files in this library, or use its default folder?", [before.sourcesRoot]),
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
                viewModel.showSettingsNotice(title: text("Game files folder"), message: text(failure.messageKey))
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = tool?.deletingLastPathComponent()
        panel.message = text("Choose the rclone executable or use the detected one.")
        guard panel.runModal() == .OK, let chosen = panel.url, editable else { return }
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
