import AppKit
import SwiftUI
import NXLibraryCore

/// The guided pages and What’s New share a single readable Selene layout.
struct OnboardingScreen: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let detail: String
        let note: String?
        let icon: MaterialIcon
        let badges: [String]
        let trailing: SetupCardRow.Trailing
        let cycle: ((Int) -> Void)?
        let action: (() -> Void)?

        init(_ id: String, _ title: String, _ detail: String, _ icon: MaterialIcon,
             _ trailing: SetupCardRow.Trailing = .chevron, note: String? = nil,
             badges: [String] = [], cycle: ((Int) -> Void)? = nil,
             action: (() -> Void)? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
            self.note = note
            self.icon = icon
            self.badges = badges
            self.trailing = trailing
            self.cycle = cycle
            self.action = action
        }
    }

    @Environment(\.seleneCanvas) private var canvas
    let title: String
    let detail: String
    var progress: String? = nil
    let rows: [Row]
    var message: String? = nil
    @Binding var focus: String
    let primary: (String, () -> Void)
    var secondary: (String, () -> Void)? = nil
    @State private var hover = SeleneHoverFocus()

    var body: some View {
        ZStack {
            SeleneBackdrop()
            SeleneOverlay(style: .deep) {
            VStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                if let progress {
                    Text(verbatim: progress).seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.ink75)
                }
                Text(verbatim: title).seleneFont(.screen, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if !detail.isEmpty {
                    Text(verbatim: detail).seleneFont(.row)
                        .foregroundColor(SeleneTheme.ink90)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !rows.isEmpty {
                    ViewThatFits(in: .vertical) {
                        rowList.fixedSize(horizontal: false, vertical: true)
                        ScrollViewReader { proxy in
                            ScrollView { rowList }
                            .onChange(of: focus) { _, target in
                                if rows.contains(where: { $0.id == target }) { proxy.scrollTo(target) }
                            }
                        }
                    }
                }
                if let message {
                    Text(verbatim: message).seleneFont(.text)
                        .foregroundColor(SeleneTheme.ink90)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                    pill(primary, id: "continue")
                    if let secondary { pill(secondary, id: "back") }
                }
            }
            .padding(.horizontal, canvas.u(SeleneTokens.Space.chromeGutter))
            .padding(.top, canvas.u(SeleneTokens.Space.group))
            .padding(.bottom, canvas.u(SeleneTokens.Space.settingsHintsClearance))
            }
            VStack {
                Spacer(minLength: 0)
                SeleneHintsBar(right: secondary == nil
                    ? [HintItem(.a, L10n.text("Select"))]
                    : [HintItem(.a, L10n.text("Select")), HintItem(.b, L10n.text(secondary?.0 ?? "Back"))],
                    bottom: SeleneBottomScrim.hintsBottom, leftInset: SeleneTokens.Space.control)
            }
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
    }

    private var rowList: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            ForEach(rows) { row in
                SetupCardRow(title: row.title, detail: row.detail, note: row.note, icon: row.icon, badges: row.badges,
                             trailing: row.trailing, focused: focus == row.id,
                             onHover: { if row.action != nil, hover.moved(true) { focus = row.id } }) {
                    guard let action = row.action else { return }
                    focus = row.id
                    action()
                }
                .allowsHitTesting(row.action != nil)
                .accessibilityAddTraits(row.action == nil ? .isStaticText : [])
                .id(row.id)
            }
        }
        .padding(.vertical, canvas.u(SeleneTokens.Space.compact))
        .padding(.horizontal, canvas.u(SeleneTokens.Space.medium))
    }

    private func pill(_ item: (String, () -> Void), id: String) -> some View {
        SelenePillButton(title: item.0, focused: focus == id, action: item.1)
            .onHover { if hover.moved($0) { focus = id } }
    }
}

struct OnboardingNewsView: View {
    let onExit: (ArcaneWelcome.Exit) -> Void
    @State private var focus = "continue"

    var body: some View {
        OnboardingScreen(title: L10n.text("What’s new in Oort NX 0.4.0"), detail: "",
                         rows: [
                            .init("services", L10n.text("Integrations"), L10n.text("Find your optional services in one place."), .link, .none),
                            .init("controllers", L10n.text("Players and controllers"), L10n.text("Assign controllers to players before you start a game."), .gamepad, .none),
                            .init("palette", L10n.text("Oort palette"), L10n.text("A darker base with warmer accents."), .palette, .none)
                         ], focus: $focus, primary: ("Open library", { onExit(.openLibrary) }))
            .onReceive(NotificationCenter.default.publisher(for: .nxArcaneWelcomeGamepadAction)) { note in
                guard NSApp.modalWindow == nil, let action = note.object as? GamepadAction else { return }
                if action == .confirm { onExit(.openLibrary) }
                if action == .cancel { onExit(.back) }
            }
    }
}

struct OnboardingCopyOffer: View {
    let choose: (Bool) -> Void
    @State private var focus: SeleneConfirmButton = .cancel
    @State private var receiver = Receiver()
    @FocusState private var acceptsKeys: Bool
    private final class Receiver { var handle: ((GamepadAction) -> Void)? }

    var body: some View {
        SeleneOverlay(style: .deep) {
            SeleneConfirmDialog(title: "Copy your Oort library?",
                                message: L10n.text("Copy your catalog, profiles, artwork and play time. Keys, accounts, queues and saves aren’t copied. The original stays unchanged."),
                                confirmTitle: "Copy", cancelTitle: "Not now", focus: $focus,
                                onCancel: { choose(false) }, onConfirm: { choose(true) })
        }
        .focusable()
        .focused($acceptsKeys)
        .defaultFocus($acceptsKeys, true)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .tab, .escape, .return, .space]) { key in
            switch key.key {
            case .leftArrow: input(.navigateLeft)
            case .rightArrow: input(.navigateRight)
            case .tab: input(key.modifiers.contains(.shift) ? .navigateLeft : .navigateRight)
            case .escape: input(.cancel)
            default: input(.confirm)
            }
            return .handled
        }
        .onAppear {
            acceptsKeys = true
            let receiver = receiver
            receiver.handle = input
            GameControllerService.shared.onAction = { [weak receiver] in receiver?.handle?($0) }
            LaunchReveal.show()
        }
        .onDisappear { receiver.handle = nil }
    }

    private func input(_ action: GamepadAction) {
        switch action {
        case .navigateLeft: focus = .confirm
        case .navigateRight: focus = .cancel
        case .cancel: choose(false)
        case .confirm: choose(focus == .confirm)
        default: break
        }
    }
}
