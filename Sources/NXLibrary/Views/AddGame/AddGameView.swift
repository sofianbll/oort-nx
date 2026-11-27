import SwiftUI
import AppKit
import NXLibraryCore

/// Add game, in Game options' manner: the home stays behind, blurred and lightly
/// shaded, and a centred column (1040u) holds the step's title and glass rows.
/// It opens and closes like Game options and the console (the shell's fade).
///
/// Input: Up/Down move along the rows (the list follows the focus), Left/Right
/// change a switch or a choice, A runs the row, B (or Esc) steps back: out of a
/// field or a dialog, then a step, then closes. During a porting Esc closes at
/// once and the porting goes on. Nothing in the column takes key focus, so a
/// local monitor maps the keys (as Game options does); the controller arrives
/// through `.nxAddGameGamepadAction`. Files can be dropped anywhere on it.
struct AddGameView: View {
    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var cloudLibrary: CloudLibraryModel
    /// The wizard and the live build (`PortingModel`), observed on their own.
    @ObservedObject var porting: PortingModel
    /// The Switch Setup (`SetupModel`): engine, keys and the Metal gate the review checks.
    @ObservedObject var setup: SetupModel
    @ObservedObject var router: AppRouter

    private let showsHints: Bool
    private let artwork: ArtworkStore?
    private let reviewSelectionID: UUID?

    @State private var confirmDiscard = false
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    /// The porting step's actions, published by its view.
    @State var actions: [AddGameAction] = []
    @State var actionsStep = 0
    @State private var focusedID: String?
    @State private var keyMonitor: Any?
    @State private var dropTargeted = false
    @FocusState private var editing: String?

    init(viewModel: AppViewModel, router: AppRouter, artwork: ArtworkStore? = nil, showsHints: Bool = true,
                reviewSelectionID: UUID? = nil) {
        self.viewModel = viewModel
        self.cloudLibrary = viewModel.cloudLibrary
        self.porting = viewModel.porting
        self.setup = viewModel.setup
        self.router = router
        self.artwork = artwork
        self.showsHints = showsHints
        self.reviewSelectionID = reviewSelectionID
    }

    var body: some View {
        let rows = rows(for: porting.buildWizardStep)
        let focused = focusedRow(in: rows)
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if !confirmDiscard { requestClose() } }
            VStack(spacing: 0) {
                column(rows, focused: focused)
                if showsHints {
                    SeleneHintsBar(left: [HintItem(.b, backLabel)], right: [HintItem(.a, aLabel(focused))],
                                   bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
                        .seleneOverlaidHints(confirmDiscard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if confirmDiscard {
                ZStack {
                    SeleneTheme.scrim45.ignoresSafeArea()
                    SeleneConfirmDialog(title: L10n.text("Discard selected sources?"),
                                        message: L10n.text("The files on disk are not changed."),
                                        confirmTitle: L10n.text("Discard"),
                                        cancelTitle: L10n.text("Keep editing"),
                                        destructive: true, focus: $confirmFocus,
                                        onCancel: dismissDiscard,
                                        onConfirm: discardAndClose)
                }
                .transition(.opacity)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: drop)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: confirmDiscard)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: dropTargeted)
        .onAppear(perform: appear)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: reviewSelectionID) { reviewEntryIfReady() }
        .onChange(of: porting.buildWizardStep) { _, step in
            editing = nil
            focusedID = defaultRowID(for: step)
        }
        .onChange(of: porting.canAddSelectedGame) { _, canAdd in
            guard porting.buildWizardStep == 1 else { return }
            reviewEntryIfReady()
            guard porting.buildWizardStep == 1 else { return }
            if canAdd, focusedID == nil || focusedID == "choose" || focusedID == "chooseFiles" { focusedID = "continue" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxAddGameGamepadAction)) { note in
            guard !viewModel.showSetupCheck else { return }
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
    }

    // MARK: - Column

    private func column(_ rows: [AddGameRow], focused: AddGameRow?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("ADD A GAME"))
                .seleneFont(.text, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.leading, canvas.u(SeleneTokens.Space.compact))
            Text(stepTitle)
                .seleneFont(.screen)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.leading, canvas.u(SeleneTokens.Space.tight))
            stepLine
                .padding(.leading, canvas.u(SeleneTokens.Space.compact))
                .padding(.top, canvas.u(SeleneTokens.Space.hairline))
                .padding(.bottom, canvas.u(SeleneTokens.Space.line))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                        if porting.buildWizardStep == 3 {
                            AddGameStepThreeView(viewModel: viewModel, porting: porting, router: router, artwork: artwork,
                                                 onActions: publish)
                                .padding(.bottom, canvas.u(SeleneTokens.Space.small))
                        }
                        ForEach(rows) { row in
                            AddGameRowView(row: row, focused: row.id == focused?.id && !confirmDiscard,
                                           editing: $editing)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture { click(row) }
                        }
                    }
                    // The clip would shave the first row's focus border.
                    .padding(.top, canvas.u(SeleneTokens.Space.tight))
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.hairline))
                    .padding(.bottom, canvas.u(SeleneTokens.Space.large))
                }
                .scrollIndicators(.hidden)
                // Rows fade under the title and into the hints instead of being cut.
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: canvas.u(10))
                        SeleneTheme.artShade
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: canvas.u(28))
                    }
                )
                .onChange(of: focused?.id) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: canvas.u(1040), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas.u(SeleneTokens.Space.pageTop))
        .padding(.bottom, canvas.u(SeleneTokens.Space.large))
        .overlay(alignment: .top) {
            if dropTargeted {
                Text(L10n.text("Drop to add these files"))
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.onFocus)
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.control))
                    .frame(height: canvas.u(34))
                    .background(Capsule().fill(SeleneTheme.focus))
                    .padding(.top, canvas.u(SeleneTokens.Space.dialogInset))
                    .transition(.opacity)
            }
        }
        // Clicks inside the column are not clicks on the shade; only the area outside closes.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var stepTitle: String {
        switch porting.buildWizardStep {
        case 1: return L10n.text("Choose a game")
        case 2: return porting.selectedGame?.name ?? L10n.text("Review")
        default:
            if !viewModel.isBuilding, porting.buildError != nil, let reason = porting.portingFailureReason {
                return reason.title
            }
            let id = viewModel.currentBuildGameID ?? viewModel.lastBuildGameID
            return viewModel.libraryGames.first { $0.id == id }?.name ?? L10n.text("Build")
        }
    }

    /// "Choose · Review · Build", the current step in full ink.
    private var stepLine: some View {
        let step = porting.buildWizardStep
        return HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            // Ryujinx-Nextendo (proposal) reads the files as they are: there is no Build step.
            let steps = setup.readiness?.engine == .ryujinx ? [L10n.text("Choose"), L10n.text("Review")]
                : [L10n.text("Choose"), L10n.text("Review"), L10n.text("Build")]
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Circle().fill(SeleneTheme.ink25).frame(width: canvas.u(4), height: canvas.u(4))
                }
                Text(title)
                    .seleneFont(.text, index + 1 == step ? .semibold : .regular)
                    .foregroundColor(index + 1 == step ? SeleneTheme.ink : SeleneTheme.ink60)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Step %@ of 3", [String(describing: step)]))
    }

    // MARK: - Focus

    private func focusedRow(in rows: [AddGameRow]) -> AddGameRow? {
        let focusable = rows.filter(\.focusable)
        if let id = focusedID, let row = focusable.first(where: { $0.id == id }) { return row }
        let preferred = defaultRowID(for: porting.buildWizardStep)
        return focusable.first { $0.id == preferred } ?? focusable.first
    }

    private func move(by delta: Int) {
        let focusable = rows(for: porting.buildWizardStep).filter(\.focusable)
        guard !focusable.isEmpty else { return }
        let currentID = focusedRow(in: focusable)?.id
        let current = focusable.firstIndex { $0.id == currentID } ?? 0
        let next = min(max(current + delta, 0), focusable.count - 1)
        focusedID = focusable[next].id
        if next != current { SoundEffectService.shared.play(.focus) }
    }

    private func horizontal(by delta: Int) {
        guard let row = focusedRow(in: rows(for: porting.buildWizardStep)) else { return }
        switch row.kind {
        case .toggle(let isOn):
            guard row.enabled else { return SoundEffectService.shared.play(.error) }
            let value = delta > 0
            guard isOn.wrappedValue != value else { return }
            isOn.wrappedValue = value
            SoundEffectService.shared.play(.key)
        case .choice(let values, let index, let select):
            let next = min(max(index + delta, 0), values.count - 1)
            guard next != index else { return }
            select(next)
            SoundEffectService.shared.play(.key)
        default:
            break
        }
    }

    private func activate(_ row: AddGameRow) {
        switch row.kind {
        case .action(let perform):
            guard row.enabled else { return SoundEffectService.shared.play(.error) }
            SoundEffectService.shared.play(.click)
            // Out of the key event first: an open panel (Choose folder) runs its own loop.
            DispatchQueue.main.async { perform() }
        case .toggle(let isOn):
            guard row.enabled else { return SoundEffectService.shared.play(.error) }
            isOn.wrappedValue.toggle()
            SoundEffectService.shared.play(.key)
        case .choice(let values, let index, let select):
            guard !values.isEmpty else { return }
            select((index + 1) % values.count)
            SoundEffectService.shared.play(.key)
        case .field:
            editing = row.id
            SoundEffectService.shared.play(.click)
        case .warning(let action):
            guard let action else { return }
            SoundEffectService.shared.play(.click)
            action()
        case .heading, .note:
            break
        }
    }

    private func click(_ row: AddGameRow) {
        guard row.focusable, !confirmDiscard else { return }
        focusedID = row.id
        activate(row)
    }

    private func publish(_ actions: [AddGameAction]) {
        self.actions = actions
        actionsStep = 3
    }

    // MARK: - Hints

    private var previousWizardStep: Int? {
        PortingModel.stepBack(from: porting.buildWizardStep, isBuilding: viewModel.isBuilding,
                              succeeded: porting.buildSuccessPath != nil, hasSelectedGame: porting.selectedGame != nil)
    }

    private var backLabel: String {
        if editing != nil { return "Done" }
        if viewModel.isBuilding { return "Hide" }
        return previousWizardStep != nil ? "Back" : "Close"
    }

    private func aLabel(_ row: AddGameRow?) -> String {
        guard let row else { return "Select" }
        switch row.kind {
        case .toggle: return "Switch"
        case .choice: return "Change"
        case .field: return editing == row.id ? "Done" : L10n.text("Edit")
        case .action: return row.title
        default: return "Select"
        }
    }

    // MARK: - Open and close

    private func appear() {
        installKeyMonitor()
        focusedID = defaultRowID(for: porting.buildWizardStep)
        reviewEntryIfReady()
    }

    private func reviewEntryIfReady() {
        guard !viewModel.showSetupCheck, porting.consumePreparedReviewEntry(reviewSelectionID) else { return }
        goToReview()
    }

    /// Show the ongoing port on return unless a game was explicitly requested.
    private func close(then finish: () -> Void) {
        editing = nil
        if router.pendingSpotlightSelect == nil, let id = viewModel.portingGameID {
            router.requestSpotlightSelect(id)
        }
        finish()
    }

    // MARK: - Input

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard router.route == .addGame,
                  !NativeMenuCommands.shared.isTracking,
                  !viewModel.showSetupCheck,
                  !router.isMenuPresented,
                  viewModel.gameToClose == nil,
                  viewModel.gameToRemove == nil,
                  viewModel.gameWithInstallFailure == nil,
                  !viewModel.shellDialogOwnsInput,
                  !viewModel.isWelcomeOpen,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return event }
            // Typing in a field: Return, Tab and Esc end the editing; everything else types.
            if window.firstResponder is NSText {
                guard [36, 76, 48, 53].contains(event.keyCode) else { return event }
                editing = nil
                window.makeFirstResponder(nil)
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
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
            handleGamepad(action)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleGamepad(_ action: GamepadAction) {
        if confirmDiscard {
            switch action {
            case .navigateLeft, .navigateRight:
                let next: SeleneConfirmButton = action == .navigateLeft ? .left : .right
                if confirmFocus != next {
                    confirmFocus = next
                    SoundEffectService.shared.play(.focus)
                }
            case .confirm:
                SoundEffectService.shared.play(.click)
                confirmFocus == .confirm ? discardAndClose() : dismissDiscard()
            case .cancel:
                dismissDiscard()
            default:
                break
            }
            return
        }
        // A controller while a field is being typed in: A or B ends the editing.
        if editing != nil {
            if action == .cancel || action == .confirm {
                editing = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            return
        }
        switch action {
        case .navigateUp: move(by: -1)
        case .navigateDown: move(by: 1)
        case .jumpToStart: move(by: -10_000)
        case .jumpToEnd: move(by: 10_000)
        case .navigateLeft: horizontal(by: -1)
        case .navigateRight: horizontal(by: 1)
        case .confirm:
            if let row = focusedRow(in: rows(for: porting.buildWizardStep)) { activate(row) }
        case .cancel: handleBack()
        case .menu: router.isMenuPresented = true
        case .menuHold: router.openSettings(.startUp)
        default: break
        }
    }

    private func handleBack() {
        if confirmDiscard { return dismissDiscard() }
        if let step = previousWizardStep {
            SoundEffectService.shared.play(.back)
            withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                porting.goToWizardStep(step)
            }
        } else {
            requestClose()
        }
    }

    /// A running porting goes on and the home shows its tile.
    private func requestClose() {
        if PortingModel.closingAsks(isBuilding: viewModel.isBuilding, succeeded: porting.buildSuccessPath != nil,
                                    hasDraft: porting.selectedGameFolder != nil || !porting.selectedSources.isEmpty) {
            confirmFocus = .cancel
            confirmDiscard = true
            SoundEffectService.shared.play(.alert)
        } else {
            close { leave() }
        }
    }

    private func dismissDiscard() {
        confirmDiscard = false
        confirmFocus = .cancel
    }

    private func leave() {
        porting.addGameDidLeave()
        router.back()
    }

    private func discardAndClose() {
        dismissDiscard()
        close {
            porting.startNewAddGame()
            leave()
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard porting.buildWizardStep == 1, !confirmDiscard, !viewModel.isBuilding,
              viewModel.settingsNotice == nil else { return false }
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { urls.append(url); group.leave() } } else { group.leave() }
            }
        }
        group.notify(queue: .main) {
            guard router.route == .addGame, porting.buildWizardStep == 1,
                  !confirmDiscard, viewModel.settingsNotice == nil else { return }
            if !urls.isEmpty { viewModel.handleDroppedURLs(urls) }
        }
        return true
    }
}
