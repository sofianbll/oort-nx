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
                ForEach(LibraryFilter.allCases) { tab($0) }
                badge(.rb)
            }
            // Selene's order, right to left: the clock, then the profile's avatar just before it.
            HStack(spacing: canvas.u(16)) {
                Spacer()
                if let profile { profileButton(profile) }
                if showClock {
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: .dateTime.hour().minute())
                            .seleneFont(.panelTitle)
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
            .seleneFont(.panelBody, on ? .semibold : .regular)
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

/// A compact list anchored above the RS hint, like the control centre's Power menu.
struct LibrarySortMenu: View {
    let current: LibrarySort
    let focused: LibrarySort
    let choose: (LibrarySort) -> Void
    let close: () -> Void
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.24).contentShape(Rectangle()).onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: canvas.u(8)) {
                Text(L10n.text("Sort games")).seleneFont(.panelBody, .semibold)
                    .foregroundStyle(SeleneTheme.ink75)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, canvas.u(15))
                ForEach(LibrarySort.allCases, id: \.rawValue) { sort in
                    SelenePillButton(title: L10n.text(sort.title), icon: sort == current ? .check : nil,
                                     minWidth: 245, height: 44, focused: sort == focused, action: { choose(sort) })
                        .accessibilityAddTraits(sort == current ? .isSelected : [])
                }
            }
            .padding(canvas.u(SeleneTokens.Space.medium))
            .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.anchoredCard)).fill(SeleneTheme.glassCard))
            .padding(.trailing, canvas.u(SeleneTokens.Space.chromeGutter))
            .padding(.bottom, canvas.u(117))
            .accessibilityAction(named: Text(L10n.text("Back")), close)
        }
    }

    static func handle(_ action: GamepadAction, focused: inout LibrarySort?, choose: (LibrarySort) -> Void) {
        guard let sort = focused else { return }
        switch action {
        case .navigateUp, .navigateDown:
            let options = LibrarySort.allCases
            var position = FocusIndex(index: options.firstIndex(of: sort) ?? 0)
            position.move(by: action == .navigateUp ? -1 : 1, count: options.count)
            focused = options[position.index]
        case .confirm: focused = nil; choose(sort)
        case .cancel, .rightStickPress, .menu: focused = nil
        default: break
        }
    }

    static func hint(_ sort: LibrarySort, action: @escaping () -> Void) -> HintItem {
        HintItem(.rs, "Sort", hold: L10n.text(sort.title), action: action)
    }
}
