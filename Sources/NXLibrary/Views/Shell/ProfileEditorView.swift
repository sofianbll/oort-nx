import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

struct ProfileEditorView: View {
    enum Step: Int, CaseIterable { case name, avatar, theme, background }
    private let original: LocalProfile
    @State var profile: LocalProfile
    let games: [PortedGame]
    var avatarGames: [CatalogGame] = []
    var artwork: ArtworkStore? = nil
    let isNew: Bool
    let nameOnly: Bool
    let onCancel: () -> Void
    let onSave: (LocalProfile) -> Bool
    @State var step: Step = .name
    @State private var indexes = [10, 0, 0, 0]
    @State private var error: String?
    @State private var shift = false
    @State private var customBackground: URL?
    @State private var savedBackgroundID: String?
    @State var cachedPortraits: [CachedAvatar] = []
    @State private var cropDraft: AvatarCropDraft?
    @State private var isCropping = false
    @State private var cropTask: Task<Void, Never>?
    @State private var discardFocus: Int?
    @State private var resumeNameFocus = false
    @FocusState private var nameFocused: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    private let keys = "1234567890QWERTYUIOPASDFGHJKL'ZXCVBNM-.".map(String.init) + ["Shift", "Space", "Erase", "Done"]
    private let keyRows = [0..<10, 10..<20, 20..<30, 30..<39, 39..<43]
    private var palettes: [SelenePalette] { theme.palettes.isEmpty ? [theme.palette] : theme.palettes }
    private var wallpapers: [String?] { theme.wallpaperChoices }
    private var customBackgroundSelected: Bool { step == .background && index == wallpapers.count }
    private var index: Int { indexes[step.rawValue] }
    private var columns: Int { [10, 10, 5, 3][step.rawValue] }
    private var presetCount: Int { cachedPortraits.count + ProfilePortrait.symbols.count }
    private var ownAvatar: Int { presetCount + (profile.portrait == nil ? 0 : 1) }
    private var itemCount: Int { [keys.count, ownAvatar + 1, palettes.count, wallpapers.count + 1][step.rawValue] }

    init(profile: LocalProfile, games: [PortedGame], avatarGames: [CatalogGame] = [], artwork: ArtworkStore? = nil,
         isNew: Bool, nameOnly: Bool = false, onCancel: @escaping () -> Void, onSave: @escaping (LocalProfile) -> Bool,
         step: Step = .name, cachedPortraits: [CachedAvatar] = []) {
        original = profile
        _profile = State(initialValue: profile)
        self.games = games
        self.avatarGames = avatarGames
        self.artwork = artwork
        self.isNew = isNew
        self.nameOnly = nameOnly
        self.onCancel = onCancel
        self.onSave = onSave
        _step = State(initialValue: step)
        _cachedPortraits = State(initialValue: cachedPortraits)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SeleneTheme.scrim.opacity(SeleneTokens.Alpha.half).ignoresSafeArea()
            VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                Text(L10n.text(title)).seleneFont(.screen, step == .avatar ? .medium : .regular)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.text(subtitle)).seleneFont(.row).foregroundStyle(SeleneTheme.ink75)
            }
            .multilineTextAlignment(.center)
            .padding(.top, canvas.u(SeleneTokens.Space.stageHeader))
            Group {
                switch step {
                case .name: nameStep
                case .avatar: avatarStep
                case .theme, .background: lookStep
                }
            }
            .padding(.top, canvas.u(step == .name ? 300 : step == .avatar ? 290 : 285))
            .accessibilityHidden(cropDraft != nil)
            .allowsHitTesting(cropDraft == nil)
            if let error {
                Text(L10n.text(error)).seleneFont(.text)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, canvas.u(SeleneTokens.Space.pageFootDeep))
            }
            if !nameOnly {
                HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    ForEach(Step.allCases, id: \.rawValue) { dot in
                        Circle().fill(SeleneTheme.ink.opacity(dot == step ? 1 : 0.3))
                            .frame(width: canvas.u(8), height: canvas.u(8))
                    }
                }
                .accessibilityHidden(true)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, canvas.u(SeleneTokens.Space.pageFoot))
            }
            SeleneHintsBar(left: backHints, right: editorHints)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .seleneOverlayOwnership(cropDraft == nil)
            if let cropDraft { cropPanel(cropDraft) }
        }
        .foregroundStyle(SeleneTheme.ink)
        .seleneOverlayOwnership(discardFocus == nil)
        .overlay {
            if discardFocus != nil { discardDialog }
        }
        .onAppear {
            indexes[Step.avatar.rawValue] = profile.portrait == nil ? profile.avatar : presetCount
            indexes[Step.theme.rawValue] = palettes.firstIndex { $0.id == profile.look.theme } ?? 0
            indexes[Step.background.rawValue] = wallpapers.firstIndex(of: profile.look.wallpaper) ?? 0
        }
        .task(id: step) {
            guard step == .avatar, cachedPortraits.isEmpty, let artwork else { return }
            let games = avatarGames
            let task = Task.detached(priority: .utility) { Self.loadAvatars(games, artwork: artwork) }
            let found = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled, !found.isEmpty else { return }
            let current = indexes[Step.avatar.rawValue]
            cachedPortraits = found
            indexes[Step.avatar.rawValue] = isNew && profile.portrait == nil && current == 0 ? 0 : current + found.count
        }
        .onDisappear { cropTask?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .nxProfileInput)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    private var discardDialog: some View {
        let focus = Binding(get: { discardFocus ?? 1 }, set: { discardFocus = $0 })
        return SeleneOverlay(style: .profileRemoval, onOutside: keepEditing) {
            SeleneChoiceDialog(title: "Discard changes?", message: L10n.text("Your profile changes won’t be saved."),
                               choices: ["Discard", "Keep editing"], focus: focus, cancelIndex: 1,
                               onCancel: keepEditing, onChoose: chooseDiscardAction)
        }
    }

    private var backHints: [HintItem] {
        [HintItem(.b, "Back", action: back), HintItem(nil, "Cancel", glyph: .close, action: requestCancel)]
    }

    private var editorHints: [HintItem] {
        let label = switch step {
        case .name: "Select"
        case .avatar: index == ownAvatar ? "Your own picture" : "Next"
        case .theme: "Next"
        case .background: customBackgroundSelected && customBackground == nil ? "Add a picture" : isNew ? "Create profile" : "Save"
        }
        let select = HintItem(.a, label, action: accept)
        let menuLabel = step == .name ? (isNew && !nameOnly ? "Next" : "Save") : label
        return [HintItem(.menu, menuLabel, keyboard: .text("+"), action: { handle(.menu) }), select]
    }

    private var title: String {
        switch step {
        case .name: "What should we call you?"
        case .avatar: "Choose your avatar"
        case .theme: "Choose your theme"
        case .background: "Choose your background"
        }
    }

    private var subtitle: String {
        switch step {
        case .name: "This is the name on your profile. Type, or use the keys below."
        case .avatar: "Pick one, or use your own picture. A GIF keeps moving."
        case .theme: "Colors for all of Arcane. Move through them to see each one in the preview."
        case .background: "Choose the picture behind your library."
        }
    }

    private var nameStep: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.dialogInset)) {
            TextField(L10n.text("Name"), text: $profile.name)
                .textFieldStyle(.plain)
                .seleneFont(.heading)
                .padding(.horizontal, canvas.u(SeleneTokens.Space.feature))
                .frame(width: canvas.u(560), height: canvas.u(68))
                .oortWell(radius: canvas.u(SeleneTokens.Radius.field))
                .seleneRowFocus(nameFocused, radius: canvas.u(SeleneTokens.Radius.field))
                .focused($nameFocused)
                .onSubmit { advance() }
            VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                ForEach(keyRows, id: \.lowerBound) { row in
                    HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                        ForEach(row, id: \.self) { item in
                            button(item, label: L10n.text(keys[item]), action: { selectKey(item) }) {
                                keyFace(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func keyWidth(_ item: Int) -> CGFloat { item < 39 ? 70 : item == 40 ? 308 : 147 }

    private func keyFace(_ item: Int) -> some View {
        let key = keys[item]
        return Group {
            if key == "Erase" { Image(systemName: "delete.left") }
            else if key == "Shift" { Image(systemName: shift ? "shift.fill" : "shift") }
            else { Text(L10n.text(key)) }
        }
        .seleneFont(item < 39 ? .heading : .text)
        .frame(width: canvas.u(keyWidth(item)), height: canvas.u(64))
        .oortPanel(radius: canvas.u(SeleneTokens.Radius.card))
        .overlay(alignment: .topTrailing) {
            if item > 39 && (item != 42 || isNew) {
                SelenePromptBadge(button: item == 40 ? .y : item == 41 ? .x : .menu, height: 22,
                                  keyboardOverride: item == 42 ? .symbol("return") : nil)
                    .padding(canvas.u(SeleneTokens.Space.hairline)).accessibilityHidden(true)
            }
        }
        .modifier(TileFocus(focused: index == item && !nameFocused, radius: 16, scale: 1.1))
    }

    private static let avatarSpacing: CGFloat = 210
    private static let avatarOpacity: [Double] = [1, 0.7, 0.45, 0.25, 0.1, 0]

    private var avatarStep: some View {
        let count = itemCount
        // Items keep their identity so they slide; the row spans the screen and fades out at both edges.
        let reach = min(Int(ceil(canvas.size.width / 2 / canvas.u(Self.avatarSpacing))), (count - 1) / 2)
        return VStack(spacing: canvas.u(SeleneTokens.Space.large)) {
            ZStack {
                ForEach((-reach...reach).map { (index + $0 + count) % count }, id: \.self) { item in
                    let wrapped = (item - index + count) % count
                    let offset = wrapped > count / 2 ? wrapped - count : wrapped
                    let selected = offset == 0
                    let distance = abs(offset)
                    let data = item < cachedPortraits.count ? cachedPortraits[item].image : item == presetCount && item < ownAvatar ? profile.portrait : nil
                    let face = LocalProfile(name: "", avatar: item - cachedPortraits.count, portrait: data, look: profile.look)
                    button(item, label: avatarLabel(item), action: {
                        if selected { accept() }
                    }) {
                        Group {
                            if item == ownAvatar {
                                Circle().fill(SeleneTheme.glass).overlay(MaterialIconView(.image, size: 52))
                                    .frame(width: canvas.u(176), height: canvas.u(176))
                            } else {
                                ProfilePortrait(profile: face, size: 176)
                            }
                        }
                        .modifier(TileFocus(focused: selected, radius: 88, scale: 1.16))
                    }
                    // Neighbours shrink and fade with distance: 100 %, 70 %, 45 %, 25 %.
                    .opacity(Self.avatarOpacity[min(distance, Self.avatarOpacity.count - 1)])
                    .animation(Motion.overlay(reduceMotion), value: index)
                    .scaleEffect(selected ? 1 : max(0.5, 1 - 0.12 * CGFloat(distance)))
                    .offset(x: canvas.u(CGFloat(offset) * Self.avatarSpacing))
                    // Reduce Motion: the row stays put and only fades.
                    .animation(Motion.focus(reduceMotion), value: index)
                    .zIndex(selected ? 1 : 0)
                }
            }
            .frame(width: canvas.size.width, height: canvas.u(230))
            .horizontalEdgeFade()
            Text(avatarLabel(index)).seleneFont(.row).foregroundStyle(SeleneTheme.ink75)
        }
    }

    private func avatarLabel(_ item: Int) -> String {
        if cachedPortraits.indices.contains(item) { return cachedPortraits[item].name }
        return item == ownAvatar ? L10n.text("Your own picture") : L10n.format("Avatar %lld", [item - cachedPortraits.count + 1])
    }

    struct CachedAvatar {
        let name: String
        let image: Data
    }

    nonisolated static func loadAvatars(_ games: [CatalogGame], artwork: ArtworkStore) -> [CachedAvatar] {
        var avatars: [CachedAvatar] = []
        for game in games.prefix(120) {
            if avatars.count == LocalProfile.avatarCount || Task.isCancelled { break }
            let id = game.personalizationKey
            let data = [ArtworkKind.hero, .square, .boxart].lazy
                .compactMap { artwork.cachedURL(titleID: id, kind: $0).flatMap(ProfileAvatar.cachedPortrait) }.first
            guard let data else { continue }
            avatars.append(.init(name: game.name, image: data))
        }
        return avatars
    }

    private var lookStep: some View {
        let palette = step == .theme ? palettes[index] : SelenePaletteCatalog.resolve(profile.look.theme, in: palettes)
        let wallpaper = step == .background && !customBackgroundSelected ? wallpapers[index] : profile.look.wallpaper
        let url = (customBackgroundSelected ? customBackground : nil)
            ?? WallpaperCatalog.resolve(wallpaper, themeID: palette.id, in: theme.wallpapers)?.url
        return HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.settingsInfoClearance)) {
            ScrollViewReader { scroll in
                ScrollView {
                    if step == .theme {
                        grid(count: palettes.count, width: 150) { item in
                            button(item, label: palettes[item].name, action: accept) {
                                ThemePaletteSwatch(palette: palettes[item], focused: index == item)
                            }
                            .id(item)
                        }
                    } else {
                        grid(count: wallpapers.count + 1, width: 220) { item in
                            let personal = item == wallpapers.count
                            let name = personal ? "Add a picture" : wallpaperName(wallpapers[item])
                            button(item, label: name, action: accept) {
                                ZStack(alignment: .bottomLeading) {
                                    Rectangle().fill(SeleneTheme.baseGradient(for: palette))
                                    if let url = personal ? customBackground
                                        : WallpaperCatalog.resolve(wallpapers[item], themeID: palette.id, in: theme.wallpapers)?.url {
                                        WallpaperThumb(url: url)
                                    } else if personal {
                                        MaterialIconView(.add, size: 32).frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                    Text(L10n.text(name)).seleneFont(.text).lineLimit(1)
                                        .padding(canvas.u(SeleneTokens.Space.compact)).background(SeleneTheme.glassSolid)
                                }
                                .frame(width: canvas.u(198), height: canvas.u(112))
                                .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content)))
                                .modifier(TileFocus(focused: index == item, radius: 12, scale: 1.05))
                                .padding(.vertical, canvas.u(SeleneTokens.Space.compact))
                            }
                            .id(item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(width: canvas.u(step == .theme ? 770 : 680), height: canvas.u(530), alignment: .top)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .onChange(of: index) { _, target in scroll.scrollTo(target) }
            }
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small)) {
                ThemePreview(palette: palette, wallpaperURL: url, games: games, width: step == .theme ? 780 : 820,
                             animated: !reduceMotion)
                Text(step == .theme ? palette.name : customBackgroundSelected
                     ? customBackground?.deletingPathExtension().lastPathComponent ?? L10n.text("Add a picture")
                     : L10n.text(wallpaperName(wallpaper)))
                    .seleneFont(.row)
            }
        }
    }

    private func wallpaperName(_ id: String?) -> String {
        id == nil ? "Theme's own" : theme.wallpaperTitle(for: id)
    }

    private func grid<Cell: View>(count: Int, width: CGFloat, @ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(canvas.u(width)), spacing: 0), count: columns), spacing: 0) {
            ForEach(0..<count, id: \.self, content: cell)
        }
        .padding(.vertical, canvas.u(SeleneTokens.Space.compact))
    }

    private func button<Cell: View>(_ item: Int, label: String, action: @escaping () -> Void,
                                    @ViewBuilder face: () -> Cell) -> some View {
        Button {
            indexes[step.rawValue] = item
            action()
        } label: { face() }
        .buttonStyle(OortPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(index == item ? .isSelected : [])
    }

    private func handle(_ action: GamepadAction) {
        if discardFocus != nil {
            switch action {
            case .navigateLeft: discardFocus = 0
            case .navigateRight: discardFocus = 1
            case .confirm: confirmDiscardChoice()
            case .cancel: keepEditing()
            default: break
            }
            return
        }
        if cropDraft != nil { handleCrop(action); return }
        switch action {
        case .navigateLeft, .navigateRight, .navigateUp, .navigateDown:
            let next: Int
            if step == .name {
                guard let row = keyRows.firstIndex(where: { $0.contains(index) }) else { return }
                if action == .navigateUp || action == .navigateDown {
                    let target = row + (action == .navigateUp ? -1 : 1)
                    guard keyRows.indices.contains(target) else { return }
                    let x = keyCenter(index, in: keyRows[row])
                    next = keyRows[target].min { abs(keyCenter($0, in: keyRows[target]) - x)
                        < abs(keyCenter($1, in: keyRows[target]) - x) } ?? index
                } else {
                    next = index + (action == .navigateLeft ? -1 : 1)
                    guard keyRows[row].contains(next) else { return }
                }
            } else if step == .avatar {
                guard action == .navigateLeft || action == .navigateRight else { return }
                next = (index + itemCount + (action == .navigateLeft ? -1 : 1)) % itemCount
            } else {
                let delta = action == .navigateLeft ? -1 : action == .navigateRight ? 1 : action == .navigateUp ? -columns : columns
                next = index + delta
            }
            guard (0..<itemCount).contains(next) else { return }
            nameFocused = false
            indexes[step.rawValue] = next
        case .confirm: accept()
        case .cancel: back()
        case .menu: advance(saveOnName: !isNew)
        case .menuHold: requestCancel()
        case .secondaryAction where step == .name: selectKey(keys.count - 2)
        case .contextAction where step == .name: selectKey(keys.count - 3)
        default: break
        }
    }

    private func keyCenter(_ item: Int, in row: Range<Int>) -> CGFloat {
        let total = row.reduce(CGFloat.zero) { $0 + keyWidth($1) + 9 }
        return row.prefix(while: { $0 < item }).reduce(-total / 2) { $0 + keyWidth($1) + 9 } + keyWidth(item) / 2
    }

    private func accept() {
        switch step {
        case .name: selectKey(index)
        default: advance()
        }
    }

    private func advance(saveOnName: Bool = false) {
        error = nil
        switch step {
        case .name:
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty && name.count <= 32 else { error = "Enter a name of 1 to 32 characters."; return }
            profile.name = name
            nameFocused = false
            if nameOnly || saveOnName { save(); return }
        case .avatar:
            if index < cachedPortraits.count {
                profile.portrait = cachedPortraits[index].image
            } else if index < presetCount {
                profile.avatar = index - cachedPortraits.count
                profile.portrait = nil
            } else if index == ownAvatar { importAvatar(); return }
        case .theme:
            profile.look.theme = palettes[index].id
        case .background:
            if customBackgroundSelected {
                guard let customBackground else {
                    OortFilePickerPresentation.open(.files(["png", "jpg", "jpeg", "heic", "webp"]), title: L10n.text("Add a picture"),
                                                    message: L10n.text("Choose a picture for your background. Arcane keeps its own copy.")) {
                        if step == .background { self.customBackground = $0.first }
                    }
                    return
                }
                do {
                    if savedBackgroundID == nil {
                        let oldIndex = index
                        savedBackgroundID = try theme.importWallpaper(from: customBackground)
                        if wallpapers.count != oldIndex { indexes[Step.background.rawValue] = wallpapers.count }
                    }
                    profile.look.wallpaper = savedBackgroundID
                } catch {
                    self.error = "Couldn't add the picture"
                    return
                }
            } else {
                profile.look.wallpaper = wallpapers[index]
            }
            save()
            return
        }
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    private func back() {
        error = nil
        if nameFocused { nameFocused = false; return }
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
        else { requestCancel() }
    }

    private func save() {
        if !onSave(profile) { error = "Profiles could not be saved." }
    }

    private func requestCancel() {
        let hasCustomBackground = customBackground != nil && indexes[Step.background.rawValue] == wallpapers.count
        guard profile != original || hasCustomBackground else { onCancel(); return }
        resumeNameFocus = nameFocused
        nameFocused = false
        discardFocus = 1
    }

    private func keepEditing() {
        discardFocus = nil
        if resumeNameFocus { nameFocused = true }
    }

    private func confirmDiscardChoice() { if let discardFocus { chooseDiscardAction(discardFocus) } }

    private func chooseDiscardAction(_ index: Int) { if index == 0 { onCancel() } else { keepEditing() } }

    private func selectKey(_ item: Int) {
        let key = keys[item]
        if key == "Done" { advance() }
        else if key == "Shift" { shift.toggle() }
        else if key == "Erase" { if !profile.name.isEmpty { profile.name.removeLast() } }
        else if profile.name.count < 32 { profile.name += key == "Space" ? " " : shift ? key : key.lowercased() }
    }

    private struct AvatarCropDraft {
        let url: URL
        let preview: CGImage
        var crop = ProfileAvatar.Crop()
    }

    private func importAvatar() {
        guard cropDraft == nil else { return }
        OortFilePickerPresentation.open(.images, title: L10n.text("Your own picture"),
                                        message: L10n.text("PNG, JPEG, HEIC, WebP or GIF.")) { urls in
            if let url = urls.first, step == .avatar { crop(url) }
        }
    }

    private func crop(_ url: URL) {
        guard let source = ProfileAvatar.source(url), let image = ProfileAvatar.thumbnail(source) else {
            error = "Couldn't add the picture"
            return
        }
        cropDraft = AvatarCropDraft(url: url, preview: image)
    }

    private func cropPanel(_ draft: AvatarCropDraft) -> some View {
        ZStack {
            SeleneTheme.scrim65.ignoresSafeArea()
            VStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                Text(L10n.text("Frame your picture")).seleneFont(.screen).accessibilityAddTraits(.isHeader)
                if let crop = draft.preview.cropping(to: draft.crop.rectangle(width: draft.preview.width, height: draft.preview.height)) {
                    Image(decorative: crop, scale: 1).resizable()
                        .frame(width: canvas.u(240), height: canvas.u(240)).clipShape(Circle())
                        .accessibilityHidden(true)
                }
                cropSlider("Horizontal position", \.x, 0...1, fallback: 0.5)
                cropSlider("Vertical position", \.y, 0...1, fallback: 0.5)
                cropSlider("Zoom", \.zoom, 1...3, fallback: 1)
                if isCropping { ProgressView().controlSize(.small).accessibilityLabel(L10n.text("Loading…")) }
                HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                    SelenePillButton(title: "Cancel", focused: false, action: cancelCrop)
                    SelenePillButton(title: "Done", focused: true, enabled: !isCropping, action: saveCrop)
                }
            }
            .disabled(isCropping)
            .modifier(SeleneDialogCard())
        }
    }

    private func cropSlider(_ name: String, _ field: WritableKeyPath<ProfileAvatar.Crop, CGFloat>,
                            _ range: ClosedRange<CGFloat>, fallback: CGFloat) -> some View {
        Slider(value: Binding(get: { cropDraft?.crop[keyPath: field] ?? fallback },
                              set: { cropDraft?.crop[keyPath: field] = $0 }), in: range) {
            Text(L10n.text(name)).seleneFont(.text)
        }
    }

    private func handleCrop(_ action: GamepadAction) {
        guard let crop = cropDraft?.crop else { return }
        switch action {
        case .cancel: cancelCrop()
        case .confirm: saveCrop()
        case .navigateLeft: cropDraft?.crop.x = max(0, crop.x - 0.05)
        case .navigateRight: cropDraft?.crop.x = min(1, crop.x + 0.05)
        case .navigateUp: cropDraft?.crop.y = max(0, crop.y - 0.05)
        case .navigateDown: cropDraft?.crop.y = min(1, crop.y + 0.05)
        case .tabPrevious: cropDraft?.crop.zoom = max(1, crop.zoom - 0.15)
        case .tabNext: cropDraft?.crop.zoom = min(3, crop.zoom + 0.15)
        default: break
        }
    }

    private func cancelCrop() {
        cropTask?.cancel()
        cropTask = nil
        isCropping = false
        cropDraft = nil
    }

    private func saveCrop() {
        guard let draft = cropDraft, !isCropping else { return }
        isCropping = true
        cropTask = Task {
            let task = Task.detached(priority: .userInitiated) { ProfileAvatar.render(draft.url, crop: draft.crop) }
            let data = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled else { return }
            cropTask = nil
            isCropping = false
            cropDraft = nil
            guard let data else { error = "Couldn't add the picture"; return }
            profile.portrait = data
            indexes[Step.avatar.rawValue] = presetCount
        }
    }
}
