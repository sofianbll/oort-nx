import NXLibraryCore
import ArcanePorting
import SwiftUI

/// Changing one folder: the whole panel is a folder browser.
extension CloudSetupAssistant {
    @ViewBuilder var browser: some View {
        if typedPath != nil {
            input(.typedPath) {
                TextField(text("Enter a path"), text: Binding(get: { typedPath ?? "" }, set: { typedPath = $0 }),
                          prompt: Text(verbatim: "Games/Switch/ROM"))
                    .focused($field, equals: .typedPath).onSubmit(primary)
                    .accessibilityLabel(text("Enter a path"))
            }
            if !primaryEnabled {
                SeleneStatusDot(text: text("Enter a folder path such as Games or Archive/Games."), color: SeleneTheme.danger, font: .row)
            }
        } else if folderName != nil {
            Text(text("Folder name")).seleneFont(.row, .semibold).foregroundStyle(SeleneTheme.ink)
            input(.folderName) {
                TextField(text("Folder name"), text: Binding(get: { folderName ?? "" }, set: { folderName = $0 }))
                    .focused($field, equals: .folderName).onSubmit(proposeCreation)
                    .accessibilityLabel(text("Folder name"))
            }
        } else {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                trail
                compact(.newFolder, "New folder…", enabled: folderControlsReady && (listing != nil || folderMissing), action: nameFolder)
                compact(.enterPath, "Enter a path", enabled: folderControlsReady, action: enterPath)
                compact(.refresh, "Refresh", enabled: folderControlsReady, action: refreshFolder)
            }
            recentRow
            folderList
            verdict
        }
    }

    /// Whether the folder on screen answers the question, before it is chosen.
    @ViewBuilder private var verdict: some View {
        if let browsing, listing != nil, !browserPath.isEmpty {
            if let advice = advice(browsing, browserPath) {
                HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                    SeleneStatusDot(text: explanation(advice), color: SeleneTheme.untested, labelColor: SeleneTheme.ink90, font: .row)
                    if let instead = advice.instead {
                        compact(.accept(browsing), "Use folder “%@”", arguments: [folderLabel(instead)], enabled: folderControlsReady) {
                            accept(browsing, instead)
                        }
                    }
                }
            } else if let label = label(browserPath) {
                SeleneStatusDot(text: "\(folderLabel(browserPath)) · \(label)", color: SeleneTheme.statusOK, labelColor: SeleneTheme.ink90, font: .row)
            }
        }
    }

    /// nil for a folder that was not read: nothing is said rather than guessed.
    private func label(_ path: String) -> String? {
        switch index?.kind(of: path) {
        case .roms(let games, _): L10n.count("%lld games", games, context: localization)
        case .compiled(let games, _): "\(text("Compiled by Oort")) · \(L10n.count("%lld games", games, context: localization))"
        case .oneGame: text("One game’s folder")
        case .further: text("Games further in")
        case .nothing: text("No game here")
        case .unknown, nil: nil
        }
    }

    private func fits(_ path: String) -> Bool {
        switch (index?.kind(of: path), browsing) {
        case (.roms, .sources), (.compiled, .library): true
        default: false
        }
    }

    @ViewBuilder private var recentRow: some View {
        if !shownRecents.isEmpty {
            HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                Text(text("Recent folders")).seleneFont(.text, .semibold).foregroundStyle(SeleneTheme.ink75)
                ForEach(shownRecents, id: \.self) { path in
                    compact(.recent(path), "%@", arguments: [folderLabel(path)], enabled: folderControlsReady) { browse(path) }
                        .accessibilityLabel(shownPath(path)).help(shownPath(path))
                }
            }
        }
    }

    /// Folders chosen before with this connection, except the one on screen.
    var shownRecents: [String] { recents.filter { $0 != browserPath }.prefix(4).map { $0 } }

    private var trail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: canvas.u(SeleneTokens.Space.hairline)) {
                ForEach(breadcrumbs, id: \.self) { path in
                    if !path.isEmpty {
                        MaterialIconView(.chevron, size: SeleneTokens.Space.medium).foregroundStyle(SeleneTheme.ink60).accessibilityHidden(true)
                    }
                    if path == browserPath {
                        Text(folderLabel(path)).seleneFont(.row, .semibold).foregroundStyle(SeleneTheme.ink)
                            .accessibilityAddTraits(.isSelected)
                    } else {
                        compact(.breadcrumb(path), path.isEmpty ? "My Drive" : "%@", arguments: path.isEmpty ? [] : [folderLabel(path)], enabled: folderControlsReady) { browse(path) }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var folderList: some View {
        if listing != nil {
            if folderNames.isEmpty { OortReadout(text: text("No folder here."), preset: .lead) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                        ForEach(folderNames, id: \.self) { name in
                            option(.folder(name), name, icon: .folder, enabled: folderControlsReady,
                                   action: { browse(CloudDriveFolders.joining(browserPath, name)) }) {
                                let path = CloudDriveFolders.joining(browserPath, name)
                                if let label = label(path) {
                                    Text(label).seleneFont(.row).foregroundStyle(fits(path) ? SeleneTheme.ink : SeleneTheme.ink60)
                                    if fits(path) { MaterialIconView(.check, size: SeleneTokens.Space.large).foregroundStyle(SeleneTheme.statusOK).accessibilityHidden(true) }
                                }
                                MaterialIconView(.chevron, size: SeleneTokens.Space.large).foregroundStyle(SeleneTheme.ink60).accessibilityHidden(true)
                            }
                            .accessibilityValue(label(CloudDriveFolders.joining(browserPath, name)) ?? "")
                            .id(Target.folder(name))
                        }
                    }
                    .padding(canvas.u(SeleneTokens.Space.hairline))
                }
                .onChange(of: focusedTarget) { _, target in if case .folder = target { proxy.scrollTo(target) } }
            }
            .frame(maxHeight: .infinity)
        }
        if (listing == nil && work != nil) || work?.kind == .create { progress("Checking…") }
        if listing == nil && work == nil { cardKey(.retry, "Try again", action: retryFolder) }
    }

    func openBrowser(_ folder: Folder) {
        guard folderControlsReady else { return }
        browsing = folder
        issue = nil
        recents = CloudRecentFolders.load(for: draft.remote)
        focus.reset()
        browse((folder == .library ? library?.path : sources?.path) ?? "")
    }

    func closeBrowser() {
        work?.task.cancel(); work = nil
        looking?.cancel()
        browsing = nil; listing = nil; folderMissing = false; shownParent = nil; issue = nil
        focus.reset()
    }

    func retryFolder() {
        if remotes == nil { inspect() } else { browse(browserPath) }
    }

    /// Asks Drive again instead of showing what was read a moment ago.
    func refreshFolder() {
        Task { @MainActor in
            await reads.clear()
            index = nil
            browse(browserPath)
        }
    }

    func browse(_ path: String) {
        guard let shown else { return }
        browserPath = path
        let ticket = draft.renewTicket()
        listing = nil; folderMissing = false; shownParent = nil
        looking?.cancel()
        focus.reset()
        start(.browse) {
            let result: CloudDriveFolders.Listing
            async let parent = try? shown.creationParent(path)
            do { result = try await shown.list(path, ticket: ticket) }
            catch StorageBackendError.notFound {
                if !Task.isCancelled && draft.matches(ticket), !path.isEmpty {
                    let above = try? await shown.creationParent(path.split(separator: "/").dropLast().joined(separator: "/"))
                    if !Task.isCancelled && draft.matches(ticket) { shownParent = above; folderMissing = true }
                }
                throw CloudLibraryFailure.folderMissing
            }
            guard !Task.isCancelled, draft.matches(result.ticket) else { return }
            listing = result
            look(result.names, in: path)
            let shownThere = await parent
            guard !Task.isCancelled, draft.matches(ticket) else { return }
            shownParent = shownThere
        }
    }

    /// What each folder holds is said after the list is shown, and stops when another folder is opened.
    private func look(_ names: [String], in path: String) {
        guard let shown else { return }
        let remote = draft.remote, known = index
        looking = Task { @MainActor in
            var seen = known
            if seen == nil, let found = try? await shown.discoverFolders(kept: nil) {
                guard !Task.isCancelled, draft.remote == remote else { return }
                seen = found.index
                index = seen
                refreshChoices()
            }
            guard let base = seen, !Task.isCancelled else { return }
            let unread = names.map { CloudDriveFolders.joining(path, $0) }.filter { base.kind(of: $0) == .unknown }
            guard !unread.isEmpty else { return }
            let glanced = await shown.glance(at: unread, into: base)
            guard !Task.isCancelled, draft.remote == remote else { return }
            index = glanced
        }
    }

    private func refreshChoices() {
        for folder in [Folder.library, .sources] {
            guard let old = folder == .library ? library : sources else { continue }
            var new = choice(folder, old.path)
            new.origin = old.origin
            if folder == .library { library = new } else { sources = new }
        }
    }

    func enterPath() {
        guard folderControlsReady else { return }
        typedPath = browserPath
        focus.select(.typedPath); field = .typedPath
    }

    /// The primary key of the browser.
    func chooseFolder() {
        guard let browsing else { return }
        field = nil
        if let typedFolder, browsing == .library || !isDirect {
            typedPath = nil
            browse(Self.cleaned(typedFolder))
            return
        }
        let path = typedFolder ?? browserPath
        if let advice = advice(browsing, path) {
            doubt = (browsing, path, advice)
            focus.reset()
            return
        }
        answer(browsing, path)
    }

    /// The player has seen the explanation: their own choice is kept.
    func answerDoubt() { doubt = nil; focus.reset() }

    func answer(_ folder: Folder, _ path: String) {
        if !(folder == .sources && isDirect) { typedPath = nil }
        accept(folder, path)
    }

    func saveSources(_ path: String) {
        let preference = model.preference
        let typed = typedPath != nil
        CloudRecentFolders.add(path, for: draft.remote)
        let apply = {
            if path != model.preference.sourcesRoot || model.sourcesNeedConfirmation { model.chooseSourcesRoot(path) }
            onClose()
        }
        if preference.referenceFolder == nil { apply() }
        else if let service {
            start(.verify) {
                try await service.verifyPersonalFolder(path, allowMissing: typed)
                guard !Task.isCancelled, self.model.preference == preference,
                      self.browsing == .sources else { return }
                apply()
            }
        }
    }

    func nameFolder() {
        guard folderControlsReady else { return }
        guard shownParent != nil else {
            if work == nil { issue = CloudLibraryFailure.scopeChanged.messageKey }
            return
        }
        if folderMissing, let name = browserPath.split(separator: "/").last {
            focus.reset()
            creation = String(name)
            return
        }
        guard listing != nil else { return }
        folderName = ""; focus.select(.folderName); field = .folderName
    }

    func proposeCreation() {
        guard let name = folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
              CloudDriveFolders.validName(name), folderControlsReady else { return }
        folderName = nil; field = nil; focus.reset()
        if folderNames.contains(name) { browse(CloudDriveFolders.joining(browserPath, name)) }
        else { creation = name }
    }

    func create(_ name: String) {
        guard creation == name, folderControlsReady, let service, let shown = shownParent else { return }
        let parent = folderMissing ? browserPath.split(separator: "/").dropLast().joined(separator: "/") : browserPath
        let ticket = draft.ticket
        creation = nil; focus.reset()
        start(.create) {
            try await service.create(name, in: parent, shown: shown)
            await reads.clear()
            if !Task.isCancelled && draft.matches(ticket) { browse(CloudDriveFolders.joining(parent, name)) }
        }
    }
}
