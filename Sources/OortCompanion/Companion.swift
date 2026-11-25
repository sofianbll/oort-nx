import Foundation
@preconcurrency import NXLibraryCore

/// The desktop app's logic, one JSON request per line (desktop/PROTOCOL.md). It keeps no window, starts no process
/// and opens no connection: it answers, and writes in its own folder and in the settings files games declare.
public final class Companion {
    public struct Setup: Sendable {
        public var data: String
        /// The folder of catalog.json.
        public var resources: String
        public var system: String
        public var home: String
        public var documents: String
        public var local: String
        public var config: String
        public var languages: [String]

        public init(data: String, resources: String, system: String, home: String = "", documents: String = "", local: String = "",
                    config: String = "", languages: [String] = []) {
            (self.data, self.resources, self.system, self.home) = (data, resources, system, home)
            (self.documents, self.local, self.config, self.languages) = (documents, local, config, languages)
        }
    }

    private var setup: Setup
    private let store: Store
    private var settings: AppSettings
    private var draft: AppSettingsDraft
    private var shelf: Shelf
    private var profiles: Profiles
    private var sessions: [PlaySession]
    private var games: [Game] = []
    private var pad = "xbox"
    private let now: () -> Date

    public init(_ setup: Setup, now: @escaping () -> Date = Date.init) throws {
        self.setup = setup
        self.now = now
        store = try Store(folder: setup.data)
        settings = store.read("settings", AppSettings())
        draft = AppSettingsDraft(settings, fields: SettingRow.all.map(\.field))
        shelf = store.read("library", Shelf())
        profiles = store.read("profiles", Profiles())
        sessions = store.read("sessions", [PlaySession]())
        // A session cut short (power, crash) counts until its last sign of life.
        for index in sessions.indices where sessions[index].isActive { sessions[index].endedAt = sessions[index].lastHeartbeatAt }
        scan()
    }

    // MARK: - Requests

    /// One line in, one line out. A line that is not a request is answered too, so the two sides never lose step.
    public func answer(_ line: String) -> String {
        let request = try? JSONDecoder().decode(CatalogJSON.self, from: Data(line.utf8))
        var reply: [String: CatalogJSON] = ["id": request?["id"] ?? .null]
        do {
            guard let method = request?["method"]?.stringValue else { throw Manifest.Failure(code: "request") }
            reply["result"] = try run(method, request?["params"] ?? [:])
        } catch let failure as Manifest.Failure { reply["error"] = .string(failure.code)
        } catch let failure as GameFile.Failure { reply["error"] = .string(failure.code)
        } catch {
            reply["error"] = "disk"
            reply["detail"] = .string(error.localizedDescription)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(CatalogJSON.object(reply))).map { String(decoding: $0, as: UTF8.self) } ?? #"{"error":"encoding"}"#
    }

    private func run(_ method: String, _ p: CatalogJSON) throws -> CatalogJSON {
        switch method {
        case "hello":
            if setup.languages.isEmpty { setup.languages = p["languages"].strings }
            return hello()
        case "view": return view()
        case "library": return library(p)
        case "library.rescan": scan(); return library(p)
        case "folders": return folders()
        case "folders.add": return try addFolder(try text(p, "path"))
        case "folders.remove":
            shelf.folders.removeAll { $0 == p["path"]?.stringValue }
            return try keepShelf()
        case "programs.add": return try addProgram(p)
        case "programs.remove":
            shelf.programs.removeAll { $0.key == p["key"]?.stringValue }
            return try keepShelf()
        case "game": return try details(try game(p))
        case "game.favorite": return try setFavorite(try game(p), p["on"]?.boolValue ?? false)
        case "game.input": return try setInput(p)
        case "game.setting": return try setGameSetting(p)
        case "game.option": return try setOption(p)
        case "game.art":
            return .text(Library.Art(of: try game(p), own: Paths.join(setup.data, "art")).path(p["kind"]?.stringValue ?? "").map(Paths.native))
        case "game.folder": return .string(Paths.native(try folder(try game(p), p["name"]?.stringValue)))
        case "game.link":
            let url = p["url"]?.stringValue ?? ""
            return .bool(url.hasPrefix("https://") && games.contains { $0.manifest?.prepare?.options.contains { $0.license?.url == url } == true })
        case "pad":
            pad = p["kind"]?.stringValue == "playstation" ? "playstation" : "xbox"
            return .null
        case "launch.plan": return try launcher(try game(p)).plan(mode: p["mode"]?.stringValue == "desktop" ? "desktop" : "bigpicture").json
        case "prepare.plan": return try launcher(try game(p)).preparePlan().json
        case "prepare.line":
            guard let progress = Launcher.progress(p["line"]?.stringValue ?? "") else { return .null }
            return ["value": .number(progress.value), "text": .string(progress.text)]
        case "prepare.end": return try endPrepare(p)
        case "session.start": return try startSession(try game(p))
        case "session.beat": return try beat(p)
        case "session.end": return try endSession(p)
        case "settings": return settingsPage()
        case "settings.set": return try setSetting(p)
        case "settings.save": return try saveSettings()
        case "settings.discard":
            restartDraft()
            return settingsPage()
        case "settings.reset": return try resetSection(p)
        case "settings.remember": return try remember(p)
        case "profiles": return profileList()
        case "profiles.add": return try addProfile(try text(p, "name"))
        case "profiles.select": return try selectProfile(p)
        case "profiles.rename": return try renameProfile(p)
        case "profiles.pin": return try setPIN(p)
        case "catalog": return try catalog()
        case "files": return try files(p)
        case "sound": return try sound(p)
        case "prompts": return prompts()
        default: throw Manifest.Failure(code: "method")
        }
    }

    private func text(_ p: CatalogJSON, _ key: String) throws -> String {
        guard let value = p[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { throw Manifest.Failure(code: "param-" + key) }
        return value
    }

    private func game(_ p: CatalogJSON) throws -> Game {
        guard let id = p["id"]?.stringValue.flatMap(UUID.init), let game = games.first(where: { $0.id == id }) else { throw Manifest.Failure(code: "game-missing") }
        return game
    }

    // MARK: - What the window needs at once

    private func hello() -> CatalogJSON {
        ["version": .string(Companion.version), "system": .string(setup.system), "view": view(), "games": .number(games.count),
         "tabs": .list(SettingRow.tabs.map(\.rawValue)), "lastGame": .text(settings.lastSelectedGameID?.uuidString),
         "lastHome": .string(settings.startOn == .last ? settings.lastHome.rawValue : settings.startOn.rawValue)]
    }

    public static let version = "0.1.0-alpha.1"

    /// The settings the window applies, with what is being tried and not saved yet.
    private func view() -> CatalogJSON {
        let s = draft.displayed(over: settings, previewsOnly: true)
        let language = AppLocale(language: s.appLanguage, region: nil, preferredLanguages: setup.languages).language
        return ["language": .string(language.rawValue), "palette": .string(s.colorThemeID), "zoom": .number(s.interfaceZoom),
                "reduceMotion": .bool(s.reduceMotion), "animated": .bool(s.animatedBackground), "keepCloud": .bool(s.keepWallpaperOnGames),
                "clock": .bool(s.showClock), "sounds": .bool(s.interfaceSounds), "volume": .number(s.soundVolume), "pack": .string(s.soundPackID),
                "figure": .string(s.noteFigure.rawValue), "octave": .number(s.noteOctave), "hints": .bool(s.showButtonHints),
                "buttonNames": .string(s.buttonNames.rawValue), "viewSwitches": .bool(s.viewButtonSwitches),
                "fullscreen": .bool(s.startInFullscreen), "startingTab": .string(s.startingTab), "sort": .string(s.librarySort.rawValue),
                "sessionCard": .bool(s.showsSessionCard), "restore": .bool(s.restoreLastGame)]
    }

    // MARK: - Library

    private var profile: LocalProfile? { profiles.list.first { $0.id == profiles.active } }
    private var history: History { History(sessions, profile: profiles.active) }

    private func scan() { games = Library.scan(shelf, favorites: profile?.favorites ?? []) }

    private func library(_ p: CatalogJSON) -> CatalogJSON {
        let history = history
        let sort = p["sort"]?.stringValue.flatMap(LibrarySort.init) ?? settings.librarySort
        let query = LibraryQuery(filter: LibraryFilter(startingTab: p["tab"]?.stringValue ?? ""), searchText: p["search"]?.stringValue ?? "", sort: sort)
        return ["games": .array(query.applyRecords(games, history: history).map { summary($0, history) }), "total": .number(games.count),
                "folders": .number(shelf.folders.count)]
    }

    private func summary(_ game: Game, _ history: History) -> CatalogJSON {
        let art = Library.Art(of: game, own: Paths.join(setup.data, "art"))
        var out: [String: CatalogJSON] = [
            "id": .string(game.id.uuidString), "name": .string(game.name), "favorite": .bool(game.isFavorite),
            "seconds": .number(history.totalDuration(for: game.id).rounded()),
            "last": history.lastPlayed(for: game.id).map { .number($0.timeIntervalSince1970.rounded()) } ?? .null,
            "cover": .bool(art.path("cover") != nil), "icon": .bool(art.path("icon") != nil),
            "hero": .bool(art.path("hero") != nil), "logo": .bool(art.path("logo") != nil),
        ]
        switch game.source {
        case .recompilation(let m, _):
            out["kind"] = "recompilation"
            out["project"] = .text(m.name ?? m.repo)
            let launcher = launcher(game)
            out["state"] = .string(!m.unsupported.isEmpty ? "unsupported" : !launcher.missing.isEmpty ? "inputs" : launcher.needsPrepare ? "prepare" : "ready")
        case .program:
            out["kind"] = "program"
            out["state"] = "ready"
        case .broken(let code):
            out["kind"] = "recompilation"
            out["state"] = "broken"
            out["reason"] = .string(code)
        }
        return .object(out)
    }

    private func launcher(_ game: Game) -> Launcher {
        let base = Places(install: game.folder, documents: setup.documents, local: setup.local, config: setup.config, home: setup.home, pad: pad)
        return Launcher(game: game, state: shelf.games[game.key] ?? GameState(), shared: shelf.shared, base: base, system: setup.system)
    }

    private func details(_ game: Game) throws -> CatalogJSON {
        guard case .object(var out) = summary(game, history) else { return .null }
        out["folder"] = .string(Paths.native(game.folder))
        out["sessions"] = .number(sessions.filter { $0.gameID == game.id && $0.profileID == profiles.active }.count)
        if case .program(let p) = game.source {
            out["program"] = ["key": .string(p.key), "path": .string(Paths.native(p.program)), "args": .list(p.args)]
        }
        if let m = game.manifest {
            let launcher = launcher(game)
            out["repo"] = .text(m.repo)
            out["unsupported"] = .list(m.unsupported)
            out["inputs"] = .array(launcher.inputs.map { input in
                ["id": .string(input.id), "label": .string(input.label), "role": .string(input.role), "optional": .bool(input.optional),
                 "shared": .text(input.shared), "path": .text(launcher.picked(input).map(Paths.native)), "unchecked": .bool(input.unchecked),
                 "folder": .bool(input.formats.contains { $0.isFolder }), "file": .bool(input.shared != nil || input.formats.contains { !$0.isFolder }),
                 "extensions": .list(Array(Set(input.formats.flatMap(\.extensions))).sorted())]
            })
            // One unreadable settings file leaves the rest of the page.
            out["settings"] = .array(m.settings.compactMap { try? launcher.shown($0) })
            out["actions"] = .array(m.actions.filter { $0.open != nil }.map {
                ["id": .string($0.id), "label": .string($0.label), "help": .text($0.help), "open": .text($0.open)]
            })
            if let prepare = m.prepare {
                out["prepare"] = ["label": .text(prepare.label), "needed": .bool(launcher.needsPrepare), "options": .array(launcher.options.map { o in
                    ["id": .string(o.id), "label": .string(o.label), "note": .text(o.note), "on": .bool(launcher.isOn(o)), "required": .bool(o.required),
                     "license": o.license.map { ["name": .string($0.name), "url": .string($0.url)] } ?? .null]
                })]
            }
        }
        return .object(out)
    }

    private func folders() -> CatalogJSON {
        ["folders": .array(shelf.folders.map { folder in
            ["path": .string(Paths.native(folder)), "key": .string(folder), "found": .bool(FileManager.default.fileExists(atPath: folder)),
             "games": .number(games.filter { Paths.isInside($0.folder, folder) || $0.folder == folder }.count)]
        }), "programs": .array(shelf.programs.map { ["key": .string($0.key), "name": .string($0.name), "path": .string(Paths.native($0.program))] })]
    }

    private func addFolder(_ path: String) throws -> CatalogJSON {
        let path = Paths.real(path)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else { throw Manifest.Failure(code: "folder-missing") }
        if !shelf.folders.contains(path) { shelf.folders.append(path) }
        return try keepShelf()
    }

    private func addProgram(_ p: CatalogJSON) throws -> CatalogJSON {
        let program = Paths.real(try text(p, "program"))
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: program, isDirectory: &isFolder), !isFolder.boolValue else { throw Manifest.Failure(code: "program-missing") }
        // The game's file goes last, as one argument whatever its name holds.
        var args = Arguments.split(p["args"]?.stringValue ?? "")
        let target = p["target"]?.stringValue.map(Paths.real)
        if let target {
            guard FileManager.default.fileExists(atPath: target) else { throw Manifest.Failure(code: "file-missing") }
            args.append(Paths.native(target))
        }
        let base = ((target ?? program) as NSString).lastPathComponent
        let name = p["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        let key = Paths.uuid(([program] + args).joined(separator: "\u{0}")).uuidString.lowercased()
        guard !shelf.programs.contains(where: { $0.key == key }) else { throw Manifest.Failure(code: "program-known") }
        shelf.programs.append(Program(key: key, name: name.isEmpty ? (base as NSString).deletingPathExtension : name, program: program, args: args))
        return try keepShelf()
    }

    private func keepShelf() throws -> CatalogJSON {
        try store.write("library", shelf)
        scan()
        return folders()
    }

    private func keep(_ game: Game, _ change: (inout GameState) -> Void) throws -> CatalogJSON {
        change(&shelf.games[game.key, default: GameState()])
        try store.write("library", shelf)
        return try details(game)
    }

    private func setInput(_ p: CatalogJSON) throws -> CatalogJSON {
        let game = try game(p), id = try text(p, "input")
        guard let input = game.manifest?.inputs.first(where: { $0.id == id }) else { throw Manifest.Failure(code: "unknown-input") }
        let path = p["path"]?.stringValue.map(Paths.real)
        if let path {
            if input.shared == nil {
                guard input.format(of: path) != nil else { throw Manifest.Failure(code: "input-kind") }
                if let check = input.checkFile, isFolder(path) {
                    guard FileManager.default.fileExists(atPath: Paths.join(path, check)) else { throw Manifest.Failure(code: "input-check") }
                }
                let others = shelf.games[game.key]?.inputs.filter { $0.key != id } ?? [:]
                guard !others.values.contains(path) else { throw Manifest.Failure(code: "input-twice") }
            } else if isFolder(path) || !FileManager.default.fileExists(atPath: path) { throw Manifest.Failure(code: "input-kind") }
        }
        if let shared = input.shared {
            shelf.shared[shared] = path
            return try keep(game) { _ in }
        }
        // Another copy prepares again.
        return try keep(game) { $0.inputs[id] = path; $0.preparedFor = nil }
    }

    private func isFolder(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
    }

    private func setGameSetting(_ p: CatalogJSON) throws -> CatalogJSON {
        let game = try game(p), id = try text(p, "setting")
        guard let setting = game.manifest?.settings.first(where: { $0.id == id }), !setting.isBindings, let value = p["value"]?.double,
              value.isFinite else { throw Manifest.Failure(code: "value") }
        if setting.within == "args" {
            let valid = setting.slider.map { ($0.min...max($0.min, $0.max)).contains(value) } ?? setting.choices.indices.contains(Int(value))
            guard valid else { throw Manifest.Failure(code: "value") }
            return try keep(game) { $0.args[id] = value }
        }
        try launcher(game).write(setting, value)
        return try details(game)
    }

    private func setOption(_ p: CatalogJSON) throws -> CatalogJSON {
        let game = try game(p), id = try text(p, "option")
        guard game.manifest?.prepare?.options.contains(where: { $0.id == id }) == true else { throw Manifest.Failure(code: "value") }
        return try keep(game) { $0.options[id] = p["on"]?.boolValue ?? false; $0.preparedFor = nil }
    }

    private func setFavorite(_ game: Game, _ on: Bool) throws -> CatalogJSON {
        var me = try activeProfile()
        if on { me.favorites.insert(game.id) } else { me.favorites.remove(game.id) }
        try keepProfile(me)
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return .null }
        games[index].isFavorite = on
        return summary(games[index], history)
    }

    private func folder(_ game: Game, _ name: String?) throws -> String {
        guard let name, name != "install" else { return game.folder }
        guard let places = game.manifest?.folders[name], let path = try launcher(game).places.place(places) else { throw Manifest.Failure(code: "folder-missing") }
        return path
    }

    // MARK: - Sessions

    private func startSession(_ game: Game) throws -> CatalogJSON {
        let date = now()
        let session = PlaySession(gameID: game.id, titleID: game.key, bundleID: nil, startedAt: date, lastHeartbeatAt: date, profileID: profiles.active)
        sessions.append(session)
        try store.write("sessions", sessions)
        return .string(session.id.uuidString)
    }

    private func index(of p: CatalogJSON) throws -> Int {
        guard let id = p["session"]?.stringValue.flatMap(UUID.init), let index = sessions.lastIndex(where: { $0.id == id && $0.isActive }) else { throw Manifest.Failure(code: "session") }
        return index
    }

    private func beat(_ p: CatalogJSON) throws -> CatalogJSON {
        sessions[try index(of: p)].lastHeartbeatAt = now()
        try store.write("sessions", sessions)
        return .null
    }

    private func endSession(_ p: CatalogJSON) throws -> CatalogJSON {
        let index = try index(of: p), date = now()
        sessions[index].lastHeartbeatAt = date
        sessions[index].endedAt = date
        try store.write("sessions", sessions)
        let session = sessions[index]
        let game = games.first { $0.id == session.gameID }
        let end = ending(game, code: p["code"]?.int, closed: p["closed"]?.boolValue ?? false)
        return ["id": .string(session.gameID.uuidString), "name": .text(game?.name), "seconds": .number((session.duration ?? 0).rounded()),
                "total": .number(history.totalDuration(for: session.gameID).rounded()), "crashed": .bool(end.crashed), "message": .text(end.message)]
    }

    /// How a game ended, in its own words when its manifest has some for that code.
    private func ending(_ game: Game?, code: Int?, closed: Bool) -> (crashed: Bool, message: String?) {
        if closed || code == 0 { return (false, nil) }
        if let code, let message = game?.manifest?.exitCodes[String(code)] ?? game?.manifest?.exitCodes[String(UInt32(truncatingIfNeeded: code))] {
            return message == "ok" ? (false, nil) : (true, message)
        }
        return (true, nil)
    }

    private func endPrepare(_ p: CatalogJSON) throws -> CatalogJSON {
        let game = try game(p), launcher = launcher(game), code = p["code"]?.int
        try? FileManager.default.removeItem(atPath: launcher.scratch)
        guard code == 0 else {
            return ["done": false, "message": .text(ending(game, code: code, closed: false).message), "code": code.map { .number($0) } ?? .null]
        }
        let stamp = launcher.stamp
        _ = try keep(game) { $0.preparedFor = stamp }
        return ["done": .bool(!self.launcher(game).needsPrepare), "message": .null, "code": 0]
    }

    // MARK: - Settings

    private func settingsPage() -> CatalogJSON {
        let values = draft.values
        return ["categories": .array(SettingsCategory.groups.flatMap { group in
            group.categories.filter(SettingRow.categories.contains).map { category -> CatalogJSON in
                let rows = SettingRow.all.filter { SettingsCategory(section: $0.section) == category }
                func level(_ sections: [SettingsSection]) -> CatalogJSON { .array(rows.filter { sections.contains($0.section) }.map { $0.json(values, saved: settings) }) }
                return ["id": .string(category.rawValue), "group": .text(group.heading), "icon": .string(category.sections.first?.icon.rawValue ?? ""),
                        "rows": level(category.inlineSections),
                        "subjects": .array(category.subjects.filter { s in rows.contains { $0.section == s } }.map { section in
                            ["id": .string(section.rawValue), "title": .string(section == .look ? "Advanced" : section.titleKey), "rows": level([section])]
                        })]
            }
        }), "changes": .array(draft.changes.map { ["id": .string($0.id), "before": .string($0.before), "after": .string($0.after)] }),
            "pending": .bool(draft.hasChanges), "view": view()]
    }

    private func setSetting(_ p: CatalogJSON) throws -> CatalogJSON {
        let id = try text(p, "id")
        guard let row = SettingRow.all.first(where: { $0.id == id }), row.set(&draft.values, p["value"] ?? .null) else { throw Manifest.Failure(code: "value") }
        return settingsPage()
    }

    private func restartDraft() { draft = AppSettingsDraft(settings, fields: SettingRow.all.map(\.field)) }

    private func saveSettings() throws -> CatalogJSON {
        let next = draft.displayed(over: settings, previewsOnly: false)
        try store.write("settings", next)
        settings = next
        restartDraft()
        return settingsPage()
    }

    private func resetSection(_ p: CatalogJSON) throws -> CatalogJSON {
        guard let section = p["section"]?.stringValue.flatMap(SettingsSection.init), SettingsReset.canReset(section) else { throw Manifest.Failure(code: "value") }
        draft.values = SettingsReset.resetShared(section, in: draft.values)
        return settingsPage()
    }

    /// Where the player is, kept without going through Settings.
    private func remember(_ p: CatalogJSON) throws -> CatalogJSON {
        if let home = p["home"]?.stringValue.flatMap(StartScreen.init) { settings.lastHome = home }
        if let id = p["game"]?.stringValue.flatMap(UUID.init) { settings.lastSelectedGameID = id }
        if let sort = p["sort"]?.stringValue.flatMap(LibrarySort.init) { settings.librarySort = sort }
        try store.write("settings", settings)
        // The draft follows, with what is being tried on top.
        var next = AppSettingsDraft(settings, fields: SettingRow.all.map(\.field))
        next.values = draft.displayed(over: settings, previewsOnly: false)
        draft = next
        return .null
    }

    // MARK: - Profiles

    private func activeProfile() throws -> LocalProfile {
        if let profile { return profile }
        let first = LocalProfile(name: "Oort", look: .init(settings))
        profiles.list.append(first)
        // What was played before anyone had a profile belongs to the first one.
        sessions = sessions.map { s in
            s.profileID != nil ? s : PlaySession(id: s.id, gameID: s.gameID, titleID: s.titleID, bundleID: s.bundleID, startedAt: s.startedAt,
                                                 endedAt: s.endedAt, lastHeartbeatAt: s.lastHeartbeatAt, profileID: first.id)
        }
        profiles.active = first.id
        try store.write("profiles", profiles)
        try store.write("sessions", sessions)
        return first
    }

    private func keepProfile(_ profile: LocalProfile) throws {
        guard let index = profiles.list.firstIndex(where: { $0.id == profile.id }) else { throw Manifest.Failure(code: "profile-missing") }
        profiles.list[index] = profile
        try store.write("profiles", profiles)
    }

    private func profileList() -> CatalogJSON {
        ["active": .text(profiles.active?.uuidString), "list": .array(profiles.list.map { p in
            ["id": .string(p.id.uuidString), "name": .string(p.name), "locked": .bool(p.isLocked), "favorites": .number(p.favorites.count)]
        })]
    }

    private func addProfile(_ name: String) throws -> CatalogJSON {
        _ = try activeProfile()
        guard name.count <= 40 else { throw Manifest.Failure(code: "param-name") }
        profiles.list.append(LocalProfile(name: name, look: .init(AppSettings())))
        try store.write("profiles", profiles)
        return profileList()
    }

    private func selectProfile(_ p: CatalogJSON) throws -> CatalogJSON {
        guard let id = p["profile"]?.stringValue.flatMap(UUID.init), let next = profiles.list.first(where: { $0.id == id }) else { throw Manifest.Failure(code: "profile-missing") }
        if next.isLocked, !next.matchesPIN(p["pin"]?.stringValue ?? "") { throw Manifest.Failure(code: "pin") }
        if var me = profile {
            me.look = .init(settings)
            try keepProfile(me)
        }
        profiles.active = id
        next.look.apply(to: &settings)
        try store.write("profiles", profiles)
        try store.write("settings", settings)
        restartDraft()
        scan()
        return profileList()
    }

    private func renameProfile(_ p: CatalogJSON) throws -> CatalogJSON {
        let name = try text(p, "name")
        guard name.count <= 40, var one = profiles.list.first(where: { $0.id.uuidString == p["profile"]?.stringValue }) else { throw Manifest.Failure(code: "param-name") }
        one.rename(to: name)
        try keepProfile(one)
        return profileList()
    }

    private func setPIN(_ p: CatalogJSON) throws -> CatalogJSON {
        var me = try activeProfile()
        if me.isLocked, !me.matchesPIN(p["old"]?.stringValue ?? "") { throw Manifest.Failure(code: "pin") }
        guard me.setPIN(p["pin"]?.stringValue) else { throw Manifest.Failure(code: "pin-shape") }
        try keepProfile(me)
        return profileList()
    }

    // MARK: - Catalog, files, sounds, prompts

    private func catalog() throws -> CatalogJSON {
        let file = URL(fileURLWithPath: Paths.join(setup.resources, "catalog.json"))
        guard let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode(CatalogJSON.self, from: data) else { throw Manifest.Failure(code: "catalog") }
        return list
    }

    /// A folder for the file picker: only names, never what files hold.
    private func files(_ p: CatalogJSON) throws -> CatalogJSON {
        var path = p["path"]?.stringValue ?? ""
        #if os(Windows)
        if path.isEmpty {
            let drives = (65...90).map { "\(Character(UnicodeScalar($0)!)):/" }.filter { FileManager.default.fileExists(atPath: $0) }
            return ["path": "", "parent": .null, "entries": .array(drives.map { ["name": .string(Paths.native($0)), "path": .string($0), "folder": true] })]
        }
        #endif
        if path.isEmpty { path = setup.home.isEmpty ? "/" : setup.home }
        path = Paths.real(path)
        guard isFolder(path) else { throw Manifest.Failure(code: "folder-missing") }
        guard let names = try? Library.read(path) else { throw Manifest.Failure(code: "folder-closed") }
        let wanted = Set(p["extensions"].strings.map { $0.lowercased() }), onlyFolders = p["folders"]?.boolValue ?? false
        let entries = names.filter { !$0.hasPrefix(".") }.prefix(4000).compactMap { name -> CatalogJSON? in
            let full = Paths.join(path, name), folder = isFolder(full)
            if !folder, onlyFolders || (!wanted.isEmpty && !wanted.contains((name as NSString).pathExtension.lowercased())) { return nil }
            return ["name": .string(name), "path": .string(full), "folder": .bool(folder)]
        }
        // Above a drive is the list of drives.
        let up: CatalogJSON = Paths.parent(path).map(CatalogJSON.string) ?? (setup.system == "windows" ? "" : .null)
        return ["path": .string(path), "shown": .string(Paths.native(path)), "parent": up, "entries": .array(Array(entries)),
                "games": .number(Library.scan(Shelf(folders: [path]), favorites: []).count)]
    }

    /// A 16-bit WAV, as text. Silent events have none.
    private func sound(_ p: CatalogJSON) throws -> CatalogJSON {
        let figure = p["figure"]?.stringValue.flatMap(OortSynth.Figure.init) ?? .rise
        guard let event = p["event"]?.stringValue.flatMap(SoundPackEvent.init), let synth = OortSynth(pack: p["pack"]?.stringValue ?? "oort") else { throw Manifest.Failure(code: "sound") }
        return .text(synth.wav(event, step: p["step"]?.int ?? 0, notes: figure.notes, octave: p["octave"]?.int ?? 0)?.base64EncodedString())
    }

    /// The names of the buttons, for every way to name them, and the keys of a keyboard.
    private func prompts() -> CatalogJSON {
        func table(_ style: ButtonNameStyle, _ pad: ConnectedPad) -> CatalogJSON {
            .object(Dictionary(uniqueKeysWithValues: PromptButton.allCases.map { ($0.rawValue, .string(ButtonPrompts.label($0, style: style, connected: pad))) }))
        }
        return ["nintendo": table(.nintendo, .nintendo), "xbox": table(.xbox, .xbox), "playstation": table(.playstation, .playstation)]
    }
}

private extension SettingsSection {
    /// The title before translation, which the window does.
    var titleKey: String { rawValue == "look" ? "Advanced" : title }
}
