import Foundation
@preconcurrency import NXLibraryCore

/// The rows about integrations (desktop/PROTOCOL.md): Settings › Integrations, and Steam wherever else the page shows it
/// (the first steps, Add game, the activity center). Each row is decided here, from the owners this core keeps (Steam,
/// information online, programs); the page draws it and sends back the one it was shown. A row is done once, as it was
/// shown, or refused: its token names what was shown and the turn it was shown in.
extension Companion {
    /// Where the page shows a row. Steam's switch is the same everywhere (SteamSourceEntries.sourceSwitch); what A does
    /// with it is the place's: at once in Settings, kept for later in the first steps.
    enum IntegrationPlace: String { case settings, guide, add, activity }

    func runIntegrations(_ method: String, _ p: CatalogJSON) throws -> CatalogJSON? {
        switch method {
        case "integrations": return try integrationsPage(at: place(p))
        case "integrations.act": return try actIntegration(p)
        case "integrations.keep": return try keepSteamChoice(p)
        default: return nil
        }
    }

    private func place(_ p: CatalogJSON) throws -> IntegrationPlace {
        guard let at = p["at"] else { return .settings }
        guard let place = at.stringValue.flatMap(IntegrationPlace.init(rawValue:)) else { throw Manifest.Failure(code: "place-missing") }
        return place
    }

    /// What information online does and sends: under its switch, and in the question asked before it is on.
    static let onlineAbout: IntegrationWords = .init("Oort NX looks for each game’s cover, description, year and genres on the Steam store, Wikipedia and Wikidata. It sends the game’s name, or its Steam number, and your language. Like any site, they see your internet address. No account, no key, and nothing else leaves this computer.")

    /// The rows of a place, in the order the page shows them: in Settings, Steam and information online, then programs;
    /// in the activity center, information still looked for online, then what Steam still downloads.
    func integrationSections(at place: IntegrationPlace) -> [[IntegrationEntry]] {
        guard place == .settings else { return [place == .activity ? onlineWaiting() : nil, steamEntry(at: place)].compactMap { $0 }.map { [$0] } }
        let on = choices.online == true, known = records.values.filter(\.found).count
        let online = IntegrationEntry(id: "online", title: .init("Game information online"), about: Self.onlineAbout,
                                      value: on ? .init("%lld games known", count: known) : .init("Off"), icon: "search",
                                      control: .toggle(checked: on), request: .online(on: !on))
        // Offered once something was found, and asked first: it cannot be taken back.
        let clear = IntegrationEntry(id: "clear", title: .init("Delete what was found online"), value: .init("%lld games", count: known),
                                     icon: "delete", control: .row, request: .clearOnline,
                                     confirmation: .init(title: .init("Delete what was found online?"),
                                                         message: .init("Covers and descriptions found online leave this computer. Your own pictures stay."),
                                                         confirm: .init("Delete")))
        let programs = IntegrationEntry(id: "prog", title: .init("Programs"),
                                        about: .init("Any program with its arguments, an emulator with a game for example. Sends nothing."),
                                        value: .verbatim(String(shelf.programs.count)), icon: "terminal", control: .open(.programs), request: nil)
        return [[steamEntry(at: .settings)!, online] + (known > 0 ? [clear] : []), [programs]]
    }

    /// Games whose information is still looked for online, while it is on: what the activity center shows and the
    /// control center's dot says. Nothing is asked: it opens Settings › Integrations.
    func onlineWaiting() -> IntegrationEntry? {
        let waiting = onlineWaitingCount
        guard waiting > 0 else { return nil }
        return IntegrationEntry(id: "online", title: .init("Information online"), about: .init("Looking…"), value: .init("%lld games", count: waiting),
                                icon: "search", control: .open(.integrations), request: nil)
    }

    /// The question asked before information online is on, in the first steps and from a game's details: what it does
    /// and sends, No and Yes. Yes turns it on (online.set); in the first steps, No turns it off. The page has it from
    /// the start (hello).
    func onlineQuestion() -> CatalogJSON {
        ["title": words(.init("Look for game information online?")), "text": words(Self.onlineAbout), "no": words(.init("No")),
         "yes": words(.init("Yes, look online"))]
    }

    /// What a game's page says of information online, decided once from what is known of the game: the row, and the
    /// sentence under « Pictures and information ». Off (A asks first: the question, then on), or Waiting until the game
    /// was looked for, then its title (or Found), None if the player chose none, Not found (A corrects what was found).
    func informationJSON(of game: Game) -> CatalogJSON {
        let on = choices.online == true, record = records[game.id]
        let found = [record?.about, record?.year].contains { !($0 ?? "").isEmpty }
        let value: IntegrationWords, pictures: IntegrationWords
        switch (on, found, record) {
        case (false, _, _): (value, pictures) = (.init("Off"), .init("Choose your own pictures, or turn on game information online."))
        case (_, true, _): (value, pictures) = (record?.title.flatMap { $0.isEmpty ? nil : .verbatim($0) } ?? .init("Found"), .init("Another cover, or another game if this is not the right one."))
        case (_, _, let record?): (value, pictures) = (record.picked == true ? .init("None") : .init("Not found"), .init("Nothing was found online. Look for it by another name, or choose your own pictures."))
        default: (value, pictures) = (.init("Waiting"), .init("Choose your own pictures, or look for this game online."))
        }
        let online = IntegrationEntry(id: "online", title: .init("Information online"), value: value,
                                      help: [on ? .init("Choose the right game, or none.") : .init("Off. Select to read what it does and what it sends.")],
                                      icon: "search", control: .open(on ? .match : .onlineQuestion), request: nil)
        return ["pictures": words(pictures), "online": json(online, token: nil)]
    }

    /// Where a game comes from besides Steam: a program, a folder of games. The same wherever the page offers them
    /// (the first steps, Add game); it has them from the start (hello).
    func gameSourcesJSON() -> CatalogJSON {
        let program: IntegrationWords = setup.system == "windows"
            ? .init("Any game or emulator you start with an .exe file. Its name and icon come with it.")
            : .init("Any game or emulator, or its menu entry. Its name and icon come with it.")
        let entries = [IntegrationEntry(id: "program", title: .init("A program"), about: program, icon: "terminal", control: .open(.programs), request: nil),
                       IntegrationEntry(id: "folder", title: .init("A folder of games"), about: .init("For recompiled games: each one has its recomplauncher.json."),
                                        icon: "folder", control: .open(.folder), request: nil)]
        return .array(entries.map { json($0, token: nil) })
    }

    /// Steam on this computer, as each place says it. The activity center reads nothing while Steam is off.
    func steamEntry(at place: IntegrationPlace) -> IntegrationEntry? {
        if place == .activity, choices.steam != true { return nil }
        return steamEntry(at: place, counts: steamSeen()?.counts)
    }

    /// Steam's row of the first steps before it is read: while it is looked for, and if the core does not answer, as
    /// where Steam is not found. Sent with the steps (guide), which the page has before it asks for the row.
    func steamBeforeReading() -> CatalogJSON {
        let looking = IntegrationEntry(id: "steam", title: .init("Steam"), value: .init("Looking…"), icon: "gamepad", control: .row, request: nil)
        return ["looking": json(looking, token: nil), "unanswered": steamEntry(at: .guide, counts: nil).map { json($0, token: nil) } ?? .null]
    }

    private func steamEntry(at place: IntegrationPlace, counts: SteamShelf.Found?) -> IntegrationEntry? {
        let on = choices.steam == true
        let reads: IntegrationWords = .init("Reads Steam’s lists of installed games and the pictures it keeps on this computer. Changes nothing and sends nothing; Steam itself starts the games.")
        let missing: IntegrationWords = .init("Steam was not found on this computer. It is looked for again each time.")
        switch place {
        case .settings:
            var steam = SteamSourceEntries.sourceSwitch(id: "steam", inForce: on)
            (steam.icon, steam.about) = ("gamepad", reads)
            if let counts {
                steam.value = .init("%lld games", count: counts.games.count)
                steam.help = [counts.libraries.isEmpty ? nil : .verbatim(counts.libraries.map(Paths.native).joined(separator: ", ")),
                              counts.downloading > 0 ? .init("%lld still downloading, left out", count: counts.downloading) : nil,
                              counts.others > 0 ? .init("%lld tools and extras, left out", count: counts.others) : nil].compactMap { $0 }
            } else {
                (steam.value, steam.help) = (.init("Not found"), [missing])
            }
            return steam
        case .guide:
            guard let counts else {
                return IntegrationEntry(id: "steam", title: .init("Steam"), about: missing, value: .init("Not found"), icon: "gamepad",
                                        control: .row, request: nil)
            }
            // Never chosen, Steam is offered on since it is here; the first steps keep what the switch shows when the
            // player goes on (integrations.keep).
            var steam = SteamSourceEntries.sourceSwitch(id: "steam", inForce: choices.steam ?? true)
            (steam.icon, steam.about, steam.value) = ("gamepad", reads, .init("%lld games", count: counts.games.count))
            return steam
        case .add:
            // Offered while it is here and off: A asks for the other state, on.
            guard let counts, !on else { return nil }
            return IntegrationEntry(id: "steam", title: .init("Steam"),
                                    about: .init("Adds the games Steam installed on this computer. Steam’s own files do not change."),
                                    value: .init("%lld games", count: counts.games.count), icon: "gamepad", control: .row,
                                    request: .steam(enabled: true))
        case .activity:
            guard on, let counts, counts.downloading > 0 else { return nil }
            return IntegrationEntry(id: "steam", title: .init("Steam"), about: .init("%lld still downloading, left out", count: counts.downloading),
                                    value: .verbatim(String(counts.downloading)), icon: "download", control: .open(.integrations), request: nil)
        }
    }

    func integrationsPage(at place: IntegrationPlace) -> CatalogJSON {
        // In the first steps A is the steps' own: their switch waits for them to go on (integrations.keep).
        let sections = integrationSections(at: place).map { $0.map { json($0, token: place == .guide ? nil : token($0)) } }
        switch place {
        case .settings: return ["sections": .array(sections.map { ["entries": .array($0)] })]
        // `working`: information is still looked for online, the control center's dot (what Steam downloads is Steam's).
        case .activity:
            let entries = sections.flatMap { $0 }
            return ["entries": .array(entries), "working": .bool(entries.contains { $0["id"]?.stringValue == "online" })]
        case .guide, .add: return ["entries": .array(sections.flatMap { $0 })]
        }
    }

    /// Done by the owner, only if the row is still the one shown and was not done since.
    func actIntegration(_ p: CatalogJSON) throws -> CatalogJSON {
        let place = try place(p)
        guard let entry = integrationSections(at: place).joined().first(where: { $0.id == p["id"]?.stringValue }) else { throw Manifest.Failure(code: "entry-missing") }
        let done: () throws -> Void
        switch (place, entry.request) {
        case (.guide, _), (_, nil), (_, .refreshSteam?), (_, .cancelSteamRefresh?), (_, .chooseSteamFolder?), (_, .readSteamAgain?):
            throw Manifest.Failure(code: "not-a-request")
        case (_, .steam(let enabled)?): done = { try self.setSteam(enabled) }
        case (_, .online(let on)?): done = { try self.setOnline(on) }
        case (_, .clearOnline?): done = { _ = try self.clearOnline() }
        }
        guard p["token"]?.stringValue == token(entry) else { throw Manifest.Failure(code: "stale") }
        integrationTurn += 1
        try done()
        guard case .object(var page) = integrationsPage(at: place) else { return .null }
        // The library shows Steam's games, or no longer does.
        if case .steam? = entry.request { page["rescan"] = true }
        return .object(page)
    }

    /// The first steps go on: Steam's switch, as the player left it, is kept if Steam is here and it changes the choice
    /// in force. `rescan` says the library changed.
    func keepSteamChoice(_ p: CatalogJSON) throws -> CatalogJSON {
        guard let shown = p["on"]?.boolValue else { throw Manifest.Failure(code: "on-missing") }
        let here = SteamShelf.root(named: steamFolder, home: setup.home, system: setup.system) != nil
        guard here, shown != (choices.steam == true) else { return ["rescan": false] }
        integrationTurn += 1
        try setSteam(shown)
        return ["rescan": true]
    }

    private func json(_ entry: IntegrationEntry, token: String?) -> CatalogJSON {
        var out: [String: CatalogJSON] = ["id": .string(entry.id), "title": words(entry.title)]
        out["sub"] = entry.about.map(words)
        out["value"] = entry.value.map(words)
        if !entry.help.isEmpty { out["help"] = .array(entry.help.map(words)) }
        out["icon"] = entry.icon.map(CatalogJSON.string)
        switch entry.control {
        case .toggle(let checked): out["checked"] = .bool(checked)
        case .open(let route): out["open"] = .string(route.rawValue)
        case .row, .button, .value: break
        }
        if let c = entry.confirmation { out["confirm"] = ["title": words(c.title), "text": words(c.message), "label": words(c.confirm)] }
        if entry.request != nil, let token { out["token"] = .string(token) }
        return .object(out)
    }

    /// `[key, count?, args…]`: the page's `t(…)` takes them in this order.
    private func words(_ words: IntegrationWords) -> CatalogJSON {
        .array([.string(words.key)] + (words.count.map { [.number($0)] } ?? []) + words.args.map(CatalogJSON.string))
    }

    /// The turn and what A asks of the row (FNV-1a): its request, its state and its question. Not the numbers it shows,
    /// which change while the page is open (games found online, Steam read again): a change of what A asks, or a row
    /// done since, refuses an old token.
    private func token(_ entry: IntegrationEntry) -> String {
        let asked = [entry.id, entry.request.map { "\($0)" }, entry.checked.map { "\($0)" }, entry.confirmation.map { "\($0)" }]
        let digest = asked.map { $0 ?? "-" }.joined(separator: "|").utf8
            .reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        return "\(integrationTurn)." + String(digest, radix: 16)
    }
}
