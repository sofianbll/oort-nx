import SwiftUI
import OortLibrary
import ArcanePorting

extension Notification.Name {
    static let nxCloudLibraryGamepadAction = Notification.Name("nxCloudLibraryGamepadAction")
}

/// The Details link opens the existing Selene card treatment; both representations of the game share the same job.
struct CloudLibraryPanel: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneShowButtonHints) private var showHints
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var model: CloudLibraryModel
    let game: PortedGame
    @State private var focus: Control?
    @State private var refreshRevision = 0
    @State private var advanced = false
    @State private var freeSelection: CloudFreeSelection?
    @State private var freeFocus: FreeControl = .cancel

    private struct ReadRequest: Equatable {
        let game: PortedGame
        let revision: Int
    }

    private enum Control: Hashable {
        case upload(CloudArtifactKind?), download(CloudArtifactKind), uploadSources, downloadSources
        case free, cancel, refresh, settings, close, advanced, pause, resume, previousApp
        case recover(CloudLibraryFailure, CloudLibraryItem?)
        case retry(UUID)
    }

    private enum FreeControl: Equatable { case item(CloudLibraryItem), cancel, confirm }

    private var state: CloudLibraryState { model.states[game.id] ?? CloudLibraryState() }
    private var interrupted: CloudLibraryModel.Request? {
        guard let head = model.queue.first, head.id == game.id, model.canResume(head.token) else { return nil }
        return head
    }
    private var pausable: UUID? {
        guard let request = model.active?.request, request.id == game.id, model.canPause(request.token) else { return nil }
        return request.token
    }
    private func canChange(_ action: CloudLibraryAction) -> Bool {
        state.action == nil && !state.refreshing && viewModel.canChangeCloudLibrary(action, for: game)
    }
    private var unavailable: String? {
        if model.preference.remote == nil { return "No cloud service is configured." }
        if !model.preference.enabled { return "The cloud library is turned off." }
        if game.titleId.map(SaveLocation.validID) != true { return "This game has no valid title ID." }
        return nil
    }

    var body: some View {
        SeleneOverlay(style: .dialog, onOutside: close) {
            VStack(spacing: 0) {
                card.frame(maxWidth: .infinity, maxHeight: .infinity)
                SeleneHintsBar(left: [HintItem(.b, "Close", action: close)],
                               right: actionHints)
            }
            .seleneOverlayOwnership(freeSelection == nil)
            if let freeSelection { freeDialog(freeSelection) }
        }
        .task(id: ReadRequest(game: game, revision: refreshRevision)) { await viewModel.refreshCloudLibrary(game) }
        .onChange(of: controls) { _, controls in
            if let focus, controls.contains(focus) { return }
            focus = startControl
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxCloudLibraryGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    private var actionHints: [HintItem] {
        switch focus ?? startControl {
        case .pause: return [HintItem(.a, "Pause") { choose(.pause) }]
        case .resume: return [HintItem(.a, "Resume") { choose(.resume) }]
        case .none: return []
        default: return [HintItem(.a, "Select")]
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                Text(text("Cloud library")).seleneFont(.heading, .semibold)
                    .foregroundColor(SeleneTheme.ink).accessibilityAddTraits(.isHeader)
                Text(game.name).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                    .lineLimit(1)
                if state.referenceUnverified || state.referenceSourcesUnverified {
                    Text(text("Reference offer not verified")).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                } else if !state.referenceKinds.isEmpty || state.referenceSources != nil {
                    Text(text("Source: reference library")).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                }
            }
            if let unavailable {
                Text(text(unavailable)).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
            } else {
                ForEach(visibleItems, id: \.self) { item in
                    artifactRow(item)
                }
            }
            if let message = state.message {
                failureLine(message, failure: state.failure, item: nil)
            } else if let failure = model.checkFailure, interrupted == nil, state.issue == nil, state.sourcesMessage == nil {
                failureLine(failure.message(context: localization), failure: failure, item: nil)
            }
            if controls.contains(where: { [.close, .settings, .refresh, .free, .upload(nil), .advanced].contains($0) }) {
                OortActionBar(actions: foot, focused: (focus ?? startControl).map(AnyHashable.init), preset: .compact) { id in
                    if let control = id.base as? Control { focus = control }
                }
            }
        }
        .modifier(SeleneDialogCard(width: 920))
    }

    private func artifactRow(_ item: CloudLibraryItem) -> some View {
        let title = text(item.title)
        let copy = item.artifact.flatMap { state.copies[$0] }
        let indicator = CloudLibraryIndicator(state: state, item: item)
        let live = state.activeItem == item && !state.queued
        let reference = !live && !state.queued && !indicator.appPublished ? referenceLine(item) : nil
        let size = state.bytes(item).map(formattedBytes)
        let published = copy?.uploadedAt.map {
            L10n.format("Published %@", [$0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)
                .locale(localization.formatLocale))],
                        context: localization)
        }
        let control = artifactControl(item)
        let interrupted = state.activeItem == item ? self.interrupted : nil
        let interruption = interrupted.flatMap { model.interruption(of: $0.token) }
        let canPause = state.activeItem == item && pausable != nil
        let cannotPause = state.activeItem == item && model.active.map {
            $0.request.id == game.id && model.explainsNoPause($0.request.token)
        } == true
        let personalCopyIsOlder = !live && !state.queued && !indicator.appPublished
            && item.artifact.map(state.personalCopyIsOlder) == true
        let downloadFill = CloudLibraryProgressView.downloadFill(state, item: item)
        let downloading = CloudLibraryProgressView.isDownloading(state, item: item)
        let checkingDownload = state.progress?.phase == .verifying || state.progress?.phase == .restoring
        let ready = downloading && state.progress?.phase == .readyToInstall
        let downloadBytes = downloading ? CloudLibraryProgressView.bytesSummary(state.progress, context: localization) : nil
        let statusText = personalCopyIsOlder ? text("Your cloud copy is older") : indicator.label(context: localization)
        return VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                    Text(title).seleneFont(.text, .semibold).foregroundColor(SeleneTheme.ink90)
                        .accessibilityAddTraits(.isHeader)
                    CloudPersonalAppUpdateRow(
                        comparison: item == .app && state.action == nil ? state.personalAppComparison : nil,
                        keepsStatus: reference != nil || state.issue?.item == item,
                        canUpdate: item == .app && model.hasRestoredQueue && canChange(.restore(.app)),
                        status: SeleneStatusDot(text: downloadBytes.map { statusText + " · " + $0 } ?? reference ?? statusText,
                                    color: indicator.status.color,
                                    labelColor: ready ? SeleneTheme.ink60
                                        : indicator.status == .failed ? PortingPillCopy.softRed : SeleneTheme.ink90,
                                    accessibilityTitle: title, pulses: false)) {
                        viewModel.reviewPersonalAppUpdate(for: game)
                    }
                }
                .multilineTextAlignment(.leading)
                .layoutPriority(1)
                Spacer(minLength: 0)
                if downloadFill == nil {
                    VStack(alignment: .trailing, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                        if live, CloudLibraryProgressView.fraction(state.progress) != nil {
                            Text(CloudLibraryProgressView.summary(state.progress, context: localization, showsPhase: false))
                                .seleneFont(.badge).monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        } else if reference == nil {
                            if let size { Text(size).seleneFont(.text).monospacedDigit() }
                            if !indicator.progress, let published {
                                Text(published).seleneFont(.badge)
                            }
                        }
                    }
                    .foregroundColor(SeleneTheme.ink75)
                    .multilineTextAlignment(.trailing)
                }
                HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    if interrupted != nil { button(.resume, "Resume") }
                    if canPause { button(.pause, "Pause") }
                    if downloading, !checkingDownload, control == .cancel {
                        downloadButton(nil, fill: downloadFill ?? 0, ready: ready)
                    }
                    if let control {
                        switch control {
                        case .cancel: artifactButton(control, "Cancel", icon: .close)
                        case .upload(let kind) where kind.flatMap({ state.copies[$0] })?.canMigrateArchive == true:
                            button(control, "Convert to the new format")
                        case .upload where personalCopyIsOlder: button(control, "Send")
                        case .upload, .uploadSources: artifactButton(control, "Send", icon: .cloudUpload)
                        default: downloadButton(control, fill: 0)
                        }
                    }
                }
                .frame(minWidth: canvas.u(44), minHeight: canvas.u(44), alignment: .trailing)
            }
            if advanced, let path = cloudPath(item) {
                Text(verbatim: path)
                    .seleneFont(.badge)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
            }
            if interrupted?.isUserPaused == true || cannotPause || interruption != nil {
                Text(interrupted?.isUserPaused == true ? text("The current file may restart from the beginning.")
                     : interruption?.message(context: localization) ?? text("This transfer cannot be paused."))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink75).fixedSize(horizontal: false, vertical: true)
            } else if live {
                if state.transfer(for: item)?.gauge(hasCover: false, hasDownloadPill: downloading) == .bar {
                    OortMeter(share: CloudTransferPresentation.fraction(state.progress), fill: indicator.status.color)
                }
            } else if let issue = state.issue, issue.item == item {
                if issue.failed {
                    let reason = state.transferFailure?.message(context: localization) ?? issue.message
                    failureLine(reason == statusText ? nil : reason, failure: state.transferFailure, item: item)
                }
                else {
                    Text(issue.message).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if item == .sources, let message = state.sourcesMessage {
                failureLine(message, failure: state.sourceFailure, item: item)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item == .app, let previous = state.previousApp {
                HStack {
                    Text(L10n.format("Previous app: %@", [previous.path], context: localization))
                        .seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3).truncationMode(.middle).textSelection(.enabled).help(previous.path)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    button(.previousApp, "Reveal in Finder")
                }
            }
        }
        .modifier(SeleneOptionRowSurface(focused: control != nil && (focus ?? startControl) == control))
    }

    private func cloudPath(_ item: CloudLibraryItem) -> String? {
        if let kind = item.artifact, state.referenceKinds.contains(kind) { return nil }
        if item == .sources, state.referenceSources != nil { return nil }
        let base: String, folder: String
        if let kind = item.artifact {
            guard let storage = model.preference.storage, let title = game.titleId else { return nil }
            base = storage
            folder = (state.copies[kind] ?? state.availability[kind])?.remoteFolder ?? "\(title.uppercased())/\(kind.rawValue)"
        } else {
            guard let storage = model.preference.sourcesStorage, let files = CloudSourceFiles(game) else { return nil }
            base = storage
            folder = files.folderName
        }
        return base + (base.hasSuffix("/") ? "" : "/") + folder + "/"
    }

    private func referenceLine(_ item: CloudLibraryItem) -> String? {
        let bytes: Int64, total: Int64, fullArchiveDownload: Bool
        if let kind = item.artifact, let copy = state.referenceCopies[kind] {
            if !copy.updatesLocal && !copy.legacy { return nil }
            (bytes, total, fullArchiveDownload) = (copy.downloadBytes, copy.totalBytes, copy.legacy && !copy.updatesLocal)
        } else if item == .sources, let status = state.referenceSources, let changed = state.referenceSourceBytes,
                  status.files.contains(where: { $0.localBytes != nil }) {
            (bytes, total, fullArchiveDownload) = (changed, status.remoteBytes, false)
        } else { return nil }
        return L10n.format(fullArchiveDownload
                           ? "Reference archive · Full download (%@ of %@)"
                           : "Update this Mac from the reference · %@ of %@",
                           [formattedBytes(bytes), formattedBytes(total)], context: localization)
    }

    private func artifactControl(_ item: CloudLibraryItem) -> Control? {
        if state.activeItem == item, state.transfer(for: item)?.canCancel == true {
            if let request = model.active?.request, request.id == game.id, !model.canCancelCloud(request.token) { return nil }
            return .cancel
        }
        if retryResult(for: item) != nil, state.transferFailure?.action == nil || state.transferFailure?.action == .retry {
            return nil
        }
        guard let kind = item.artifact else {
            if state.referenceSourceBytes != nil { return canChange(.downloadSources) ? .downloadSources : nil }
            switch state.sources?.state {
            case .notInCloud:
                return canChange(.uploadSources) && GameResourceState.sourcesAvailable(for: game) ? .uploadSources : nil
            case .cloudOnly: return canChange(.downloadSources) ? .downloadSources : nil
            default: return nil
            }
        }
        if state.referenceCopies[kind] != nil || state.copies[kind]?.state == .cloudOnly {
            return canChange(.restore(kind)) ? .download(kind) : nil
        }
        return canChange(.upload(kind)) && state.canUpload(kind) ? .upload(kind) : nil
    }

    private var visibleItems: [CloudLibraryItem] {
        CloudLibraryItem.allCases.filter {
            advanced || $0 == .app || $0 == state.activeItem || $0 == state.issue?.item || $0 == state.completedItem
        }
    }

    /// Where the panel opens: never on what moves files to the Trash.
    private var startControl: Control? { controls.first { $0 != .free } }

    /// The foot as drawn: Free up space apart on the left, Close, then Send last.
    private var foot: [OortActionBar.Action] {
        let keys: [(Control, String, ActionBarRole)] = [(.free, "Free up space", .destructive), (.close, "Close", .back),
            (.advanced, advanced ? "Hide" : "Advanced", .secondary), (.settings, "Open settings", .secondary),
            (.refresh, "Refresh", .secondary), (.upload(nil), state.combinedUploadTitle, .primary)]
        return keys.filter { controls.contains($0.0) }.map { control, title, role in
            .init(id: control, title: title, role: role) { choose(control) }
        }
    }

    /// The arrows walk the rows, then the foot in its drawn order.
    private var controls: [Control] {
        let drawn: [Control] = [.free, .close, .advanced, .settings, .refresh, .upload(nil)]
        let all = offered
        return all.filter { !drawn.contains($0) } + drawn.filter(all.contains)
    }

    private var offered: [Control] {
        let close: [Control] = showHints ? [] : [.close]
        if state.action != nil {
            let primary: [Control] = interrupted != nil ? [.resume] : pausable != nil ? [.pause] : []
            return primary + visibleItems.compactMap(artifactControl) + close + [.advanced]
        }
        if model.archive == nil { return close + [.settings] }
        if unavailable != nil { return close }
        let artifacts = visibleItems.compactMap(artifactControl) + (state.previousApp == nil ? [] : [.previousApp])
        if state.refreshing { return artifacts + close + [.advanced] }
        var buttons = artifacts + close + [.advanced]
        if let failure = state.failure ?? (state.message == nil && state.issue == nil && state.sourcesMessage == nil
                                           ? model.checkFailure : nil), canRecover(failure) {
            buttons.append(.recover(failure, nil))
        }
        if let issue = state.issue, let failure = state.transferFailure,
           failure.action != .retry, canRecover(failure) {
            buttons.append(.recover(failure, issue.item))
        } else if let item = state.issue?.item, let retry = retryResult(for: item) {
            buttons.append(.retry(retry))
        }
        if advanced, state.issue?.item != .sources, let failure = state.sourceFailure, canRecover(failure) {
            buttons.append(.recover(failure, .sources))
        }
        if (state.message != nil && state.failure == nil) || (state.sourcesMessage != nil && state.sourceFailure == nil) {
            buttons.append(.settings)
        }
        if advanced && !buttons.contains(where: {
            if case .recover(let failure, _) = $0 { return failure.action == .retry }
            return false
        }) { buttons.append(.refresh) }
        let available = CloudFreeSelection(state: state).available
        if !available.isEmpty && canChange(.free(available)) { buttons.append(.free) }
        if (advanced || state.needsCombinedUpload) && canChange(.upload(nil)) && state.showsCombinedUpload {
            buttons.append(.upload(nil))
        }
        return buttons
    }

    private func canRecover(_ failure: CloudLibraryFailure) -> Bool {
        switch failure.action {
        case .reconnect, .chooseFolder: return viewModel.canConfigureCloudLibrary
        default: return true
        }
    }

    private func failureLine(_ message: String?, failure: CloudLibraryFailure?, item: CloudLibraryItem?) -> some View {
        HStack {
            if let message {
                Text(message).seleneFont(.text).foregroundColor(CloudLibraryStatus.failed.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure, controls.contains(.recover(failure, item)) {
                button(.recover(failure, item), failure.action == .retry ? "Refresh" : failure.action.titleKey)
            } else if let item, let retry = retryResult(for: item), controls.contains(.retry(retry)) {
                button(.retry(retry), "Retry")
            }
        }
    }

    private func retryResult(for item: CloudLibraryItem) -> UUID? {
        guard state.issue?.item == item, let id = state.failedTransferID,
              viewModel.activityResults.entries.contains(where: { $0.id == id && $0.canRetry }) else { return nil }
        return id
    }

    private func button(_ control: Control, _ key: String) -> some View {
        SelenePillButton(title: key, minWidth: 96, height: 36, horizontalPadding: 14,
                         focused: (focus ?? startControl) == control, action: { choose(control) })
            .seleneHover { focus = control }
    }

    private func artifactButton(_ control: Control, _ key: String, icon: MaterialIcon) -> some View {
        SelenePillButton.roundIcon(icon) { choose(control) }
            .help(text(key))
            .accessibilityLabel(text(key))
            .seleneHover { focus = control }
    }

    private func downloadButton(_ control: Control?, fill: Double, ready: Bool = false) -> some View {
        SelenePillButton(title: ready ? "Ready to install" : "Download", icon: .cloudDownload, iconSize: 20, minWidth: 0, height: 44,
                         horizontalPadding: 14, focused: false, downloadFill: fill, passive: control == nil) {
            if let control { choose(control) }
        }
        .accessibilityHidden(control == nil)
        .seleneHover { if let control { focus = control } }
    }

    private func handle(_ action: GamepadAction) {
        if let freeSelection { handleFree(action, selection: freeSelection); return }
        let controls = self.controls
        if action == .cancel { close(); return }
        guard !controls.isEmpty else { return }
        guard let current = (focus ?? startControl).flatMap(controls.firstIndex) ?? controls.indices.first else { return }
        switch action {
        case .navigateUp, .navigateLeft, .navigateDown, .navigateRight:
            let direction = action == .navigateUp || action == .navigateLeft ? -1 : 1
            var index = FocusIndex(index: current)
            index.move(by: direction, count: controls.count)
            if index.index != current {
                focus = controls[index.index]
                SoundEffectService.shared.play(.focus)
            }
        case .confirm: choose(controls[current])
        default: break
        }
    }

    private func choose(_ control: Control) {
        guard controls.contains(control) else { return }
        switch control {
        case .upload(let kind): viewModel.performCloudLibrary(.upload(kind), for: game)
        case .uploadSources: viewModel.performCloudLibrary(.uploadSources, for: game)
        case .downloadSources: viewModel.performCloudLibrary(.downloadSources, for: game)
        case .free:
            freeFocus = .cancel
            freeSelection = CloudFreeSelection(state: state)
        case .download(let kind): viewModel.performCloudLibrary(.restore(kind), for: game)
        case .cancel: viewModel.cancelCloudLibrary(game)
        case .pause:
            if let pausable { viewModel.pauseCloudTransfer(pausable) }
        case .resume:
            if let interrupted { viewModel.resumeCloudTransfer(interrupted.token) }
        case .previousApp:
            if let previous = state.previousApp { viewModel.revealInFinder(url: previous) }
        case .refresh:
            refreshRevision += 1
        case .advanced:
            advanced.toggle()
        case .retry(let id):
            viewModel.retryActivity(id)
        case .recover(let failure, let item):
            let global = item == nil && state.failure == nil || model.checkFailure == failure && failure == .offline
            if failure.action == .retry, global {
                viewModel.retryCloudCheck()
            }
            if failure.action == .reconnect || failure.action == .chooseFolder || failure.action == .freeMacStorage { close() }
            viewModel.recoverCloud(failure.action, sourceFolder: item == .sources || (global && model.checkFailureOnSources)) {
                refreshRevision += 1
            }
        case .settings:
            close()
            viewModel.router?.openSettings(.cloudLibrary)
        case .close: close()
        }
    }

    private func freeDialog(_ selection: CloudFreeSelection) -> some View {
        SeleneOverlay(style: .dialog, onOutside: { freeSelection = nil }) {
            SeleneConfirmDialog(title: "Free up space",
                message: text("Your verified copy stays available in your personal cloud. Your saves are unchanged. Empty the Trash to reclaim space."),
                confirmTitle: "Free up space", confirmEnabled: !selection.selected.isEmpty,
                highlightsPills: freeFocus == .cancel || freeFocus == .confirm, destructive: true,
                focus: Binding(get: { freeFocus == .confirm ? .confirm : .cancel },
                               set: { freeFocus = $0 == .cancel ? .cancel : .confirm }),
                onCancel: { freeSelection = nil }, onConfirm: confirmFree) {
                VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                    Text(freeSummary(selection))
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.ink90)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(CloudLibraryItem.allCases, id: \.self) { item in
                        let size = selection.sizes[item].map(formattedBytes) ?? "—"
                        SeleneRow(item.title, subtitle: size, verbatimSubtitle: true) {
                            SeleneSwitch(isOn: Binding(get: { freeSelection?.selected.contains(item) == true },
                                                       set: { _ in freeSelection?.toggle(item) }))
                                .disabled(!selection.allows(item))
                                .accessibilityLabel(text(item.title))
                        }
                        .environment(\.seleneFocusedRowID, freeFocus == .item(item) ? item.title : nil)
                        .seleneHover { if selection.allows(item) { freeFocus = .item(item) } }
                    }
                }
                .padding(.top, canvas.u(SeleneTokens.Space.control))
            }
        }
    }

    private func freeSummary(_ selection: CloudFreeSelection) -> String {
        guard !selection.selected.isEmpty else { return text("No items selected.") }
        var total: Int64 = 0
        for item in selection.selected {
            guard let bytes = selection.sizes[item], bytes >= 0 else {
                return text("Trash on this Mac: total size unknown.")
            }
            let (sum, overflow) = total.addingReportingOverflow(bytes)
            guard !overflow else { return text("Trash on this Mac: total size unknown.") }
            total = sum
        }
        return L10n.format("On this Mac: %@ to move to the Trash.", [formattedBytes(total)], context: localization)
    }

    private func handleFree(_ action: GamepadAction, selection: CloudFreeSelection) {
        let choices = CloudLibraryItem.allCases.filter(selection.allows).map(FreeControl.item)
            + [.cancel] + (selection.selected.isEmpty ? [] : [.confirm])
        switch action {
        case .cancel: freeSelection = nil
        case .confirm:
            switch freeFocus {
            case .cancel: freeSelection = nil
            case .confirm: confirmFree()
            case .item(let item):
                freeSelection?.toggle(item)
                SoundEffectService.shared.play(.key)
            }
        case .navigateLeft, .navigateUp, .navigateRight, .navigateDown:
            var index = FocusIndex(index: (choices.firstIndex(of: freeFocus) ?? choices.firstIndex(of: .cancel))!)
            index.move(by: action == .navigateLeft || action == .navigateUp ? -1 : 1, count: choices.count)
            let next = choices[index.index]
            if next != freeFocus { SoundEffectService.shared.play(.focus); freeFocus = next }
        default: break
        }
    }

    private func confirmFree() {
        guard let selection = freeSelection, !selection.selected.isEmpty else { return }
        freeSelection = nil
        viewModel.performCloudLibrary(.free(selection.selected), for: game)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(localization.formatLocale))
    }
    private func close() { viewModel.cloudLibraryGameID = nil }
    private func text(_ key: String) -> String { L10n.text(key, context: localization) }
}

/// Shared status for Spotlight, where a visible cover can carry the progress.
struct CloudGameStatus: View {
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneCanvas) private var canvas
    let state: CloudLibraryState
    let playable: Bool
    var hasCover = false
    let hasDownloadPill: Bool

    var body: some View {
        let keys = (playable ? ["Playable on this Mac"] : []) + state.appAvailabilityKeys
        let indicator = CloudLibraryIndicator(state: state)
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.tight)) {
            if !keys.isEmpty {
                Text(keys.map { L10n.text($0, context: localization) }.joined(separator: " · "))
                    .seleneFont(.text).foregroundColor(SeleneTheme.ink75)
            }
            if let transfer = state.transfer() {
                let bytes = transfer.canCancel ? CloudLibraryProgressView.bytesSummary(state.progress, context: localization) : nil
                let title = indicator.label(context: localization)
                let message = transfer == .failed ? state.issue?.message : bytes
                SeleneStatusDot(text: [title, message == title ? nil : message].compactMap { $0 }.joined(separator: " · "),
                                color: indicator.status.color, labelColor: SeleneTheme.ink90)
                if transfer.gauge(hasCover: hasCover, hasDownloadPill: hasDownloadPill) == .bar {
                    OortMeter(share: CloudTransferPresentation.fraction(state.progress), fill: indicator.status.color)
                }
            }
        }
        .frame(maxWidth: canvas.u(SeleneTokens.Space.transferMeasure), alignment: .leading)
    }
}

struct CloudLibraryProgressView: View {
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneCanvas) private var canvas
    let progress: CloudArchiveProgress?
    let showsBar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
            Text(showsBar ? Self.summary(progress, context: localization)
                 : Self.downloadSummary(progress, context: localization))
                .seleneFont(.text).monospacedDigit()
                .foregroundColor(showsBar ? SeleneTheme.ink90 : SeleneTheme.ink75)
            if showsBar {
                OortMeter(share: Self.fraction(progress), height: 6, fill: CloudLibraryStatus.pending.color)
            }
        }
    }

    static func fraction(_ progress: CloudArchiveProgress?) -> Double? {
        CloudTransferPresentation.fraction(progress)
    }

    static func isDownloading(_ state: CloudLibraryState, item: CloudLibraryItem) -> Bool {
        guard !state.queued, state.activeItem == item else { return false }
        switch state.action {
        case .restore, .restoreBuildCache, .downloadSources: return true
        default: return false
        }
    }

    static func downloadFill(_ state: CloudLibraryState, item: CloudLibraryItem) -> Double? {
        guard isDownloading(state, item: item) else { return nil }
        return state.progress?.downloadComplete == true ? 1 : fraction(state.progress)
    }

    static func bytesSummary(_ progress: CloudArchiveProgress?, context: AppLocale) -> String? {
        guard let transfer = progress?.transfer, transfer.totalBytes > 0 else { return nil }
        func bytes(_ count: Int64) -> String { count.formatted(.byteCount(style: .file).locale(context.formatLocale)) }
        return L10n.format("%@ of %@", [bytes(transfer.bytesTransferred), bytes(transfer.totalBytes)], context: context)
    }

    static func downloadSummary(_ progress: CloudArchiveProgress?, context: AppLocale) -> String {
        guard let progress else { return L10n.text("Preparing cloud operation…", context: context) }
        let phase = L10n.text(phaseKey(progress), context: context)
        return bytesSummary(progress, context: context).map { phase + " · " + $0 } ?? phase
    }

    static func summary(_ progress: CloudArchiveProgress?, context: AppLocale, showsPhase: Bool = true) -> String {
        func text(_ key: String) -> String { L10n.text(key, context: context) }
        guard let progress else { return text("Preparing cloud operation…") }
        var segments = showsPhase ? [text(phaseKey(progress))] : []
        let locale = context.formatLocale
        if let transfer = progress.transfer, let fraction = fraction(progress) {
            if let bytes = bytesSummary(progress, context: context) { segments.append(bytes) }
            if showsPhase { segments.append(percent(fraction, context: context)) }
            if let speed = transfer.bytesPerSecond, speed.isFinite, speed > 0, speed < Double(Int64.max) {
                segments.append(L10n.format("%@/s", [Int64(speed).formatted(.byteCount(style: .file).locale(locale))], context: context))
            }
            if let eta = estimate(progress, context: context) { segments.append(eta) }
        }
        return segments.joined(separator: " · ")
    }

    static func estimate(_ progress: CloudArchiveProgress?, context: AppLocale, compact: Bool = false) -> String? {
        guard let fraction = fraction(progress), fraction < 1, let eta = progress?.transfer?.etaSeconds,
              eta.isFinite, eta >= 0, eta <= 86_400 else { return nil }
        let seconds = max(1, Int(eta.rounded()))
        let count = seconds < 60 ? seconds : Int((Double(seconds) / 60).rounded())
        let duration = L10n.format(seconds < 60 ? "%@ s" : "%@ min",
                                   [count.formatted(.number.locale(context.formatLocale))], context: context)
        return L10n.format(compact ? "~%@" : "About %@ left", [duration], context: context)
    }

    static func percent(_ fraction: Double, context: AppLocale) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(context.formatLocale))
    }

    static func phaseKey(_ progress: CloudArchiveProgress) -> String {
        switch (progress.phase, progress.kind) {
        case (.preparing, _): return "Preparing cloud operation…"
        case (.uploading, .app): return "Sending app"
        case (.uploading, .cache): return "Sending build cache"
        case (.uploading, nil): return "Sending game files"
        case (.verifying, .app): return "Verifying app"
        case (.verifying, .cache): return "Verifying build cache"
        case (.verifying, nil): return "Verifying cloud copy"
        case (.downloading, .app): return "Downloading app"
        case (.downloading, .cache): return "Downloading build cache"
        case (.downloading, nil): return "Downloading game files"
        case (.restoring, .app): return "Restoring app"
        case (.restoring, _): return "Restoring build cache"
        // The Details header keeps its original copy; the Activity and Cloud panels use the shared transfer status.
        case (.readyToInstall, _): return "Details: Update ready · applied when you quit the game"
        }
    }

}

enum CloudLibraryStatus {
    case synchronized, queued, pending, needsUpload, failed, unknown

    var color: Color {
        switch self {
        case .synchronized: return SeleneTheme.statusOK
        case .pending: return SeleneTheme.statusCloud
        case .needsUpload: return SeleneTheme.untested
        case .failed: return SeleneTheme.danger
        case .queued, .unknown: return SeleneTheme.ink60
        }
    }
}

/// Shared cloud copy vocabulary. An artifact row only shows its own transfer or failure.
struct CloudLibraryIndicator {
    let state: CloudLibraryState
    var item: CloudLibraryItem? = nil

    private var showsAction: Bool {
        guard let active = state.activeItem else { return false }
        return item.map { $0 == active } ?? true
    }
    var progress: Bool { showsAction && !state.queued }
    /// Cache preparation starts only after the app is published.
    var appPublished: Bool {
        item == .app && state.action == .upload(nil) && state.activeItem == .cache
    }
    var queued: Bool { showsAction && state.queued }
    var copy: CloudArtifactStatus.State { state.copy(item ?? .app) ?? .unknown }

    // Keep the cloud glyph on the round action; the shared status line describes the transfer phase.
    var pillIcon: MaterialIcon {
        if queued { return .cloudQueue }
        if progress {
            switch state.action {
            case .upload, .uploadSources: return .cloudUpload
            default: return .cloudDownload
            }
        }
        switch copy {
        case .synchronized: return .cloudDone
        case .cloudOnly: return .cloudDownload
        case .newerOnThisMac: return .cloudUpload
        case .notInCloud, .unknown: return .cloud
        }
    }

    var isTransferring: Bool {
        showsAction && !state.queued && (state.progress?.phase == .uploading || state.progress?.phase == .downloading)
    }
    // Bound once: comparing two optional-chained tuple fields crashes Swift 6.4.2's Release optimizer (SemanticARCOpts).
    var failed: Bool {
        if item == .sources, state.sourceFailure != nil { return true }
        if (item == nil || item == .app), state.failure != nil { return true }
        guard let issue = state.issue, issue.failed else { return false }
        return item.map { $0 == issue.item } ?? (issue.item != .sources)
    }

    var status: CloudLibraryStatus {
        if queued || (progress && state.progress?.phase == .readyToInstall) { return .queued }
        if appPublished { return .synchronized }
        if progress { return .pending }
        if failed { return .failed }
        if state.transfer(for: item) == .ready { return .synchronized }
        if let item, item.artifact.flatMap({ state.referenceCopies[$0] }) != nil ||
            item == .sources && state.referenceSourceBytes != nil { return .pending }
        switch copy {
        case .synchronized: return .synchronized
        case .cloudOnly: return .pending
        case .newerOnThisMac: return .needsUpload
        case .notInCloud:
            if let artifact = (item ?? .app).artifact {
                let copy = state.copies[artifact] ?? state.availability[artifact]
                return copy?.hasLocalCopy == true ? .needsUpload : .unknown
            }
            return .needsUpload
        case .unknown: return state.refreshing ? .pending : .unknown
        }
    }

    var icon: MaterialIcon {
        switch state.transfer(for: item) {
        case .queued: return .cloudQueue
        case .waitingForGame: return .schedule
        case .verifying: return .checklist
        case .ready: return .cloudDone
        case .failed: return .info
        default: break
        }
        if failed { return .info }
        if progress {
            switch state.action {
            case .upload, .uploadSources: return .cloudUpload
            case .restore, .restoreBuildCache, .downloadSources: return .cloudDownload
            default: return .cloud
            }
        }
        switch copy {
        case .synchronized: return .cloudDone
        case .cloudOnly: return .cloudDownload
        case .newerOnThisMac: return .cloudUpload
        case .notInCloud, .unknown: return .cloud
        }
    }

    func label(context: AppLocale) -> String {
        if showsAction && state.isUserPaused { return L10n.text("Paused", context: context) }
        if appPublished { return L10n.text("App published · sending build cache…", context: context) }
        if let kind = item?.artifact, state.copies[kind]?.canMigrateArchive == true,
           !showsAction, !failed {
            return L10n.text("Copy in your cloud", context: context)
        }
        if let transfer = state.transfer(for: item) {
            return L10n.text(transfer.titleKey, context: context)
        }
        if failed { return L10n.text("Cloud operation failed", context: context) }
        let key: String
        switch copy {
        case .synchronized: key = "Synchronized"
        case .cloudOnly: key = "Cloud only"
        case .newerOnThisMac:
            key = item == .sources ? "Different in the cloud. Nothing is overwritten." : "Newer on this Mac"
        case .notInCloud: key = "Not in the cloud"
        case .unknown: key = state.refreshing ? "Checking…" : "Cloud status unknown"
        }
        return L10n.text(key, context: context)
    }

}

/// A non-interactive tile overlay. The tile keeps its own accessible name and selection ring.
struct CloudLibraryTileBadge: ViewModifier {
    let state: CloudLibraryState?
    var showsCopyBadge = true
    var position = TileBadgePosition.topRight
    /// What a game that cannot be played yet needs; it replaces the old lock, so it always shows.
    var look: PortingTileLook = .normal
    var onlineTitleID: String? = nil
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.onlinePlayersByTitle) private var onlinePlayers
    @Environment(\.onlinePlayersDisplay) private var onlineDisplay

    private var alignment: Alignment {
        switch position {
        case .topRight: return .topTrailing
        case .topLeft: return .topLeading
        case .bottomLeft: return .bottomLeading
        }
    }

    private var need: (icon: MaterialIcon, label: String)? {
        guard state?.transfer() == nil, state.map({ CloudLibraryIndicator(state: $0).failed }) != true else { return nil }
        switch look {
        case .toDownload: return (.cloudDownload, "Cloud only")
        case .toBuild: return (.build, "Not built yet")
        case .toDownloadFiles: return (.cloudDownload, "Download game files")
        case .missing: return (.search, "Game files not found")
        case .engineUpdate: return (.update, "Engine update available")
        default: return nil
        }
    }

    func body(content: Content) -> some View {
        let badge = state.flatMap {
            showsCopyBadge || $0.transfer() != nil ? CloudLibraryBadge(indicator: CloudLibraryIndicator(state: $0)) : nil
        }
        let need = need
        let visibleBadge = badge.flatMap { $0.isVisibleOnTile ? $0 : nil }
        let online = onlineDisplay.count(for: onlineTitleID, in: onlinePlayers, at: .tile)
        content.overlay(alignment: alignment) {
            Group {
                if let need { TileMark(icon: need.icon) }
                else if let visibleBadge { visibleBadge }
            }
            .padding(canvas.u(SeleneTokens.Space.small))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomTrailing) {
            if let online {
                NextendoOnlineBadge(count: online)
                    .padding(canvas.u(SeleneTokens.Space.small))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue([
            need.map { L10n.text($0.label, context: localization) } ?? visibleBadge?.indicator.label(context: localization),
            online.map { OnlinePlayersDisplay.label(for: $0, context: localization) },
        ].compactMap { $0 }.joined(separator: ", "))
    }
}

/// The round mark in a tile's corner.
struct TileMark: View {
    let icon: MaterialIcon
    var paused = false
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        Group {
            if paused {
                Image(systemName: "pause.fill").seleneFont(.text, .semibold)
            } else {
                MaterialIconView(icon, size: SeleneTokens.Space.control)
            }
        }
            .foregroundColor(SeleneTheme.ink)
            .frame(width: canvas.u(SeleneTokens.Space.section), height: canvas.u(SeleneTokens.Space.section))
            .background(Circle().fill(SeleneTheme.scrim.opacity(SeleneTokens.Effect.cloudBadgeOpacity)))
    }
}

/// Static cloud mark on tiles; only the cover expresses progress.
struct CloudLibraryBadge: View {
    let indicator: CloudLibraryIndicator
    @Environment(\.seleneCanvas) private var canvas
    var isVisibleOnTile: Bool {
        if indicator.state.transfer() != nil || indicator.failed { return true }
        switch indicator.copy {
        case .synchronized, .cloudOnly, .newerOnThisMac: return true
        case .notInCloud, .unknown: return false
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TileMark(icon: indicator.icon, paused: indicator.state.isUserPaused)
            SeleneStatusMark(color: indicator.status.color, pulses: false)
                .padding(canvas.u(SeleneTokens.Space.seam))
        }
        .frame(width: canvas.u(SeleneTokens.Space.section), height: canvas.u(SeleneTokens.Space.section))
        .accessibilityHidden(true)
    }
}

struct CloudLibraryPill: View {
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let indicator: CloudLibraryIndicator
    let focused: Bool
    var showsTransferDot = true
    let action: () -> Void

    var body: some View {
        SelenePillButton(title: nil, icon: indicator.pillIcon, iconSize: SeleneTokens.Space.panel,
                         minWidth: 52, height: 52, horizontalPadding: 0, focused: focused, action: action)
            .overlay(alignment: .bottomTrailing) {
                if indicator.isTransferring && !reduceMotion && !systemReduceMotion {
                    SeleneStatusMark(color: indicator.status.color, pulses: true, showsDot: showsTransferDot)
                        .padding(SeleneTokens.Space.hairline)
                }
            }
            .accessibilityLabel(L10n.text("Cloud library", context: localization))
            .accessibilityValue(indicator.label(context: localization))
    }
}
