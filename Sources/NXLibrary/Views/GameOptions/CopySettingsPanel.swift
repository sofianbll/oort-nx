import AppKit
import ArcanePorting
import NXLibraryCore
import SwiftUI

/// The other games these settings can go to, each with how many would change. A shows what changes before anything
/// is written; Undo puts the other game back.
struct CopySettingsPanel: View {
    struct Target: Identifiable {
        var id: UUID { game.id }
        let game: PortedGame
        let copy: GameSettingsCopy
    }

    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let targets: [Target]
    let onClose: () -> Void
    @State private var focus = 0
    @State private var keyMonitor: Any?
    @State private var hover = SeleneHoverFocus()
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SeleneTheme.scrim65.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { onClose() }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                    Text(L10n.text("Copy the settings of")).seleneFont(.text, .semibold).foregroundColor(SeleneTheme.ink60)
                        .accessibilityAddTraits(.isHeader)
                    Text(game.name).seleneFont(.screen).foregroundColor(SeleneTheme.ink).lineLimit(1)
                        .padding(.bottom, canvas.u(SeleneTokens.Space.line))
                    if targets.isEmpty {
                        OortEmptyState(title: L10n.text("No other game takes these settings."),
                                       hint: L10n.text("Build another game, then copy them to it."))
                    } else {
                        Text(L10n.text("To another game")).seleneFont(.text, .semibold).foregroundColor(SeleneTheme.ink60)
                            .accessibilityAddTraits(.isHeader)
                        list
                    }
                }
                .frame(width: canvas.u(SeleneTokens.Space.settingsMeasure), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, canvas.u(SeleneTokens.Space.pageTop)).padding(.bottom, canvas.u(SeleneTokens.Space.panel))
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"), action: onClose)],
                               right: targets.isEmpty ? [] : [HintItem(.a, L10n.text("Preview"), action: { preview(focus) })],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: SeleneTokens.Space.panel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                    ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                        let same = target.copy.changes.isEmpty
                        Button { preview(index) } label: {
                            SeleneOptionRow(icon: nil, title: target.game.name,
                                            about: same ? L10n.text("Already the same") : L10n.count("%lld settings change", target.copy.changes.count),
                                            focused: index == focus, enabled: !same) {}
                        }
                        .buttonStyle(OortPressStyle())
                        .onHover { if hover.moved($0) { focus = index } }
                        .id(target.id)
                    }
                }
                .padding(.top, canvas.u(SeleneTokens.Space.tight)).padding(.bottom, canvas.u(SeleneTokens.Space.large))
            }
            .scrollIndicators(.hidden)
            .onChange(of: focus) { _, index in
                guard targets.indices.contains(index) else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(targets[index].id, anchor: .center) }
            }
        }
    }

    private func preview(_ index: Int) {
        guard viewModel.settingsNotice == nil, targets.indices.contains(index), !targets[index].copy.changes.isEmpty else {
            SoundEffectService.shared.play(.error)
            return
        }
        focus = index
        SoundEffectService.shared.play(.click)
        let target = targets[index]
        viewModel.showSettingsNotice(title: L10n.format("Copy settings to %@?", [target.game.name]),
                                     message: CopySettingsPanel.summary(target.copy), actionTitle: "Copy", cancelTitle: "Cancel") {
            guard viewModel.runtimeSettings.copySettings(from: game, to: target.game) else { return }
            onClose()
        }
    }

    /// The first lines, then how many more.
    static func summary(_ copy: GameSettingsCopy, limit: Int = 8) -> String {
        var lines = copy.changes.prefix(limit).map(\.line)
        let more = copy.changes.count - lines.count
        if more > 0 { lines.append(L10n.count("and %lld more", more)) }
        return lines.joined(separator: "\n")
    }

    private func handle(_ action: GamepadAction) {
        guard viewModel.settingsNotice == nil else { return }
        let last = max(0, targets.count - 1)
        let previous = focus
        switch action {
        case .navigateUp: focus = max(0, focus - 1)
        case .navigateDown: focus = min(last, focus + 1)
        case .jumpToStart: focus = 0
        case .jumpToEnd: focus = last
        case .confirm: preview(focus); return
        case .cancel: SoundEffectService.shared.play(.back); onClose(); return
        default: return
        }
        if focus != previous { SoundEffectService.shared.play(.focus) }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.gameForSettingsSheet?.id == game.id, let window = event.window,
                  !viewModel.cloudQuitRequested,
                  viewModel.gameWithInstallFailure == nil, viewModel.settingsNotice == nil,
                  !window.isSheet, window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 115: action = .jumpToStart
            case 119: action = .jumpToEnd
            case 36, 76, 49: action = .confirm
            case 53: action = .cancel
            default: return event
            }
            handle(action)
            return nil
        }
    }
}
