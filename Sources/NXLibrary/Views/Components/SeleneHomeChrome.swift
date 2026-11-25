import SwiftUI
import NXLibraryCore

private struct ControllerHomeAvailableKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var controllerHomeAvailable: Bool {
        get { self[ControllerHomeAvailableKey.self] }
        set { self[ControllerHomeAvailableKey.self] = newValue }
    }
}

/// The frame Spotlight and Collection share, so what stays put between them sits
/// in the same place: the art (and any dimming) full bleed, the bottom fade, the
/// 1920 × 1080 stage centred across and pinned to the top (a taller window gives
/// its spare height to the bottom, never to a gap above the tabs), and the hints
/// on the window's bottom edge. The stage draws the top bar at its own (0, 0).
struct SeleneHomeChrome<Backdrop: View, Stage: View>: View {
    @Environment(\.seleneCanvas) private var canvas

    var leftHints: [HintItem]
    var rightHints: [HintItem]
    var rightReserve: [[String]] = []
    /// An overlay with its own hints is up (`AppRouter.overlayHasHints`).
    var hintsHidden = false
    /// Spotlight's entrance holds them until everything else has landed; the change brings its own fade.
    var hintsHeld = false
    @ViewBuilder var backdrop: () -> Backdrop
    @ViewBuilder var stage: () -> Stage

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop()
            SeleneBottomScrim()
            stage()
                .frame(width: canvas.stageSize.width, height: canvas.size.height, alignment: .topLeading)
                .offset(x: canvas.stageOrigin.x)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: leftHints, right: rightHints,
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18,
                               rightReserve: rightReserve)
            }
            .seleneOverlaidHints(hintsHidden)
            .opacity(hintsHeld ? 0 : 1)
            .allowsHitTesting(!hintsHeld)
            .frame(width: canvas.size.width, height: canvas.size.height)
        }
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .clipped()
    }
}

extension HintItem {
    /// Both home screens share View's hold label and the keyboard-only search keycap.
    static func homeGlobals(other: String, onOther: (() -> Void)?, onMenu: @escaping () -> Void,
                            onSearch: @escaping () -> Void, onProfiles: @escaping () -> Void,
                            layout: GamepadLayout = .arcane, hasHome: Bool = true,
                            showsOptions: Bool = true) -> [HintItem] {
        var view = HintItem(layout.tap(.view)?.prompt, onOther == nil ? "Hold: Search" : other,
                            hold: onOther == nil ? nil : "Hold: Search", action: onOther ?? onSearch)
        view.controllerOnly = onOther == nil
        var hints = [view, HintItem(.search, "Search", action: onSearch)]
        if let menu = layout.tap(.menu) {
            hints.insert(HintItem(menu.prompt, "Menu", hold: "Hold: Settings", action: onMenu), at: 1)
        } else {
            var keyboardMenu = HintItem(.menu, "Menu", action: onMenu)
            keyboardMenu.keyboardOnly = true
            hints.insert(keyboardMenu, at: 1)
        }
        if let search = layout.tap(.browseSearch) {
            var hint = HintItem(search.prompt, "Search", action: onSearch)
            hint.controllerOnly = true
            hints.append(hint)
        }
        if let center = layout.tap(.controlCenter), hasHome {
            var hint = HintItem(center.prompt, "Control center", hold: "Hold: Settings", action: onMenu)
            hint.controllerOnly = true
            hints.append(hint)
        } else if !showsOptions, let fallback = layout.guide().first(where: { $0.hold == .controlCenter }) {
            var hint = HintItem(fallback.prompt, "Hold: Control center", action: onMenu)
            hint.controllerOnly = true
            hints.append(hint)
        }
        var profiles = HintItem(layout.tap(.profiles)?.prompt ?? .home, "Profiles", action: onProfiles)
        profiles.keyboardOnly = !hasHome || layout.tap(.profiles) == nil
        return hints + [profiles]
    }

    static func browsingOptions(_ layout: GamepadLayout, _ label: String, hasHome: Bool,
                                action: (() -> Void)? = nil) -> HintItem {
        let binding = layout.tap(.contextAction)
        return HintItem(binding?.prompt, label, hold: !hasHome && binding?.hold == .controlCenter
                        ? "Hold: Control center" : nil, keyboard: .text("Y"), action: action)
    }
}

extension AppRouter {
    /// The control center, search, Game options, Add game or the console is up: each draws its own hints,
    /// so the screen's step aside instead of showing through.
    @MainActor
    func overlayHasHints(_ viewModel: AppViewModel) -> Bool {
        isMenuPresented || isSearchPresented || isPalettePresented || viewModel.isGameOptionsOpen || viewModel.profileOwnsInput || route.isOverlay
    }
}

extension View {
    /// A screen's hints under an overlay that has its own: they sink a little and
    /// fade out as it opens, and come back the same way as it closes.
    func seleneOverlaidHints(_ hidden: Bool) -> some View {
        modifier(OverlaidHints(hidden: hidden))
    }
}

private struct OverlaidHints: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden && !reduceMotion ? canvas.u(12) : 0)
            .animation(reduceMotion ? nil : SeleneTheme.cubicOut(0.3), value: hidden)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}
