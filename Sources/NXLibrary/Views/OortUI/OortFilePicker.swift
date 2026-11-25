import AppKit
import SwiftUI
import NXLibraryCore
import UniformTypeIdentifiers

/// The sheet keeps the launcher behind it out of the native input and accessibility routes.
@MainActor final class OortFilePickerPresentation: ObservableObject {
    static let shared = OortFilePickerPresentation()
    @Published private(set) var isOpen = false
    private var controller: ((GamepadAction) -> Void)?
    private weak var sheet: NSPanel?
    private var recent: [URL] = []

    nonisolated static func open(_ choice: FileBrowser.Choice, title: String, message: String, startingAt start: URL? = nil,
                                 canCreateDirectories: Bool = false, cancelled: @escaping () -> Void = {},
                                 completion: @escaping ([URL]) -> Void) {
        Task { @MainActor in
            shared.open(choice, title: title, message: message, startingAt: start,
                        canCreateDirectories: canCreateDirectories, cancelled: cancelled, completion: completion)
        }
    }

    func handle(_ action: GamepadAction) -> Bool {
        guard isOpen else { return false }
        if sheet?.isKeyWindow == true, NSApp.isActive { controller?(action) }
        return true
    }

    private func open(_ choice: FileBrowser.Choice, title: String, message: String, startingAt start: URL? = nil,
                      canCreateDirectories: Bool = false, cancelled: @escaping () -> Void, completion: @escaping ([URL]) -> Void) {
        guard !isOpen, let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil else { return cancelled() }
        let home = AppData.profile.home
        let panel = NSPanel()
        panel.styleMask = [.titled, .fullSizeContentView]
        panel.title = title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        let model = OortFilePickerModel(home: home, choice: choice, start: start, recent: recent)
        let display = window.contentLayoutRect.size
        let size = NSSize(width: min(1020, display.width * 0.94), height: min(670, display.height * 0.88))
        var picked: [URL] = []
        let finish: ([URL]) -> Void = { urls in
            if let first = urls.first {
                let folder = first.hasDirectoryPath && !choice.accepts(first.lastPathComponent) ? first : first.deletingLastPathComponent()
                self.recent = Array(([folder] + self.recent.filter { $0.path != folder.path }).prefix(5))
            }
            picked = urls
            window.endSheet(panel)
        }
        let root = OortFilePicker(model: model, title: title, message: message, choose: finish) {
            window.endSheet(panel, returnCode: .continue)
        } cancel: { window.endSheet(panel) }
        panel.contentViewController = NSHostingController(rootView: root
            .environment(\.nxAppLocale, AppLocalization.shared.context)
            .preferredColorScheme(.dark)
            .seleneCanvasRoot())
        panel.setContentSize(size)
        panel.backgroundColor = NSColor(SeleneTheme.pageSurface)
        panel.isReleasedWhenClosed = false
        controller = { model.input($0) }
        sheet = panel
        isOpen = true
        model.enter(model.folder)
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard let panel, event.window === panel, let action = Self.key(event),
                  !(panel.firstResponder is NSText) || [.cancel, .search, .navigateDown, .navigateUp, .tabNext, .tabPrevious].contains(action)
            else { return event }
            model.input(action)
            return nil
        }
        window.beginSheet(panel) { result in
            if let keys { NSEvent.removeMonitor(keys) }
            self.isOpen = false
            self.controller = nil
            self.sheet = nil
            model.stop()
            panel.contentViewController = nil
            panel.orderOut(nil)
            if result == .continue {
                self.nativeFallback(choice, title: title, message: message, folder: model.ready ? model.folder : home,
                                    canCreateDirectories: canCreateDirectories, window: window, cancelled: cancelled, completion: completion)
            } else if !picked.isEmpty {
                completion(picked)
            } else {
                cancelled()
            }
        }
    }

    private func nativeFallback(_ choice: FileBrowser.Choice, title: String, message: String, folder: URL,
                                canCreateDirectories: Bool, window: NSWindow, cancelled: @escaping () -> Void,
                                completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = choice.allowsFolder
        panel.canChooseFiles = choice != .folder
        panel.canCreateDirectories = canCreateDirectories
        panel.resolvesAliases = false
        panel.allowsMultipleSelection = choice.allowsMultiple
        switch choice {
        case .gameFiles: panel.allowedContentTypes = FileBrowser.gameExtensions.compactMap { UTType(filenameExtension: $0) }
        case .files(let extensions, let folder, _):
            panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) } + (folder ? [.folder] : [])
        case .apps: panel.allowedContentTypes = [.applicationBundle]
        case .folder, .keys, .tool: break
        }
        panel.directoryURL = folder
        panel.prompt = L10n.text("Choose")
        panel.title = title
        panel.message = message
        panel.beginSheetModal(for: window) { result in
            guard result == .OK else { return cancelled() }
            let urls = panel.urls
            guard !urls.isEmpty, urls.allSatisfy(choice.accepts) else {
                self.open(choice, title: title, message: message, startingAt: folder,
                          canCreateDirectories: canCreateDirectories, cancelled: cancelled, completion: completion)
                return
            }
            completion(urls)
        }
    }

    private static func key(_ event: NSEvent) -> GamepadAction? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command && event.charactersIgnoringModifiers == "f" { return .search }
        if event.keyCode == 48, flags == .shift { return .tabPrevious }
        guard flags.isEmpty else { return nil }
        switch event.keyCode {
        case 48: return .tabNext
        case 53: return .cancel
        case 36, 76, 49: return .confirm
        case 123: return .navigateLeft
        case 124: return .navigateRight
        case 125: return .navigateDown
        case 126: return .navigateUp
        case 7: return .secondaryAction
        case 16: return .search
        default: return nil
        }
    }
}

@MainActor final class OortFilePickerModel: ObservableObject {
    enum Column: Int, CaseIterable { case places, files, actions }
    @Published var query = ""
    @Published var search = false
    @Published var showHidden = false
    @Published var column: Column = .files
    @Published var index = 0
    @Published var multiple = false
    @Published var selected: [URL] = []
    @Published private(set) var folder: URL
    @Published private(set) var places: [FileBrowser.Place] = []
    @Published private(set) var entries: [FileBrowser.Entry] = []
    @Published private(set) var problem: FileBrowser.Failure?
    @Published private(set) var ready = false
    let home: URL
    let choice: FileBrowser.Choice
    private var recent: [URL]
    private var load: Task<Void, Never>?
    var confirm: (() -> Void)?
    var close: (() -> Void)?
    var canSelectMultiple: Bool { choice.allowsMultiple }
    /// X adds the focused file to the choice.
    var canPickSeveral: Bool {
        canSelectMultiple && column == .files && visible.indices.contains(index) && !visible[index].isFolder
    }
    /// B leaves the search, then climbs, then closes: the hint says which.
    var backLabel: String {
        if search { return "Back" }
        return FileBrowser.parent(of: folder, home: home) == nil ? "Close" : "Up one folder"
    }
    var visible: [FileBrowser.Entry] { FileBrowser.visible(entries, query: query, showHidden: showHidden) }

    init(home: URL, choice: FileBrowser.Choice, start: URL?, recent: [URL] = []) {
        self.home = home
        self.choice = choice
        self.recent = recent
        let protected = FileBrowser.protectedHomeFolders.map { home.appendingPathComponent($0).path } + ["/Volumes"]
        if let start = start?.standardizedFileURL, !protected.contains(where: { start.path == $0 || start.path.hasPrefix($0 + "/") }) {
            folder = URL(fileURLWithPath: start.path, isDirectory: true)
        } else { folder = home }
    }

    func enter(_ url: URL) {
        load?.cancel()
        folder = url
        ready = false
        problem = nil
        entries = []
        query = ""
        search = false
        selected = []
        index = 0
        column = .files
        load = Task { [weak self] in await self?.read(url) }
    }

    func read(_ url: URL, includeMountedDisks: Bool = true) async {
        let home = home
        let choice = choice
        let recent = recent
        let discover = Task.detached {
            let fm = FileManager.default
            let names = Set((try? fm.contentsOfDirectory(atPath: home.path)) ?? [])
            let disks = includeMountedDisks ? (fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [])
                .filter { $0.path.hasPrefix("/Volumes/") } : []
            return FileBrowser.places(home: home, homeChildren: names, disks: disks, recent: recent)
        }
        defer { discover.cancel() }
        let result: Result<[FileBrowser.Entry], Error>
        do { result = .success(try await FileBrowser.list(url, choice: choice, home: home)) }
        catch { result = .failure(error) }
        let available = await discover.value
        guard !Task.isCancelled, folder == url else { return }
        switch result {
        case .success(let entries): self.entries = entries; ready = true
        case .failure(let error):
            problem = error as? FileBrowser.Failure ?? .unavailable
            if problem == .unavailable || problem == .link { self.recent.removeAll { $0.path == url.path } }
        }
        places = available.filter { $0.kind != .recent || self.recent.contains($0.url) }
    }

    func stop() {
        load?.cancel()
        confirm = nil
        close = nil
    }

    func input(_ action: GamepadAction) {
        switch action {
        case .navigateUp: index = max(0, index - 1)
        case .navigateDown: index += 1
        case .jumpToStart: index = 0
        case .jumpToEnd: index = 100_000
        case .navigateLeft, .tabPrevious:
            column = Column(rawValue: (column.rawValue + 2) % 3) ?? .files
            index = 0
        case .navigateRight, .tabNext:
            column = Column(rawValue: (column.rawValue + 1) % 3) ?? .files
            index = 0
        case .confirm: confirm?()
        case .cancel:
            if search { search = false; query = "" }
            else if let parent = FileBrowser.parent(of: folder, home: home) { enter(parent) }
            else { close?() }
        case .search, .browseSearch, .contextAction:
            search.toggle()
            if !search { query = "" }
            column = .files
            index = 0
        case .secondaryAction:
            if canPickSeveral {
                multiple = true
                toggle(visible[index].url)
            }
        default: break
        }
        let limit = switch column {
        case .places: places.count
        case .files: visible.count
        case .actions: 3 + (canSelectMultiple ? 1 : 0) + (choice.allowsFolder ? 1 : 0) + (problem == .denied ? 1 : 0)
        }
        if index >= limit { index = max(0, limit - 1) }
    }

    func toggle(_ url: URL) {
        if selected.contains(url) { selected.removeAll { $0 == url }; return }
        if url.pathExtension.lowercased() == "nup" || selected.contains(where: { $0.pathExtension.lowercased() == "nup" }) {
            selected = [url]
        } else { selected.append(url) }
    }
}

struct OortFilePicker: View {
    @ObservedObject var model: OortFilePickerModel
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    @FocusState private var searchFocused: Bool
    let title: String
    let message: String
    let choose: ([URL]) -> Void
    let finder: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
            Text(title).seleneFont(.screen, .semibold).accessibilityAddTraits(.isHeader)
            OortReadout(text: message)
            HStack {
                Text(verbatim: displayPath).seleneFont(.text).lineLimit(1).truncationMode(.middle)
                    .accessibilityLabel(model.folder.path)
                Spacer()
                if let parent = FileBrowser.parent(of: model.folder, home: model.home) {
                    OortButton(title: L10n.text("Up one folder"), preset: .compact) { model.enter(parent) }
                }
                OortButton(title: L10n.text("Search this folder"), preset: .compact) { model.input(.search) }
            }
            if model.search {
                OortSearchField(query: $model.query, lit: searchFocused) {
                    TextField(L10n.text("Search this folder"), text: $model.query)
                        .focused($searchFocused).onAppear { searchFocused = true }
                        .onSubmit { searchFocused = false; activate() }
                }
            }
            HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.medium)) {
                list(.places, heading: L10n.text("Places"), items: model.places) { place, index in
                    row(placeTitle(place), icon: .folder, focused: focused(.places, index)) { model.enter(place.url) }
                }
                .frame(maxWidth: canvas.u(SeleneTokens.Space.sliderMeasure * 1.8))
                Divider()
                files
            }
            ViewThatFits(in: .horizontal) {
                HStack { actionButtons }
                VStack(alignment: .leading) { actionButtons }
            }
            SeleneHintsBar(left: [HintItem(.b, model.backLabel), HintItem(.y, "Search", keyboard: .text("⌘F"))],
                           right: hints, bottom: 0, leftInset: 0, press: model.input)
        }
        .padding(canvas.u(SeleneTokens.Space.section))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(SeleneTheme.ink)
        .background(SeleneTheme.pageSurface)
        .environment(\.seleneMinimumFont, 12)
        .onAppear {
            model.confirm = activate
            model.close = cancel
        }
        .onDisappear { model.confirm = nil; model.close = nil }
        .onChange(of: model.query) { _, _ in model.index = 0 }
        .onChange(of: model.column) { _, column in if column != .files { searchFocused = false } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            model.enter(model.folder)
        }
    }

    private var hints: [HintItem] {
        [HintItem(.move, "Change column")] + (model.canPickSeveral ? [HintItem(.x, "Select multiple files")] : [])
            + [HintItem(.a, "Select")]
    }

    private var displayPath: String {
        let path = model.folder.path
        let home = model.home.path
        if path == home { return L10n.text("Home") }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private var files: some View {
        Group {
            if let issue = model.problem {
                VStack(alignment: .leading) {
                    OortReadout(text: issueText(issue))
                }
            } else if !model.ready {
                ProgressView().accessibilityLabel(L10n.text("Reading folder…"))
            } else if model.visible.isEmpty {
                OortReadout(text: L10n.text("No matching files or folders."))
            } else {
                list(.files, heading: L10n.text("In this folder"), items: model.visible) { item, index in
                    let detail = item.isFolder ? nil : fileType(item) + (item.size.map { " · " + Int64($0).formatted(.byteCount(style: .file).locale(locale.formatLocale)) } ?? "")
                    row(item.name, icon: item.isFolder ? .folder : nil, detail: detail,
                        focused: focused(.files, index), selected: model.selected.contains(item.url)) { open(item) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func list<Item: Identifiable, Content: View>(_ column: OortFilePickerModel.Column, heading: String, items: [Item],
                                                         @ViewBuilder content: @escaping (Item, Int) -> Content) -> some View where Item.ID: Hashable {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.small)) {
            Text(heading).seleneFont(.text, .semibold).accessibilityAddTraits(.isHeader)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                        ForEach(items.indices, id: \.self) { index in
                            content(items[index], index).id(items[index].id)
                        }
                    }
                    .padding(canvas.u(SeleneTokens.Space.hairline))
                }
                .onChange(of: model.index) { _, index in
                    if model.column == column, items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, icon: MaterialIcon?, detail: String? = nil, focused: Bool,
                     selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SeleneOptionRow(icon: icon, title: title, about: detail, focused: focused, aboutIsHelp: false) {
                if selected { MaterialIconView(.check, size: 22).accessibilityHidden(true) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(detail ?? (icon == .folder ? L10n.text("Folder") : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var actions: [(title: String, enabled: Bool, perform: () -> Void)] {
        var actions: [(String, Bool, () -> Void)] = []
        if model.choice.allowsFolder {
            actions.append((L10n.text("Choose this folder"), model.ready && model.selected.isEmpty, { choose([model.folder]) }))
        }
        if model.canSelectMultiple {
            actions.append((model.multiple && !model.selected.isEmpty
                            ? L10n.format("Choose %lld files", [model.selected.count]) : L10n.text("Select multiple files"),
                            model.ready, {
                if !model.selected.isEmpty { choose(model.selected) }
                else { model.multiple.toggle() }
            }))
        }
        if model.problem == .denied {
            actions.append((L10n.text("Open System Settings"), true, {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                    NSWorkspace.shared.open(url)
                }
            }))
        }
        actions.append((model.showHidden ? L10n.text("Hide hidden files") : L10n.text("Show hidden files"), true, {
            model.showHidden.toggle()
            model.index = model.column == .actions ? model.index : 0
        }))
        actions.append((L10n.text("Cancel"), true, cancel))
        actions.append((L10n.text("Open in Finder…"), true, finder))
        return actions
    }

    @ViewBuilder private var actionButtons: some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
            OortButton(title: action.title, focused: focused(.actions, index), state: action.enabled ? .ready : .blocked,
                       preset: .compact, action: action.perform)
        }
    }

    private func focused(_ column: OortFilePickerModel.Column, _ index: Int) -> Bool {
        model.column == column && model.index == index
    }

    private func activate() {
        switch model.column {
        case .places:
            if model.places.indices.contains(model.index) { model.enter(model.places[model.index].url) }
        case .files:
            let entries = model.visible
            if entries.indices.contains(model.index) { open(entries[model.index]) }
        case .actions:
            let actions = actions
            if actions.indices.contains(model.index), actions[model.index].enabled { actions[model.index].perform() }
        }
    }

    private func open(_ entry: FileBrowser.Entry) {
        if entry.isFolder { model.enter(entry.url) }
        else if model.multiple { model.toggle(entry.url) }
        else { choose([entry.url]) }
    }

    private func placeTitle(_ place: FileBrowser.Place) -> String {
        switch place.kind {
        case .home: L10n.text("Home")
        case .games: "Games"
        case .desktop: L10n.text("Desktop")
        case .downloads: L10n.text("Downloads")
        case .documents: L10n.text("Documents")
        case .disk, .recent: place.url.lastPathComponent
        }
    }

    private func fileType(_ entry: FileBrowser.Entry) -> String {
        switch entry.url.pathExtension.lowercased() {
        case "nup": L10n.text("Switch 2 game package")
        case "xci", "xcz": L10n.text("Switch cartridge file")
        case "keys": L10n.text("Switch keys")
        case let name where FileBrowser.gameExtensions.contains(name): L10n.text("Switch game or update")
        case "": L10n.text("File")
        case let name: name.uppercased()
        }
    }

    private func issueText(_ issue: FileBrowser.Failure) -> String {
        switch issue {
        case .denied: L10n.text("Access was refused. In System Settings → Privacy & Security → Files and Folders, allow Oort NX to access this folder.")
        case .link: L10n.text("This folder is a link. Choose its original location instead.")
        case .unavailable: L10n.text("This folder is no longer available. If it is on an external disk, reconnect it or go back.")
        }
    }
}
