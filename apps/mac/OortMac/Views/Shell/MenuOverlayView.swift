import SwiftUI
import OortLibrary

/// Selene's control center (MenuScreen.cs): the screen dimmed at 0.55, one row of
/// icon buttons along the bottom, the focused item's name above a white ring.
/// Profile, Library and Power open a card of lines stacked above their icon, all as wide as the widest;
/// the screen then blurs under a heavier veil, as for the profile picker.
///
/// Keyboard input (arrows, Return, Space, Esc) is taken by the shell's key monitor
/// while the menu is open and sent through `menuInput`, the same path as the
/// controller. Mouse: hover focuses, click activates, a click on the scrim closes.
struct MenuOverlayView: View {
    @Environment(\.controllerHomeAvailable) private var hasHome
    var gamepadLayout: GamepadLayout = .arcane
    @ObservedObject var router: AppRouter
    @ObservedObject var cloudLibrary: CloudLibraryModel
    var activeProfile: LocalProfile? = nil
    let hasBuildActivity: Bool
    /// A click on a row button; the shell runs it.
    let onSelect: (MenuAction) -> Void
    /// A click on a Power pill; the shell runs it.
    let onSelectPower: (PowerAction) -> Void
    /// A click on a line of the Profile or Library card; the shell runs it.
    var onSelectEntry: (MenuEntry) -> Void = { _ in }
    let onTab: (Int) -> Void

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneReduceMotion) private var settingsReduceMotion
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var presented = false
    @State private var hover = SeleneHoverFocus()

    /// Gates scale and movement only; opacity always animates.
    private var reduceMotion: Bool {
        settingsReduceMotion || accessibilityReduceMotion
    }

    private var submenuOpen: Bool { router.menuSelection.isSubmenuOpen }

    // Selene units (MenuScreen.cs): 96u cells with no gap, a 70u dot with a 3u
    // ring, the bar 70u above the bottom edge, so the dot's centre is 105u up
    // (y = 975u of 1080u).
    private let cellWidth: CGFloat = 96
    private let dotSize: CGFloat = 70
    private let ringWidth: CGFloat = 3
    private let iconSize: CGFloat = 34
    private let labelBand: CGFloat = 26
    /// Between the name and the top of the ring (Selene: the pill sits Ring + 12 above the cell's bottom).
    private let labelGap = SeleneTokens.Space.small
    private let rowBottom: CGFloat = 70
    private let focusedScale: CGFloat = 1.1
    /// Above the Power pills' bottom edge, the gap to the name.
    private let pillsGap: CGFloat = 14

    var body: some View {
        SeleneOverlay(style: submenuOpen ? .deep : .menu, alignment: .bottom, onOutside: router.closeMenu) {
            row
                .padding(.bottom, canvas.u(rowBottom))

            // A sibling of the row, not an overlay of an icon: it sits outside that icon's bounds and must take the pointer.
            if let open = openCard {
                MenuCard(lines: open.lines)
                    .offset(x: canvas.u(CGFloat(open.index - MenuAction.allCases.count / 2) * cellWidth))
                    .padding(.bottom, canvas.u(rowBottom + labelBand + labelGap + dotSize + pillsGap))
                    .transition(.opacity)
            }

            // Where the screen underneath had its hints, which step aside while this is open.
            SeleneHintsBar(left: backHints,
                           right: [HintItem(.lb, "Previous") { onTab(-1) },
                                   HintItem(.rb, "Next") { onTab(1) },
                                   HintItem(.a, L10n.text("Select"))],
                           bottom: SeleneBottomScrim.hintsBottom, leftInset: 18,
                           press: { if $0 == .cancel { router.menuStep(.back) } })
        }
        .animation(Motion.anchoredCard(reduceMotion), value: submenuOpen)
        .onAppear { presented = true }
    }

    private var backHints: [HintItem] {
        // B closes the card first, then the control center.
        let back = HintItem(.b, submenuOpen ? "Back" : "Close")
        if hasHome, let center = gamepadLayout.tap(.controlCenter) {
            var hint = HintItem(center.prompt, "Close", hold: "Hold: Settings", action: router.closeMenu)
            hint.controllerOnly = true
            return [back, hint]
        }
        if router.route == .library || router.route.isCollection || isDetail,
           let fallback = gamepadLayout.guide().first(where: { $0.hold == .controlCenter }) {
            var hint = HintItem(fallback.prompt, "Hold: Close", action: router.closeMenu)
            hint.controllerOnly = true
            return [back, hint]
        }
        return [back]
    }

    private var isDetail: Bool { if case .detail = router.route { true } else { false } }

    // MARK: - Row

    private var row: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(MenuAction.allCases.enumerated()), id: \.element) { index, action in
                button(action, index: index)
            }
        }
    }

    private func button(_ action: MenuAction, index: Int) -> some View {
        let isFocused = router.menuSelection.selected == action
        let hasActivity = action == .activityCenter && (hasBuildActivity || cloudLibrary.isWorking)

        return Button {
            onSelect(action)
        } label: {
            VStack(spacing: 0) {
                Text(action == .profile ? activeProfile?.name ?? action.title : action.title)
                    .seleneFont(.text, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: canvas.u(labelBand), alignment: .bottom)
                    .opacity(isFocused ? 1 : 0)
                    .offset(y: isFocused || reduceMotion ? 0 : canvas.u(6))
                    .animation(Motion.focus(reduceMotion), value: isFocused)
                if action == .profile, activeProfile != nil, isFocused {
                    Text(action.title).seleneFont(.text).foregroundColor(SeleneTheme.ink60).lineLimit(1).fixedSize()
                }

                ZStack {
                    Circle()
                        .fill(SeleneTheme.ink.opacity(isFocused ? 0.12 : 0))
                        .frame(width: canvas.u(dotSize), height: canvas.u(dotSize))
                        .animation(Motion.focus(reduceMotion), value: isFocused)
                    Circle()
                        .strokeBorder(SeleneTheme.ink, lineWidth: canvas.u(ringWidth))
                        .frame(width: canvas.u(dotSize), height: canvas.u(dotSize))
                        .opacity(isFocused ? 1 : 0)
                        .animation(Motion.focus(reduceMotion), value: isFocused)
                    Group {
                        if action == .profile, let activeProfile {
                            ProfilePortrait(profile: activeProfile, size: 52)
                        } else {
                            MaterialIconView(action.icon, size: iconSize)
                        }
                    }
                        .foregroundColor(SeleneTheme.ink)
                        .overlay(alignment: .topTrailing) {
                            if hasActivity {
                                Circle().fill(SeleneTheme.statusOK)
                                    .frame(width: canvas.u(9), height: canvas.u(9))
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .padding(.top, canvas.u(labelGap))
                .frame(width: canvas.u(dotSize), height: canvas.u(dotSize))
                .scaleEffect(isFocused && !reduceMotion ? focusedScale : 1)
                .animation(Motion.focus(reduceMotion), value: isFocused)
            }
            .frame(width: canvas.u(cellWidth))
            .contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .onHover { hovering in
            if hover.moved(hovering), !submenuOpen { router.menuSelection.selected = action }
        }
        .accessibilityLabel(action.title)
        .accessibilityValue(hasActivity ? L10n.text("Activity in progress", context: localization) : "")
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
        .opacity(presented ? 1 : 0)
        .offset(y: presented || reduceMotion ? 0 : canvas.u(24))
        .animation(Motion.menuIcon(reduceMotion, index: index), value: presented)
    }

    // MARK: - Cards

    /// The icon with a card open above it, and the card's lines: Power's pills, or the entries of Profile and Library.
    private var openCard: (index: Int, lines: [MenuCard.Line])? {
        let model = router.menuSelection
        let action: MenuAction
        let lines: [MenuCard.Line]
        if model.isPowerOpen {
            action = .power
            lines = PowerAction.allCases.map { power in
                .init(id: power.id, title: power.title, icon: power.icon, width: 240, focused: model.power == power,
                      focus: { router.menuSelection.power = power },
                      choose: { router.menuSelection.power = power; onSelectPower(power) })
            }
        } else if model.isEntryOpen {
            action = model.selected
            lines = model.entries.map { entry in
                .init(id: entry.id, title: entry.title, icon: entry.icon, width: 320, focused: model.entry == entry,
                      focus: { router.menuSelection.entry = entry },
                      choose: { router.menuSelection.entry = entry; onSelectEntry(entry) })
            }
        } else {
            return nil
        }
        return (MenuAction.allCases.firstIndex(of: action) ?? 0, lines)
    }
}

/// The pills stacked above an icon. Over a 96-unit cell: the card takes the width of its widest title when that
/// is more than its minimum, and every pill takes that width, so the icons and titles line up.
struct MenuCard: View {
    struct Line: Identifiable {
        let id: String
        let title: String
        let icon: MaterialIcon
        let width: CGFloat
        let focused: Bool
        /// The pointer reached the pill.
        let focus: () -> Void
        let choose: () -> Void
    }

    let lines: [Line]
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            ForEach(lines) { line in
                SelenePillButton(title: line.title,
                                 icon: line.icon,
                                 minWidth: line.width,
                                 fillsWidth: true,
                                 focused: line.focused, action: line.choose)
                .seleneHover(line.focus)
                .accessibilityLabel(line.title)
            }
        }
        .fixedSize()
    }
}
