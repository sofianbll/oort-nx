import AppKit
import NXLibraryCore
import ArcanePorting
import SwiftUI

struct CloudSetupAssistant: View {
    enum Entry { case account, library, sources, credentials }
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: CloudLibraryModel
    let entry: Entry
    let onClose: () -> Void

    init(viewModel: AppViewModel, model: CloudLibraryModel, entry: Entry = .account, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.model = model
        self.entry = entry
        self.onClose = onClose
        _editingCredentials = State(initialValue: entry == .credentials)
        if let remote = model.preference.remote, entry == .sources || entry == .library {
            var draft = CloudSetupAssistantDraft()
            draft.chooseAccount(remote)
            draft.browse(model.preference.root.split(separator: "/").joined(separator: "/"))
            _draft = State(initialValue: draft)
            if entry == .sources {
                _selectingSources = State(initialValue: true)
                _sourcesPath = State(initialValue: model.preference.sourcesRoot.split(separator: "/").joined(separator: "/"))
            }
        }
    }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @State var focus = CloudSetupAssistantFocus()
    @State var keyMonitor: Any?
    @State private var draft = CloudSetupAssistantDraft()
    @State private var tool: URL?
    @State private var version: String?
    @State private var remotes: [RcloneRemote]?
    @State private var advanced = false
    @State private var editingCredentials = false
    @State private var client = ""
    @State private var secret = ""
    @State private var replacement: CloudDriveCredentialChange?
    @State private var onboarding = false
    @State private var librarySuggestion: CloudDriveFolders.Library?
    @State private var selectingSources = false
    @State private var sourcesSuggestion: CloudDriveFolders.Sources?
    @State private var sourcesPath = ""
    @State private var enteredSourcesPath: String?
    @State private var discoveryUnknown = false
    @State private var listing: CloudDriveFolders.Listing?
    @State private var folderMissing = false
    @State private var count: Int?
    @State private var countUnknown = false
    @State private var movePlan: CloudDriveFolders.MovePlan?
    @State private var checkingMove = false
    @State private var moveUnavailable = false
    @State private var confirmingMove = false
    @State private var moveID: UUID?
    @State private var moveConflicts: [String] = []
    @State private var issue: String?
    @State private var moveFailure: String?
    @State private var work: (id: UUID, kind: Work, task: Task<Void, Never>)?
    @State private var folderName: String?
    @State private var creation: String?
    @State private var activated = false
    @FocusState private var field: CloudSetupAssistantFocus.Target?

    typealias Target = CloudSetupAssistantFocus.Target
    private enum Work { case inspect, connect, discover, browse, create, verify }
    private var move: LibraryMoveActivity? {
        guard model.libraryMove?.id == moveID else { return nil }
        return model.libraryMove
    }
    private var existing: RcloneRemote? {
        let selected = remotes?.first { $0.type == "drive" && $0.name == model.preference.remote }
        return selected ?? (entry == .credentials ? nil : remotes?.first { $0.type == "drive" })
    }
    private var canEdit: Bool { viewModel.canConfigureCloudLibrary }
    private let bundledClient = CloudGoogleClient.bundled
    private var showCredentials: Bool { remotes != nil && (editingCredentials || (existing == nil && bundledClient == nil)) }
    private var validID: Bool { CloudSetupAssistantDraft.validGoogleClientID(client) }
    private var folderReady: Bool { listing != nil && draft.candidate != nil }
    private var folderControlsReady: Bool { work?.kind != .create && canEdit }
    private var folderNames: [String] { listing?.names ?? [] }
    private var browsingPath: String { selectingSources ? sourcesPath : draft.path }
    private var defaultSourcesPath: String { CloudDriveFolders.joining(draft.path, "GameFiles") }
    private var shouldSuggestSources: Bool { entry != .sources || model.preference.sourcesRootOverride == nil }
    private var usesDefaultSources: Bool { onboarding && sourcesPath == defaultSourcesPath }
    private var selectedSourcesOverride: String? { usesDefaultSources ? nil : sourcesPath }
    private var typedSourcesRoot: String? { enteredSourcesPath?.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canEnterSourcesPath: Bool { entry == .sources && selectingSources && canEdit && work == nil }
    private var moveOffered: Bool {
        guard let movePlan, movePlan.games > 0 else { return false }
        return folderReady && folderControlsReady && CloudDriveFolders.canMove(from: movePlan.source, to: draft.path)
    }
    private var service: CloudDriveFolders? {
        guard let remote = draft.remote, let tool else { return nil }
        return CloudDriveFolders(remote: remote, executable: tool, config: replacement?.config)
    }
    private var breadcrumbs: [String] {
        var path = ""
        return [""] + browsingPath.split(separator: "/").map {
            path = CloudDriveFolders.joining(path, String($0))
            return path
        }
    }
    private var primaryTitle: String {
        if entry == .sources { return "Save" }
        switch draft.step {
        case .account: return showCredentials || existing == nil ? "Sign in" : "Keep this account"
        case .folder: return selectingSources ? "Continue" : "Use this folder"
        case .verify: return "Activate"
        }
    }
    private var primaryEnabled: Bool {
        guard canEdit, !activated else { return false }
        if let typedSourcesRoot { return CloudLibraryPreference.validSourcesRoot(typedSourcesRoot) }
        switch draft.step {
        case .account:
            return work == nil && remotes != nil && (showCredentials
                ? validID && RcloneConfiguration.validCredential(secret) : existing != nil || bundledClient != nil)
        case .folder:
            guard work?.kind != .discover, librarySuggestion == nil, sourcesSuggestion == nil else { return false }
            if selectingSources {
                return work?.kind != .create && CloudLibraryPreference.validSourcesRoot(sourcesPath)
                    && (listing != nil || (usesDefaultSources && folderMissing))
            }
            return folderReady && folderControlsReady && !checkingMove
        case .verify: return work == nil && draft.verified
        }
    }
    private var showsPrimary: Bool {
        (draft.step != .account || remotes != nil)
            && (enteredSourcesPath != nil || (work?.kind != .discover
                && librarySuggestion == nil && sourcesSuggestion == nil))
    }

    var body: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: cancel)
            if let creation {
                SeleneConfirmDialog(title: format("Create “%@”?", [creation]),
                                    message: text("Existing files stay where they are."),
                                    confirmTitle: "Create", focus: Binding(get: { focusedTarget == .create ? .confirm : .cancel },
                                        set: { focus.select($0 == .confirm ? .create : .cancel) }),
                                    onCancel: cancel, onConfirm: { create(creation) })
            } else if confirmingMove, let movePlan {
                let size = movePlan.bytes.formatted(.byteCount(style: .file).locale(localization.formatLocale))
                SeleneConfirmDialog(title: format(movePlan.games == 1
                    ? "Move %d game (%@) to %@?" : "Move %d games (%@) to %@?", [movePlan.games, size, draft.path]),
                    message: text("Only app and build cache archives move. Game files stay where they are.")
                        + " " + text("Pause uploads on other Macs. Drive cannot lock both folders; uploads during or after the final check may be missed."),
                    confirmTitle: "Move",
                    focus: Binding(get: { focusedTarget == .confirmMove ? .confirm : .cancel },
                                   set: { focus.select($0 == .confirm ? .confirmMove : .cancel) }),
                    onCancel: cancel, onConfirm: moveGames)
            } else {
                VStack(spacing: canvas.u(18)) {
                    Text(text("Set up cloud library")).seleneFont(30, .semibold)
                        .foregroundColor(SeleneTheme.ink).accessibilityAddTraits(.isHeader)
                    stepper
                    switch draft.step {
                    case .account: account
                    case .folder: folders
                    case .verify: verification
                    }
                    if enteredSourcesPath == nil, let issue {
                        Text(text(issue)).seleneFont(16).foregroundColor(SeleneTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let moveFailure {
                        Text(verbatim: moveFailure).seleneFont(.caption).foregroundColor(SeleneTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let first = moveConflicts.first {
                        Text(format(moveConflicts.count == 1 ? "%d file has a conflict: %@"
                                    : "%d files have conflicts. First: %@", [moveConflicts.count, first]))
                            .seleneFont(16).foregroundColor(SeleneTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: canvas.u(14)) {
                        if folderName != nil {
                            pill(.create, "Continue", enabled: folderName.map(CloudDriveFolders.validName) == true,
                                 action: proposeCreation)
                        } else if showsPrimary {
                            pill(.primary, primaryTitle, enabled: primaryEnabled, action: primary)
                        }
                        pill(.cancel, move != nil ? "Cancel" : draft.step == .verify || folderName != nil
                             || enteredSourcesPath != nil || (selectingSources && entry != .sources) ? "Back" : "Cancel",
                             enabled: move?.canCancel != false, action: cancel)
                    }
                }
                .modifier(SeleneDialogCard(
                    cancelHint: move?.canCancel == false ? nil : HintItem(.b, "Cancel"),
                    confirmHint: focusRows.joined().isEmpty ? nil : HintItem(.a, "Select")))
            }
        }
        .onAppear { inspect(); installAssistantKeys() }
        .onDisappear { work?.task.cancel(); removeAssistantKeys(); secret = ""; replacement = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            work?.task.cancel()
        }
        .onExitCommand(perform: cancel)
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handleAssistantInput(action) }
        }
        .onChange(of: focusRows) { _, rows in focus.retainSelection(in: rows) }
        .onChange(of: model.libraryMove?.id) { previous, current in
            guard current == nil, let previous, previous == moveID,
                  let result = viewModel.activityResults.entries.first(where: { $0.id == previous }) else { return }
            switch result.outcome {
            case .cancelled:
                if model.hasPendingMove { issue = "Move paused. Close this window and choose Retry in Activity." }
                else if moveConflicts.isEmpty { issue = LibraryMoveActivity.unfinished }
            case .failed(let cause):
                moveFailure = cause
            case .succeeded:
                draft.acceptMove(draft.ticket)
                guard draft.activation != nil else { return }
                activated = true
                onClose()
            }
        }
        .onChange(of: field) { _, target in if let target { focus.select(target) } }
    }

    private var stepper: some View {
        let labels = ["Google account", "Folder", "Verify"]
        return SeleneStepper(labels: labels.map(text), active: draft.step.rawValue)
            .accessibilityLabel(format("Step %d of 3: %@", [draft.step.rawValue + 1, text(labels[draft.step.rawValue])]))
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: canvas.u(10)) {
            if let version { SeleneStatusDot(text: format("rclone detected · %@", [version]), color: SeleneTheme.statusOK) }
            if tool != nil, remotes != nil, work == nil {
                Text(text("New connections request full Google Drive access. Google does not limit that permission to the folders you choose here."))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if work?.kind == .inspect { progress("Checking…") }
            else if work?.kind == .connect { progress("Waiting for Google sign-in in your browser…") }
            else if tool == nil {
                Text(text("Install rclone: brew install rclone"))
                pill(.retry, "Try again", action: inspect)
            } else if remotes == nil {
                pill(.retry, "Try again", action: inspect)
            } else if !showCredentials {
                if let existing {
                    Text(verbatim: "\(text("Google Drive")) · \(existing.name)").seleneFont(19, .semibold)
                }
                if bundledClient != nil {
                    option(.advanced, text("Advanced")) { advanced.toggle() }
                        .accessibilityValue(text(advanced ? "Expanded" : "Collapsed"))
                    if advanced {
                        option(.changeCredentials, text("Use another Google client")) { editingCredentials = true }
                    }
                } else {
                    option(.changeCredentials, text("Change credentials")) { editingCredentials = true }
                }
            } else {
                Text(text("Use a Google OAuth client for a desktop app."))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: canvas.u(12)) {
                    option(.console, text("Google Console")) { openConsole() }
                    option(.guide, text("Setup guide")) { openGuide() }
                }
                Text(text("Google client ID"))
                input(.client) {
                    TextField(text("Google client ID"), text: $client).focused($field, equals: .client)
                        .onSubmit { field = .secret }
                }
                if !client.isEmpty {
                    SeleneStatusDot(text: text(validID ? "Valid format" : "Use an ID ending in .apps.googleusercontent.com"),
                                    color: validID ? SeleneTheme.statusOK : SeleneTheme.danger)
                }
                Text(text("Google client secret"))
                input(.secret) {
                    SecureField(text("Google client secret"), text: $secret).focused($field, equals: .secret)
                        .onSubmit(primary)
                }
            }
        }
        .seleneFont(16).foregroundColor(SeleneTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folders: some View {
        VStack(alignment: .leading, spacing: canvas.u(10)) {
            if selectingSources {
                Text(text("Game files folder")).seleneFont(17, .semibold)
                Text(text("Choose a path on the same cloud service. No files are moved."))
                    .seleneFont(15).foregroundColor(SeleneTheme.ink75)
            }
            if enteredSourcesPath != nil {
                input(.sourcesPath) {
                    TextField(text("Game files folder"),
                              text: Binding(get: { enteredSourcesPath ?? "" }, set: { enteredSourcesPath = $0 }),
                              prompt: Text(verbatim: "Games/GameFiles"))
                        .focused($field, equals: .sourcesPath).onSubmit(primary)
                }
                if !primaryEnabled {
                    Text(text("Enter a folder path such as Games or Archive/Games."))
                        .seleneFont(15).foregroundColor(SeleneTheme.danger)
                }
            } else if work?.kind == .discover {
                progress("Checking…")
            } else if let librarySuggestion {
                option(.resumeFolder, format(librarySuggestion.games == 1 ? "Resume %@ (%d game)" : "Resume %@ (%d games)",
                       [folderLabel(librarySuggestion.path), librarySuggestion.games]), icon: .folder, enabled: canEdit,
                       wide: true, action: resumeFolder)
                Text(verbatim: librarySuggestion.path).seleneFont(15).foregroundColor(SeleneTheme.ink75)
                option(.otherFolder, text("Choose another folder"), action: chooseOtherFolder)
            } else if let sourcesSuggestion {
                option(.resumeFolder, sourcesSuggestion.games.map { games in
                    format(games == 1 ? "Resume %@ (%d game)" : "Resume %@ (%d games)",
                           [folderLabel(sourcesSuggestion.path), games])
                } ?? format("Reuse game files in %@", [folderLabel(sourcesSuggestion.path)]), icon: .folder,
                       enabled: canEdit, wide: true, action: resumeFolder)
                Text(verbatim: sourcesSuggestion.path).seleneFont(15).foregroundColor(SeleneTheme.ink75)
                option(.otherFolder, text("Choose another folder"), action: chooseOtherFolder)
            } else if folderName != nil {
                Text(text("Folder name")).seleneFont(17)
                input(.folderName) {
                    TextField(text("Folder name"), text: Binding(get: { folderName ?? "" }, set: { folderName = $0 }))
                        .focused($field, equals: .folderName).onSubmit(proposeCreation)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: canvas.u(5)) {
                        ForEach(breadcrumbs, id: \.self) { path in
                            if !path.isEmpty { MaterialIconView(.chevron, size: 13).accessibilityHidden(true) }
                            if path == browsingPath { Text(folderLabel(path)).seleneFont(17, .semibold) }
                            else { option(.breadcrumb(path), folderLabel(path), enabled: folderControlsReady) { browse(path) } }
                        }
                    }
                }
                if listing != nil {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: canvas.u(5)) {
                                ForEach(folderNames, id: \.self) { name in
                                    option(.folder(name), name, icon: .folder, enabled: folderControlsReady, wide: true) {
                                        browse(CloudDriveFolders.joining(browsingPath, name))
                                    }
                                    .id(Target.folder(name))
                                }
                            }
                        }
                        .frame(height: canvas.u(CGFloat(min(folderNames.count * 64, 192))))
                        .onChange(of: focusedTarget) { _, target in if case .folder = target { proxy.scrollTo(target) } }
                    }
                    option(.newFolder, text("New folder…"), enabled: folderControlsReady && !checkingMove,
                           wide: true, action: nameFolder)
                }
                if (listing == nil && work != nil) || work?.kind == .create { progress("Checking…") }
                if listing == nil && work == nil { pill(.retry, "Try again", action: retryFolder) }
                if folderMissing { option(.newFolder, text("New folder…"), action: nameFolder) }
                if let count, count > 0 {
                    SeleneStatusDot(text: format(count == 1 ? "Arcane library found: %d game" : "Arcane library found: %d games", [count]),
                                    color: SeleneTheme.statusOK)
                } else if countUnknown {
                    SeleneStatusDot(text: text("Arcane library status unavailable"), color: SeleneTheme.ink60)
                }
                if checkingMove { progress("Checking the old folder…") }
                else if moveUnavailable {
                    SeleneStatusDot(text: text("Could not check the old folder."), color: SeleneTheme.ink60)
                } else if let movePlan, movePlan.games > 0 {
                    SeleneStatusDot(text: format(movePlan.games == 1 ? "%d game in %@" : "%d games in %@",
                                                 [movePlan.games, movePlan.source]), color: SeleneTheme.statusOK)
                    if moveOffered {
                        option(.moveGames, text("Move my games here"), checked: draft.wantsMove,
                               wide: true) { draft.toggleMove() }
                            .accessibilityValue(text(draft.wantsMove ? "On" : "Off"))
                    }
                }
            }
            if enteredSourcesPath == nil && canEnterSourcesPath && folderName == nil {
                option(.enterSourcesPath, text("Enter a path"), action: enterSourcesPath)
            }
            if enteredSourcesPath == nil && discoveryUnknown {
                SeleneStatusDot(text: text("Existing cloud folders could not be checked"), color: SeleneTheme.ink60)
            }
        }
        .foregroundColor(SeleneTheme.ink)
    }

    private var verification: some View {
        VStack(spacing: canvas.u(10)) {
            Text(verbatim: "\(draft.remote ?? ""):/\(draft.path)").seleneFont(18).foregroundColor(SeleneTheme.ink)
            if onboarding {
                Text(verbatim: "\(draft.remote ?? ""):/\(sourcesPath)")
                    .seleneFont(16).foregroundColor(SeleneTheme.ink75)
            }
            if let move {
                let status = CloudLibraryStatus.pending
                SeleneStatusDot(text: text(move.isVerifying ? "Verifying the move…" : move.isCancelling ? "Cancelling…" : "Moving games…"),
                                color: status.color, pulses: !move.isCancelling)
                SeleneProgressBar(progress: move.fraction, color: status.color)
            } else if work != nil { progress("Checking…") }
            else if draft.verified { SeleneStatusDot(text: text("Connection OK"), color: SeleneTheme.statusOK) }
            else { pill(.retry, "Try again", action: verify) }
        }
    }

    private func progress(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            Text(text(key)).seleneFont(16).foregroundColor(SeleneTheme.ink75)
            SeleneProgressBar(progress: nil, color: CloudLibraryStatus.pending.color)
        }
    }

    private func input<V: View>(_ target: Target, @ViewBuilder content: () -> V) -> some View {
        content().modifier(SeleneFieldSurface(focused: focusedTarget == target))
    }

    private func option(_ target: Target, _ title: String, icon: MaterialIcon? = nil, checked: Bool? = nil, enabled: Bool = true,
                        wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SeleneOptionRow(icon: icon, title: title, about: nil,
                            focused: focusedTarget == target, enabled: enabled) {
                if checked == true { MaterialIconView(.check, size: 20).accessibilityHidden(true) }
            }
            .fixedSize(horizontal: !wide, vertical: true)
        }
        .buttonStyle(.plain).disabled(!enabled).onHover { if $0 && enabled { focus.select(target) } }
    }

    private func pill(_ target: Target, _ key: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        SelenePillButton(title: key, minWidth: 115, height: 48, horizontalPadding: 17,
                         focused: focusedTarget == target, enabled: enabled, action: action)
            .disabled(!enabled).onHover { if $0 && enabled { focus.select(target) } }
    }

    private func folderLabel(_ path: String) -> String { path.split(separator: "/").last.map(String.init) ?? text("My Drive") }
    private func text(_ key: String) -> String { L10n.text(key, context: localization) }
    private func format(_ key: String, _ arguments: [CVarArg]) -> String {
        L10n.format(key, arguments, context: localization)
    }

    private func start(_ kind: Work, _ operation: @escaping @MainActor () async throws -> Void) {
        work?.task.cancel()
        issue = nil
        let id = UUID()
        work = (id, kind, Task { @MainActor in
            defer { if work?.id == id { work = nil } }
            do { try await operation() }
            catch is CancellationError {}
            catch {
                if !Task.isCancelled && work?.id == id {
                    issue = (error as? CloudLibraryFailure)?.messageKey
                        ?? (error as? RcloneConfiguration.Failure)?.key ?? RcloneConfiguration.Failure.test.key
                }
            }
        })
    }

    private func inspect() {
        let chosen = model.chosenExecutable
        tool = nil; version = nil; remotes = nil
        start(.inspect) {
            let found = await Task.detached(priority: .utility) { RcloneStorageBackend.findExecutable(preferred: chosen) }.value
            try Task.checkCancellation()
            guard let found, RcloneStorageBackend.isExecutable(found) else { return }
            tool = found
            let config = RcloneConfiguration(executable: found)
            let detected = try await config.version()
            try Task.checkCancellation()
            version = detected.replacingOccurrences(of: "rclone ", with: "", options: .anchored)
            let listed = try await config.remotes()
            try Task.checkCancellation()
            remotes = listed
            if entry == .library { browse(draft.path) }
            if entry == .sources { discoverSources() }
        }
    }

    private func retryFolder() {
        if remotes == nil { inspect() } else { browse(browsingPath) }
    }

    private func selectAccount(_ name: String) {
        draft.chooseAccount(name)
        onboarding = model.preference.remote != name
        guard onboarding, let service else {
            browse(model.preference.root.split(separator: "/").joined(separator: "/"))
            return
        }
        focus.reset()
        start(.discover) {
            let ticket = draft.ticket
            do {
                let suggestion = try await service.discoverLibrary()
                if !Task.isCancelled && draft.matches(ticket) { librarySuggestion = suggestion }
            }
            catch is CancellationError { return }
            catch { if !Task.isCancelled && draft.matches(ticket) { discoveryUnknown = true } }
            try Task.checkCancellation()
            if librarySuggestion == nil { browse("") }
        }
    }

    private func selectLibrary() {
        guard onboarding else { finishFolder(); return }
        selectingSources = true
        sourcesPath = defaultSourcesPath
        discoverSources()
    }

    private func discoverSources() {
        guard shouldSuggestSources else { browse(sourcesPath); return }
        guard let service else { return }
        let path = draft.path, ticket = draft.renewTicket()
        listing = nil; folderMissing = false; count = nil; countUnknown = false
        discoveryUnknown = false
        focus.reset()
        start(.discover) {
            do {
                let suggestion = try await service.discoverSources(library: path)
                if !Task.isCancelled && draft.matches(ticket) { sourcesSuggestion = suggestion }
            }
            catch is CancellationError { return }
            catch { if !Task.isCancelled && draft.matches(ticket) { discoveryUnknown = true } }
            guard !Task.isCancelled, draft.matches(ticket) else { return }
            if sourcesSuggestion == nil { browse(sourcesPath) }
        }
    }

    private func resumeFolder() {
        guard canEdit else { return }
        if let librarySuggestion {
            self.librarySuggestion = nil
            draft.browse(librarySuggestion.path)
            selectLibrary()
        } else if let sourcesSuggestion {
            self.sourcesSuggestion = nil
            browse(sourcesSuggestion.path)
        }
    }

    private func chooseOtherFolder() {
        focus.reset()
        if librarySuggestion != nil {
            librarySuggestion = nil
            browse("")
        } else {
            sourcesSuggestion = nil
            browse("")
        }
    }

    private func useSources() {
        if entry == .sources {
            let path = typedSourcesRoot ?? sourcesPath
            if path != model.preference.sourcesRoot || model.sourcesNeedConfirmation { model.chooseSourcesRoot(path) }
            onClose()
        } else { finishFolder() }
    }

    private func enterSourcesPath() {
        guard canEnterSourcesPath else { return }
        enteredSourcesPath = sourcesPath
        focus.select(.sourcesPath); field = .sourcesPath
    }

    private func finishFolder() {
        field = nil
        discoveryUnknown = false
        if draft.useFolder() { focus.reset(); verify() }
    }

    private func connect() {
        guard let tool else { return }
        let id = showCredentials ? client : bundledClient?.id ?? ""
        let password = showCredentials ? secret : bundledClient?.secret ?? ""
        let target = existing?.name
        field = nil; secret = ""; focus.reset()
        model.isChangingConnection = true
        start(.connect) {
            defer { model.isChangingConnection = false }
            if let target {
                let staged = try await CloudDriveCredentialChange.prepare(remote: target, executable: tool,
                                                                          clientID: id, secret: password)
                try Task.checkCancellation()
                replacement = staged
                selectAccount(target)
            } else {
                let remote = try await RcloneConfiguration(executable: tool).connect(clientID: id, secret: password)
                try Task.checkCancellation()
                selectAccount(remote.name)
            }
        }
    }

    private func browse(_ path: String) {
        guard let service else { return }
        let ticket: UUID
        if selectingSources {
            sourcesPath = path
            ticket = draft.renewTicket()
        } else { ticket = draft.browse(path) }
        listing = nil; count = nil; countUnknown = false; folderMissing = false
        movePlan = nil; moveUnavailable = false; checkingMove = false; moveConflicts = []; moveFailure = nil
        let old = model.preference.root.split(separator: "/").joined(separator: "/")
        let checkOld = !selectingSources && model.preference.remote == draft.remote && replacement == nil
            && CloudDriveFolders.canMove(from: old, to: path)
        focus.reset()
        start(.browse) {
            let result: CloudDriveFolders.Listing
            do { result = try await service.list(path, ticket: ticket) }
            catch StorageBackendError.notFound {
                if !Task.isCancelled && draft.matches(ticket) { folderMissing = !path.isEmpty }
                if usesDefaultSources { return }
                throw CloudLibraryFailure.folderMissing
            }
            guard !Task.isCancelled, draft.matches(result.ticket) else { return }
            checkingMove = checkOld
            listing = result
            if checkOld {
                do {
                    let plan = try await service.movePlan(from: old, to: path)
                    if !Task.isCancelled && draft.matches(ticket) { movePlan = plan }
                } catch let failure as CloudDriveFolders.MoveFailure {
                    if !Task.isCancelled && draft.matches(ticket) { moveFailure = failure.localizedDescription }
                } catch {
                    if !Task.isCancelled && draft.matches(ticket) { moveUnavailable = true }
                }
                guard !Task.isCancelled, draft.matches(ticket) else { return }
                checkingMove = false
            }
            guard !selectingSources, !path.isEmpty else { return }
            do {
                let games = try await service.libraryCount(in: path, folders: result.names)
                if !Task.isCancelled && draft.matches(ticket) { count = games }
            } catch {
                if !Task.isCancelled && draft.matches(ticket) { countUnknown = true }
            }
        }
    }

    private func nameFolder() {
        guard folderControlsReady, !checkingMove else { return }
        if folderMissing, let name = browsingPath.split(separator: "/").last {
            focus.reset()
            creation = String(name)
            return
        }
        guard listing != nil else { return }
        folderName = ""; focus.select(.folderName); field = .folderName
    }

    private func proposeCreation() {
        guard let name = folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
              CloudDriveFolders.validName(name), folderControlsReady else { return }
        folderName = nil; field = nil; focus.reset()
        if folderNames.contains(name) { browse(CloudDriveFolders.joining(browsingPath, name)) }
        else { creation = name }
    }

    private func create(_ name: String) {
        guard creation == name, folderControlsReady, let service else { return }
        let parent = folderMissing ? browsingPath.split(separator: "/").dropLast().joined(separator: "/") : browsingPath
        let ticket = draft.ticket
        creation = nil; focus.reset()
        start(.create) {
            try await service.create(name, in: parent)
            if !Task.isCancelled && draft.matches(ticket) { browse(CloudDriveFolders.joining(parent, name)) }
        }
    }

    private func verify() {
        guard let service, draft.step == .verify else { return }
        let path = draft.path, ticket = draft.renewTicket()
        let sources = onboarding ? selectedSourcesOverride : nil
        start(.verify) {
            try await service.verifyAccess(to: path)
            if let sources, sources != path { try await service.verifyAccess(to: sources) }
            if !Task.isCancelled { draft.acceptAccessCheck(ticket) }
        }
    }

    private func activate() {
        guard let preference = draft.activation else { return }
        do {
            let replaced = replacement != nil
            try replacement?.apply()
            activated = true
            let sources = onboarding ? selectedSourcesOverride : model.preference.sourcesRootOverride
            model.configure(remote: preference.remote, root: preference.root, enabled: true, sourcesRoot: sources,
                            reload: replaced, confirmLibrary: true)
            model.connectionCheck = .init(date: .now, failure: nil)
            onClose()
        } catch {
            issue = RcloneConfiguration.Failure.configuration.key
        }
    }

    private func moveGames() {
        guard confirmingMove, draft.wantsMove, primaryEnabled, let movePlan, let tool,
              replacement == nil else { return }
        confirmingMove = false; focus.reset(); moveConflicts = []; issue = nil; moveFailure = nil
        moveID = viewModel.startLibraryMove(.init(plan: movePlan, destination: draft.path), executable: tool) {
            moveConflicts = $0
        }
    }

    func cancel() {
        field = nil; focus.reset()
        if creation != nil { creation = nil; return }
        if confirmingMove { confirmingMove = false; return }
        if let move { viewModel.cancelLibraryMove(move.id); return }
        if model.hasPendingMove { onClose(); return }
        if enteredSourcesPath != nil { enteredSourcesPath = nil; focus.select(.enterSourcesPath); return }
        if folderName != nil { folderName = nil; return }
        if work?.kind == .create { return }
        if draft.step == .verify {
            draft.backToFolders()
            work?.task.cancel(); work = nil; issue = nil
            browse(browsingPath)
            return
        }
        if selectingSources && entry != .sources {
            selectingSources = false; sourcesSuggestion = nil; discoveryUnknown = false
            browse(draft.path)
            return
        }
        if draft.step == .account && editingCredentials && work == nil && entry != .credentials {
            editingCredentials = false; client = ""; secret = ""; issue = nil
            return
        }
        work?.task.cancel()
        onClose()
    }

    private func primary() {
        guard primaryEnabled else { return }
        switch draft.step {
        case .account:
            if !showCredentials, let existing { selectAccount(existing.name) }
            else { connect() }
        case .folder:
            if selectingSources { useSources() }
            else { selectLibrary() }
        case .verify:
            if draft.activation != nil { activate() }
            else if draft.wantsMove { focus.reset(); confirmingMove = true }
        }
    }

    var focusedTarget: Target { focus.current(in: focusRows) }

    private var focusRows: [[Target]] {
        if creation != nil { return [[.create, .cancel]] }
        if confirmingMove { return [[.confirmMove, .cancel]] }
        if folderName != nil { return [[.folderName], (folderName.map(CloudDriveFolders.validName) == true ? [.create] : []) + [.cancel]] }
        if enteredSourcesPath != nil { return [[.sourcesPath], (primaryEnabled ? [.primary] : []) + [.cancel]] }
        var rows: [[Target]] = []
        switch draft.step {
        case .account:
            if work == nil {
                if remotes == nil { rows = [[.retry]] }
                else if showCredentials { rows = [[.console, .guide], [.client], [.secret]] }
                else if bundledClient != nil { rows = [[.advanced]] + (advanced ? [[.changeCredentials]] : []) }
                else { rows = [[.changeCredentials]] }
            }
        case .folder:
            if work?.kind == .discover { break }
            if librarySuggestion != nil || sourcesSuggestion != nil {
                rows = canEdit ? [[.resumeFolder], [.otherFolder]] : [[.otherFolder]]
            } else if folderControlsReady {
                rows = [breadcrumbs.dropLast().map(Target.breadcrumb)]
                rows += folderNames.map { [.folder($0)] }
                if listing != nil && !checkingMove { rows.append([.newFolder]) }
                else if work == nil { rows.append([.retry]) }
                if folderMissing { rows.append([.newFolder]) }
                if moveOffered { rows.append([.moveGames]) }
            }
            if canEnterSourcesPath { rows.append([.enterSourcesPath]) }
        case .verify:
            if work == nil && !draft.verified { rows = [[.retry]] }
        }
        return rows + [(showsPrimary && primaryEnabled ? [.primary] : []) + (move?.canCancel == false ? [] : [.cancel])]
    }

    func perform(_ target: Target) {
        guard focusRows.contains(where: { $0.contains(target) }) else { return }
        switch target {
        case .cancel: cancel()
        case .primary: primary()
        case .advanced: advanced.toggle()
        case .changeCredentials: editingCredentials = true
        case .client, .secret, .folderName, .sourcesPath: field = target
        case .enterSourcesPath: enterSourcesPath()
        case .console: openConsole()
        case .guide: openGuide()
        case .retry:
            switch draft.step {
            case .account: inspect()
            case .folder: retryFolder()
            case .verify: verify()
            }
        case .breadcrumb(let path): browse(path)
        case .folder(let name): browse(CloudDriveFolders.joining(browsingPath, name))
        case .resumeFolder: resumeFolder()
        case .otherFolder: chooseOtherFolder()
        case .newFolder: nameFolder()
        case .moveGames: draft.toggleMove()
        case .confirmMove: moveGames()
        case .create:
            if let creation { create(creation) }
            else { proposeCreation() }
        }
    }

    func moveAssistantFocus(_ direction: CloudSetupAssistantFocus.Direction) {
        focus.move(direction, in: focusRows)
        switch focusedTarget {
        case .client, .secret, .folderName, .sourcesPath: field = focusedTarget
        default: field = nil
        }
    }

    private func openConsole() { NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!) }
    private func openGuide() { NSWorkspace.shared.open(URL(string: "https://rclone.org/drive/#making-your-own-client-id")!) }
}
