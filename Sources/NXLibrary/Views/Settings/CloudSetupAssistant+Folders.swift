import NXLibraryCore
import ArcanePorting
import SwiftUI

/// Step 2: both folders on one page, already found, each with its own Change.
extension CloudSetupAssistant {
    var folders: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
                card(.sources, icon: .storage, choice: sources)
                card(.library, icon: .cloud, choice: library)
                moveRow
                if discoveryUnknown {
                    SeleneStatusDot(text: text("Existing cloud folders could not be checked"), color: SeleneTheme.ink60)
                }
            }
            .padding(canvas.u(SeleneTokens.Space.hairline))
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func card(_ folder: Folder, icon: MaterialIcon, choice: Choice?) -> some View {
        let creates = folder == .library && choice == nil && newLibrary != nil
        let path = choice?.path ?? (creates ? newLibrary?.path : nil)
        let advice = choice.flatMap { advice(folder, $0.path) }
        return OortFolderCard(
            icon: icon, title: question(folder), about: expectation(folder), account: text("Google Drive"),
            path: path.map(shownPath), placeholder: text(work?.kind == .discover ? "Oort is looking in your Drive…" : "No folder chosen yet")
        ) {
            if choice == nil, work?.kind == .discover { OortMeter(share: nil, fill: CloudLibraryStatus.pending.color) }
            else {
                SeleneStatusDot(text: advice.map(explanation) ?? status(folder, choice),
                                color: choice == nil && !creates || advice != nil ? SeleneTheme.untested : SeleneTheme.statusOK,
                                labelColor: SeleneTheme.ink90)
            }
        } actions: {
            if let advice, advice.swaps {
                // One swap answers both questions: it is offered once.
                if folder == .sources { compact(.accept(folder), "Swap the two folders", enabled: folderControlsReady, action: swapFolders) }
            } else if let instead = advice?.instead {
                compact(.accept(folder), "Use folder “%@”", arguments: [folderLabel(instead)], enabled: folderControlsReady) { accept(folder, instead) }
            }
            compact(.change(folder), path == nil ? "Choose" : "Change this", enabled: folderControlsReady) { openBrowser(folder) }
                .accessibilityLabel("\(text(path == nil ? "Choose" : "Change this")) · \(question(folder))")
        }
    }

    /// "Games › Switch › Jeux": where it is, as a person says it.
    func shownPath(_ path: String) -> String {
        ([text("My Drive")] + path.split(separator: "/").map(String.init)).joined(separator: " › ")
    }

    func advice(_ folder: Folder, _ path: String) -> CloudFolderIndex.Advice? {
        index?.advice(folder, choosing: path, other: folder == .sources ? library?.path : sources?.path)
    }

    /// The first card whose folder answers the other question.
    var firstAdvice: (folder: Folder, path: String, advice: CloudFolderIndex.Advice)? {
        for (folder, choice) in [(Folder.sources, sources), (.library, library)] {
            if let path = choice?.path, let advice = advice(folder, path) { return (folder, path, advice) }
        }
        return nil
    }

    private func status(_ folder: Folder, _ choice: Choice?) -> String {
        guard let choice else {
            if folder == .sources { return text("No ROM found. Choose the folder, or continue without: you can add it later.") }
            return text(newLibrary == nil ? "Choose a folder for Oort." : "Oort will create this folder when you continue.")
        }
        guard let games = choice.games else {
            return text(choice.origin == .chosen ? "Chosen by you" : choice.origin == .current ? "In use now" : "Found on your Drive")
        }
        if games == 0 { return text(folder == .library ? "Empty for now: your compiled games will go there." : "Kept from last time. No game in it yet.") }
        return found(games, choice.names)
    }

    /// "15 games found: Animal Crossing, Mario Kart 8…"
    func found(_ games: Int, _ names: [String]) -> String {
        let shown = names.prefix(3).joined(separator: ", ")
        guard !shown.isEmpty else { return L10n.count("%lld games found.", games, context: localization) }
        return L10n.count("%lld games found: %@", games, arguments: [names.count > 3 || games > names.count ? shown + "…" : shown], context: localization)
    }

    func accept(_ folder: Folder, _ path: String) {
        guard folderControlsReady else { return }
        if folder == .sources, isDirect { saveSources(path); return }
        if browsing != nil { closeBrowser() }
        if folder == .library { chooseLibrary(choice(folder, path)) } else { chooseSources(path) }
        focus.reset()
    }

    func swapFolders() {
        guard folderControlsReady, let rom = sources?.path, let own = library?.path else { return }
        if browsing != nil { closeBrowser() }
        chooseLibrary(choice(.library, rom))
        chooseSources(own)
        focus.reset()
    }

    /// What is known of a folder the player points at.
    func choice(_ folder: Folder, _ path: String) -> Choice {
        let origin: Choice.Origin = path == Self.cleaned(folder == .library ? model.preference.root : model.preference.sourcesRoot) ? .current : .chosen
        switch index?.kind(of: path) {
        case .compiled(let games, let names) where folder == .library: return .init(path: path, games: games, names: names, origin: origin)
        case .roms(let games, let names) where folder == .sources: return .init(path: path, games: games, names: names, origin: origin)
        default: return .init(path: path, games: nil, origin: origin)
        }
    }

    @ViewBuilder private var moveRow: some View {
        if checkingMove { progress("Checking the old folder…") }
        else if moveUnavailable {
            SeleneStatusDot(text: text("Could not check the old folder."), color: SeleneTheme.ink60)
        } else if let movePlan, movePlan.games > 0 {
            SeleneStatusDot(text: format(movePlan.games == 1 ? "%d game in %@" : "%d games in %@",
                                         [movePlan.games, movePlan.source]), color: SeleneTheme.statusOK)
            if moveOffered {
                option(.moveGames, text("Move my games here"), action: { draft.toggleMove() }) {
                    if draft.wantsMove { MaterialIconView(.check, size: SeleneTokens.Space.panel).accessibilityHidden(true) }
                }
                .accessibilityValue(text(draft.wantsMove ? "On" : "Off"))
            }
        }
    }

    func selectAccount(_ name: String) {
        draft.chooseAccount(name)
        onboarding = model.preference.remote != name
        library = nil; sources = nil; newLibrary = nil; index = nil; sourcesOverride = nil; sourcesChanged = false
        movePlan = nil; moveUnavailable = false; discoveryUnknown = false
        if !onboarding {
            library = .init(path: Self.cleaned(model.preference.root), games: nil, origin: .current)
            draft.browse(Self.cleaned(model.preference.root))
            sourcesOverride = model.preference.sourcesRootOverride
            if sourcesOverride != nil {
                sources = .init(path: Self.cleaned(model.preference.sourcesRoot), games: nil, origin: .current)
            }
        }
        focus.reset()
        discover()
    }

    /// One look at the Drive for both folders. What was chosen before comes first; nothing is saved here.
    private func discover() {
        guard let service else { return }
        let ticket = draft.ticket, kept = model.keptFolders
        start(.discover) {
            do {
                let found = try await service.discoverFolders(kept: kept)
                guard !Task.isCancelled, draft.matches(ticket) else { return }
                index = found.index
                show(found)
            } catch is CancellationError { return }
            catch { if !Task.isCancelled && draft.matches(ticket) { discoveryUnknown = true } }
            guard !Task.isCancelled, draft.matches(ticket), library == nil else { return }
            let path = CloudFolderDiscovery.newLibrary
            if let place = try? await service.deepestParent(of: path), !Task.isCancelled, draft.matches(ticket) {
                newLibrary = (path, place.path, place.parent)
            }
        }
    }

    private func show(_ found: CloudFolderDiscovery) {
        if let current = library {
            if found.library?.path == current.path { library?.games = found.library?.games; library?.names = found.library?.names ?? [] }
        } else if let place = found.library {
            library = .init(path: place.path, games: place.games, names: place.names, origin: place.kept ? .kept : .found)
            draft.browse(place.path)
        }
        if let current = sources {
            if found.sources?.path == current.path { sources?.games = found.sources?.games; sources?.names = found.sources?.names ?? [] }
        } else if let place = found.sources {
            sources = .init(path: place.path, games: place.games, names: place.names, origin: place.kept ? .kept : .found)
            sourcesOverride = place.path == defaultSourcesPath ? nil : place.path
            sourcesChanged = sourcesOverride != model.preference.sourcesRootOverride
        } else if !onboarding {
            sources = .init(path: Self.cleaned(model.preference.sourcesRoot), games: nil, origin: .current)
        }
    }

    func proposeLibrary() {
        guard folderControlsReady, newLibrary != nil else { return }
        focus.reset()
        confirmingLibrary = true
    }

    func createLibrary() {
        guard confirmingLibrary, folderControlsReady, let service, let place = newLibrary else { return }
        let ticket = draft.ticket
        confirmingLibrary = false; focus.reset()
        start(.create) {
            try await service.createPath(place.path, below: place.below, shown: place.parent)
            guard !Task.isCancelled, draft.matches(ticket) else { return }
            newLibrary = nil
            chooseLibrary(.init(path: place.path, games: 0, origin: .chosen))
            finishFolders()
        }
    }

    func chooseLibrary(_ choice: Choice) {
        library = choice
        draft.browse(choice.path)
        if sourcesOverride == nil, sources?.origin == .current {
            sources = .init(path: defaultSourcesPath, games: nil, origin: .current)
        }
        checkMove()
    }

    func chooseSources(_ path: String) {
        sources = choice(.sources, path)
        sourcesOverride = path == defaultSourcesPath && model.preference.sourcesRootOverride != path ? nil : path
        sourcesChanged = true
        draft.renewTicket()
    }

    /// The games left in the folder used until now, offered to follow. Every check of the move stays in the service.
    private func checkMove() {
        movePlan = nil; moveUnavailable = false; checkingMove = false; moveConflicts = []; moveFailure = nil
        let old = Self.cleaned(model.preference.root), path = draft.path, ticket = draft.ticket, approved = model.driveScope
        guard let service, model.preference.remote == draft.remote, replacement == nil,
              CloudDriveFolders.canMove(from: old, to: path) else { return }
        checkingMove = true
        start(.browse) {
            defer { if draft.matches(ticket) { checkingMove = false } }
            do {
                let plan = try await service.movePlan(from: old, to: path, approved: approved)
                if !Task.isCancelled && draft.matches(ticket) && model.driveScope == approved { movePlan = plan }
            } catch let failure as CloudDriveFolders.MoveFailure {
                if !Task.isCancelled && draft.matches(ticket) { moveFailure = failure.localizedDescription }
            } catch CloudLibraryFailure.referenceOverlap {
                if !Task.isCancelled && draft.matches(ticket) {
                    moveFailure = CloudLibraryFailure.referenceOverlap.localizedDescription
                }
            } catch {
                if !Task.isCancelled && draft.matches(ticket) { moveUnavailable = true }
            }
        }
    }
}
