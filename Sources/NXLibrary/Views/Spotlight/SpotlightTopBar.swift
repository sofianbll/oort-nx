import SwiftUI
import NXLibraryCore

/// Selene's top bar (Main.xaml HubTopBarBackground + HomeNav.RenderFilterTabs):
/// 110 high, 64 side margins, LB · filter tabs · RB centered, profile avatar and clock on the right.
/// Shared by Spotlight and Collection.
struct SpotlightTopBar: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.nxAppLocale) private var locale
    @Environment(\.profilePortrait) private var profile
    @Environment(\.integrationBar) private var integrationBar

    let filter: LibraryFilter
    let sort: LibrarySort
    var tabs = LibraryFilter.defaultTabs
    var played = LibraryPlayed.any
    var onFilters: () -> Void = {}
    var showClock: Bool = true
    var profileFocused = false
    /// The profile's Nextendo account: its presence dot shows while the profile is visible online.
    var nextendo: NextendoSettings? = nil
    var onSelect: (LibraryFilter) -> Void = { _ in }

    @State private var popScale: CGFloat = 1
    @State private var popOpacity: Double = 1

    var body: some View {
        ZStack {
            HStack {
                integrationBar
                Spacer()
            }
            HStack(spacing: 0) {
                badge(.lb)
                ForEach(LibraryFilter.tabs(tabs + [filter])) { tab($0) }
                badge(.rb)
            }
            // Beside the tabs, which stay where they are.
            .overlay(alignment: .trailing) {
                if played != .any { activeFilter.fixedSize().alignmentGuide(.trailing) { $0[.leading] } }
            }
            // Selene's order, right to left: the clock, then the profile's avatar just before it.
            HStack(spacing: canvas.u(16)) {
                Spacer()
                if let profile { profileButton(profile) }
                if showClock {
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: .dateTime.hour().minute())
                            .seleneFont(.heading)
                            .foregroundColor(SeleneTheme.ink)
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityValue(L10n.text(sort.title, context: locale))
        .padding(.horizontal, canvas.u(SeleneTokens.Space.chromeGutter))
        .frame(height: canvas.u(110))
        .onChange(of: filter) { pop() }
    }

    private func profileButton(_ profile: LocalProfile) -> some View {
        Button(action: Self.openProfile) {
            ProfilePortrait(profile: profile, size: 44, ring: true)
                .overlay(alignment: .bottomTrailing) {
                    if let nextendo, profile.sharesPresence {
                        OnlineDot(nextendo: nextendo).offset(x: canvas.u(2), y: canvas.u(2))
                    }
                }
                .modifier(TileFocus(focused: profileFocused, radius: 22, scale: 1.1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.name)
        .accessibilityHint(L10n.text("Open profile", context: locale))
        .accessibilityAddTraits(profileFocused ? .isSelected : [])
    }

    static func openProfile() { NotificationCenter.default.post(name: .nxOpenLocalProfile, object: nil) }

    private func tab(_ item: LibraryFilter) -> some View {
        let on = item == filter
        return Text(L10n.text(item.rawValue))
            .seleneFont(.text, on ? .semibold : .regular)
            .foregroundColor(on ? SeleneTheme.onFocus : SeleneTheme.ink.opacity(0.7))
            .padding(EdgeInsets(top: canvas.u(5), leading: canvas.u(18),
                                bottom: canvas.u(7), trailing: canvas.u(20)))
            .background(
                RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.anchoredCard), style: .continuous)
                    .fill(on ? SeleneTheme.focus.opacity(0.95) : .clear)
            )
            .scaleEffect(on ? popScale : 1)
            .opacity(on ? popOpacity : 1)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.seam))
            .contentShape(Rectangle())
            .onTapGesture { onSelect(item) }
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// Says why games are missing, and opens the panel that brings them back.
    private var activeFilter: some View {
        Button(action: onFilters) {
            HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                MaterialIconView(.tune, size: 20)
                Text(L10n.text(played.rawValue, context: locale)).seleneFont(.text, .medium)
            }
            .foregroundStyle(SeleneTheme.ink)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.medium))
            .padding(.vertical, canvas.u(SeleneTokens.Space.tight))
            .background(Capsule().fill(SeleneTheme.glassSolid))
        }
        .buttonStyle(.plain)
        .padding(.leading, canvas.u(SeleneTokens.Space.small))
        .accessibilityLabel(L10n.text("Sort and filter", context: locale))
        .accessibilityValue(L10n.text(played.rawValue, context: locale))
    }

    private func badge(_ button: PromptButton) -> some View {
        SelenePromptBadge(button: button, height: 26)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
            .accessibilityHidden(true)
    }

    /// The new tab pops 0.86 → 1 over 200 ms (cubic out) and fades 0.4 → 1 over
    /// 160 ms. Reduce motion drops the pop and keeps the fade.
    private func pop() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            popScale = reduceMotion ? 1 : 0.86
            popOpacity = 0.4
        }
        DispatchQueue.main.async {
            if !reduceMotion { withAnimation(SeleneTheme.cubicOut(0.2)) { popScale = 1 } }
            withAnimation(.linear(duration: 0.16)) { popOpacity = 1 }
        }
    }
}

/// The presence dot on the avatar: green while Nextendo shares this profile as online.
private struct OnlineDot: View {
    @ObservedObject var nextendo: NextendoSettings
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        if nextendo.presenceShared == true {
            Circle().fill(SeleneTheme.statusOK)
                .frame(width: canvas.u(12), height: canvas.u(12))
                .overlay(Circle().strokeBorder(SeleneTheme.scrim, lineWidth: canvas.u(2)))
                .accessibilityHidden(true)
        }
    }
}

/// Sort and filter, beside the games they change. A choice applies at once and the panel stays open.
struct LibrarySortMenu: View {
    let sort: LibrarySort
    let played: LibraryPlayed
    let focused: LibraryMenuItem
    let choose: (LibraryMenuItem) -> Void
    let close: () -> Void
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        ZStack(alignment: .trailing) {
            SeleneTheme.scrim45.contentShape(Rectangle()).onTapGesture(perform: close)
            OortSidePanel(title: L10n.text("Sort and filter")) {
                SettingsSubheading(L10n.text("Sort games"))
                ForEach(LibrarySort.allCases, id: \.self) { row(.sort($0), chosen: $0 == sort) }
                SettingsSubheading(L10n.text("Games shown"))
                ForEach(LibraryPlayed.allCases, id: \.self) { row(.played($0), chosen: $0 == played) }
            }
            .accessibilityAction(named: Text(L10n.text("Back")), close)
            VStack {
                Spacer()
                SeleneHintsBar(left: [HintItem(.b, "Back", action: close)],
                               right: [HintItem(.a, "Select", action: { choose(focused) })])
            }
        }
    }

    private func row(_ item: LibraryMenuItem, chosen: Bool) -> some View {
        Button { choose(item) } label: {
            SeleneOptionRow(icon: nil, title: L10n.text(item.title), about: nil, focused: item == focused) {
                if chosen { MaterialIconView(.check, size: 24).foregroundStyle(SeleneTheme.ink) }
            }
        }
        .buttonStyle(.plain)
        .containerValue(\.oortSettingsRow, true)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    static func handle(_ action: GamepadAction, focused: inout LibraryMenuItem?, choose: (LibraryMenuItem) -> Void) {
        guard let item = focused else { return }
        switch action {
        case .navigateUp, .navigateDown:
            let options = LibraryMenuItem.all
            var position = FocusIndex(index: options.firstIndex(of: item) ?? 0)
            position.move(by: action == .navigateUp ? -1 : 1, count: options.count)
            focused = options[position.index]
        case .confirm: choose(item)
        case .cancel, .rightStickPress, .menu: focused = nil
        default: break
        }
    }

    static func hint(_ sort: LibrarySort, action: @escaping () -> Void) -> HintItem {
        HintItem(.rs, "Sort and filter", hold: L10n.text(sort.title), action: action)
    }
}
