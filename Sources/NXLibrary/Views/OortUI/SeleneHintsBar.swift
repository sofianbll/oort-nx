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

extension ConnectedPad {
    init(connected: Bool, brand: GamepadBrand) {
        guard connected else { self = .none; return }
        switch brand {
        case .nintendoSwitch: self = .nintendo
        case .xbox: self = .xbox
        case .playstation: self = .playstation
        case .generic: self = .other
        }
    }
}

struct SeleneHintsBar: View {
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneButtonNames) private var style
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

    var body: some View {
        if showHints {
            HStack(alignment: .bottom, spacing: canvas.u(SeleneTokens.Space.titleGap)) {
                HStack(spacing: canvas.u(SeleneTokens.Space.titleGap)) {
                    ForEach(visibleLeft(style: style, connected: pad)) { item($0) }
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

    private var pad: ConnectedPad {
        ConnectedPad(connected: controller.isGamepadConnected, brand: controller.activeBrand)
    }

    func visibleLeft(style: ButtonNameStyle, connected: ConnectedPad) -> [HintItem] {
        left.filter {
            (!$0.keyboardOnly || ButtonPrompts.usesKeyboard(style: style, connected: connected))
                && ButtonPrompts.showsHint($0.button, controllerOnly: $0.controllerOnly, style: style, connected: connected)
        }
    }

    private var rightSlots: [HintItem?] {
        (0..<max(right.count, rightReserve.count)).map { $0 < right.count ? right[$0] : nil }
    }

    private func reserve(_ slot: Int) -> [String] {
        slot < rightReserve.count ? rightReserve[slot] : []
    }

    @ViewBuilder
    private func item(_ item: HintItem, reserve: [String] = []) -> some View {
        if let action = item.action {
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
                if let hold = item.hold, !ButtonPrompts.usesKeyboard(style: style, connected: pad) || item.button == .rs {
                    Text(item.button == .rs ? hold : L10n.text(hold, context: localization))
                        .seleneFont(.badge).foregroundColor(SeleneTheme.ink60)
                }
            }
        }
        .shadow(color: SeleneTheme.artShade.opacity(SeleneTokens.Alpha.veil), radius: canvas.u(4), y: canvas.u(1))
    }
}
