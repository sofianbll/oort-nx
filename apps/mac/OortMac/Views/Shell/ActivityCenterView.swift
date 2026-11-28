import SwiftUI
import OortLibrary
import NxnativeAdapter

struct ActivityCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var porting: PortingModel
    @ObservedObject var cloudLibrary: CloudLibraryModel
    let focus: ActivityCenterFocus
    let onFocus: (ActivityCenterFocus.Row) -> Void
    let onOpen: (ActivityCenterFocus.Row) -> Void
    let onCancel: (ActivityCenterFocus.Row) -> Void
    let onBack: () -> Void
    let onOutside: () -> Void
    var onTab: ((Int) -> Void)? = nil

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @State private var hover = SeleneHoverFocus()

    private var refresh: LibraryRefreshModel { viewModel.libraryRefresh }

    static func rows(_ viewModel: AppViewModel) -> [ActivityCenterFocus.Row] {
        let cloud = viewModel.cloudLibrary
        let porting = viewModel.porting
        let pending = Set(porting.pendingBuilds.entries.map(\.value.id) + cloud.queue.map(\.token)
            + [porting.activeBuildRequest?.id, cloud.active?.request.token, cloud.libraryMove?.id].compactMap { $0 })
        let results = viewModel.activityResults.entries.map(\.id).filter { !pending.contains($0) }
        let rows = ActivityCenterFocus.rows(isBuilding: viewModel.isBuilding || porting.activeBuildRequest != nil,
            activeBuild: viewModel.portingGameID ?? porting.activeBuildRequest?.gameID,
            queuedBuilds: viewModel.buildQueue, activeCloud: cloud.active?.request.token,
            queuedCloud: cloud.queue.map(\.token), move: cloud.libraryMove?.id,
            refresh: viewModel.libraryRefresh.current?.id, results: results, undo: viewModel.undoOffers.offer != nil)
        return results.count == 1 && results.first == cloud.pendingMove?.id ? rows.filter { $0 != .clearAll } : rows
    }

    static func selectedRow(_ focus: ActivityCenterFocus, in rows: [ActivityCenterFocus.Row]) -> ActivityCenterFocus.Row {
        if let selected = focus.selected, !rows.contains(selected) {
            switch selected {
            case .cloud(let token) where rows.contains(.queuedCloud(token)): return .queuedCloud(token)
            case .queuedCloud(let token) where rows.contains(.cloud(token)): return .cloud(token)
            default: break
            }
        }
        return focus.current(in: rows)
    }

    private var focusInset: EdgeInsets {
        EdgeInsets(top: canvas.u(12), leading: canvas.u(24), bottom: canvas.u(12), trailing: canvas.u(24))
    }

    #if DEBUG
    /// Offscreen probes only (apps/mac/Tests/CatalogAppChecks): ImageRenderer draws neither a ScrollView nor a lazy
    /// stack, so a probe asks for the plain list. Nothing in the app sets it; Release builds do not contain it.
    @MainActor static var oortProbeRendersFlat = false
    @MainActor private static var rendersFlat: Bool { oortProbeRendersFlat }
    #else
    private static let rendersFlat = false
    #endif

    var body: some View {
        let rows = Self.rows(viewModel)
        let focused = Self.selectedRow(focus, in: rows)
        SeleneOverlay(style: .activity, alignment: .bottom, onOutside: onOutside) {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.panel)) {
                Text(text("Activity center")).seleneFont(.heading, .semibold)
                    .accessibilityAddTraits(.isHeader)
                // The list takes its own height up to the cap, then scrolls; the inset keeps focus glows unclipped.
                if Self.rendersFlat {
                    sections(rows, focused: focused).padding(focusInset)
                } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        sections(rows, focused: focused).padding(focusInset)
                    }
                    .padding(EdgeInsets(top: -focusInset.top, leading: -focusInset.leading,
                                        bottom: -focusInset.bottom, trailing: -focusInset.trailing))
                    .frame(maxHeight: canvas.u(620))
                    .fixedSize(horizontal: false, vertical: true)
                    .onAppear { scroll.scrollTo(focused) }
                    .onChange(of: focused) { _, row in scroll.scrollTo(row) }
                }
                }
            }
            .foregroundColor(SeleneTheme.ink)
            .multilineTextAlignment(.leading)
            .modifier(SeleneDialogCard(width: 920))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SeleneHintsBar(left: [HintItem(.b, "Close", action: onBack)],
                           right: (onTab.map { tab in
                               [HintItem(.lb, "Previous") { tab(-1) }, HintItem(.rb, "Next") { tab(1) }]
                           } ?? []) + hints(focused))
        }
        .accessibilityAction(.escape, onBack)
    }

    private func sections(_ rows: [ActivityCenterFocus.Row], focused: ActivityCenterFocus.Row) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.panel)) {
            section("Compilation", empty: "No compilation", rows: rows.filter(\.opensPorting), focused: focused)
            section("Cloud", empty: "No cloud transfer", rows: rows.filter {
                switch $0 { case .cloud, .queuedCloud, .move: return true; default: return false }
            }, focused: focused)
            section("Library", rows: rows.filter { if case .refresh = $0 { true } else { false } }, focused: focused)
            section("Results", rows: rows.filter {
                switch $0 { case .undo, .result, .clearAll: return true; default: return false }
            }, focused: focused)
        }
    }

    private func hints(_ row: ActivityCenterFocus.Row) -> [HintItem] {
        switch row {
        case .result(let id):
            return [
                result(id)?.canRetry == true ? HintItem(.a, "Retry", action: { onOpen(row) }) : nil,
                cloudLibrary.pendingMove?.id != id ? HintItem(.x, "Clear", action: { onCancel(row) }) : nil
            ].compactMap { $0 }
        case .undo:
            return [HintItem(.a, "Undo", action: { onOpen(row) })]
        case .clearAll:
            return [HintItem(.a, "Clear all", action: { onOpen(row) })]
        case .refresh:
            return [HintItem(.a, refreshCommand, action: { onOpen(row) }),
                    HintItem(.x, refresh.current?.isRunning == true ? "Cancel" : "Clear", action: { onCancel(row) })]
        default: break
        }
        return [
            primaryTitle(row).map { HintItem(.a, $0, action: { onOpen(row) }) },
            canCancel(row) ? HintItem(.x, "Cancel", action: { onCancel(row) }) : nil
        ].compactMap { $0 }
    }

    private func primaryTitle(_ row: ActivityCenterFocus.Row) -> String? {
        switch row {
        case .cloud(let token) where cloudLibrary.canPause(token): return "Pause"
        case .queuedCloud(let token) where cloudLibrary.canResume(token): return "Resume"
        default: return row.opensPorting ? "Open" : nil
        }
    }

    /// The way out of what failed, else another refresh. A refresh that runs can be started again.
    private var refreshCommand: String {
        guard refresh.current?.isRunning == false, let failure = refresh.cloudFailure else { return "Refresh" }
        return failure.action.titleKey
    }

    @ViewBuilder private func section(_ key: String, empty: String? = nil, rows: [ActivityCenterFocus.Row],
                         focused: ActivityCenterFocus.Row) -> some View {
        if !rows.isEmpty || empty != nil {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                Text(text(key)).seleneFont(.badge, .bold)
                    .foregroundColor(SeleneTheme.ink60)
                    .accessibilityAddTraits(.isHeader)
                if rows.isEmpty, let empty {
                    Text(text(empty)).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                        .padding(.vertical, canvas.u(SeleneTokens.Space.hairline))
                } else {
                    rowList(rows, focused: focused)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rowList(_ rows: [ActivityCenterFocus.Row], focused: ActivityCenterFocus.Row) -> some View {
        RowStack(flat: Self.rendersFlat, spacing: canvas.u(SeleneTokens.Space.compact)) {
            ForEach(rows, id: \.self) { row in
                Group {
                    switch row {
                    case .clearAll:
                        SelenePillButton(title: "Clear all", minWidth: 0, height: 44, horizontalPadding: 16,
                                         focused: focused == row) { onOpen(row) }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    case .refresh:
                        if let current = refresh.current {
                            ActivityRow(title: text("Library refresh"), detail: LibraryRefreshModel.detail(current, context: localization),
                                        fraction: nil, indeterminate: current.isRunning, pulses: current.isRunning,
                                        status: LibraryRefreshModel.title(current, context: localization),
                                        color: refreshColor(current), focused: focused == row, open: nil,
                                        cancel: current.isRunning ? { onCancel(row) } : nil,
                                        retry: { onOpen(row) }, retryTitle: refreshCommand,
                                        clear: current.isRunning ? nil : { onCancel(row) }, detailLines: 8)
                        }
                    case .undo:
                        if let offer = viewModel.undoOffers.offer {
                            ActivityRow(title: offer.message, detail: nil, fraction: nil, status: text("Succeeded"),
                                        color: CloudLibraryStatus.synchronized.color, focused: focused == row,
                                        open: nil, cancel: nil, retry: { onOpen(row) }, retryTitle: "Undo", clear: nil)
                        }
                    case .result(let id):
                        if let item = result(id) {
                            let status = status(item.outcome, job: item.job)
                            ActivityRow(title: title(item.job, name: item.name), detail: status.detail,
                                        fraction: nil, status: text(status.key), color: status.color, focused: focused == row,
                                        open: nil, cancel: nil, retry: item.canRetry ? { onOpen(row) } : nil,
                                        clear: cloudLibrary.pendingMove?.id != id ? { onCancel(row) } : nil)
                        }
                    default:
                        let job = liveJob(row)
                        let indicator = transferIndicator(row)
                        let cloud = !row.opensPorting
                        let command = row.opensPorting ? nil : primaryTitle(row)
                        let color = cloud ? (indicator?.status ?? .pending).color
                            : (job.active ? SeleneTheme.ink : SeleneTheme.ink60)
                        let moving: Bool = if case .move = row { cloudLibrary.libraryMove?.canCancel == true } else { false }
                        ActivityRow(title: job.title, detail: job.detail, fraction: job.fraction,
                                    indeterminate: indicator?.state.transfer()?.gauge(hasCover: false, hasDownloadPill: false) == .bar || moving,
                                    pulses: moving,
                                    status: indicator?.label(context: localization) ?? text(job.active ? "In progress" : "Queued"),
                                    color: color, progressColor: cloud ? color : SeleneTheme.focus,
                                    focused: focused == row, open: row.opensPorting ? { onOpen(row) } : nil,
                                    cancel: canCancel(row) ? { onCancel(row) } : nil,
                                    retry: command == nil ? nil : { onOpen(row) }, retryTitle: command ?? "Retry", clear: nil)
                    }
                }
                .id(row)
                .onHover { if hover.moved($0) { onFocus(row) } }
            }
        }
    }

    private func refreshColor(_ refresh: LibraryRefresh) -> Color {
        switch refresh.outcome {
        case .running: return CloudLibraryStatus.pending.color
        case .upToDate, .changed: return CloudLibraryStatus.synchronized.color
        case .incomplete: return CloudLibraryStatus.failed.color
        case .cancelled: return CloudLibraryStatus.unknown.color
        }
    }

    private func liveJob(_ row: ActivityCenterFocus.Row) -> (title: String, detail: String?, fraction: Double?, active: Bool) {
        switch row {
        case .build(let id):
            let progress = viewModel.isBuilding ? viewModel.portingProgress : nil
            let fraction = progress?.activityFraction
            let stage = !viewModel.isBuilding ? text("Preparing build…")
                : porting.isInstallingBuild ? text("Installing…")
                : porting.isCancellingBuild ? text("Cancelling…")
                : progress?.isUpdatingShaderCache == true ? text("Updating shader cache")
                : BuildStageCopy.title(porting.currentStageName, context: localization)
            let eta = porting.isCancellingBuild || porting.isInstallingBuild ? nil : progress.flatMap {
                PortingETA.text($0, lastFinishingSeconds: porting.lastPortingFinishSeconds,
                                context: localization, compact: true)
            }
            let request = porting.activeBuildRequest
            let name = viewModel.libraryGames.first { $0.id == id }?.name ?? request?.name
            return (label(request?.rebuild == true ? "Rebuild" : "Build", name), detail(stage, fraction, eta), fraction, true)
        case .queuedBuild(let id):
            guard let request = porting.pendingBuilds.entries.first(where: { $0.id == id })?.value else {
                return (text("Build"), nil, nil, false)
            }
            return (title(.build(request), name: request.name), nil, nil, false)
        case .cloud:
            guard let request = cloudLibrary.active?.request else { return (text("Cloud"), nil, nil, true) }
            let state = cloudLibrary.states[request.id]
            let progress = state?.progress
            let fraction = state?.transfer()?.gauge(hasCover: false, hasDownloadPill: false) == .bar
                ? CloudTransferPresentation.fraction(progress) : nil
            return (title(.cloud(request.entry), name: request.name),
                    cloudLibrary.explainsNoPause(request.token) ? text("This transfer cannot be paused.")
                        : CloudLibraryProgressView.bytesSummary(progress, context: localization),
                    fraction, true)
        case .queuedCloud(let token):
            guard let request = cloudLibrary.queue.first(where: { $0.token == token }) else {
                return (text("Cloud"), nil, nil, false)
            }
            return (title(.cloud(request.entry), name: request.name),
                    request.isUserPaused ? text("The current file may restart from the beginning.")
                        : cloudLibrary.interruption(of: token)?.message(context: localization), nil, false)
        case .move:
            guard let move = cloudLibrary.libraryMove else { return (text("Move library"), nil, nil, true) }
            return (title(.move(move.request), name: move.request.destination),
                    detail(text(move.isVerifying ? "Verifying the move…" : move.isCancelling ? "Cancelling…" : "Moving games…"), move.fraction, nil),
                    move.fraction, true)
        case .refresh, .undo, .result, .clearAll, .close: return ("", nil, nil, false)
        }
    }

    private func detail(_ stage: String, _ fraction: Double?, _ eta: String?) -> String {
        [stage, fraction.map { CloudLibraryProgressView.percent($0, context: localization) }, eta]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func canCancel(_ row: ActivityCenterFocus.Row) -> Bool {
        switch row {
        case .build: return viewModel.isBuilding && !porting.isInstallingBuild
            && row.canCancel(isCancellingBuild: porting.isCancellingBuild)
        case .move: return cloudLibrary.libraryMove?.canCancel == true
        case .cloud(let token), .queuedCloud(let token): return cloudLibrary.canCancelCloud(token)
        default: return row.canCancel(isCancellingBuild: porting.isCancellingBuild)
        }
    }

    private func result(_ id: UUID) -> ActivityHistory.Result? {
        viewModel.activityResults.entries.first { $0.id == id }
    }

    private func transferIndicator(_ row: ActivityCenterFocus.Row) -> CloudLibraryIndicator? {
        let request: CloudLibraryModel.Request?
        switch row {
        case .cloud: request = cloudLibrary.active?.request
        case .queuedCloud(let token): request = cloudLibrary.queue.first { $0.token == token }
        default: return nil
        }
        guard let request else { return nil }
        var state = cloudLibrary.states[request.id] ?? CloudLibraryState()
        state.action = request.action
        if case .queuedCloud = row { state.queued = true; state.progress = nil }
        return .init(state: state, item: state.activeItem)
    }

    private func title(_ job: ActivityHistory.Job, name: String?) -> String {
        let key: String
        switch job {
        case .build(let request): key = request.rebuild ? "Rebuild" : "Build"
        case .move: key = "Move library"
        case .cloud(let request):
            switch request.action {
            case .upload(.app): key = "Send app"
            case .upload(.cache): key = "Send build cache"
            case .upload(nil): key = "Send app and build cache"
            case .restore(.app): key = "Download app"
            case .restore(.cache), .restoreBuildCache: key = "Download build cache"
            case .uploadSources: key = "Send game files"
            case .downloadSources: key = "Download game files"
            case .free: key = "Free up space"
            }
        }
        return label(key, name)
    }

    private func label(_ key: String, _ name: String?) -> String {
        [text(key), name].compactMap { $0 }.joined(separator: " · ")
    }

    private func status(_ outcome: ActivityHistory.Outcome, job: ActivityHistory.Job) -> (key: String, color: Color, detail: String?) {
        switch outcome {
        case .succeeded:
            if case .cloud(let request) = job, case .upload = request.action {
                return ("Published", CloudLibraryStatus.synchronized.color, nil)
            }
            if case .cloud = job { return ("Ready", CloudLibraryStatus.synchronized.color, nil) }
            return ("Succeeded", CloudLibraryStatus.synchronized.color, nil)
        case .failed(let reason): return ("Failed", CloudLibraryStatus.failed.color, reason)
        case .cancelled: return ("Cancelled", CloudLibraryStatus.unknown.color, nil)
        }
    }

    private func text(_ key: String) -> String { L10n.text(key, context: localization) }
}

private struct ActivityRow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    let title: String
    let detail: String?
    let fraction: Double?
    var indeterminate = false
    var pulses = false
    let status: String
    let color: Color
    var progressColor = SeleneTheme.focus
    let focused: Bool
    let open: (() -> Void)?
    let cancel: (() -> Void)?
    let retry: (() -> Void)?
    var retryTitle = "Retry"
    let clear: (() -> Void)?
    /// A reason that must be read whole has more.
    var detailLines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                Group {
                    if let open {
                        Button(action: open) { content }.buttonStyle(OortPressStyle())
                            .accessibilityHint(L10n.text("Open porting", context: localization))
                    } else {
                        content
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SeleneStatusDot(text: status, color: color, pulses: pulses)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    SelenePillButton(title: retryTitle, minWidth: 0, height: 44, horizontalPadding: 16,
                                     focused: focused, action: retry)
                        .accessibilityHint(title)
                }
                if let clear {
                    SelenePillButton(title: "Clear", minWidth: 0, height: 44, horizontalPadding: 16,
                                     focused: focused && retry == nil, action: clear)
                        .accessibilityHint(title)
                }
                if let cancel {
                    SelenePillButton.roundIcon(.close, action: cancel)
                        .help(L10n.text("Cancel", context: localization))
                        .accessibilityLabel(L10n.text("Cancel", context: localization))
                        .accessibilityHint(title)
                }
            }
            .frame(minHeight: canvas.u(44))
            if indeterminate || fraction.map({ $0 > 0 }) == true {
                OortMeter(share: fraction, fill: progressColor)
            }
        }
        .modifier(SeleneOptionRowSurface(focused: focused))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
            Text(title).seleneFont(.text, .semibold).lineLimit(1)
            if let detail, detail != status {
                Text(detail).seleneFont(.text).foregroundColor(SeleneTheme.ink60).lineLimit(detailLines)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The rows' stack: lazy in the app, plain when a probe renders offscreen.
private struct RowStack<Content: View>: View {
    let flat: Bool
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if flat {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            LazyVStack(alignment: .leading, spacing: spacing) { content }
        }
    }
}
