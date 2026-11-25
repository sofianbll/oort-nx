import Foundation
@preconcurrency import NXLibraryCore

/// Where games come from and what is known of them: programs' own icons and names, Steam on this computer, information
/// found online when the player said yes, and the first steps.
extension Companion {
    func runOwn(_ method: String, _ p: CatalogJSON) throws -> CatalogJSON? {
        switch method {
        case "guide": return try setGuide(p)
        case "programs.rename": return try renameProgram(p)
        case "programs.about": return programAbout(p)
        case "game.picture": return try setPicture(p)
        case "steam.where":
            guard let path = p["path"]?.stringValue, path != steamFolder else { return .null }
            steamFolder = path
            if choices.steam == true { scan() }
            return .null
        case "steam": return steam()
        case "steam.set":
            choices.steam = p["on"]?.boolValue ?? false
            try store.write("choices", choices)
            scan()
            return steam()
        case "steam.updating":
            guard case .steam(let one) = try game(p).source else { throw Manifest.Failure(code: "game-missing") }
            return SteamShelf.isUpdating(one).map(CatalogJSON.bool) ?? .null
        case "online": return online()
        case "online.set":
            choices.online = p["on"]?.boolValue ?? false
            lookup = nil
            try store.write("choices", choices)
            return online()
        case "online.clear": return try clearOnline()
        case "online.none": return try noneOnline(try game(p))
        case "online.start": return try startLookup(p)
        case "online.answer": return try answerLookup(p)
        default: return nil
        }
    }

    var languages: [String] {
        let chosen = AppLocale(language: settings.appLanguage, region: nil, preferredLanguages: setup.languages).language
        return [chosen.rawValue] + setup.languages
    }
    var language: AppLanguage { AppLocale(language: settings.appLanguage, region: nil, preferredLanguages: setup.languages).language }

    // MARK: - The first steps

    static let guidePages = ["welcome", "controller", "games", "online", "done"]

    func guide() -> CatalogJSON {
        let isNew = choices.guideDone != true
        return ["open": .bool(isNew), "page": .string(choices.guide.flatMap { Self.guidePages.contains($0) ? $0 : nil } ?? Self.guidePages[0]),
                "pages": .list(Self.guidePages), "news": .bool(!isNew && choices.newsSeen != true)]
    }

    private func setGuide(_ p: CatalogJSON) throws -> CatalogJSON {
        if let page = p["page"]?.stringValue, Self.guidePages.contains(page) { choices.guide = page }
        if p["done"]?.boolValue == true { (choices.guideDone, choices.guide, choices.newsSeen) = (true, nil, true) }
        if p["seen"]?.boolValue == true { (choices.guideDone, choices.newsSeen) = (true, true) }
        try store.write("choices", choices)
        return guide()
    }

    // MARK: - Programs

    var programFolders: [String] {
        setup.system == "windows" ? [] : [Paths.join(setup.home, ".local/bin"), "/usr/local/bin", "/usr/bin", "/bin", "/usr/local/games", "/usr/games"]
    }
    private var dataFolders: [String] {
        [Paths.join(setup.home, ".local/share"), "/usr/local/share", "/usr/share", "/var/lib/flatpak/exports/share"]
    }

    private func renameProgram(_ p: CatalogJSON) throws -> CatalogJSON {
        let name = try text(p, "name")
        guard name.count <= 120, let index = shelf.programs.firstIndex(where: { $0.key == p["key"]?.stringValue }) else { throw Manifest.Failure(code: "param-name") }
        shelf.programs[index].name = name
        return try keepShelf()
    }

    /// What a program would be called, before it is added.
    private func programAbout(_ p: CatalogJSON) -> CatalogJSON {
        guard let path = p["path"]?.stringValue else { return .null }
        if path.lowercased().hasSuffix(".desktop") { return ["name": .text(DesktopEntry(path, languages: languages, folders: programFolders)?.name)] }
        let file = ProgramFile(path)
        return ["name": .text(file?.name), "publisher": .text(file?.publisher), "version": .text(file?.version)]
    }

    private func stamp(_ path: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "1|\(path)|\(Int(date))|\((attributes?[.size] as? NSNumber)?.intValue ?? 0)"
    }

    /// Reads the programs that changed, for a few seconds at most; true when something new was learnt.
    func readPrograms() -> Bool {
        let until = Date.now.addingTimeInterval(3)
        var changed = false
        unread = 0
        let keys = Set(games.map(\.key))
        for key in found.keys where !keys.contains(key) && !key.hasPrefix("steam:") { found[key] = nil; changed = true }
        for game in games {
            let source: String
            switch game.source {
            case .program(let p): source = p.program
            case .steam(let s): source = s.manifest
            case .recompilation(let m, _):
                guard let program = launcher(game).places.program(m.start?.program ?? []) else { continue }
                source = program
            case .broken: continue
            }
            let mark = stamp(source)
            if found[game.key]?.stamp == mark { continue }
            guard Date.now < until else { unread += 1; continue }
            found[game.key] = look(game, source, mark)
            changed = true
        }
        if changed {
            artStamp += 1
            try? store.write("found", found)
        }
        return changed
    }

    private func look(_ game: Game, _ source: String, _ mark: String) -> Found {
        var out = Found(stamp: mark), program = source
        if case .steam(let s) = game.source {
            guard let file = SteamShelf.program(s) else { return out }
            program = file
        }
        if let file = ProgramFile(program) {
            (out.name, out.publisher, out.version) = (file.name, file.publisher, file.version)
            if let icon = file.icon {
                let folder = Paths.join(setup.data, "found"), path = Paths.join(folder, game.id.uuidString.lowercased() + ".png")
                try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                if (try? icon.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil { out.icon = path }
            }
            return out
        }
        guard case .program(let p) = game.source else { return out }
        let folder = (program as NSString).deletingLastPathComponent
        if !programFolders.contains(folder) {
            out.icon = [p.stem, "icon"].map { Paths.join(folder, $0 + ".png") }.first { Picture.check($0) != nil }
        }
        if setup.system == "linux", let entry = DesktopEntry.entry(for: program, languages: languages, folders: programFolders, data: dataFolders) {
            out.name = entry.name
            if out.icon == nil { out.icon = entry.icon.flatMap { DesktopEntry.icon($0, data: dataFolders) } }
        }
        return out
    }

    func art(_ game: Game) -> Library.Art { Library.Art(of: game, data: setup.data, mark: found[game.key]?.icon) }

    /// A picture the player chose, copied into the app's own folder; without a path, theirs is put away.
    private func setPicture(_ p: CatalogJSON) throws -> CatalogJSON {
        let game = try game(p), kind = try text(p, "kind")
        guard ["cover", "icon", "hero", "logo"].contains(kind) else { throw Manifest.Failure(code: "value") }
        let folder = Paths.join(setup.data, "art/" + game.id.uuidString.lowercased())
        var copy: (from: String, to: String)?
        if let path = p["path"]?.stringValue.map(Paths.real) {
            guard let picture = Picture.check(path) else { throw Manifest.Failure(code: "picture") }
            copy = (path, Paths.join(folder, kind + "." + picture.ext))
        }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let data = try copy.map { try Data(contentsOf: URL(fileURLWithPath: $0.from)) }
        for ext in ["png", "jpg", "jpeg", "webp"] { try? FileManager.default.removeItem(atPath: Paths.join(folder, kind + "." + ext)) }
        if let copy, let data { try data.write(to: URL(fileURLWithPath: copy.to), options: .atomic) }
        artStamp += 1
        return try details(game)
    }

    // MARK: - Steam

    private func steam() -> CatalogJSON {
        guard let root = SteamShelf.root(named: steamFolder, home: setup.home, system: setup.system) else {
            return ["found": false, "on": .bool(choices.steam == true), "chosen": .bool(choices.steam != nil), "games": 0]
        }
        let counts = choices.steam == true ? steamCounts : SteamShelf(root: root).scan()
        return ["found": true, "on": .bool(choices.steam == true), "chosen": .bool(choices.steam != nil), "path": .string(Paths.native(root)),
                "games": .number(counts.games.count), "downloading": .number(counts.downloading), "others": .number(counts.others),
                "libraries": .list(counts.libraries.map(Paths.native))]
    }

    func steamPlan(_ game: SteamGame) throws -> CatalogJSON {
        guard SteamShelf.isUpdating(game) != nil else { throw Manifest.Failure(code: "steam-gone") }
        return ["steam": .number(Int(game.appID)), "folder": .string(Paths.native(game.folder))]
    }

    // MARK: - What is known of a game

    func facts(_ game: Game, _ out: inout [String: CatalogJSON]) {
        let own = found[game.key], record = records[game.id]
        out["publisher"] = .text(record?.publishers?.first ?? own?.publisher)
        out["developer"] = .text(record?.developers?.first)
        out["version"] = .text(own?.version)
        out["about"] = .text(record?.about)
        out["source"] = .text(record?.source)
        out["page"] = .text(record?.page)
        out["title"] = .text(record?.title)
        out["online"] = .bool(choices.online == true)
        out["searched"] = .bool(record != nil)
        out["chosen"] = .bool(record?.picked == true)
        let folder = Paths.join(setup.data, "art/" + game.id.uuidString.lowercased()), files = Library.names(folder)
        out["pictures"] = .list(["cover", "icon", "hero", "logo"].filter { kind in files.contains { $0.hasPrefix(kind + ".") } })
    }

    // MARK: - Online, when the player said yes

    private var onlineFolder: String { Paths.join(setup.data, "online") }
    private func onlineFolder(_ id: UUID) -> String { Paths.join(onlineFolder, id.uuidString.lowercased()) }

    func readRecords() -> [UUID: OnlineRecord] {
        var out: [UUID: OnlineRecord] = [:]
        for name in Library.names(onlineFolder) {
            guard let id = UUID(uuidString: name), let data = FileManager.default.contents(atPath: Paths.join(onlineFolder, name + "/info.json")), data.count <= 1 << 20,
                  let record = try? Store.decoder.decode(OnlineRecord.self, from: data) else { continue }
            out[id] = record
        }
        return out
    }

    private func keep(_ record: OnlineRecord, _ id: UUID) throws {
        let folder = onlineFolder(id)
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try Store.encoder.encode(record).write(to: URL(fileURLWithPath: Paths.join(folder, "info.json")), options: .atomic)
        records[id] = record
        artStamp += 1
    }

    private func forgetPictures(_ id: UUID) {
        let folder = onlineFolder(id)
        for name in Library.names(folder) where name != "info.json" { try? FileManager.default.removeItem(atPath: Paths.join(folder, name)) }
    }

    /// Whether this game should be looked for: online is on, and nothing good is known.
    func wantsLook(_ game: Game) -> Bool {
        guard choices.online == true else { return false }
        if case .broken = game.source { return false }
        guard let record = records[game.id] else { return true }
        if record.picked == true { return record.found && record.language != language.rawValue }
        return !record.isFresh(now()) || record.language != language.rawValue || record.query != OnlineLookup.plain(game.name)
    }

    private func online() -> CatalogJSON {
        ["on": .bool(choices.online == true), "chosen": .bool(choices.online != nil), "known": .number(records.values.filter(\.found).count),
         "waiting": .number(games.filter(wantsLook).count)]
    }

    private func clearOnline() throws -> CatalogJSON {
        lookup = nil
        if FileManager.default.fileExists(atPath: onlineFolder) { try FileManager.default.removeItem(atPath: onlineFolder) }
        records = [:]
        artStamp += 1
        return online()
    }

    private func noneOnline(_ game: Game) throws -> CatalogJSON {
        forgetPictures(game.id)
        var record = OnlineRecord()
        (record.picked, record.query, record.language, record.fetchedAt) = (true, OnlineLookup.plain(game.name), language.rawValue, now())
        try keep(record, game.id)
        return try details(game)
    }

    /// `item` or `appID`: the result the player chose. `text`: another name to look for, when choosing.
    private func startLookup(_ p: CatalogJSON) throws -> CatalogJSON {
        guard choices.online == true else { throw Manifest.Failure(code: "online-off") }
        let game = try game(p), choosing = p["want"]?.stringValue == "choices"
        var steam = p["appID"]?.int.flatMap(UInt32.init(exactly:)), item = p["item"]?.stringValue
        let chosen = steam != nil || item != nil
        if let one = item, !WikidataRatings.isItemID(one) { throw Manifest.Failure(code: "value") }
        // A choice made before is kept when the texts are read again in another language.
        if !choosing, !chosen, let record = records[game.id], record.picked == true, record.found {
            (steam, item) = (record.appID, record.appID == nil ? record.item : nil)
        }
        if !choosing, !chosen, steam == nil, item == nil, case .steam(let own) = game.source { steam = own.appID }
        let name = choosing ? p["text"]?.stringValue?.nonEmpty ?? game.name : game.name
        guard !OnlineLookup.plain(name).isEmpty || steam != nil || item != nil else { throw Manifest.Failure(code: "online-none") }
        let next = OnlineLookup(name: name, steam: choosing ? nil : steam, item: choosing ? nil : item, folder: onlineFolder(game.id), language: language,
                                want: choosing ? .choices : .info)
        if chosen { forgetPictures(game.id) }
        lookup = (game.id, next)
        pickedNow = chosen
        return try lookupStep()
    }

    private func answerLookup(_ p: CatalogJSON) throws -> CatalogJSON {
        guard choices.online == true, lookup != nil else { throw Manifest.Failure(code: "online-off") }
        var saved = false
        if case .get(_, let save?, let limit)? = lookup?.lookup.step() {
            // What came is a picture, of a size a game's picture has, or it is thrown away.
            let part = save + ".part"
            if p["status"]?.int == 200, let picture = Picture.check(part, limit: limit), picture.width >= 64, picture.height >= 64 {
                for ext in ["png", "jpg", "jpeg", "webp"] { try? FileManager.default.removeItem(atPath: save + "." + ext) }
                saved = (try? FileManager.default.moveItem(atPath: part, toPath: save + "." + picture.ext)) != nil
            }
            try? FileManager.default.removeItem(atPath: part)
        }
        do {
            try lookup?.lookup.answer(status: p["status"]?.int ?? 0, text: p["text"]?.stringValue, saved: saved)
        } catch {
            lookup = nil
            throw error
        }
        return try lookupStep()
    }

    private func lookupStep() throws -> CatalogJSON {
        guard let (id, one) = lookup else { throw Manifest.Failure(code: "online") }
        if case .get(let url, let save, let limit) = one.step() {
            guard OnlineLookup.allowed(url) else { lookup = nil; throw Manifest.Failure(code: "online") }
            if let save { try FileManager.default.createDirectory(atPath: (save as NSString).deletingLastPathComponent, withIntermediateDirectories: true) }
            return ["get": .string(url), "save": .text(save.map(Paths.native)), "limit": .number(limit)]
        }
        lookup = nil
        if one.want == .choices {
            return ["done": true, "choices": .array(one.choices.map { c in
                ["title": .string(c.title), "appID": c.appID.map { .number(Int($0)) } ?? .null, "item": .text(c.item)]
            })]
        }
        var record = one.record
        record.fetchedAt = now()
        if pickedNow || (records[id]?.picked == true && record.found) { record.picked = true }
        try keep(record, id)
        return ["done": true, "found": .bool(record.found)]
    }
}
