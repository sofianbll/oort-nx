import AppKit
import OortLibrary
import NxnativeAdapter
import SwiftUI

/// Google account, both Drive folders, then a check: one panel, three steps, back at any time.
struct CloudSetupAssistant: View {
    enum Entry { case account, library, sources, credentials }
    enum AccountPage { case choose, have, help }
    enum Work { case inspect, connect, discover, browse, create, checkMove, verify }
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
    @State var remotes: [RcloneRemote]?
    @State var kept: RcloneAccount?
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
    /// A folder Oort would create, and the one the player saw above it.
    struct NewFolder {
        let path: String
        let below: String
        let parent: CloudDriveScope.CreationParent
    }
    @State var newLibrary: NewFolder?
    @State var newSources: NewFolder?
    @State var confirmingNew = false
    /// What this visit has read. Nothing that writes or moves is decided from it.
    @State var reads = CloudDriveReads()
    @State var recents: [String] = []
    /// What the folders already read hold, in words.
    @State var index: CloudFolderIndex?
    @State var looking: Task<Void, Never>?
    /// The folder the player chose for the wrong question, waiting for their answer.
    @State var doubt: (folder: Folder, path: String, advice: CloudFolderIndex.Advice)?
    @State var discoveryUnknown = false
    @State var browsing: Folder?
    @State var browserPath = ""
    @State var typedPath: String?
    @State var listing: CloudDriveFolders.Listing?
    @State var folderMissing = false
    @State var movePlan: CloudDriveFolders.MovePlan?
    @State var resumeMoveCheck = false
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
        let drives = remotes?.filter { $0.type == "drive" }
        let selected = drives?.first { $0.name == (model.preference.remote ?? model.keptConnection) }
        return selected ?? (model.preference.remote == nil ? drives?.first : nil)
    }
    var keepsAccount: Bool { existing != nil && kept?.isSignedIn != false }
    var reusesClient: Bool { !accountNeedsClient && existing?.name == model.keptConnection && kept?.keepsClient == true }
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
    /// Checks and changes: always asked again.
    var service: CloudDriveFolders? { drive(reads: nil) }
    /// Folders on screen: what was read a moment ago is shown at once.
    var shown: CloudDriveFolders? { drive(reads: reads) }
    private func drive(reads: CloudDriveReads?) -> CloudDriveFolders? {
        guard let remote = draft.remote, let tool else { return nil }
        return CloudDriveFolders(remote: remote, executable: tool, config: replacement?.config,
                                 reference: model.preference.referenceFolder, reads: reads)
    }
    var breadcrumbs: [String] {
        var path = ""
        return [""] + browserPath.split(separator: "/").map {
            path = CloudDriveFolders.joining(path, String($0))
            return path
        }
    }
    var waitingForGoogle: Bool { work?.kind == .connect }
    var checkingMove: Bool { work?.kind == .checkMove }
    var accountNeedsClient: Bool { accountPage != .choose }

    var primaryTitle: String {
        if browsing != nil { return typedPath == nil ? "Choose this folder" : "Continue" }
        switch draft.step {
        case .account: return accountNeedsClient || !keepsAccount ? "Sign in" : "Keep this account"
        case .folder: return "Continue"
        case .verify: return "See my games"
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
            return accountNeedsClient ? validID && validSecret : keepsAccount || reusesClient || bundledClient != nil
        case .folder:
            return work?.kind != .discover && work?.kind != .create && !checkingMove
                && (library == nil ? newLibrary != nil : draft.candidate != nil)
        case .verify: return work == nil && draft.verified
        }
    }
    var showsPrimary: Bool {
        guard !movePaused, !waitingForGoogle, move == nil else { return false }
        if browsing != nil { return true }
        switch draft.step {
        case .account: return remotes != nil && (accountNeedsClient || keepsAccount || reusesClient || bundledClient != nil)
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
            if let question { asked(question) } else { panel }
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

    /// A question over the panel: its words; its keys are in the bar.
    private var question: (title: String, message: String)? {
        if let creation { return (format("Create “%@”?", [creation]), text("Existing files stay where they are.")) }
        if confirmingNew {
            let folders = newFolders
            let names = folders.map { shownPath($0.path) }.joined(separator: "\n")
            return (text(folders.count > 1 ? "Create these two folders?" : "Create this folder?"),
                    names + "\n" + text("Existing files stay where they are."))
        }
        if confirmingMove, let movePlan {
            let size = movePlan.bytes.formatted(.byteCount(style: .file).locale(localization.formatLocale))
            return (text("Move app and build cache archives?"),
                    format("Destination: “%@” · %@. Game files stay where they are.", [draft.path, size])
                        + " " + text("Pause uploads on other Macs. Drive cannot lock both folders; uploads during or after the final check may be missed."))
        }
        if let doubt { return (questionText(doubt.folder), explanation(doubt.advice)) }
        return nil
    }

    private func asked(_ question: (title: String, message: String)) -> some View {
        OortQuestion(title: question.title, message: question.message, actions: bar, focused: AnyHashable(focusedTarget),
                     onFocus: hoverBar, onCancel: cancel, onConfirm: { perform(focusedTarget) })
    }

    private func hoverBar(_ id: AnyHashable) {
        if let target = id.base as? Target { focus.select(target) }
    }

    /// The keys under what is on screen, in any order: the bar places them.
    var bar: [OortActionBar.Action] {
        func key(_ target: Target, _ title: String, _ role: ActionBarRole, arguments: [String] = [], enabled: Bool = true) -> OortActionBar.Action {
            .init(id: AnyHashable(target), title: title, arguments: arguments, role: role, enabled: enabled) { perform(target) }
        }
        if creation != nil { return [key(.cancel, "Cancel", .back), key(.create, "Create", .primary)] }
        if confirmingNew {
            return [key(.cancel, "Cancel", .back)] + (library == nil ? [] : [key(.keep, "Continue without", .secondary)])
                + [key(.create, "Create", .primary)]
        }
        if confirmingMove { return [key(.confirmMove, "Move", .destructive), key(.cancel, "Cancel", .back)] }
        if let doubt {
            let keep = doubt.advice.reason == .sameFolder ? [] : [key(.keep, "Keep this folder", .secondary)]
            let better = doubt.advice.swaps ? [key(.swap, "Swap the two folders", .primary)]
                : doubt.advice.instead.map { [key(.accept(doubt.folder), "Use folder “%@”", .primary, arguments: [folderLabel($0)])] } ?? []
            return [key(.cancel, "Cancel", .back)] + keep + better
        }
        let back = key(.cancel, cancelTitle, .back, enabled: move?.canCancel != false)
        if folderName != nil {
            return [back, key(.create, "Continue", .primary, enabled: folderName.map(CloudDriveFolders.validName) == true)]
        }
        if swapOffered {
            return [back, key(.keep, "Keep as it is", .secondary), key(.swap, "Swap the two folders", .primary, enabled: folderControlsReady)]
        }
        return [back] + (showsPrimary ? [key(.primary, primaryTitle, .primary, enabled: primaryEnabled)] : [])
    }

    /// The two folders answer each other's question: one key puts both right.
    var swapOffered: Bool {
        draft.step == .folder && browsing == nil && work?.kind != .discover && firstAdvice?.advice.swaps == true
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
            canOpen: canOpen, onStep: openStep, press: handleAssistantInput,
            actions: bar, focusedAction: AnyHashable(focusedTarget), onFocusAction: hoverBar
        ) {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
                if browsing != nil { browser }
                else {
                    switch draft.step {
                    case .account: account
                    case .folder: folders
                    case .verify: ready
                    }
                }
                problems
            }
        }
    }

    private var heading: String {
        if let browsing { return questionText(browsing) }
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
            return text((sources == nil && newSources == nil) || (library == nil && newLibrary == nil) ? "Choose what is missing, or continue."
                        : "Oort found these. If they are right, continue.")
        case .verify: return nil
        }
    }

    func questionText(_ folder: Folder) -> String {
        text(folder == .sources ? "Where are your ROMs?" : "Where should your games go?")
    }

    func expectation(_ folder: Folder) -> String {
        text(folder == .sources ? "The folder with your .nsp, .xci or .nup game files. Oort changes nothing there unless you ask."
             : "Oort puts its apps there. An empty folder is fine.")
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
        Text(verbatim: text).seleneFont(.row).foregroundColor(SeleneTheme.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    func progress(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            OortReadout(text: text(key), preset: .lead)
            OortMeter(share: nil, fill: CloudLibraryStatus.pending.color)
        }
    }

    func input<V: View>(_ target: Target, @ViewBuilder content: () -> V) -> some View {
        content().modifier(SeleneFieldSurface(focused: focusedTarget == target, font: .row))
    }

    func option<Trailing: View>(_ target: Target, _ title: String, about: String? = nil, icon: MaterialIcon? = nil,
                                enabled: Bool = true, large: Bool = false, action: @escaping () -> Void,
                                @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) -> some View {
        Button(action: action) {
            SeleneOptionRow(icon: icon, title: title, about: about, focused: focusedTarget == target, enabled: enabled,
                            titleFont: large ? .heading : .row, trailing: trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(OortPressStyle()).disabled(!enabled).seleneHover { if enabled { focus.select(target) } }
    }

    func pill(_ target: Target, _ key: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        OortButton(title: key, focused: focusedTarget == target, state: enabled ? .ready : .blocked, action: action)
            .disabled(!enabled).seleneHover { if enabled { focus.select(target) } }
    }

    /// A key on a card: as large as the bar's, as narrow as its words.
    func cardKey(_ target: Target, _ key: String, arguments: [String] = [], enabled: Bool = true,
                 action: @escaping () -> Void) -> some View {
        OortButton(title: key, arguments: arguments, focused: focusedTarget == target, state: enabled ? .ready : .blocked,
                   preset: .card, action: action)
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
