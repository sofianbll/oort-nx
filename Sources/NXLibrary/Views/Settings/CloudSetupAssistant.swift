import AppKit
import NXLibraryCore
import ArcanePorting
import SwiftUI

/// Google account, both Drive folders, then a check: one panel, three steps, back at any time.
struct CloudSetupAssistant: View {
    enum Entry { case account, library, sources, credentials }
    enum AccountPage { case choose, have, help }
    enum Work { case inspect, connect, discover, browse, create, verify }
    typealias Target = CloudSetupAssistantFocus.Target
    typealias Folder = CloudSetupAssistantFocus.Folder

    /// A folder on its card, and why it is there.
    struct Choice: Equatable {
        enum Origin { case current, kept, found, chosen }
        var path: String
        var games: Int?
        var names: [String] = []
        var origin: Origin
    }

    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: CloudLibraryModel
    let entry: Entry
    let onClose: () -> Void

    init(viewModel: AppViewModel, model: CloudLibraryModel, entry: Entry = .account, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.model = model
        self.entry = entry
        self.onClose = onClose
        guard let remote = model.preference.remote, entry == .sources || entry == .library else { return }
        var draft = CloudSetupAssistantDraft()
        draft.chooseAccount(remote)
        draft.browse(Self.cleaned(model.preference.root))
        _draft = State(initialValue: draft)
        _library = State(initialValue: .init(path: draft.path, games: nil, origin: .current))
        _sources = State(initialValue: .init(path: Self.cleaned(model.preference.sourcesRoot), games: nil, origin: .current))
        _sourcesOverride = State(initialValue: model.preference.sourcesRootOverride)
        _browsing = State(initialValue: entry == .sources ? .sources : .library)
        _browserPath = State(initialValue: entry == .sources ? Self.cleaned(model.preference.sourcesRoot) : draft.path)
    }

    static func cleaned(_ path: String) -> String { path.split(separator: "/").joined(separator: "/") }

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.nxAppLocale) var localization
    @State var focus = CloudSetupAssistantFocus()
    @State var keyMonitor: Any?
    @State var draft = CloudSetupAssistantDraft()
    @State var tool: URL?
    @State var version: String?
    @State var remotes: [RcloneRemote]?
    @State var accountPage: AccountPage = .choose
    @State var client = ""
    @State var secret = ""
    @State var replacement: CloudDriveCredentialChange?
    @State var onboarding = false
    @State var library: Choice?
    @State var sources: Choice?
    /// What is saved for the ROM folder; nil follows the library's own GameFiles folder.
    @State var sourcesOverride: String?
    @State var sourcesChanged = false
    /// Where a first library would be created, and the folder the player saw there.
    @State var newLibrary: (path: String, below: String, parent: CloudDriveScope.CreationParent)?
    @State var confirmingLibrary = false
    /// What the folders already read hold, in words.
    @State var index: CloudFolderIndex?
    @State var looking: Task<Void, Never>?
    /// The folder the player chose for the wrong question, waiting for their answer.
    @State var doubt: (folder: Folder, path: String, advice: CloudFolderIndex.Advice)?
    @State var doubtFocus = 0
    @State var discoveryUnknown = false
    @State var browsing: Folder?
    @State var browserPath = ""
    @State var typedPath: String?
    @State var listing: CloudDriveFolders.Listing?
    @State var folderMissing = false
    @State var movePlan: CloudDriveFolders.MovePlan?
    @State var checkingMove = false
    @State var moveUnavailable = false
    @State var confirmingMove = false
    @State var moveID: UUID?
    @State var moveConflicts: [String] = []
    @State var issue: String?
    @State var moveFailure: String?
    @State var work: (id: UUID, kind: Work, task: Task<Void, Never>)?
    @State var folderName: String?
    @State var creation: String?
    /// The account and folder on screen; a folder is only created there.
    @State var shownParent: CloudDriveScope.CreationParent?
    @State var activated = false
    @FocusState var field: Target?

    let bundledClient = CloudGoogleClient.bundled
    var move: LibraryMoveActivity? {
        guard model.libraryMove?.id == moveID else { return nil }
        return model.libraryMove
    }
    var movePaused: Bool { move == nil && model.hasPendingMove }
    var canEdit: Bool { viewModel.canConfigureCloudLibrary }
    /// Opened for one folder only: choosing it is the whole task.
    var isDirect: Bool { entry == .sources || entry == .library }
    var existing: RcloneRemote? {
        remotes?.first { $0.type == "drive" && $0.name == model.preference.remote }
            ?? (model.preference.remote == nil ? remotes?.first { $0.type == "drive" } : nil)
    }
    var validID: Bool { CloudSetupAssistantDraft.validGoogleClientID(client) }
    var validSecret: Bool { RcloneConfiguration.validCredential(secret) }
    var defaultSourcesPath: String { CloudDriveFolders.joining(draft.path, "GameFiles") }
    var folderControlsReady: Bool { work?.kind != .create && canEdit }
    var folderNames: [String] { listing?.names ?? [] }
    var typedFolder: String? { typedPath?.trimmingCharacters(in: .whitespacesAndNewlines) }
    var moveOffered: Bool {
        guard browsing == nil, let movePlan, movePlan.games > 0 else { return false }
        return folderControlsReady && CloudDriveFolders.canMove(from: movePlan.source, to: draft.path)
    }
    var service: CloudDriveFolders? {
        guard let remote = draft.remote, let tool else { return nil }
        return CloudDriveFolders(remote: remote, executable: tool, config: replacement?.config,
                                 reference: model.preference.referenceFolder)
    }
    var breadcrumbs: [String] {
        var path = ""
        return [""] + browserPath.split(separator: "/").map {
            path = CloudDriveFolders.joining(path, String($0))
            return path
        }
    }
    var waitingForGoogle: Bool { work?.kind == .connect }
    var accountNeedsClient: Bool { accountPage != .choose }

    var primaryTitle: String {
        if browsing != nil { return typedPath == nil ? "Choose this folder" : "Continue" }
        switch draft.step {
        case .account: return accountNeedsClient || existing == nil ? "Sign in" : "Keep this account"
        case .folder: return "Continue"
        case .verify: return "Activate"
        }
    }
    var primaryEnabled: Bool {
        guard canEdit, !activated else { return false }
        if let browsing {
            if let typedFolder {
                return work == nil && (browsing == .sources ? CloudLibraryPreference.validSourcesRoot(typedFolder)
                                       : CloudLibraryPreference.validRoot(typedFolder))
            }
            return work?.kind != .create && listing != nil && CloudLibraryPreference.validSourcesRoot(browserPath)
        }
        switch draft.step {
        case .account:
            guard work == nil, remotes != nil else { return false }
            return accountNeedsClient ? validID && validSecret : existing != nil || bundledClient != nil
        case .folder:
            return work?.kind != .discover && work?.kind != .create && !checkingMove
                && (library == nil ? newLibrary != nil : draft.candidate != nil)
        case .verify: return work == nil && draft.verified
        }
    }
    var showsPrimary: Bool {
        guard !movePaused, !waitingForGoogle else { return false }
        if browsing != nil { return true }
        switch draft.step {
        case .account: return remotes != nil && (accountNeedsClient || existing != nil || bundledClient != nil)
        case .folder: return work?.kind != .discover
        case .verify: return true
        }
    }
    var cancelTitle: String {
        if move != nil || waitingForGoogle { return "Cancel" }
        if movePaused { return "Close" }
        if typedPath != nil || folderName != nil { return "Back" }
        if browsing != nil { return isDirect ? "Cancel" : "Back" }
        if draft.step == .verify || (draft.step == .folder && !isDirect) || accountNeedsClient { return "Back" }
        return "Cancel"
    }

    var body: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: cancel)
            if let creation { creationDialog(creation) { create(creation) } }
            else if confirmingLibrary, let newLibrary { creationDialog(newLibrary.path, confirm: createLibrary) }
            else if confirmingMove, let movePlan { moveDialog(movePlan) }
            else if let doubt { doubtDialog(doubt) }
            else { panel }
        }
        .onAppear { inspect(); installAssistantKeys() }
        .onDisappear { work?.task.cancel(); looking?.cancel(); removeAssistantKeys(); secret = ""; replacement = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            work?.task.cancel()
        }
        .onExitCommand(perform: cancel)
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handleAssistantInput(action) }
        }
        .onChange(of: focusRows) { _, rows in focus.retainSelection(in: rows, rail: focusRail) }
        .onChange(of: model.libraryMove?.id) { previous, current in moveEnded(previous, current) }
        .onChange(of: field) { _, target in if let target { focus.select(target) } }
    }

    private func creationDialog(_ name: String, confirm: @escaping () -> Void) -> some View {
        SeleneConfirmDialog(title: format("Create “%@”?", [name]), message: text("Existing files stay where they are."),
                            confirmTitle: "Create", focus: Binding(get: { focusedTarget == .create ? .confirm : .cancel },
                                set: { focus.select($0 == .confirm ? .create : .cancel) }),
                            onCancel: cancel, onConfirm: confirm)
    }

    private func moveDialog(_ plan: CloudDriveFolders.MovePlan) -> some View {
        let size = plan.bytes.formatted(.byteCount(style: .file).locale(localization.formatLocale))
        return SeleneConfirmDialog(title: text("Move app and build cache archives?"),
            message: format("Destination: “%@” · %@. Game files stay where they are.", [draft.path, size])
                + " " + text("Pause uploads on other Macs. Drive cannot lock both folders; uploads during or after the final check may be missed."),
            confirmTitle: "Move",
            focus: Binding(get: { focusedTarget == .confirmMove ? .confirm : .cancel },
                           set: { focus.select($0 == .confirm ? .confirmMove : .cancel) }),
            onCancel: cancel, onConfirm: moveGames)
    }

    private var panel: some View {
        let names = ["Account", "Folders", "It’s ready"]
        return OortAssistantPanel(
            title: text("Cloud library"), heading: heading, message: message,
            steps: names.indices.map { index in
                .init(id: index, title: text(names[index]),
                      state: index < draft.step.rawValue ? .done : index == draft.step.rawValue ? .current : .ahead)
            },
            focusedStep: focusedStep,
            back: move?.canCancel == false ? nil : HintItem(.b, cancelTitle, action: cancel),
            confirm: focusRows.joined().isEmpty ? nil : HintItem(.a, "Select"),
            canOpen: canOpen, onStep: openStep, press: handleAssistantInput
        ) {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
                if browsing != nil { browser }
                else {
                    switch draft.step {
                    case .account: account
                    case .folder: folders
                    case .verify: verification
                    }
                }
                problems
            }
        } actions: {
            if folderName != nil {
                pill(.create, "Continue", enabled: folderName.map(CloudDriveFolders.validName) == true, action: proposeCreation)
            } else if showsPrimary {
                pill(.primary, primaryTitle, enabled: primaryEnabled, action: primary)
            }
            pill(.cancel, cancelTitle, enabled: move?.canCancel != false, action: cancel)
        }
    }

    private var heading: String {
        if let browsing { return question(browsing) }
        switch draft.step {
        case .account: return text("Connect your Google Drive")
        case .folder: return text("Your folders")
        case .verify: return text("It’s ready")
        }
    }

    private var message: String? {
        if let browsing { return expectation(browsing) }
        switch draft.step {
        case .account:
            return text("Google grants access to your whole Drive, but Oort only writes to the two folders you choose.")
        case .folder:
            if work?.kind == .discover { return text("Oort is looking in your Drive…") }
            if firstAdvice != nil { return text("One answer looks wrong. Oort proposes the right folder.") }
            return text(sources == nil || (library == nil && newLibrary == nil) ? "Choose what is missing, or continue."
                        : "Oort found these. If they are right, continue.")
        case .verify: return nil
        }
    }

    func question(_ folder: Folder) -> String {
        text(folder == .sources ? "Where are your ROMs?" : "Where should your compiled games go?")
    }

    func expectation(_ folder: Folder) -> String {
        text(folder == .sources ? "The folder with your .nsp, .xci or .nup game files. Oort never touches it."
             : "Oort puts its apps there. An empty folder is fine.")
    }

    private func doubtDialog(_ doubt: (folder: Folder, path: String, advice: CloudFolderIndex.Advice)) -> some View {
        SeleneChoiceDialog(title: question(doubt.folder), message: explanation(doubt.advice),
                           choices: doubtChoices.map(\.title), focus: $doubtFocus, cancelIndex: doubtChoices.count - 1,
                           onCancel: cancel) { doubtChoices[$0].perform() }
    }

    /// The right folder first, then the player's own choice: Oort explains, it never decides.
    var doubtChoices: [(title: String, perform: () -> Void)] {
        guard let doubt else { return [] }
        var choices: [(String, () -> Void)] = []
        if doubt.advice.swaps { choices.append((text("Swap the two folders"), { answerDoubt(); swapFolders() })) }
        else if let instead = doubt.advice.instead {
            choices.append((format("Use folder “%@”", [folderLabel(instead)]), { answerDoubt(); accept(doubt.folder, instead) }))
        }
        if doubt.advice.reason != .sameFolder {
            choices.append((text("Keep this folder"), {
                answerDoubt()
                if browsing != nil { accept(doubt.folder, doubt.path) }
                else if library == nil { proposeLibrary() } else { finishFolders() }
            }))
        }
        return choices + [(text("Cancel"), cancel)]
    }

    func explanation(_ advice: CloudFolderIndex.Advice) -> String {
        switch advice.reason {
        case .compiledHere: text("These are the games Oort compiled, not your ROMs.")
        case .romsHere: text("These are your ROMs. Oort needs another folder for its apps.")
        case .oneGame: text("This is one game’s folder. The right one is just above it.")
        case .further: format("The games are further in, in “%@”.", [folderLabel(advice.instead ?? "")])
        case .nothingHere: text("No game in this folder.")
        case .sameFolder: text("Both answers are the same folder. Oort needs two.")
        }
    }

    @ViewBuilder private var problems: some View {
        if let issue { problem(text(issue)) }
        if let moveFailure { problem(moveFailure) }
        if let first = moveConflicts.first {
            problem(format(moveConflicts.count == 1 ? "%d file has a conflict: %@"
                           : "%d files have conflicts. First: %@", [moveConflicts.count, first]))
        }
    }

    private func problem(_ text: String) -> some View {
        Text(verbatim: text).seleneFont(.text).foregroundColor(SeleneTheme.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var verification: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small)) {
            Text(verbatim: "\(draft.remote ?? ""):/\(draft.path)").seleneFont(.text).foregroundColor(SeleneTheme.ink)
            if onboarding || sourcesChanged {
                Text(verbatim: "\(draft.remote ?? ""):/\(sourcesOverride ?? defaultSourcesPath)")
                    .seleneFont(.text).foregroundColor(SeleneTheme.ink75)
            }
            if let move {
                let status = CloudLibraryStatus.pending
                SeleneStatusDot(text: text(move.isVerifying ? "Verifying the move…" : move.isCancelling ? "Cancelling…" : "Moving games…"),
                                color: status.color, pulses: !move.isCancelling)
                OortMeter(share: move.fraction, fill: status.color)
            } else if work != nil { progress("Checking…") }
            else if draft.verified { SeleneStatusDot(text: text("Connection OK"), color: SeleneTheme.statusOK) }
            else if !movePaused { pill(.retry, "Try again", action: verify) }
        }
    }

    func progress(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(text(key)).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
            OortMeter(share: nil, fill: CloudLibraryStatus.pending.color)
        }
    }

    func input<V: View>(_ target: Target, @ViewBuilder content: () -> V) -> some View {
        content().modifier(SeleneFieldSurface(focused: focusedTarget == target))
    }

    func option<Trailing: View>(_ target: Target, _ title: String, about: String? = nil, icon: MaterialIcon? = nil,
                                enabled: Bool = true, wide: Bool = true, action: @escaping () -> Void,
                                @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) -> some View {
        Button(action: action) {
            SeleneOptionRow(icon: icon, title: title, about: about, focused: focusedTarget == target, enabled: enabled,
                            trailing: trailing)
                .fixedSize(horizontal: !wide, vertical: true)
        }
        .buttonStyle(OortPressStyle()).disabled(!enabled).seleneHover { if enabled { focus.select(target) } }
    }

    func pill(_ target: Target, _ key: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        OortButton(title: key, focused: focusedTarget == target, state: enabled ? .ready : .blocked, action: action)
            .disabled(!enabled).seleneHover { if enabled { focus.select(target) } }
    }

    func compact(_ target: Target, _ key: String, arguments: [String] = [], enabled: Bool = true,
                 action: @escaping () -> Void) -> some View {
        OortButton(title: key, arguments: arguments, focused: focusedTarget == target, state: enabled ? .ready : .blocked, preset: .compact, action: action)
            .disabled(!enabled).seleneHover { if enabled { focus.select(target) } }
    }

    func folderLabel(_ path: String) -> String { path.split(separator: "/").last.map(String.init) ?? text("My Drive") }
    func text(_ key: String) -> String { L10n.text(key, context: localization) }
    func format(_ key: String, _ arguments: [CVarArg]) -> String { L10n.format(key, arguments, context: localization) }
}
