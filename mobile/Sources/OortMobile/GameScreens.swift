import PhotosUI
import ShellHost
import ShellModel
import SwiftUI

/// A game's page: what it is, where its data and saves are, and what can be done with it.
struct GameScreen: View {
    let id: String
    let model: ShellHostModel
    @Bindable var nav: OortNav
    @State private var deleting = false
    @State private var picking = false
    @State private var picture: PhotosPickerItem?
    @State private var copied = false
    @Environment(\.horizontalSizeClass) private var across
    @Environment(\.verticalSizeClass) private var down
    /// Room for the picture beside the list: iPad, or a phone on its side.
    private var beside: Bool { across == .regular || down == .compact }

    private var detail: GameDetail? { model.details.first { $0.id == id } }

    var body: some View {
        if let detail {
            layout(detail)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .photosPicker(isPresented: $picking, selection: $picture, matching: .images)
                .onChange(of: picture) { _, item in
                    Task {
                        guard let data = try? await item?.loadTransferable(type: Data.self), let cover = OortCover.banner(from: data) else { return }
                        model.actions.onSaveCustomCover?(id, cover)
                    }
                }
                .confirmationDialog(Oort.text("Remove \(detail.game.title) from this device?"), isPresented: $deleting, titleVisibility: .visible) {
                    Button(Oort.text("Remove the game, keep its saves"), role: .destructive) { remove(saves: false) }
                    Button(Oort.text("Remove the game and its saves"), role: .destructive) { remove(saves: true) }
                } message: {
                    Text(Oort.text("Its data is deleted from this device. You can send it again from your Mac; a deleted save cannot come back."))
                }
        } else {
            ContentUnavailableView(Oort.text("This game is no longer here"), systemImage: "square.dashed")
        }
    }

    @ViewBuilder private func layout(_ detail: GameDetail) -> some View {
        if beside {
            HStack(spacing: 0) {
                ScrollView { header(detail, key: down != .compact).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, SeleneTokens.Space.panel) }
                    .scrollBounceBehavior(.basedOnSize)
                    // A phone on its side is short: the one action stays above the tab bar.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if down == .compact, !isBroken(detail) {
                            playKey(detail).padding(.horizontal, SeleneTokens.Space.panel).padding(.vertical, SeleneTokens.Space.compact)
                        }
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in min(width * Oort.Measure.sideShare, Oort.Measure.side) }
                OortList(model: model, nav: nav, title: "", sections: sections(detail), backdrop: false) { EmptyView() }
            }
            .background { OortBackdrop(strength: Oort.Measure.backdrop) }
            .navigationTitle(detail.game.title)
        } else {
            OortList(model: model, nav: nav, title: detail.game.title, sections: sections(detail)) { header(detail, key: false) }
                // The one action stays under the thumb however far the list goes.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isBroken(detail) {
                        playKey(detail)
                            .padding(.horizontal, SeleneTokens.Space.panel)
                            .padding(.top, SeleneTokens.Space.large)
                            .padding(.bottom, SeleneTokens.Space.compact)
                            .background { LinearGradient(colors: [.clear, Oort.night.opacity(Oort.Measure.foot)], startPoint: .top, endPoint: .center).ignoresSafeArea() }
                    }
                }
        }
    }

    private func isBroken(_ detail: GameDetail) -> Bool { if case .broken = detail.game.state { true } else { false } }

    private func playKey(_ detail: GameDetail) -> some View {
        let action = OortGameAction(detail, model: model, nav: nav)
        return Button(action: action.run) { Label(action.label, systemImage: action.symbol).frame(maxWidth: .infinity) }
            .buttonStyle(OortKeyStyle(solid: true))
            .disabled(!action.enabled)
    }

    private func remove(saves: Bool) {
        _ = nav.back()
        model.actions.onDeleteGame(id, saves)
        nav.cloud?.removed(id)
    }

    private func header(_ detail: GameDetail, key: Bool) -> some View {
        let action = OortGameAction(detail, model: model, nav: nav)
        return VStack(alignment: .leading, spacing: SeleneTokens.Space.medium) {
            if let banner = detail.game.banner {
                OortPicture(artwork: banner).aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: down == .compact ? 150 : nil)
                    .clipShape(RoundedRectangle(cornerRadius: Oort.tile, style: .continuous))
            }
            Text(detail.game.title).font(.title.bold()).foregroundStyle(Oort.ink).accessibilityAddTraits(.isHeader)
            HStack(spacing: SeleneTokens.Space.compact) {
                OortStateDot(state: detail.game.state)
                Text(action.line).foregroundStyle(Oort.ink2)
            }
            .font(.subheadline)
            if case .broken(_, let message, _) = detail.game.state, !message.isEmpty {
                Text(message).font(.subheadline).foregroundStyle(Oort.ink2)
            } else if key {
                playKey(detail)
            }
        }
        .padding(.vertical, SeleneTokens.Space.compact)
        // A row cuts at its edge: the dot needs its own room.
        .padding(.horizontal, SeleneTokens.Space.seam)
    }

    private func sections(_ detail: GameDetail) -> [OortSection] {
        let a = model.actions
        var facts: [OortRow] = []
        func fact(_ id: String, _ title: String, _ value: String?) { if let value, !value.isEmpty { facts.append(OortRow(id: id, title: title, value: value)) } }
        fact("played", Oort.text("Play time"), detail.playSummary)
        fact("last", Oort.text("Last played"), detail.game.recentlyPlayed)
        fact("version", Oort.text("Version"), detail.game.version)
        fact("dlc", Oort.text("Add-on content"), detail.dlc)
        var play = [OortRow(id: "options", title: Oort.text("Options"), value: detail.hasModifiedSettings ? Oort.text("Changed") : "",
                            symbol: "slider.horizontal.3", kind: .open(.options(id))),
                    OortRow(id: "mapping", title: Oort.text("Buttons for this game"), symbol: "gamecontroller", kind: .open(.mapping(id)))]
        if let cheats = detail.cheatsSummary {
            play.append(OortRow(id: "cheats", title: Oort.text("Cheats"), value: cheats.totalCount == 0 ? "" : Oort.text("\(cheats.enabledCount) on"), symbol: "wand.and.stars",
                                kind: .open(.cheats(id))))
        }
        var data = [OortRow(id: "data", title: detail.dataSource.isEmpty ? Oort.text("No data") : detail.dataSource, note: detail.dataNote, symbol: "internaldrive"),
                    OortRow(id: "pick", title: Oort.text("Choose a folder in Files"), symbol: "folder", kind: .button { a.onPickGameData(id) })]
        if !detail.dataFromShell {
            data.append(OortRow(id: "appdata", title: Oort.text("Use the app's own folder"), symbol: "arrow.uturn.backward", kind: .button { a.onUseAppData(id) }))
        }
        var saves = [OortRow(id: "save", title: Oort.text("On this device"), note: Oort.text("In Files: On My iPhone or iPad, Oort NX, games, \(id), save."), symbol: "square.and.arrow.down"),
                     OortRow(id: "cloud", title: detail.cloudSaves ?? Oort.text("Follow a folder you choose"), note: detail.cloudNote,
                             symbol: "folder.badge.gearshape", kind: .button { a.onPickCloudSaves(id) })]
        if detail.cloudSaves != nil {
            saves.append(OortRow(id: "cloudoff", title: Oort.text("Stop following the folder"), symbol: "xmark.circle", kind: .button { a.onDisableCloudSaves(id) }))
        }
        if let backup = detail.latestSaveBackup {
            saves.append(OortRow(id: "restore", title: Oort.text("Bring back the last copy"), note: backup, symbol: "clock.arrow.circlepath",
                                 kind: .button { a.onRestoreSaveBackup(id) }))
        }
        var look = [OortRow(id: "cover", title: Oort.text("Choose its picture"), symbol: "photo", kind: .button { picking = true })]
        if detail.game.hasCustomCover {
            look.append(OortRow(id: "coveroff", title: Oort.text("Back to the game's own picture"), symbol: "arrow.uturn.backward", kind: .button { a.onResetCustomCover?(id) }))
        }
        look.append(OortRow(id: "link", title: copied ? Oort.text("Link copied") : Oort.text("Copy the link that starts this game"),
                            note: Oort.text("For Shortcuts and the Home Screen."), symbol: "link", kind: .button { a.onCopyShortcutURL?(id); copied = true }))
        if let add = a.onAddToHomeScreen {
            look.append(OortRow(id: "home", title: Oort.text("Make a Home Screen icon"), note: Oort.text("Saves the icon to Photos and opens Shortcuts."),
                                symbol: "plus.app", kind: .button { Task { _ = await add(id) } }))
        }
        var problem: [OortRow] = []
        if case .broken(_, _, let technical) = detail.game.state, !technical.isEmpty {
            problem.append(OortRow(id: "technical", title: Oort.text("Details"), note: technical, symbol: "stethoscope"))
        }
        problem += [OortRow(id: "log", title: Oort.text("Game log"), symbol: "doc.text", kind: .button { a.onShowLog(id) }),
                    OortRow(id: "delete", title: Oort.text("Remove from this device"), symbol: "trash", tint: Oort.danger, kind: .button { deleting = true })]
        if nav.device != nil, !isBroken(detail) {
            let action = OortGameAction(detail, model: model, nav: nav)
            play.insert(OortRow(id: "start", title: action.label, symbol: action.symbol, enabled: action.enabled, kind: .button(action.run)), at: 0)
        }
        return [OortSection(id: "facts", rows: facts), OortSection(id: "play", title: Oort.text("Play"), rows: play),
                OortSection(id: "data", title: Oort.text("Game data"), rows: data),
                OortSection(id: "saves", title: Oort.text("Saves"), footer: Oort.text("Nothing is sent anywhere unless you choose a folder."), rows: saves),
                OortSection(id: "look", title: Oort.text("Picture and shortcut"), rows: look),
                OortSection(id: "problem", title: Oort.text("If something is wrong"), rows: problem)].filter { !$0.rows.isEmpty }
    }
}

/// A photo as the 16:9 picture the app shows, cut around its middle.
enum OortCover {
    static func banner(from data: Data) -> Data? {
        guard let source = Artwork(id: "cover", data: data)?.image else { return nil }
        let ratio = 16.0 / 9, w = Double(source.width), h = Double(source.height)
        let crop = w / h > ratio ? CGRect(x: (w - h * ratio) / 2, y: 0, width: h * ratio, height: h)
                                 : CGRect(x: 0, y: (h - w / ratio) / 2, width: w, height: w / ratio)
        guard let image = source.cropping(to: crop.integral) else { return nil }
        let out = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(target) ? out as Data : nil
    }
}

/// A game's own settings, the ones its `launcher.json` lists.
struct OptionsScreen: View {
    let id: String
    let model: ShellHostModel
    let nav: OortNav

    var body: some View {
        let detail = model.details.first { $0.id == id }
        OortList(model: model, nav: nav, title: Oort.text("Options"), sections: sections(detail)) {
            Text(detail?.game.title ?? "").font(.title2.bold()).foregroundStyle(Oort.ink).padding(.vertical, SeleneTokens.Space.compact)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func sections(_ detail: GameDetail?) -> [OortSection] {
        guard let detail else { return [] }
        var result = detail.sections.filter { $0.id != PadMappingRows.sectionID }.map { section in
            OortSection(id: section.id, title: section.title, rows: section.rows.map { row in
                OortRow(row) { model.actions.onChange(id, row.id, $0) }
            })
        }
        if result.isEmpty {
            result.append(OortSection(id: "none", rows: [OortRow(id: "none", title: Oort.text("This game has no options"))]))
        }
        if detail.hasModifiedSettings {
            result.append(OortSection(id: "reset", rows: [OortRow(id: "reset", title: Oort.text("Back to the tested settings"), symbol: "arrow.counterclockwise",
                                                                  kind: .button { model.actions.onResetDefaults(id) })]))
        }
        return result
    }
}

struct CheatsScreen: View {
    let id: String
    let model: ShellHostModel
    let nav: OortNav
    @State private var snapshot: GameCheatsSnapshot?
    @State private var mismatch: (token: String, name: String)?

    var body: some View {
        OortList(model: model, nav: nav, title: Oort.text("Cheats"), sections: sections) { EmptyView() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { snapshot = await model.actions.onLoadCheatsAsync?(id) }
            .alert(Oort.text("This file is for another version of the game"), isPresented: Binding(get: { mismatch != nil }, set: { if !$0 { mismatch = nil } })) {
                Button(Oort.text("Use it anyway")) {
                    let token = mismatch?.token ?? ""
                    Task { take(await model.actions.onConfirmMismatchCheatImportAsync?(id, token)) }
                }
                Button(Oort.text("Cancel"), role: .cancel) { model.actions.onCancelMismatchCheatImport?(id) }
            } message: { Text(mismatch?.name ?? "") }
    }

    private func take(_ outcome: CheatImportOutcome?) {
        switch outcome {
        case .imported(let next, _, _): snapshot = next
        case .buildMismatch(_, _, let name, let token): mismatch = (token, name)
        case .failed(let why): model.notice = why
        case .cancelled, nil: break
        }
    }

    private var sections: [OortSection] {
        let a = model.actions
        var rows: [OortRow] = []
        if let snapshot, !snapshot.entries.isEmpty {
            rows.append(OortRow(id: "master", title: Oort.text("Use cheats in this game"), symbol: "power",
                                kind: .toggle(snapshot.masterOn) { on in Task { self.snapshot = await a.onToggleCheatMasterAsync?(id, on) } }))
        }
        let entries = (snapshot?.entries ?? []).filter { !$0.isLabel && !$0.isSectionMarker }.map { entry in
            OortRow(id: entry.key, title: entry.name, note: entry.isBroken ? Oort.text("This code cannot be read") : "", enabled: !entry.isBroken && snapshot?.masterOn == true,
                    kind: .toggle(entry.enabled) { on in Task { snapshot = await a.onToggleCheatEntryAsync?(id, entry.key, on) } })
        }
        rows.append(OortRow(id: "import", title: Oort.text("Add a cheat file"), symbol: "plus",
                            kind: .button { Task { take(await a.onImportCheatFile?(id)) } }))
        var result = [OortSection(id: "main", footer: Oort.text("Cheats change the game while it runs. Keep a copy of your save."), rows: rows)]
        if !entries.isEmpty { result.append(OortSection(id: "codes", title: Oort.text("Codes"), rows: entries)) }
        if let alert = snapshot?.fuseAlert {
            result.insert(OortSection(id: "fuse", rows: [OortRow(id: "fuse", title: Oort.text("Cheats were turned off after a crash"), note: alert.disabledItems.joined(separator: ", "), symbol: "exclamationmark.triangle",
                                                                 tint: Oort.warning, kind: .button { Task { snapshot = await a.onDismissCheatFuseAlertAsync?(id) } })]), at: 0)
        }
        return result
    }
}
