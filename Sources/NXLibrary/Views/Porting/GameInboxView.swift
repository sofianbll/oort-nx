import ArcanePorting
import NXLibraryCore
import SwiftUI

struct GameInboxView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    @ObservedObject var model: GameInboxModel
    @ObservedObject var router: AppRouter
    var showsHints = true
    @State var focused: Action = .folder
    @State private var dropTarget = false

    enum Action: Hashable {
        case correction, folder, refresh, sortAll, file(URL)
    }

    var ready: [GameInbox.Entry] { model.entries.filter { $0.destination != nil } }
    var actions: [Action] {
        var list: [Action] = model.needsGameFilesCorrection ? [.correction] : []
        list += [.folder, .refresh]
        if !ready.isEmpty, !model.needsGameFilesCorrection { list += [.sortAll] + ready.map { .file($0.id) } }
        return list
    }

    var body: some View {
        let _ = locale
        ZStack(alignment: .bottomLeading) {
            SeleneBackdrop()
            ScrollViewReader { proxy in
                ScrollView {
                    page
                }
                .onChange(of: focused) { _, target in proxy.scrollTo(target) }
            }
            .padding(.bottom, canvas.u(SeleneTokens.Space.inboxHintsClearance))
            if showsHints {
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"), action: { router.back() })],
                               right: model.busy ? [] : [HintItem(.a, L10n.text("Select"))])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { model.refresh() }
        .onChange(of: actions) { _, next in if !next.contains(focused) { focused = next.first ?? .folder } }
        .onReceive(NotificationCenter.default.publisher(for: .nxGameInboxAction)) { note in
            guard router.route == .gameInbox, let action = note.object as? GamepadAction else { return }
            input(action)
        }
    }

    var page: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.panel)) {
            Text(L10n.text("Inbox"))
                .seleneFont(.screen, .semibold)
                .foregroundStyle(SeleneTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text("Review the names and destinations before sorting your Switch files."))
                .seleneFont(.row)
                .foregroundStyle(SeleneTheme.ink82)
            if model.needsGameFilesCorrection {
                SeleneOptionRow(icon: .folder, title: L10n.text("Game files points to a different folder"),
                                about: GameInboxModel.gamesRoot.path,
                                focused: focused == .correction, enabled: !model.busy) {
                    pill(L10n.text("Correct Game files"), action: .correction)
                }
            }
            HStack(spacing: canvas.u(SeleneTokens.Space.line)) {
                pill(L10n.text("Choose Inbox folder"), action: .folder)
                pill(L10n.text("Refresh"), action: .refresh)
                Spacer(minLength: 0)
                if !ready.isEmpty, !model.needsGameFilesCorrection {
                    pill(L10n.text("Sort all ready files"), action: .sortAll)
                }
            }
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.tight)) {
                Text(L10n.text("Drop files here"))
                    .seleneFont(.heading, .semibold)
                    .foregroundStyle(SeleneTheme.ink)
                Text(model.folder.path)
                    .seleneFont(.text)
                    .foregroundStyle(SeleneTheme.ink82)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(canvas.u(SeleneTokens.Space.large))
            .oortPanel(radius: canvas.u(SeleneTokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.card))
                .strokeBorder(dropTarget ? SeleneTheme.focus : SeleneTheme.ink25,
                              style: StrokeStyle(lineWidth: canvas.u(SeleneTokens.Space.focusStroke), dash: [canvas.u(8), canvas.u(6)])))
            .dropDestination(for: URL.self) { urls, _ in model.accept(urls) } isTargeted: { dropTarget = $0 }
            if model.busy {
                Text(L10n.text("Checking files…")).seleneFont(.text).foregroundStyle(SeleneTheme.ink82)
            }
            if let message = model.message {
                Text(verbatim: message).seleneFont(.text).foregroundStyle(SeleneTheme.ink)
            }
            if model.entries.isEmpty, !model.busy {
                OortEmptyState(title: L10n.text("No incoming files"),
                               hint: L10n.text("Drop game files here, or put them in the Inbox folder and refresh."))
            }
            ForEach(model.entries) { entry in
                row(entry)
            }
        }
        .frame(maxWidth: canvas.u(1270), alignment: .leading)
        .padding(.horizontal, canvas.u(SeleneTokens.Space.group))
        .padding(.vertical, canvas.u(SeleneTokens.Space.inboxPageInset))
        .frame(maxWidth: .infinity)
    }

    private func row(_ entry: GameInbox.Entry) -> some View {
        let target = Action.file(entry.id)
        let metadata = entry.content.map {
            let kind: String
            switch $0.kind {
            case .base: kind = L10n.text("Base game")
            case .update: kind = L10n.text("Update")
            case .dlc: kind = L10n.text("DLC")
            case .unknown: kind = L10n.text("Unknown")
            }
            return "\(kind)  ·  \(String(format: "%016llX", $0.titleId))  ·  v\($0.version ?? 0)"
        }
        let preview = entry.destination.map { $0.path.replacingOccurrences(of: GameInboxModel.gamesRoot.path + "/", with: "Switch/Games/") }
        let details = [metadata, preview, entry.issue].compactMap { $0 }.joined(separator: "\n")
        return SeleneOptionRow(icon: .folder, title: entry.source.lastPathComponent, about: details,
                               focused: focused == target) {
            if entry.issue == nil {
                pill(entry.duplicate ? L10n.text("Review duplicate") : L10n.text("Sort file"), action: target,
                     enabled: !model.needsGameFilesCorrection)
            } else if !entry.needsKeys {
                Text(L10n.text("Cannot sort", context: locale)).seleneFont(.text, .semibold).foregroundStyle(SeleneTheme.ink82)
            }
        }
    }

    private func pill(_ title: String, action: Action, enabled: Bool = true) -> some View {
        SelenePillButton(title: title, minWidth: 0, horizontalPadding: SeleneTokens.Space.large, focused: focused == action,
                         scalesOnFocus: false, enabled: enabled && !model.busy) {
            focused = action
            run(action)
        }
        .id(action)
        .seleneHover { if enabled && !model.busy { focused = action } }
    }
}
