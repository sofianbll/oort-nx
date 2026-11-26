import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

struct SavesPanel: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let onClose: () -> Void
    @StateObject private var model: SavePanelModel
    @State private var target: SaveSlot = .account
    @State private var focus = 0
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    /// Opening the settings or the file risks nothing: the question opens on it.
    @State private var cloudFocus: SeleneConfirmButton = .confirm
    @State private var keyMonitor: Any?
    @State private var cloudPrompt = false
    @State private var copyFrom: [LocalProfile] = []
    private enum CopyAnswer: Hashable { case cancel, profile(UUID) }
    @State private var copyFocus = CopyAnswer.cancel
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    private enum Row: CaseIterable, Hashable {
        case open, backup, target, add, refresh, backups, copy

        var icon: MaterialIcon {
            switch self {
            case .open: return .folder
            case .backup: return .save
            case .target: return .swap
            case .add, .copy: return .add
            case .refresh: return .sync
            case .backups: return .history
            }
        }
    }
    init(viewModel: AppViewModel, game: PortedGame, onClose: @escaping () -> Void) {
        self.viewModel = viewModel; self.game = game; self.onClose = onClose
        _model = StateObject(wrappedValue: SavePanelModel(viewModel: viewModel, game: game))
    }
    private var confirming: Bool { model.preview != nil || model.restorePreview != nil || cloudPrompt || model.issue != nil || !copyFrom.isEmpty }
    private var rows: [Row] { Row.allCases.filter { $0 != .copy || !model.saveCopySources.isEmpty } }
    @Environment(\.oortSettingsPane) private var embedding

    var body: some View {
        ZStack {
            if embedding == nil {
                SeleneTheme.scrim65.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { close() }
            }
            OortSettingsPaneLayout(back: close, hints: [HintItem(.a, "Select")], locked: confirming || model.busy) {
                Text(L10n.text("SAVES")).seleneFont(.text, .semibold).foregroundColor(SeleneTheme.ink60)
                    .padding(.leading, canvas.u(SeleneTokens.Space.compact))
                Text(game.name).seleneFont(.screen).foregroundColor(SeleneTheme.ink).lineLimit(1)
                    .padding(.leading, canvas.u(SeleneTokens.Space.tight))
            } content: {
                summary
                saveList
                statusLine
            }
            .seleneOverlayOwnership(!confirming)
            if confirming {
                ZStack {
                    SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { close() }
                    confirmation
                }
                .transition(.opacity)
                .zIndex(1)
            }
            ZStack {
                if model.importSuccess != nil && !confirming {
                    SeleneSuccessNotice(title: L10n.text("Imported successfully"))
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : SeleneTheme.standard, value: model.importSuccess)
            .zIndex(2)
        }
        .onAppear { model.refresh(); installKeyMonitor() }
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil; model.close() }
        .onChange(of: model.preview) { confirmFocus = .cancel }
        .onChange(of: model.restorePreview) { confirmFocus = .cancel }
        .task(id: model.importSuccess) {
            guard model.importSuccess != nil else { return }
            do { try await Task.sleep(nanoseconds: 3_000_000_000) }
            catch { return }
            model.dismissImportSuccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in model.refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
    private var summary: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            Text([game.versionString.map { "v" + $0 }, model.running ? L10n.text("Game running") : SavePresentation.size(model.currentBytes)].compactMap { $0 }.joined(separator: " · "))
                .seleneFont(.text).foregroundColor(SeleneTheme.ink60).lineLimit(1)
            Spacer()
            // Always occupies the same space: refresh never changes header/list geometry.
            ProgressView().controlSize(.small).tint(SeleneTheme.ink60)
                .frame(width: canvas.u(20), height: canvas.u(20))
                .opacity(model.busy ? 1 : 0)
                .accessibilityHidden(!model.busy)
                .accessibilityLabel(L10n.text("Working"))
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
        .padding(.top, canvas.u(SeleneTokens.Space.tight)).padding(.bottom, canvas.u(SeleneTokens.Space.line))
    }
    private var saveList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                        rowView(row, focused: embedding?.active.wrappedValue != false && index == focus)
                            .id(row).contentShape(Rectangle())
                            .onTapGesture { focus = index; activate(row) }
                    }
                }.padding(.top, canvas.u(SeleneTokens.Space.tight)).padding(.bottom, canvas.u(SeleneTokens.Space.large))
            }.scrollIndicators(.hidden)
            .onChange(of: focus) { _, index in
                guard rows.indices.contains(index) else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(rows[index], anchor: .center) }
            }
        }
    }
    private var statusLine: some View {
        Text(model.message ?? " ")
            .seleneFont(.text).foregroundColor(SeleneTheme.ink60)
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: canvas.u(24))
            .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
    }
    private var importValue: String? {
        if model.running { return "Game running" }
        if model.recoveryRequired { return L10n.text("Recovery needed") }
        return model.context?.cloudReason == nil ? nil : L10n.text("Cloud on")
    }
    private func description(_ row: Row) -> (title: String, value: String?, enabled: Bool) {
        switch row {
        case .open: return (L10n.text("Open folder"), nil, model.context != nil && !model.busy)
        case .backup: return (L10n.text("Back up now"), model.running ? L10n.text("Game running") : nil, model.context != nil && !model.running && !model.recoveryRequired && !model.busy)
        case .target: return (L10n.text("Save type"), SavePresentation.slotName(target), model.context != nil && !model.busy && !model.running && !model.recoveryRequired)
        case .add: return (L10n.text("Import save…"), importValue, model.importAction != .unavailable)
        case .refresh: return (model.recoveryRequired ? L10n.text("Retry recovery") : L10n.text("Refresh"), nil, !model.busy)
        case .backups: return (L10n.text("Backup folder"), model.latestBackupDate.map(SavePresentation.date) ?? L10n.text("No backups"), !model.busy)
        case .copy: return (L10n.text("Copy saves from another profile"), nil, model.canMutate && model.currentBytes == 0)
        }
    }
    private func subtitle(_ row: Row) -> String {
        switch row {
        case .open: return L10n.text("Open the current save in Finder.")
        case .backup: return L10n.text("Back up all local users and the device save.")
        case .target: return L10n.text("Destination for imports only.")
        case .add: return L10n.text("Choose a save folder to import.")
        case .refresh: return L10n.text("Check saves and backups again.")
        case .backups: return L10n.text("Open this game's backups in Finder.")
        case .copy: return L10n.text("Only an empty profile can receive a copy of this game's saves.")
        }
    }
    private func rowView(_ row: Row, focused: Bool) -> some View {
        let text = description(row)
        return SeleneOptionRow(icon: row.icon, title: text.title, about: subtitle(row), focused: focused, enabled: text.enabled) {
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                if let value = text.value {
                    Text(value).seleneFont(.text).foregroundColor(SeleneTheme.ink60).lineLimit(1)
                }
                if row == .target {
                    MaterialIconView(.chevronLeft, size: 18)
                    MaterialIconView(.chevron, size: 18)
                } else if row == .add {
                    MaterialIconView(.chevron, size: 20)
                }
            }.foregroundColor(SeleneTheme.ink60)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.title + ". " + subtitle(row)).accessibilityValue(text.value ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate(row) }
    }

    @ViewBuilder private var confirmation: some View {
        if let issue = model.issue {
            SeleneChoiceDialog(title: issue.title, message: issue.message, choices: [L10n.text("Back")],
                               focus: .constant(0), onCancel: close, onChoose: { _ in close() })
        } else if let preview = model.preview, let context = model.context {
            SeleneConfirmDialog(title: L10n.text("Import this save?"),
                                message: SavePresentation.importSummary(preview, version: game.versionString),
                                confirmTitle: L10n.text("Import"), destructive: true, focus: $confirmFocus,
                                onCancel: { if !model.busy { model.cancelPreview() } },
                                onConfirm: { if !model.busy { model.confirmImport() } }) {
                SaveImportDetails(source: preview.source, destination: context.location.directory(preview.slot))
            }
            .disabled(model.busy)
        } else if let snapshot = model.restorePreview?.snapshot {
            SeleneConfirmDialog(title: L10n.text("Restore this backup?"), message: SavePresentation.restoreMessage(snapshot, installedVersion: game.versionString),
                confirmTitle: L10n.text("Restore"), destructive: true, focus: $confirmFocus,
                onCancel: { if !model.busy { model.cancelPreview() } }, onConfirm: { if !model.busy { model.confirmRestore() } }).disabled(model.busy)
        } else if !copyFrom.isEmpty {
            SeleneChoiceDialog(title: L10n.text("Copy saves from another profile"),
                               message: L10n.text("Only an empty profile can receive a copy of this game's saves."),
                               answers: copyChoices, focus: $copyFocus, list: copyFrom.count > 2,
                               onCancel: close, onAnswer: chooseCopySource)
        } else if cloudPrompt {
            SeleneConfirmDialog(title: L10n.text("Cloud saves on"), message: cloudHelp.message + "\n\n" + SavePresentation.cloudNotice, confirmTitle: cloudHelp.button,
                cancelTitle: cloudHelp.button == "OK" ? nil : "Cancel", focus: $cloudFocus, onCancel: { cloudPrompt = false }, onConfirm: resolveCloud)

        }
    }
    private var cloudHelp: (message: String, button: String) {
        switch model.context?.cloudReason {
        case "Arcane → Settings → Cloud saves": return (L10n.text("Turn off Cloud saves in Settings → Cloud saves to import or restore."), "Settings")
        case "the game's env.txt", "the app's env.txt": return (L10n.text("Turn off cloud sync in this configuration file first."), L10n.text("Show file"))
        case "the game's Cloud saves settings": return (L10n.text("Turn off Cloud saves in the game's own settings first."), "OK")
        default: return (L10n.text("Turn off cloud sync in the launch environment first."), "OK")
        }
    }
    private func resolveCloud() {
        cloudPrompt = false
        switch model.context?.cloudReason {
        case "Arcane → Settings → Cloud saves":
            viewModel.gameForSettingsSheet = nil
            viewModel.router?.openSettings(.cloudSaves)
        case "the game's env.txt":
            if let context = model.context { NSWorkspace.shared.activateFileViewerSelecting([context.location.root.appendingPathComponent("env.txt")]) }
        case "the app's env.txt": NSWorkspace.shared.activateFileViewerSelecting([game.url.appendingPathComponent("Contents/Resources/dm/env.txt")])
        default: break
        }
    }
    private func activate(_ row: Row) {
        guard !confirming, description(row).enabled else { return }
        SoundEffectService.shared.play(.click)
        switch row {
        case .open: model.showFolder()
        case .backup: model.backUp()
        case .target: target = target == .account ? .device : .account
        case .add:
            if model.importAction == .cloudSettings { cloudPrompt = true; cloudFocus = .confirm }
            else { model.chooseImport(slot: target) }
        case .refresh: model.refresh()
        case .backups: model.showBackups()
        case .copy: copyFrom = model.saveCopySources; copyFocus = .cancel
        }
    }
    private func close() {
        guard !model.busy else { return }
        if model.issue != nil { model.dismissIssue(); return }
        if model.preview != nil || model.restorePreview != nil { model.cancelPreview(); return }
        if cloudPrompt { cloudPrompt = false; return }
        if !copyFrom.isEmpty { copyFrom = []; return }
        onClose()
        embedding?.onBack()
    }
    /// Two profiles fit beside Cancel; more make a list, Cancel at the bottom.
    private var copyChoices: [DialogAnswer<CopyAnswer>] {
        let choices = copyFrom.map { DialogAnswer(CopyAnswer.profile($0.id), $0.name, .secondary) }
            + [DialogAnswer(.cancel, "Cancel", .back)]
        return copyFrom.count > 2 ? ActionBarOrder.stacked(choices, role: \.role)
            : ActionBarOrder.sorted(choices, role: \.role)
    }
    private func chooseCopySource(_ answer: CopyAnswer) {
        let sources = copyFrom
        copyFrom = []
        if case .profile(let id) = answer, let source = sources.first(where: { $0.id == id }) {
            model.copySaves(from: source)
        }
    }
    private func handle(_ action: GamepadAction) {
        guard embedding?.active.wrappedValue != false else { return }
        if confirming {
            guard !model.busy else { return }
            if !copyFrom.isEmpty {
                switch action {
                case .navigateLeft, .navigateUp, .navigateRight, .navigateDown:
                    let delta = action == .navigateLeft || action == .navigateUp ? -1 : 1
                    copyFocus = ActionBarOrder.move(copyFocus, by: delta, in: copyChoices.map(\.id))
                case .cancel: close()
                case .confirm: chooseCopySource(copyFocus)
                default: break
                }
                return
            }
            switch action {
            case .navigateLeft where cloudPrompt: if cloudHelp.button != "OK" { cloudFocus = .left }
            case .navigateRight where cloudPrompt: cloudFocus = .right
            case .navigateLeft, .navigateRight:
                confirmFocus = action == .navigateLeft ? .left : .right
            case .cancel: close()
            case .confirm:
                if model.issue != nil { model.dismissIssue() }
                else if (cloudPrompt ? cloudFocus : confirmFocus) == .cancel { close() }
                else if model.preview != nil { model.confirmImport() }
                else if model.restorePreview != nil { model.confirmRestore() }
                else if cloudPrompt { resolveCloud() }
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: focus = max(0, focus - 1)
        case .navigateDown: focus = min(max(0, rows.count - 1), focus + 1)
        case .jumpToStart: focus = 0
        case .jumpToEnd: focus = max(0, rows.count - 1)
        case .navigateLeft, .navigateRight:
            if rows.indices.contains(focus), rows[focus] == .target { activate(.target) }
        case .confirm: if rows.indices.contains(focus) { activate(rows[focus]) }
        case .cancel: close()
        default: break
        }
    }
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard embedding?.active.wrappedValue != false, viewModel.gameForSettingsSheet?.id == game.id, let window = event.window,
                  !viewModel.cloudQuitRequested, !viewModel.noticeFocus.isActive,
                  viewModel.gameWithInstallFailure == nil, viewModel.settingsNotice == nil,
                  !window.isSheet, window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText), event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 36, 76, 49: action = .confirm
            case 53: action = .cancel
            default: return event
            }
            handle(action); return nil
        }
    }
}
