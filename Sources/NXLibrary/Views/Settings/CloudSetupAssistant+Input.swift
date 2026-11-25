import AppKit
import NXLibraryCore
import ArcanePorting

extension CloudSetupAssistant {
    var focusedTarget: Target { focus.current(in: focusRows, rail: focusRail) }
    var focusedStep: Int? {
        if case .step(let step) = focusedTarget { return step }
        return nil
    }

    /// Only steps already done can be reopened, and never under a running sign-in, creation or move.
    func canOpen(_ step: Int) -> Bool {
        guard step < draft.step.rawValue, move == nil, !movePaused, work?.kind != .create, !waitingForGoogle, browsing == nil else { return false }
        return step > 0 || !isDirect
    }

    var focusRail: [Target] {
        guard doubt == nil, creation == nil, !confirmingMove, !confirmingLibrary, folderName == nil, typedPath == nil else { return [] }
        return (0..<3).filter(canOpen).map { .step($0) }
    }

    func openStep(_ step: Int) {
        guard canOpen(step) else { return }
        work?.task.cancel(); work = nil
        issue = nil; moveFailure = nil; moveConflicts = []
        focus.reset()
        if step == 0 {
            replacement = nil
            accountPage = .choose
            draft.backToAccount()
        } else { draft.backToFolders() }
    }

    var focusRows: [[Target]] {
        if doubt != nil { return [[.cancel]] }
        if movePaused { return [[.cancel]] }
        if creation != nil || confirmingLibrary { return [[.create, .cancel]] }
        if confirmingMove { return [[.confirmMove, .cancel]] }
        if folderName != nil { return [[.folderName], (folderName.map(CloudDriveFolders.validName) == true ? [.create] : []) + [.cancel]] }
        if typedPath != nil { return [[.typedPath], (primaryEnabled ? [.primary] : []) + [.cancel]] }
        var rows: [[Target]] = []
        if browsing != nil {
            if folderControlsReady {
                rows = [breadcrumbs.dropLast().map(Target.breadcrumb)
                    + (listing != nil || folderMissing ? [.newFolder] : []) + [.enterPath, .refresh]]
                rows += folderNames.map { [.folder($0)] }
                if listing == nil && work == nil { rows.append([.retry]) }
                if let browsing, listing != nil, !browserPath.isEmpty, advice(browsing, browserPath)?.instead != nil { rows.append([.accept(browsing)]) }
            }
        } else {
            switch draft.step {
            case .account:
                guard work == nil else { break }
                if remotes == nil { rows = [[.retry]] }
                else {
                    switch accountPage {
                    case .choose: rows = [[.haveClient], [.helpCreate]]
                    case .have: rows = [[.guide], [.client], [.secret]]
                    case .help: rows = Self.googleSteps.indices.map { [.link($0)] } + [[.client], [.secret]]
                    }
                }
            case .folder:
                guard folderControlsReady else { break }
                rows = [cardRow(.sources, sources), cardRow(.library, library)]
                if moveOffered { rows.append([.moveGames]) }
            case .verify:
                if work == nil && !draft.verified { rows = [[.retry]] }
            }
        }
        return rows + [(showsPrimary && primaryEnabled ? [.primary] : []) + (move?.canCancel == false ? [] : [.cancel])]
    }

    private func cardRow(_ folder: Folder, _ choice: Choice?) -> [Target] {
        guard let advice = choice.flatMap({ advice(folder, $0.path) }), advice.instead != nil, folder == .sources || !advice.swaps
        else { return [.change(folder)] }
        return [.accept(folder), .change(folder)]
    }

    func perform(_ target: Target) {
        if case .step(let step) = target { openStep(step); return }
        guard focusRows.contains(where: { $0.contains(target) }) else { return }
        switch target {
        case .step: break
        case .cancel: cancel()
        case .primary: primary()
        case .haveClient: openAccountPage(.have)
        case .helpCreate: openAccountPage(.help)
        case .link(let index): openGoogle(index)
        case .guide: openGuide()
        case .client, .secret, .folderName, .typedPath: field = target
        case .enterPath: enterPath()
        case .retry:
            if browsing != nil { retryFolder() }
            else if draft.step == .verify { verify() }
            else { inspect() }
        case .change(let folder): openBrowser(folder)
        case .accept(let folder):
            let path = browsing == nil ? (folder == .sources ? sources : library)?.path : browserPath
            guard let advice = path.flatMap({ advice(folder, $0) }), let instead = advice.instead else { return }
            if advice.swaps, browsing == nil { swapFolders() } else { accept(folder, instead) }
        case .breadcrumb(let path): browse(path)
        case .folder(let name): browse(CloudDriveFolders.joining(browserPath, name))
        case .refresh: browse(browserPath)
        case .newFolder: nameFolder()
        case .moveGames: draft.toggleMove()
        case .confirmMove: moveGames()
        case .create:
            if let creation { create(creation) }
            else if confirmingLibrary { createLibrary() }
            else { proposeCreation() }
        }
    }

    func primary() {
        guard primaryEnabled else { return }
        if browsing != nil { chooseFolder(); return }
        switch draft.step {
        case .account:
            if !accountNeedsClient, let existing { selectAccount(existing.name) }
            else { connect() }
        case .folder:
            if let wrong = firstAdvice { doubt = wrong; doubtFocus = 0 }
            else if library == nil { proposeLibrary() } else { finishFolders() }
        case .verify:
            if draft.activation != nil { activate() }
            else if draft.wantsMove { focus.reset(); confirmingMove = true }
        }
    }

    func cancel() {
        field = nil; focus.reset()
        if doubt != nil { doubt = nil; return }
        if creation != nil { creation = nil; return }
        if confirmingLibrary { confirmingLibrary = false; return }
        if confirmingMove { confirmingMove = false; return }
        if let move { viewModel.cancelLibraryMove(move.id); return }
        if model.hasPendingMove { onClose(); return }
        if typedPath != nil { typedPath = nil; focus.select(.enterPath); return }
        if folderName != nil { folderName = nil; return }
        if work?.kind == .create { return }
        if waitingForGoogle { work?.task.cancel(); work = nil; return }
        if let browsing, !isDirect {
            closeBrowser()
            focus.select(.change(browsing))
            return
        }
        if browsing == nil {
            if draft.step == .verify { openStep(1); return }
            if draft.step == .folder, !isDirect { openStep(0); return }
            if draft.step == .account, accountNeedsClient, work == nil {
                accountPage = .choose; client = ""; secret = ""; issue = nil
                return
            }
        }
        work?.task.cancel()
        onClose()
    }

    func start(_ kind: Work, _ operation: @escaping @MainActor () async throws -> Void) {
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

    func finishFolders() {
        field = nil
        discoveryUnknown = false
        if draft.useFolder() { focus.reset(); verify() }
    }

    func verify() {
        guard let service, draft.step == .verify else { return }
        let path = draft.path, ticket = draft.renewTicket()
        let rom = onboarding || sourcesChanged ? sourcesOverride : nil
        start(.verify) {
            try await service.verifyAccess(to: path)
            try await service.verifyPersonalFolder(path)
            if let rom, rom != path {
                try await service.verifyAccess(to: rom)
                try await service.verifyPersonalFolder(rom)
            }
            if !Task.isCancelled { draft.acceptAccessCheck(ticket) }
        }
    }

    func activate() {
        guard let preference = draft.activation else { return }
        do {
            let replaced = replacement != nil
            try replacement?.apply()
            let rom = onboarding || sourcesChanged ? sourcesOverride : model.preference.sourcesRootOverride
            model.configure(remote: preference.remote, root: preference.root, enabled: true, sourcesRoot: rom,
                            reload: replaced, confirmLibrary: true)
            model.connectionCheck = .init(date: .now, failure: nil)
            completeActivation()
        } catch {
            issue = RcloneConfiguration.Failure.configuration.key
        }
    }

    private func completeActivation() {
        activated = true
        onClose()
        viewModel.showSettingsNotice(title: text("Cloud library"),
                                     message: text("Your cloud games will appear in Library → Cloud."),
                                     cancelTitle: "Close")
    }

    func moveGames() {
        guard confirmingMove, draft.wantsMove, primaryEnabled, let movePlan, let tool,
              tool == model.resolvedDriveTool, replacement == nil else { return }
        confirmingMove = false; focus.reset(); moveConflicts = []; issue = nil; moveFailure = nil
        moveID = viewModel.startLibraryMove(.init(plan: movePlan, destination: draft.path)) {
            moveConflicts = $0
        }
    }

    func moveEnded(_ previous: UUID?, _ current: UUID?) {
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
            // The move keeps the ROM folder where it was; another one chosen here is applied once it is done.
            if sourcesChanged, sourcesOverride != model.preference.sourcesRootOverride { model.chooseSourcesRoot(sourcesOverride) }
            completeActivation()
        }
    }

    func moveAssistantFocus(_ direction: CloudSetupAssistantFocus.Direction) {
        focus.move(direction, in: focusRows, rail: focusRail)
        switch focusedTarget {
        case .client, .secret, .folderName, .typedPath: field = focusedTarget
        default: field = nil
        }
    }

    func handleAssistantInput(_ action: GamepadAction) {
        guard viewModel.router?.isMenuPresented != true, !viewModel.cloudQuitRequested else { return }
        if doubt != nil {
            switch action {
            case .navigateLeft: doubtFocus = max(0, doubtFocus - 1)
            case .navigateRight: doubtFocus = min(doubtChoices.count - 1, doubtFocus + 1)
            case .confirm: if doubtChoices.indices.contains(doubtFocus) { doubtChoices[doubtFocus].perform() }
            case .cancel: cancel()
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: moveAssistantFocus(.up)
        case .navigateDown: moveAssistantFocus(.down)
        case .navigateLeft: moveAssistantFocus(.left)
        case .navigateRight: moveAssistantFocus(.right)
        case .confirm: perform(focusedTarget)
        case .cancel: cancel()
        default: break
        }
    }

    func installAssistantKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window, window.attachedSheet == nil, !window.isSheet,
                  NSApp.modalWindow == nil, !NativeMenuCommands.shared.isTracking,
                  viewModel.router?.isMenuPresented != true, viewModel.router?.isPalettePresented != true,
                  !viewModel.cloudQuitRequested,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            let typing = window.firstResponder is NSText
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 123 where !typing: action = .navigateLeft
            case 124 where !typing: action = .navigateRight
            case 36 where !typing, 49 where !typing, 76 where !typing: action = .confirm
            case 53: action = .cancel
            default: return event
            }
            handleAssistantInput(action)
            return nil
        }
    }

    func removeAssistantKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
