import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// Game options → Mods: file mods apply on Play; code mods may require Rebuild.
///
/// Input: Up/Down move, A (Return, Space) switches a mod or activates an action, Left/Right move the focused mod up or
/// down, Y (Delete, or a click on the Remove hint) moves it to the Trash after a confirmation, B (or Esc) returns. A
/// click activates a row.
struct ModsPanel: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let online: Bool
    let onRebuild: () -> Void
    let onClose: () -> Void

    @State private var mods: [LocalMod] = []
    @State private var conflicts: [ModConflict] = []
    @State private var conflictRefresh: Task<Void, Never>?
    @State private var needsRebuild = false
    @State private var importing = false
    @State private var running: Bool
    @State private var focus = FocusIndex()
    @State private var confirmRemove: String?
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    /// The last refusal or failed write, one sentence; cleared by the next action.
    @State private var message: String?
    @State private var keyMonitor: Any?

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.nxAppLocale) private var locale

    private typealias Row = ModsPanelPresentation.Row

    init(viewModel: AppViewModel, game: PortedGame, online: Bool,
         onRebuild: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.game = game
        self.online = online
        self.onRebuild = onRebuild
        self.onClose = onClose
        _running = State(initialValue: RunningGameMonitor.runningApplication(for: game) != nil)
    }

    private var store: ModStore? { viewModel.modStore(for: game) }

    private var presentation: ModsPanelPresentation { ModsPanelPresentation(mods: mods, needsRebuild: needsRebuild) }

    private var focusedRow: Row? {
        let rows = presentation.rows
        return rows.indices.contains(focus.index) ? rows[focus.index] : nil
    }

    private var inactiveOnlineCodeMods: Set<String> {
        guard online else { return [] }
        return Set(mods.filter { $0.isOn && $0.exefs != nil }.map(\.folderName))
    }

    private var focusedMod: LocalMod? {
        guard case .mod(let name)? = focusedRow else { return nil }
        return mods.first { $0.folderName == name }
    }

    // MARK: - Body

    @Environment(\.oortSettingsPane) private var embedding

    var body: some View {
        let inactiveOnline = inactiveOnlineCodeMods
        return ZStack {
            if embedding == nil {
                SeleneTheme.scrim65.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { close() }
            }
            OortSettingsPaneLayout(back: close, hints: hints, locked: confirmRemove != nil) {
                Text(L10n.text("MODS"))
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.leading, canvas.u(SeleneTokens.Space.compact))
                Text(game.name)
                    .seleneFont(.screen)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                    .padding(.leading, canvas.u(SeleneTokens.Space.tight))
            } content: {
                Text(ModsCopy.header(on: mods.filter(\.isOn).count, total: mods.count))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.leading, canvas.u(SeleneTokens.Space.compact))
                    .padding(.bottom, canvas.u(SeleneTokens.Space.line))
                noticeArea(hasInactiveOnlineMods: !inactiveOnline.isEmpty)
                list(presentation, inactiveOnline: inactiveOnline)
            }
            .seleneOverlayOwnership(confirmRemove == nil)

            if let name = confirmRemove {
                confirmOverlay(name)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: confirmRemove)
        .onAppear {
            sync(preservingFocus: false)
            installKeyMonitor()
        }
        .onDisappear {
            conflictRefresh?.cancel()
            removeKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        // A mod added or removed in Finder, or the game quitting, shows when Arcane comes back.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in sync() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in sync() }
    }

    private var hints: [HintItem] {
        guard let mod = focusedMod else { return [HintItem(.a, L10n.text("Select"))] }
        var items = [HintItem(.move, "Move"), HintItem(.y, L10n.text("Remove"), action: askRemove)]
        items.append(HintItem(.a, !mod.isMod ? L10n.text("Select") : mod.isOn ? L10n.text("Turn off") : L10n.text("Turn on")))
        return items
    }

    @ViewBuilder private func noticeArea(hasInactiveOnlineMods: Bool) -> some View {
        let notices = (hasInactiveOnlineMods ? [L10n.text("Code mods off", context: locale)] : [])
            + (running ? [ModsCopy.running(gameName: game.name)] : [])
            + (needsRebuild ? [L10n.text("Rebuild to apply code mod changes.", context: locale)] : [])
        if !notices.isEmpty || message != nil || !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                ForEach(notices, id: \.self) { notice in
                    Label { Text(notice).fixedSize(horizontal: false, vertical: true) } icon: { MaterialIconView(.info, size: 20) }
                        .seleneFont(.text)
                        .foregroundColor(SeleneTheme.ink75)
                }
                ForEach(conflicts, id: \.message) { conflict in
                    Label { Text(conflict.message).fixedSize(horizontal: false, vertical: true) } icon: { MaterialIconView(.swap, size: 20) }
                        .seleneFont(.text)
                        .foregroundColor(SeleneTheme.ink75)
                }
                if let message {
                    Text(message)
                        .seleneFont(.text, .medium)
                        .foregroundColor(SeleneTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
            .padding(.bottom, canvas.u(SeleneTokens.Space.line))
        }
    }

    private func list(_ presentation: ModsPanelPresentation, inactiveOnline: Set<String>) -> some View {
        let rows = presentation.rows
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                    if mods.isEmpty {
                        SeleneOptionRow(icon: nil, title: L10n.text("No mods yet"), about: ModsCopy.empty, focused: false, enabled: false) {}
                    }
                    ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                        if row == presentation.fileRows.first {
                            sectionHeader("File mods", subtitle: online
                                ? "File mods may block online trades. Re-enable them in Mods."
                                : "Apply at the next launch.")
                        }
                        if row == presentation.codeRows.first {
                            sectionHeader("Code mods", subtitle: "Rebuild the game after making changes. Turning off all code mods or re-enabling the entire built set needs no rebuild. Inactive online (Nextendo).")
                        }
                        rowView(row, focused: embedding?.active.wrappedValue != false && index == focus.index,
                                inactiveOnline: inactiveOnline)
                            .padding(.top, row == .openFolder ? canvas.u(8) : 0)
                            .id(row)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focus.index = index
                                activate(row)
                            }
                    }
                }
                .padding(.top, canvas.u(SeleneTokens.Space.tight))
                .padding(.bottom, canvas.u(SeleneTokens.Space.large))
                .animation(reduceMotion ? nil : SeleneTheme.quick, value: mods)
            }
            .scrollIndicators(.hidden)
            .onChange(of: focus.index) { _, index in
                guard rows.indices.contains(index) else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(rows[index], anchor: .center) }
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
            Text(L10n.text(title, context: locale))
                .seleneFont(.text, .semibold)
                .foregroundColor(ThemeStore.shared.palette.id == SelenePaletteCatalog.classicBlueID ? SeleneTheme.ink75 : SeleneTheme.glyph)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text(subtitle, context: locale))
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink60)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, canvas.u(SeleneTokens.Space.large))
        .padding(.top, canvas.u(SeleneTokens.Space.medium))
        .padding(.trailing, canvas.u(SeleneTokens.Space.large))
    }

    private func rowView(_ row: Row, focused: Bool, inactiveOnline: Set<String>) -> some View {
        let text = describe(row)
        let inactiveBadge: String?
        if case .mod(let name) = row {
            inactiveBadge = inactiveOnline.contains(name) ? L10n.text("Inactive online", context: locale) : nil
        } else {
            inactiveBadge = nil
        }
        return SeleneOptionRow(icon: text.icon, title: text.title, about: text.about, focused: focused,
                               enabled: text.enabled) {
            if let inactiveBadge { SeleneValueChip(text: inactiveBadge) }
            if let isOn = text.isOn {
                SeleneSwitch(isOn: .constant(isOn)).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text.title, inactiveBadge, text.about].compactMap { $0 }.joined(separator: ". "))
        .accessibilityValue(text.isOn.map { $0 ? L10n.text("On") : L10n.text("Off") } ?? "")
        .accessibilityAddTraits(.isButton)
    }

    private func describe(_ row: Row) -> (icon: MaterialIcon?, title: String, about: String?, isOn: Bool?, enabled: Bool) {
        switch row {
        case .mod(let name):
            guard let mod = mods.first(where: { $0.folderName == name }) else { return (nil, name, nil, nil, false) }
            if !mod.isMod {
                let isFolder = (try? mod.folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return (.puzzle, name, isFolder ? ModsCopy.notAMod : ModsCopy.notAFolder, nil, false)
            }
            if name.contains(":") { return (.puzzle, name, ModsCopy.colon, nil, false) }
            return (.puzzle, name, nil, mod.isOn, !running && !importing)
        case .importCode:
            return (.folder, L10n.text("Import code mod"), L10n.text("Copy a folder with exefs patches. The original stays in place."), nil, !running && !importing)
        case .openFolder:
            return (.folder, L10n.text("Open mods folder"), L10n.text("Put each mod in its own folder here."), nil, true)
        case .rebuild:
            let about = GameResourceState.sourcesAvailable(for: game)
                ? L10n.text("Build a new app; the old app stays if the build fails.")
                : L10n.text("Game files are missing or not attached. Attach them to rebuild.")
            return (.build, L10n.text("Rebuild"), about, nil, !running && !importing)
        }
    }

    private func confirmOverlay(_ name: String) -> some View {
        ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissConfirm() }
            SeleneConfirmDialog(title: L10n.format("Move %@ to the Trash?", [String(describing: name)]),
                                message: L10n.text("The game stops loading it. You can put it back from the Trash."),
                                confirmTitle: L10n.text("Move to Trash"), focus: $confirmFocus,
                                onCancel: dismissConfirm, onConfirm: runRemove)
        }
    }

    // MARK: - Actions

    private func reload(preservingFocus: Bool = true) {
        let previousRow = preservingFocus ? focusedRow : nil
        running = RunningGameMonitor.runningApplication(for: game) != nil
        let store = store
        mods = store?.mods() ?? []
        needsRebuild = store?.codeModsNeedRebuild(app: game.url, build: game.lastBuild) == true
        let rows = presentation.rows
        focus.index = previousRow.flatMap { rows.firstIndex(of: $0) } ?? GameOptionsFocus.clamped(focus.index, count: rows.count)
        conflictRefresh?.cancel()
        guard let store else { conflicts = []; return }
        let engineFolder = viewModel.setup.nxnativePath
        conflictRefresh = Task { @MainActor in
            let merges = await InstalledEngineCapabilities.shared.mergesTrpfd(
                in: game.url, engineFolder: engineFolder, gameData: store.supportFolder)
            guard !Task.isCancelled else { return }
            conflicts = store.conflicts(mergesTrpfd: merges)
        }
    }

    /// Re-reads the folder and lets the store drop mods that are gone (only while the game is not running).
    private func sync(preservingFocus: Bool = true) {
        guard !importing else { return }
        if let store, let failure = viewModel.performModChange({ try store.sync() }) { message = failure }
        reload(preservingFocus: preservingFocus)
    }

    private func activate(_ row: Row) {
        message = nil
        switch row {
        case .mod(let name):
            guard let mod = mods.first(where: { $0.folderName == name }) else { return }
            change(click: true) { try $0.setOn(!mod.isOn, folderName: name) }
        case .importCode:
            importCodeMod()
        case .openFolder:
            guard let folder = store?.modsFolder else {
                SoundEffectService.shared.play(.error)
                return
            }
            SoundEffectService.shared.play(.click)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            viewModel.revealInFinder(url: folder)
        case .rebuild:
            guard !running, !importing else {
                SoundEffectService.shared.play(.error)
                return
            }
            onRebuild()
        }
    }

    private func importCodeMod() {
        guard let store, store.isWritable, !importing else {
            SoundEffectService.shared.play(.error)
            return
        }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Import code mod")
        panel.prompt = L10n.text("Add")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        importing = true
        Task { @MainActor in
            let outcome = Task.detached(priority: .userInitiated) { () -> String? in
                do { try store.importCodeMod(from: folder); return nil }
                catch let error as ModStoreError { return AppViewModel.modMessage(error) }
                catch { return ModInstallError.writeFailed(error.localizedDescription).message }
            }
            let error = await outcome.value
            importing = false
            message = error
            reload()
            if error == nil { SoundEffectService.shared.play(.success) }
            else { SoundEffectService.shared.play(.error) }
        }
    }

    private func moveFocusedMod(by offset: Int) {
        guard let mod = focusedMod else { return }
        message = nil
        let before = focus
        guard change(click: false, { try $0.move(folderName: mod.folderName, by: offset) }) else { return }
        if focus != before { SoundEffectService.shared.play(.focus) }
    }

    private func askRemove() {
        guard let mod = focusedMod else { return }
        message = nil
        guard !running, !importing, RunningGameMonitor.runningApplication(for: game) == nil else {
            reload()
            SoundEffectService.shared.play(.error)
            return
        }
        confirmFocus = .cancel
        confirmRemove = mod.folderName
        SoundEffectService.shared.play(.click)
    }

    private func runRemove() {
        guard let name = confirmRemove else { return }
        confirmRemove = nil
        if change(click: false, { try $0.remove(folderName: name) }) { SoundEffectService.shared.play(.success) }
    }

    private func dismissConfirm() {
        confirmRemove = nil
        SoundEffectService.shared.play(.focus)
    }

    /// True when the change is on disk.
    @discardableResult
    private func change(click: Bool, _ edit: (ModStore) throws -> Void) -> Bool {
        guard let store, !importing else {
            SoundEffectService.shared.play(.error)
            return false
        }
        defer { reload() }
        if let failure = viewModel.performModChange({ try edit(store) }) {
            message = failure
            if failure == AppViewModel.modMessage(.notAllowed) { running = true }
            SoundEffectService.shared.play(.error)
            return false
        }
        if click { SoundEffectService.shared.play(.click) }
        return true
    }

    // MARK: - Input

    private func move(by delta: Int) {
        let previous = focus
        focus.move(by: delta, count: presentation.rows.count)
        if focus != previous { SoundEffectService.shared.play(.focus) }
    }

    private func close() {
        SoundEffectService.shared.play(.focus)
        onClose()
        embedding?.onBack()
    }

    private func moveConfirmFocus(_ to: SeleneConfirmButton) {
        guard confirmFocus != to else { return }
        confirmFocus = to
        SoundEffectService.shared.play(.focus)
    }

    private func handleGamepad(_ action: GamepadAction) {
        guard embedding?.active.wrappedValue != false else { return }
        if confirmRemove != nil {
            switch action {
            case .navigateLeft: moveConfirmFocus(.left)
            case .navigateRight: moveConfirmFocus(.right)
            case .confirm: confirmFocus == .confirm ? runRemove() : dismissConfirm()
            case .cancel: dismissConfirm()
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: move(by: -1)
        case .navigateDown: move(by: 1)
        case .navigateLeft: moveFocusedMod(by: -1)
        case .navigateRight: moveFocusedMod(by: 1)
        case .confirm:
            if let focusedRow { activate(focusedRow) }
        case .contextAction: askRemove()
        case .cancel: close()
        default: break
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard embedding?.active.wrappedValue != false, viewModel.gameForSettingsSheet?.id == game.id,
                  !viewModel.cloudQuitRequested,
                  viewModel.gameWithInstallFailure == nil, viewModel.settingsNotice == nil,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil, !(window.firstResponder is NSText) else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 36, 76, 49: action = .confirm
            case 51, 117: action = .contextAction
            case 53: action = .cancel
            default: return event
            }
            handleGamepad(action)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// The Mods panel's sentences.
enum ModsCopy {
    static func header(on: Int, total: Int) -> String {
        switch (on, total) {
        case (_, 0): return L10n.text("No mods in this game's folder")
        case (0, _): return total == 1 ? L10n.text("1 mod, off") : L10n.format("%@ mods, all off", [String(describing: total)])
        default: return L10n.format("%@ of %@ on", [String(on), String(total)])
        }
    }

    static func running(gameName: String) -> String { L10n.format("%@ is running. Quit it to change its mods.", [String(describing: gameName)]) }

    static var empty: String {
        L10n.text("Open the mods folder to add RomFS mods, or import a code mod.")
    }
    static var notAMod: String {
        L10n.text("Not a mod: needs romfs or exefs patches.")
    }
    static var notAFolder: String {
        L10n.text("Not a mod: unzip it into its own folder first.")
    }
    static var colon: String {
        L10n.text("Rename this folder: its name can't contain ':'.")
    }
}
