import SwiftUI
import NXLibraryCore

/// Shared from the launcher controls and a built game's options. Each entry owns
/// its existing parent navigation; this screen only owns its own panels and hints.
struct PlayersScreen: View {
    static let columns = 4

    @ObservedObject var model: PlayersScreenModel
    let onClose: () -> Void
    var orderNotes: [Int: String] = [:]
    var modeNote: String?
    var profileNotes: [Int: String] = [:]
    var saveSettingsDraft: (() -> Void)?

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var hover = SeleneHoverFocus()

    var body: some View {
        let covered = model.pin != nil || model.capturePlayer != nil || model.confirmsReset
        SeleneOverlay(style: .page, onOutside: back) {
            VStack(spacing: 0) {
                stage
                SeleneHintsBar(left: [HintItem(.b, isEditing ? "Cancel" : "Back", action: back)],
                               right: commandHints)
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

    private var stage: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.section)) {
            Text(verbatim: t("Players"))
                .seleneFont(.screen)
                .foregroundStyle(SeleneTheme.ink)
                .accessibilityAddTraits(.isHeader)
            copy(model.message ?? (model.loading ? "Loading…" : instruction))
            if model.readable {
                modes
                Grid(horizontalSpacing: canvas.u(SeleneTokens.Space.small), verticalSpacing: canvas.u(SeleneTokens.Space.small)) {
                    ForEach(0..<(model.places.count / Self.columns), id: \.self) { band in
                        GridRow {
                            ForEach(1...Self.columns, id: \.self) { index in
                                playerCard(band * Self.columns + index)
                            }
                        }
                    }
                }
                if case .profiles(let number) = model.page {
                    profileChoices(number)
                } else if let note = launchNote {
                    copy(note)
                }
            } else if !model.loading {
                SelenePillButton(title: "Retry", focused: true, scalesOnFocus: false, action: activate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, canvas.u(SeleneTokens.Space.chromeGutter))
        .padding(.top, canvas.u(SeleneTokens.Space.stageHeader))
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var modes: some View {
        let focused: PlayerControllerMode? = if case .mode(let mode) = gridFocus { mode } else { nil }
        return OortSegmented(selection: Binding(get: { model.plan.mode }, set: {
            model.focus = .mode($0)
            model.selectMode($0)
        }), options: PlayerControllerMode.allCases.map { ($0, modeTitle($0)) },
        preset: .modeBar, focused: focused, hint: modeDescription,
        onFocus: { if !isEditing { model.focus = .mode($0) } })
        .disabled(isEditing || model.saving)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("Controller mode"))
    }

    private func playerCard(_ number: Int) -> some View {
        let profile = model.profile(for: number)
        let populated = model.plan.slot(number) != nil
        let receivesAllPads = model.plan.mode == .merge && number == model.mergeTarget
        let mark = receivesAllPads || model.joinedPlayer == number && model.connectedPad(number) != nil
        let name = profile?.name ?? (populated || receivesAllPads ? t("Guest") : t("Empty place"))
        let hasPlayer = populated || receivesAllPads
        let title = hasPlayer
            ? L10n.format("Player %lld · %@", [number, name], context: localization) : playerTitle(number)
        let details = hasPlayer ? padDescription(number) : name
        let row: PlayersScreenModel.Row = isMoving ? .swapWith(number) : .player(number)
        let spoken = ((hasPlayer ? [name] : []) + (receivesAllPads && !model.pads.isEmpty ? model.pads.map(padLabel) : [details]))
            .joined(separator: ", ")
        return OortPlayerSlot(title: title, detail: details, accessibilityTitle: playerTitle(number),
                          accessibilityValue: spoken, focused: gridFocus == row || profilePlayer == number,
                          selected: receivesAllPads, marked: mark, action: { chooseCard(number) }) {
            portrait(profile)
        }
        .onHover { if hover.moved($0), profilePlayer == nil { model.focus = row } }
        .disabled(model.saving)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: model.joinedPlayer)
    }

    private func profileChoices(_ number: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    ForEach(model.rows, id: \.self) { row in
                        if case .profile(let id) = row {
                            let profile = model.profiles.first { $0.id == id }
                            Button { model.select(row) } label: {
                                SeleneOptionRow(icon: profile?.isLocked == true ? .lock : nil,
                                                title: profile?.name ?? t("Guest"), about: nil, focused: gridFocus == row,
                                                leading: portrait(profile)) {
                                    if model.plan.slot(number)?.profileID == id {
                                        MaterialIconView(.done, size: SeleneTokens.Space.large)
                                            .foregroundStyle(SeleneTheme.glyph)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(OortPressStyle())
                            .accessibilityAddTraits(model.plan.slot(number)?.profileID == id ? .isSelected : [])
                            .id(row)
                            .onHover { if hover.moved($0) { model.focus = row } }
                        }
                    }
                }
                .padding(canvas.u(SeleneTokens.Space.tight))
            }
            .scrollIndicators(.hidden)
            .onChange(of: gridFocus, initial: true) { _, row in
                proxy.scrollTo(row)
            }
            .accessibilityLabel(t("Choose a profile"))
            .accessibilityHint(t("The profile name is used only offline and in local play. Online, Nextendo keeps its own name."))
        }
    }

    private var instruction: String {
        if isMoving { return "Choose the destination place." }
        if profilePlayer != nil { return "Choose a profile for offline or local play." }
        if model.plan.mode == .merge { return "Every controller plays for the selected profile." }
        return "Press a button on a free controller to join."
    }

    private var launchNote: String? {
        if model.plan.mode == .merge && model.showsGameLimits && !model.supportsExtendedMerge {
            return "This game's app can only combine controllers on player 1."
        }
        if let number = focusedPlayer {
            switch model.access(for: number) {
            case .missing: return "Profile not found"
            case .locked: return "Profile locked"
            default: break
            }
            let notes = [orderNotes[number], profileNotes[number]].compactMap { $0 }.map(t)
            if !notes.isEmpty { return notes.joined(separator: " · ") }
        }
        return modeNote
    }

    private func capturePrompt(_ number: Int) -> some View {
        SeleneOverlay(style: .dialog, onOutside: back) {
            VStack(spacing: canvas.u(SeleneTokens.Space.control)) {
                Label(L10n.format("Press a button on the controller for player %lld", [number], context: localization),
                      systemImage: "gamecontroller")
                    .seleneFont(.screen, .semibold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if model.hasIdenticalPads {
                    Text(verbatim: t("These controllers look identical. Your button press tells them apart."))
                        .seleneFont(.text)
                        .foregroundStyle(SeleneTheme.ink75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SelenePillButton(title: "Cancel", focused: true, scalesOnFocus: false, action: back)
            }
            .foregroundStyle(SeleneTheme.ink)
            .modifier(SeleneDialogCard())
        }
        .overlay(alignment: .bottom) {
            SeleneHintsBar(left: [HintItem(.b, "Cancel", action: back)])
        }
    }

    private func portrait(_ profile: LocalProfile?) -> AnyView {
        if let profile {
            return AnyView(ProfilePortrait(profile: profile, size: SeleneTokens.Space.group))
        }
        return AnyView(MaterialIconView(.person, size: SeleneTokens.Space.large)
            .foregroundStyle(SeleneTheme.rowIcon)
            .frame(width: canvas.u(SeleneTokens.Space.group))
            .accessibilityHidden(true))
    }

    private func padDescription(_ number: Int) -> String {
        if model.plan.mode == .merge {
            guard number == model.mergeTarget else { return t("On hold while controllers are combined") }
            if model.pads.isEmpty { return t("No controllers connected") }
            let suffix = model.pads.count > 2
                ? [L10n.format("+%lld more", [model.pads.count - 2], context: localization)] : []
            return (model.pads.prefix(2).map(padLabel) + suffix).joined(separator: "\n")
        }
        if let pad = model.connectedPad(number) { return padLabel(pad) }
        if model.plan.slot(number) == nil { return t("No controller assigned") }
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
        return [pad.name ?? t("Gamepad"), battery ?? t("Connected")].joined(separator: "\n")
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
    private func copy(_ value: String) -> some View {
        Text(verbatim: t(value))
            .seleneFont(.row)
            .foregroundStyle(SeleneTheme.ink75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
