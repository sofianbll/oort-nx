import SwiftUI
import NXLibraryCore

struct HintItem: Identifiable {
    /// Stable across renders: the button (or glyph) and the label.
    var id: String { "\(button?.rawValue ?? glyph?.rawValue ?? "-")|\(label)" }
    let button: PromptButton?
    let glyph: MaterialIcon?
    var label: String
    var hold: String?
    var keyboard: KeyCap?
    var controllerOnly = false
    var keyboardOnly = false
    /// A mouse click on the hint, when the screen has one for it.
    var action: (() -> Void)?

    init(_ button: PromptButton?, _ label: String, glyph: MaterialIcon? = nil, hold: String? = nil, keyboard: KeyCap? = nil,
         action: (() -> Void)? = nil) {
        self.button = button
        self.glyph = glyph
        self.label = label
        self.hold = hold
        self.keyboard = keyboard
        self.action = action
    }
}

struct SeleneHintsBar: View {
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneShowButtonHints) private var showHints
    @Environment(\.seleneHintsCovered) private var covered
    @ObservedObject private var controller = GameControllerService.shared

    var left: [HintItem] = []
    var right: [HintItem] = []
    /// Every screen uses the same bottom inset.
    var bottom: CGFloat = SeleneBottomScrim.hintsBottom
    /// Extra inset before the left group (Spotlight's prompts carry Selene's 18 margin).
    var leftInset: CGFloat = 18
    /// Labels each right slot can show on this screen, left to right. A slot is
    /// as wide as its longest label, and a missing item keeps its slot, so the
    /// prompts never shift as the focus moves.
    var rightReserve: [[String]] = []
    /// A click on a hint without an action of its own does what its button does on this screen.
    var press: ((GamepadAction) -> Void)? = nil

    var body: some View {
        if showHints {
            HStack(alignment: .bottom, spacing: canvas.u(SeleneTokens.Space.titleGap)) {
                HStack(spacing: canvas.u(SeleneTokens.Space.titleGap)) {
                    ForEach(visibleLeft(inHand: pad)) { item($0) }
                }
                    .padding(.leading, canvas.u(leftInset))
                Spacer(minLength: canvas.u(22))
                HStack(spacing: canvas.u(SeleneTokens.Space.titleGap)) {
                    ForEach(Array(rightSlots.enumerated()), id: \.offset) { slot in
                        if let hint = slot.element {
                            item(hint, reserve: reserve(slot.offset))
                        } else {
                            content(HintItem(.a, ""), reserve: reserve(slot.offset)).hidden()
                        }
                    }
                }
            }
            .padding(.horizontal, canvas.u(SeleneTokens.Space.chromeGutter))
            .padding(.bottom, canvas.u(bottom))
            .frame(maxWidth: .infinity)
            // A soft shadow lifts the prompts off whatever art is behind them.
            .shadow(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.half), radius: canvas.u(6), y: canvas.u(1))
            .seleneOverlaidHints(covered)
        }
    }

    private var pad: ConnectedPad { controller.padInHand }

    func visibleLeft(inHand: ConnectedPad) -> [HintItem] {
        left.filter {
            (!$0.keyboardOnly || ButtonPrompts.usesKeyboard(inHand))
                && ButtonPrompts.showsHint($0.button, controllerOnly: $0.controllerOnly, inHand: inHand)
        }
    }

    private var rightSlots: [HintItem?] {
        (0..<max(right.count, rightReserve.count)).map { $0 < right.count ? right[$0] : nil }
    }

    private func reserve(_ slot: Int) -> [String] {
        slot < rightReserve.count ? rightReserve[slot] : []
    }

    /// Every hint the screen can press is clickable, so a mouse reaches what a button does.
    func clickAction(_ item: HintItem) -> (() -> Void)? {
        if let action = item.action { return action }
        guard let press, let action = item.button?.action else { return nil }
        return { press(action) }
    }

    @ViewBuilder
    private func item(_ item: HintItem, reserve: [String] = []) -> some View {
        if let action = clickAction(item) {
            Button(action: action) { content(item, reserve: reserve).contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            content(item, reserve: reserve)
        }
    }

    private func content(_ item: HintItem, reserve: [String] = []) -> some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            if let button = item.button {
                SelenePromptBadge(button: button, keyboardOverride: item.keyboard)
            } else if let glyph = item.glyph {
                MaterialIconView(glyph, size: 18)
                    .foregroundColor(SeleneTheme.scrim)
                    .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
                    .frame(minWidth: canvas.u(30), minHeight: canvas.u(30))
                    .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.hint), style: .continuous).fill(SeleneTheme.ink))
            }
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .leading) {
                    ForEach(reserve, id: \.self) { Text(L10n.text($0, context: localization)).seleneFont(.text).hidden() }
                    Text(L10n.text(item.label, context: localization))
                        .seleneFont(.text)
                        .foregroundColor(SeleneTheme.ink90)
                }
                if let hold = item.hold, !ButtonPrompts.usesKeyboard(pad) || item.button == .rs {
                    Text(item.button == .rs ? hold : L10n.text(hold, context: localization))
                        .seleneFont(.badge).foregroundColor(SeleneTheme.ink60)
                }
            }
        }
        .shadow(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.veil), radius: canvas.u(4), y: canvas.u(1))
    }
}
