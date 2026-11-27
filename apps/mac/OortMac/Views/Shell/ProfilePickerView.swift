import AppKit
import SwiftUI
import OortLibrary
import ArcanePorting

struct ProfilePortrait: View {
    let profile: LocalProfile
    let size: CGFloat
    var ring = false
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    @ObservedObject private var theme = ThemeStore.shared
    static let symbols = ["person.fill", "moon.stars.fill", "hare.fill", "cat.fill", "tortoise.fill",
                          "bird.fill", "leaf.fill", "bolt.fill", "flame.fill", "drop.fill",
                          "snowflake", "sparkle", "fish.fill", "pawprint.fill", "sun.max.fill",
                          "mountain.2.fill", "cloud.fill", "heart.fill", "star.fill", "gamecontroller.fill",
                          "circle.lefthalf.filled", "triangle.fill", "diamond.fill", "hexagon.fill",
                          "circle.hexagongrid.fill", "swirl.circle.fill", "sparkles", "person.crop.circle"]
    private static let colors: [UInt32] = [SeleneTokens.Art.portrait1, SeleneTokens.Art.portrait2, SeleneTokens.Art.portrait3, SeleneTokens.Art.portrait4, SeleneTokens.Art.portrait5,
                                           SeleneTokens.Art.portrait6, SeleneTokens.Art.portrait7, SeleneTokens.Art.portrait8, SeleneTokens.Art.portrait9, SeleneTokens.Art.portrait10]

    var accent: Color { Color(hex: SelenePaletteCatalog.resolve(profile.look.theme, in: theme.palettes).glyph) }

    var body: some View {
        let index = max(0, min(profile.avatar, Self.symbols.count - 1))
        let tint = Color(hex: Self.colors[index % Self.colors.count])
        ZStack {
            Circle().fill(tint.gradient)
            if let data = profile.portrait, ProfileAvatar.isGIF(data), !motion && !systemMotion {
                AnimatedProfilePortrait(data: data)
            } else if let data = profile.portrait, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: Self.symbols[index])
                    .font(.system(size: canvas.u(size * 0.43), weight: .medium))
                    .foregroundStyle(SeleneTheme.artInk)
            }
        }
        .frame(width: canvas.u(size), height: canvas.u(size))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ring ? accent : SeleneTheme.artInk.opacity(SeleneTokens.Alpha.soft), lineWidth: canvas.u(ring ? 2 : 1)))
        .accessibilityHidden(true)
    }
}

struct ProfilePickerView: View {
    @ObservedObject var profiles: LocalProfileStore
    let initialSelection: UUID?
    let canClose: Bool
    var isOverlay = false
    let games: [PortedGame]
    var avatarGames: [CatalogGame] = []
    var artwork: ArtworkStore? = nil
    let onChoose: (UUID) -> Void
    let onClose: () -> Void
    let onActiveEdited: () -> Void
    var onRemoved: (UUID) -> Void = { _ in }
    var onGuest: ((LocalProfile) -> Void)?
    var canRemove: (LocalProfile) -> Bool = { _ in true }
    var onEditActive: (() -> Void)?
    var dialogOwnsInput = false
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject private var theme = ThemeStore.shared
    @State var selected: UUID?
    @State var draft: LocalProfile?
    @State var removing: LocalProfile?
    @State var removalFocus: SeleneConfirmButton = .cancel
    @State private var appeared = false
    @State private var hover = SeleneHoverFocus()
    @State private var fadingEdges: Edge.Set = []
    @State private var newGuest = LocalProfile(name: L10n.text("Guest"), avatar: LocalProfile.avatarCount - 1, look: .init(AppSettings()))
    @AccessibilityFocusState(for: .voiceOver) private var accessibilityFocus: Tile?
    private enum Tile: Hashable { case profile(UUID), add }
    private var selection: UUID? { appeared ? selected : initialSelection }
    private var layers: ProfileLayers { .init(editing: draft != nil, removing: removing != nil) }
    private var guest: LocalProfile? { onGuest == nil ? nil : profiles.guest ?? newGuest }
    private var selectedProfile: LocalProfile? { profiles.profiles.first { $0.id == selection } }

    var body: some View {
        Group {
            if isOverlay {
                SeleneOverlay(style: .deep, onOutside: canClose && layers.isTop(.selector) ? onClose : nil) {
                    profileLayers
                }
            } else {
                ZStack {
                    SeleneBackdrop().still(true).environment(\.seleneSharesBackdrop, false)
                    profileLayers
                }
            }
        }
        .animation(Motion.overlay(reduceMotion), value: draft != nil)
        .onAppear {
            guard !appeared else { return }
            appeared = true
            selected = initialSelection
            accessibilityFocus = initialSelection.map(Tile.profile) ?? .add
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxProfileInput)) { note in
            guard !dialogOwnsInput, layers.top != .editor, let action = note.object as? GamepadAction else { return }
            handle(action)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var profileLayers: some View {
        ZStack {
            // Keep the selector mounted so closing the wizard restores its selection and scroll.
            selector.opacity(layers.showsSelector ? 1 : 0)
                .seleneOverlayOwnership(layers.isTop(.selector))
            if let draft {
                ProfileEditorView(profile: draft, games: games,
                                  avatarGames: avatarGames, artwork: artwork,
                                  isNew: true,
                                  onCancel: editorClosed, onSave: save)
                    .seleneOverlayOwnership(layers.isTop(.editor))
                    .transition(.opacity)
            }
            if let removing {
                SeleneOverlay(style: .profileRemoval, onOutside: { self.removing = nil }) {
                    SeleneConfirmDialog(title: L10n.format("Delete %@?", [removing.name]),
                                        message: L10n.text("This profile will lose its favorites and play time."),
                                        confirmTitle: L10n.text("Delete"), cancelTitle: L10n.text("Keep"),
                                        warningIcon: true, destructive: true, focus: $removalFocus,
                                        onCancel: { self.removing = nil }, onConfirm: remove)
                }
            }
        }
    }

    private var selector: some View {
        let haloInset = canvas.u(SeleneTokens.Space.group)
        let extraHeight = haloInset - canvas.u(SeleneTokens.Space.control)
        return GeometryReader { geometry in
            VStack(spacing: canvas.u(SeleneTokens.Space.settingsInfoClearance)) {
                Text(L10n.text("Who's playing?")).seleneFont(.screen).accessibilityAddTraits(.isHeader)
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        HStack(spacing: canvas.u(SeleneTokens.Space.chromeGutter)) {
                            ForEach(profiles.profiles) { profile in
                                tile(profile)
                            }
                            if let guest { tile(guest).id(guest.id) }
                            tile(nil).id("add")
                        }
                        .padding(haloInset)
                        .frame(minWidth: geometry.size.width, alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: Edge.Set.self) { scroll in
                        var edges: Edge.Set = []
                        if scroll.visibleRect.minX > 0.5 { edges.insert(.leading) }
                        if scroll.visibleRect.maxX < scroll.contentSize.width - 0.5 { edges.insert(.trailing) }
                        return edges
                    } action: { _, edges in
                        fadingEdges = edges
                    }
                    .horizontalEdgeFade(edges: fadingEdges)
                    // Give both the scroll clip and the fade room to paint without moving the row.
                    .padding(.vertical, -extraHeight)
                    .onChange(of: selection, initial: true) { _, id in
                        if let id { scroll.scrollTo(id, anchor: .center) }
                        else { scroll.scrollTo("add", anchor: .center) }
                    }
                }
                // Same height with and without keys, so the portraits never move.
                OortItemActions(hints: profileHints(selectedProfile), deletes: [.x])
                    .frame(height: canvas.u(SeleneTokens.Space.compactPillHeight))
                if profiles.failed { Text(L10n.text("Profiles could not be saved.")).seleneFont(.text) }
            }
            .foregroundStyle(SeleneTheme.ink)
            .padding(.top, geometry.size.height * 0.28)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            SeleneHintsBar(left: leftHints, right: [HintItem(.a, "Select", action: accept)])
                .seleneOverlaidHints(!layers.isTop(.selector))
        }
    }

    private var leftHints: [HintItem] {
        var hints = canClose ? [HintItem(.b, "Back", action: onClose)] : []
        hints.append(HintItem(.menu, "Add", keyboard: .text("+"), action: add))
        return hints + profileHints(selectedProfile)
    }

    private func profileHints(_ profile: LocalProfile?) -> [HintItem] {
        guard let profile else { return [] }
        var hints: [HintItem] = []
        if profile.id == profiles.active?.id, onEditActive != nil {
            hints.append(HintItem(.y, "Edit profile") { selected = profile.id; edit() })
        }
        if canRemoveProfile(profile) {
            hints.append(HintItem(.x, "Delete") { selected = profile.id; askRemoval() })
        }
        return hints
    }

    private func tile(_ profile: LocalProfile?) -> some View {
        let isFocused = selection == profile?.id
        let title = profile?.name ?? L10n.text("Add")
        let accent = profile.map { Color(hex: SelenePaletteCatalog.resolve($0.look.theme, in: theme.palettes).glyph) } ?? SeleneTheme.focus
        return Button {
            selected = profile?.id
            accept()
        } label: {
            VStack(spacing: canvas.u(SeleneTokens.Space.large)) {
                Group {
                    if let profile {
                        ProfilePortrait(profile: profile, size: 170)
                    } else {
                        // Opaque: the Sun never shows through a key.
                        Circle().fill(SeleneTheme.panelRaised)
                            .overlay(Circle().strokeBorder(SeleneTheme.ink15, lineWidth: canvas.u(SeleneTokens.Space.thinStroke)))
                            .overlay { MaterialIconView(.add, size: SeleneTokens.Space.chromeGutter)
                                .foregroundStyle(isFocused ? SeleneTheme.ink : SeleneTheme.ink60) }
                            .frame(width: canvas.u(170), height: canvas.u(170))
                    }
                }
                .overlay {
                    if isFocused {
                        Circle().strokeBorder(accent, lineWidth: canvas.u(SeleneTokens.Space.strongStroke)).padding(-canvas.u(9))
                            .oortGlow(true, color: accent.opacity(SeleneTokens.Alpha.heavy))
                    }
                }
                .scaleEffect(isFocused && !reduceMotion ? 1.1 : 1)
                Text(title).seleneFont(.heading).lineLimit(1)
                    .foregroundStyle(isFocused ? SeleneTheme.ink : SeleneTheme.ink60)
                    .frame(width: canvas.u(170))
            }
        }
        .buttonStyle(OortPressStyle())
        .oortItemMenu(profileHints(profile), deletes: [.x])
        .onHover { if hover.moved($0) { selected = profile?.id } }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityFocused($accessibilityFocus, equals: profile.map { .profile($0.id) } ?? .add)
        .animation(Motion.focus(reduceMotion), value: isFocused)
    }

    private func handle(_ action: GamepadAction) {
        if removing != nil {
            switch action {
            case .navigateLeft, .navigateRight:
                removalFocus = action == .navigateLeft ? .left : .right
            case .confirm: if removalFocus == .confirm { remove() } else { removing = nil }
            case .cancel: removing = nil
            default: break
            }
            return
        }
        let ids = (profiles.profiles + (guest.map { [$0] } ?? [])).map { Optional($0.id) } + [nil]
        switch action {
        case .navigateLeft, .navigateRight:
            let current = ids.firstIndex(of: selected) ?? 0
            selected = ids[max(0, min(ids.count - 1, current + (action == .navigateLeft ? -1 : 1)))]
            accessibilityFocus = selected.map(Tile.profile) ?? .add
        case .confirm: accept()
        case .menu: add()
        case .contextAction: edit()
        case .secondaryAction: askRemoval()
        case .cancel: if canClose { onClose() }
        default: break
        }
    }

    private func accept() {
        if let guest, selected == guest.id, profiles.guest == nil { onGuest?(guest) }
        else if let selected { onChoose(selected) }
        else { add() }
    }

    private func add() { draft = LocalProfile(name: "", look: .init(AppSettings())) }

    private func edit() { if let selectedProfile, selectedProfile.id == profiles.active?.id { onEditActive?() } }

    private func editorClosed() {
        draft = nil
        accessibilityFocus = selected.map(Tile.profile) ?? .add
    }

    private func save(_ profile: LocalProfile) -> Bool {
        guard profiles.update(profile) else { return false }
        selected = profile.id
        if profiles.active?.id == profile.id { onActiveEdited() }
        editorClosed()
        return true
    }

    private func canRemoveProfile(_ profile: LocalProfile) -> Bool {
        profiles.profiles.count > 1 && profile.id != profiles.originalID && canRemove(profile)
    }

    private func askRemoval() {
        guard let selectedProfile, canRemoveProfile(selectedProfile) else { return }
        removalFocus = .cancel
        removing = selectedProfile
    }

    private func remove() {
        guard let removing, canRemoveProfile(removing), let index = profiles.profiles.firstIndex(where: { $0.id == removing.id }),
              profiles.remove(removing.id) else { return }
        selected = profiles.profiles[min(index, profiles.profiles.count - 1)].id
        self.removing = nil
        accessibilityFocus = selected.map(Tile.profile) ?? .add
        onRemoved(removing.id)
        onActiveEdited()
    }
}
