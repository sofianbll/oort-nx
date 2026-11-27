import SwiftUI
import AppKit
import OortLibrary
import ArcanePorting

/// The column and its rows: entries, hints, the info line, accessibility values and each row's trailing value.
extension GameOptionsView {
    @ViewBuilder
    func column(_ p: GameOptionsPresentation) -> some View {
        if level == .main { quickPanel(p) } else { detailsColumn(p) }
    }

    /// Beside the game it belongs to, which stays in view: name, a few rows, then the full page.
    private func quickPanel(_ p: GameOptionsPresentation) -> some View {
        let focused = focusedRow
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            OortSidePanel(title: current.name) {
                playersRow
                ForEach(p.quickRows(), id: \.self) { rowView($0, p, focused: focused) }
                rowView(.allSettings, p, focused: focused)
            }
        }
    }

    private func detailsColumn(_ p: GameOptionsPresentation) -> some View {
        let entries = p.entries(level: level, origin: origin, context: localization)
        let focused = focusedRow
        return VStack(alignment: .leading, spacing: 0) {
            Text(current.name)
                .seleneFont(.screen)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.leading, canvas.u(SeleneTokens.Space.tight))
            PlatformLabel(current.isSwitch2 ? .switch2 : .switch1, preset: .caption)
                .foregroundStyle(SeleneTheme.ink75)
                .padding(.leading, canvas.u(SeleneTokens.Space.tight))
                .padding(.bottom, canvas.u(SeleneTokens.Space.line))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            entryView(entry, p, focused: focused)
                        }
                    }
                    // The clip would shave the first row's focus border.
                    .padding(.top, canvas.u(SeleneTokens.Space.tight))
                    .padding(.bottom, canvas.u(SeleneTokens.Space.large))
                    // Rows are measured in the list's own space, which scrolling never changes.
                    .coordinateSpace(name: OptionsScrollBox.space)
                    .onPreferenceChange(OptionRowFrames.self) { scrollBox.frames = $0 }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: canvas.u(680))
                .onChange(of: focusedItem) { _, row in
                    // A focus that followed the wheel leaves the list where the user put it.
                    if scrollBox.holdScroll { scrollBox.holdScroll = false; return }
                    guard let row else { return }
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                        proxy.scrollTo(row, anchor: .center)
                    }
                }
            }
            .id(level)
        }
        .frame(width: canvas.u(1040), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas.u(SeleneTokens.Space.pageTop))
        .padding(.bottom, canvas.u(SeleneTokens.Space.stageHeader))
        // Clicks inside the column are not clicks on the scrim; only the dimmed area outside closes.
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func entryView(_ entry: GameOptionsEntry, _ p: GameOptionsPresentation,
                           focused: GameOptionsRow?) -> some View {
        switch entry {
        case .row(let row):
            rowView(row, p, focused: focused)
        case .heading(let text):
            Text(text)
                .seleneFont(.text, .semibold)
                .foregroundColor(isSelene ? SeleneTheme.ink75 : SeleneTheme.glyph)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, canvas.u(SeleneTokens.Space.large))
                .padding(.top, canvas.u(SeleneTokens.Space.medium))
        case .note(let title, let text):
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                Text(title)
                    .seleneFont(.row, .medium)
                    .foregroundColor(SeleneTheme.ink60)
                Text(text)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, canvas.u(SeleneTokens.Space.large))
            .padding(.top, canvas.u(SeleneTokens.Space.control))
            .padding(.trailing, canvas.u(SeleneTokens.Space.large))
            .padding(.bottom, canvas.u(SeleneTokens.Space.control))
            .oortPanel(radius: canvas.u(SeleneTokens.Radius.card))
        case .gap:
            // Stack spacing is 8u on each side, so 8u here makes the 24u gap before a danger zone.
            Color.clear.frame(height: canvas.u(8))
        }
    }

    /// Selene's headings are a soft ink, not its blue accent.
    private var isSelene: Bool { ThemeStore.shared.palette.id == SelenePaletteCatalog.classicBlueID }

    private func rowView(_ row: GameOptionsRow, _ p: GameOptionsPresentation,
                         focused: GameOptionsRow?) -> some View {
        let downloadsSources = row == .rebuild && p.sourcesDetached && viewModel.canCheckCloudSources(for: current)
        let checking = row == .rebuild && checkingRebuild
        let title = checking ? L10n.text("Checking the build cache…") : row.title
        let about = row == .multiplayer && !p.isFixed(row) ? multiplayerRoute
            : row == .mods && multiplayerMode == .online ? L10n.text("Code mods off")
            : row == .gameDisplay ? gameDisplayNote ?? p.about(row)
            : checking ? nil : downloadsSources && !p.toolchainBlocked
            ? L10n.text("Arcane checks the cloud for missing game files.") : p.about(row)
        return SeleneOptionRow(icon: row == .multiplayer ? nil : row.icon,
                        title: title,
                        about: about,
                        focused: focused == row,
                        destructive: row.isDestructive,
                        enabled: checking || (downloadsSources ? !p.toolchainBlocked : !p.isDimmed(row))
                            && (row != .gameDisplay || canChooseGameDisplay),
                        leading: row == .multiplayer ? AnyView(
                            Image(systemName: "person.2.fill")
                                .seleneFont(.row)
                                .foregroundColor(p.isDimmed(row) ? SeleneTheme.ink60 : SeleneTheme.rowIcon)
                                .frame(width: canvas.u(24))
                                .accessibilityHidden(true)
                        ) : nil) {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                if checking {
                    OortMeter(share: nil).frame(width: canvas.u(96))
                    Text(L10n.text("Cancel")).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                } else if let info = p.info(row) {
                    SeleneInfoTip(info, isShowing: Binding(
                        get: { infoRow == row },
                        set: { show in
                            if show { setFocus(row) }
                            infoRow = show ? row : (infoRow == row ? nil : infoRow)
                        }))
                }
                if !checking { trailing(row) }
            }
        }
        .help(checking ? L10n.text("Cancel") : p.info(row) ?? "")
        .background(GeometryReader { geometry in
            Color.clear.preference(key: OptionRowFrames.self,
                                   value: [.game(row): geometry.frame(in: .named(OptionsScrollBox.space))])
        })
        .contentShape(Rectangle())
        .onTapGesture { activate(row) }
        .onHover {
            guard rows.contains(.game(row)), row != focusedRow, hover.moved($0) else { return }
            scrollBox.holdScroll = true
            setFocus(row)
        }
        .containerValue(\.oortSettingsRow, true)
        .id(GameOptionsItem.game(row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(checking ? L10n.text("Cancel") : about ?? "")
        .accessibilityValue(accessibilityValue(row) ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate(row) }
    }

    private var playersRow: some View {
        Button(action: openPlayers) {
            SeleneOptionRow(icon: .gamepad, title: L10n.text("Players", context: localization), about: nil,
                            focused: focusedItem == .players) {
                MaterialIconView(.chevron, size: 24).foregroundColor(SeleneTheme.ink60).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .containerValue(\.oortSettingsRow, true)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: OptionRowFrames.self,
                                   value: [.players: geometry.frame(in: .named(OptionsScrollBox.space))])
        })
        .onHover {
            guard focusedItem != .players, hover.moved($0) else { return }
            scrollBox.holdScroll = true
            setFocus(GameOptionsItem.players)
        }
        .id(GameOptionsItem.players)
    }

    private var multiplayerRoute: String? {
        switch multiplayerMode {
        case .offline: return L10n.text("No network")
        case .online: return "Nextendo · Koya"
        case .local:
            let app = appNetworkSettings
            let vpn = app.multiplayerVPN
            if vpn == .none { return L10n.text("Same Wi-Fi") }
            guard snapshot?.setting(NXNativeGameSettings.remotePlayKey)?.accepts("1") == true else {
                return L10n.text("VPN unavailable · same Wi-Fi")
            }
            let connection = multiplayerAdapters.connection(for: vpn, manual: app.multiplayerAdapter)
            if case .connected = connection { return L10n.format("Via %@", [vpn.label]) }
            return L10n.text("VPN unavailable · same Wi-Fi")
        }
    }

    private var gameDisplayNote: String? {
        if fileGameDisplay != nil { return L10n.text("Set in env.txt") }
        guard let gameDisplayOverride else { return nil }
        return GameDisplay.resolve(gameDisplayOverride, connected: gameDisplays, arcane: nil).missing
            ? L10n.text(GameDisplay.disconnected) : nil
    }

    private var gameDisplayLabel: String {
        guard let choice = fileGameDisplay ?? gameDisplayOverride else { return L10n.text(GameDisplay.useGlobal) }
        let display = GameDisplay.resolve(choice, connected: gameDisplays, arcane: nil)
        if let name = gameDisplays.first(where: { $0.id == display.id })?.name { return name }
        if let fileGameDisplay { return fileGameDisplay.isEmpty ? "—" : fileGameDisplay }
        return L10n.text(GameDisplay.likeArcane)
    }

    /// Y opens the focused row's explanation, when it has one.
    func rightHints(_ p: GameOptionsPresentation) -> [HintItem] {
        if confirm == nil, focusedRow == .rebuild, checkingRebuild { return [HintItem(.a, L10n.text("Cancel"))] }
        let steps = confirm == nil && focusedRow.map(stepsBothWays) == true ? [HintItem(.move, "Change")] : []
        guard confirm == nil, let row = focusedRow, p.info(row) != nil else { return steps + [HintItem(.a, L10n.text("Select"))] }
        return steps + [HintItem(.y, infoRow == row ? L10n.text("Hide info") : L10n.text("Info")), HintItem(.a, L10n.text("Select"))]
    }

    /// Y: the focused row's explanation, open or closed.
    func toggleInfo() {
        guard confirm == nil, let row = focusedRow, presentation.info(row) != nil else { return }
        infoRow = infoRow == row ? nil : row
    }

    /// The state a VoiceOver user hears for a switch or a value chip.
    func accessibilityValue(_ row: GameOptionsRow) -> String? {
        if row.isToggle { return L10n.text(toggleValue(row) ? "On" : "Off") }
        if row.isChoice { return choiceText(row) }
        if row == .cheats { return cheatsValue }
        if row == .mods { return presentation.modsValue }
        return nil
    }

    @ViewBuilder
    private func trailing(_ row: GameOptionsRow) -> some View {
        if row.isToggle {
            // The row takes the click; the switch only shows the state.
            SeleneSwitch(isOn: .constant(toggleValue(row))).allowsHitTesting(false)
        } else if stepsBothWays(row) {
            SeleneCycleValue(title: row.title, value: choiceText(row)) { adjust(row, by: $0) }
        } else if row.isChoice {
            SeleneValueChip(text: choiceText(row))
        } else if row == .cheats || row == .mods {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                if row == .mods || cheatsValue != nil {
                    SeleneValueChip(text: row == .cheats ? presentation.cheatsValue : presentation.modsValue)
                }
                MaterialIconView(.chevron, size: 24)
                    .foregroundColor(SeleneTheme.ink60)
            }
        } else if row.opensSubmenu {
            MaterialIconView(.chevron, size: 24)
                .foregroundColor(SeleneTheme.ink60)
        } else {
            EmptyView()
        }
    }

    /// A value with more than one way to go: ‹ › take a click, ← → the keys.
    private func stepsBothWays(_ row: GameOptionsRow) -> Bool {
        row.isChoice && !presentation.isFixed(row) && (row != .gameDisplay || canChooseGameDisplay)
    }

    private func toggleValue(_ row: GameOptionsRow) -> Bool {
        if let (setting, value) = settingValue(row) {
            return value == (setting.kind == "toggle" ? setting.on : row.onValue)
        }
        switch row {
        case .favorite: return current.isFavorite
        case .hidden: return current.isHidden
        case .fullscreen: return config.fullscreen
        case .fps60: return config.enable60FPS
        case .metalFX: return config.enableMetalFXUpscale
        case .metalHUD: return config.enableMetalHUD
        case .rumble: return config.rumble
        default: return false
        }
    }

    private func choiceText(_ row: GameOptionsRow) -> String {
        if row == .multiplayer { return L10n.text(multiplayerMode.label) }
        if let (setting, value) = settingValue(row) { return L10n.text(GameSettingValues.label(setting, value)) }
        switch row {
        case .gameDisplay:
            return gameDisplayLabel
        case .consoleMode:
            return GameOptionsValues.consoleModeLabel(docked: config.isDockedMode)
        case .language:
            return viewModel.availableLanguages.first { $0.code == config.language }?.label ?? config.language
        case .rumbleStrength:
            return "\(config.rumbleGain)"
        case .renderScale:
            return GameOptionsValues.renderScaleLabel(config.renderScale)
        default:
            return ""
        }
    }
}
