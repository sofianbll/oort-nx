import SwiftUI
import NXLibraryCore

/// Shared from the launcher controls and a built game's options. Each entry owns
/// its existing parent navigation; this screen only owns its own panels and hints.
struct PlayersScreen: View {
    @ObservedObject var model: PlayersScreenModel
    let onClose: () -> Void
    var orderNotes: [Int: String] = [:]
    var modeNote: String?
    var profileNotes: [Int: String] = [:]

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var hover = SeleneHoverFocus()

    var body: some View {
        let covered = model.pin != nil || model.capturePlayer != nil || model.confirmsReset
        SeleneOverlay(style: .deep, onOutside: back) {
            VStack(spacing: 0) {
                column
                SeleneHintsBar(left: [HintItem(.b, "Back", action: back)],
                               right: [HintItem(.navigate, "Move"), HintItem(.a, "Select", action: activate)])
            }
            .seleneOverlayOwnership(!covered)
            .opacity(model.capturePlayer != nil || model.pin != nil ? 0.24 : 1)
            if let pin = model.pin {
                SeleneOverlay(style: .profileRemoval, onOutside: back) {
                    ProfilePINDialog(title: "Unlock profile", input: .playersPIN,
                                     onCancel: back, onPIN: model.submitPIN)
                        .id(pin.id)
                }
            }
            if let number = model.capturePlayer {
                capturePrompt(number)
            }
            if model.confirmsReset {
                SeleneOverlay(style: .dialog, onOutside: back) {
                    SeleneConfirmDialog(title: "Reset players?", message: t("This clears the player profiles and controller assignments."),
                                        confirmTitle: "Reset", focus: $model.resetFocus, onCancel: back, onConfirm: model.reset)
                }
            }
        }
        .environment(\.seleneMinimumFont, 12)
        .onDisappear { model.endCapture() }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small)) {
            Text(verbatim: heading)
                .seleneFont(.screenTitle)
                .foregroundStyle(SeleneTheme.ink)
                .accessibilityAddTraits(.isHeader)
            if model.page == .overview {
                copy("The profile name is used only offline and in local play. Online, Nextendo keeps its own name.")
            }
            if let message = model.message { copy(message) }
            if model.loading || model.saving { SeleneProgressBar(progress: nil) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                        if model.page == .overview && model.hasIdenticalPads && model.leaseCapture != nil {
                            copy("These controllers look identical. Choose a player and press a button on the controller to assign it.")
                        }
                        ForEach(model.rows, id: \.self) { id in row(id) }
                    }
                    .padding(canvas.u(SeleneTokens.Space.tight))
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.focusedRow) { _, focus in
                    guard let focus else { return }
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(focus) }
                }
            }
        }
        .frame(maxWidth: canvas.u(1040), maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, canvas.u(SeleneTokens.Space.chromeGutter))
        .padding(.top, canvas.u(SeleneTokens.Space.stageHeader))
        .padding(.bottom, canvas.u(SeleneTokens.Space.control))
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var heading: String {
        switch model.page {
        case .overview: t("Players")
        case .modes: t("Controller mode")
        case .player(let number): playerTitle(number)
        case .profiles: t("Choose a profile")
        case .swap: t("Swap with…")
        case .mergeTargets: t("Choose who gets all controllers")
        }
    }

    private func capturePrompt(_ number: Int) -> some View {
        SeleneOverlay(style: .dialog, onOutside: back) {
            VStack(spacing: canvas.u(SeleneTokens.Space.control)) {
                Label(L10n.format("Press a button on the controller for player %lld", [number], context: localization),
                      systemImage: "gamecontroller")
                    .seleneFont(.dialogTitle, .semibold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if model.hasIdenticalPads {
                    copy("These controllers look identical. Your button press tells them apart.")
                }
                SelenePillButton(title: "Cancel", focused: false, action: back)
            }
            .foregroundStyle(SeleneTheme.ink)
            .modifier(SeleneDialogCard(width: nil))
        }
        .overlay(alignment: .bottom) {
            // Every controller button is input for this step, even the usual Back button.
            SeleneHintsBar(left: [HintItem(nil, "Cancel (Esc)", glyph: .close, action: back)])
        }
    }

    private func row(_ id: PlayersScreenModel.Row) -> some View {
        let presentation = presentation(id)
        return Button {
            model.select(id)
        } label: {
            SeleneOptionRow(icon: presentation.icon, title: presentation.title, about: presentation.about,
                            focused: model.focusedRow == id, destructive: id == .remove,
                            leading: presentation.portrait.map { AnyView(ProfilePortrait(profile: $0, size: SeleneTokens.Space.group)) }) {
                if presentation.selected {
                    MaterialIconView(.done, size: SeleneTokens.Space.large)
                        .foregroundStyle(SeleneTheme.glyph)
                        .accessibilityHidden(true)
                } else if presentation.opens {
                    HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                        if let pad = presentation.pad {
                            Image(systemName: pad)
                                .seleneFont(.rowTitle)
                                .foregroundStyle(SeleneTheme.rowIcon)
                        }
                        MaterialIconView(.chevron, size: SeleneTokens.Space.large)
                            .foregroundStyle(SeleneTheme.ink60)
                    }
                    .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.saving || model.loading)
        .accessibilityAddTraits(presentation.selected ? .isSelected : [])
        .onHover { if hover.moved($0) { model.focus = id } }
        .id(id)
    }

    private struct Presentation {
        var title: String
        var about: String?
        var icon: MaterialIcon?
        var portrait: LocalProfile?
        var pad: String?
        var selected = false
        var opens = false
    }

    private func presentation(_ row: PlayersScreenModel.Row) -> Presentation {
        switch row {
        case .modes:
            return .init(title: t("Controller mode"), about: joined([modeTitle(model.plan.mode), modeDescription(model.plan.mode),
                          modeNote.map(t)]), icon: .gamepad, opens: true)
        case .mode(let mode):
            return .init(title: modeTitle(mode), about: modeDescription(mode), selected: model.plan.mode == mode)
        case .player(let number), .swapWith(let number):
            let profile = model.profile(for: number)
            let label = L10n.format("Player %lld · %@", [number, profile?.name ?? t("Guest")], context: localization)
            let note: String?
            switch model.access(for: number) {
            case .missing: note = t("Profile not found")
            case .locked: note = t("Profile locked")
            default: note = profileNotes[number].map(t)
            }
            return .init(title: label, about: joined([padDescription(number), orderNotes[number].map(t), note]), icon: profile == nil ? .person : nil,
                         portrait: profile, pad: padSymbol(number), opens: row == .player(number))
        case .add: return .init(title: t("Add player"), icon: .add)
        case .reset: return .init(title: t("Reset players"), icon: .restore)
        case .retry: return .init(title: t("Retry"), icon: .sync)
        case .profiles:
            let number = if case .player(let number) = model.page { number } else { 0 }
            let profile = model.profile(for: number)
            return .init(title: t("Choose a profile"), about: profile?.name ?? t("Guest"),
                         icon: profile == nil ? .person : nil, portrait: profile, opens: true)
        case .assign: return .init(title: t("Assign controller"), icon: .gamepad, opens: true)
        case .identify: return .init(title: t("Identify"), icon: .gamepad)
        case .swap: return .init(title: t("Swap players"), icon: .swap, opens: true)
        case .remove: return .init(title: t("Remove player"), icon: .delete)
        case .mergeTarget:
            let number = model.mergeTarget
            let limitation = model.showsGameLimits && !model.supportsExtendedMerge
                ? t("This game's app can only combine controllers on player 1.") : nil
            return .init(title: t("Choose who gets all controllers"),
                         about: joined([playerTitle(number), limitation]), icon: .person, opens: true)
        case .target(let number):
            let profile = model.profile(for: number)
            return .init(title: playerTitle(number), about: profile?.name ?? t("Guest"), icon: profile == nil ? .person : nil,
                         portrait: profile, selected: number == model.mergeTarget)
        case .profile(let id):
            let profile = model.profiles.first { $0.id == id }
            let number = if case .profiles(let number) = model.page { number } else { 0 }
            return .init(title: profile?.name ?? t("Guest"), about: profile?.isLocked == true ? t("Profile locked") : nil,
                         icon: profile == nil ? .person : nil, portrait: profile, selected: model.plan.slot(number)?.profileID == id)
        }
    }

    private func padDescription(_ number: Int) -> String {
        if model.plan.mode == .merge {
            guard number == model.mergeTarget else { return t("On hold while controllers are combined") }
            if model.pads.isEmpty { return t("No controllers connected") }
            return model.pads.map(padLabel).joined(separator: "\n")
        }
        if let pad = model.connectedPad(number) { return padLabel(pad) }
        switch model.resolution.slots[number] {
        case .inactive: return t("On hold while controllers are combined")
        case .needsConfirmation: return t(model.leaseCapture == nil
                                         ? "Controller assignment is unavailable right now."
                                         : "Press a button to confirm the controller")
        case .disconnected: return t("Controller disconnected")
        default: return t("No controller assigned")
        }
    }

    private func padLabel(_ pad: ConnectedController) -> String {
        let battery = pad.status.batteryLevel.map {
            L10n.format("Battery: %@", [Double($0).formatted(.percent.precision(.fractionLength(0)).locale(localization.formatLocale))],
                        context: localization)
        }
        return joined([pad.name ?? t("Gamepad"), t("Connected"), battery], separator: " · ") ?? ""
    }

    private func padSymbol(_ number: Int) -> String? {
        if model.plan.mode == .merge && number == model.mergeTarget { return "gamecontroller" }
        if let pad = model.connectedPad(number) {
            switch pad.kind {
            case .nintendoSwitch: return "logo.nintendoswitch"
            case .xbox: return "logo.xbox"
            case .playstation: return "logo.playstation"
            case .generic: return "gamecontroller"
            }
        }
        return model.plan.slot(number)?.controller == nil ? nil : "gamecontroller"
    }

    private func modeTitle(_ mode: PlayerControllerMode) -> String {
        switch mode {
        case .inOrder: t("In order")
        case .pressToJoin: t("Press to join")
        case .merge: t("All controllers on one player")
        }
    }

    private func modeDescription(_ mode: PlayerControllerMode) -> String {
        switch mode {
        case .inOrder: t("Keep the player order you set here.")
        case .pressToJoin: t("Each player presses a button in the game to join.")
        case .merge: t("Every controller plays for the selected profile.")
        }
    }

    private func t(_ value: String) -> String { L10n.text(value, context: localization) }
    private func playerTitle(_ number: Int) -> String {
        L10n.format("Player %lld", [number], context: localization)
    }
    private func joined(_ lines: [String?], separator: String = "\n") -> String? {
        let content = lines.compactMap { $0 }.joined(separator: separator)
        return content.isEmpty ? nil : content
    }
    private func copy(_ value: String) -> some View {
        Text(verbatim: t(value))
            .seleneFont(.caption)
            .foregroundStyle(SeleneTheme.ink75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
