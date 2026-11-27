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
        guard let name = p["at"]?.stringValue else { return .settings }
        guard let place = IntegrationPlace(rawValue: name) else { throw Manifest.Failure(code: "place-missing") }
        return place
    }

    /// The rows of a place, in the order the page shows them: in Settings, Steam and information online, then programs.
    func integrationSections(at place: IntegrationPlace) -> [[IntegrationEntry]] {
        guard place == .settings else { return [steamEntry(at: place)].compactMap { $0 }.map { [$0] } }
        let on = choices.online == true, known = records.values.filter(\.found).count
        let online = IntegrationEntry(id: "online", title: .init("Game information online"),
                                      about: .init("Oort NX looks for each game’s cover, description, year and genres on the Steam store, Wikipedia and Wikidata. It sends the game’s name, or its Steam number, and your language. Like any site, they see your internet address. No account, no key, and nothing else leaves this computer."),
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

    /// Steam on this computer, as each place says it.
    func steamEntry(at place: IntegrationPlace) -> IntegrationEntry? {
        let counts = steamSeen()?.counts, on = choices.steam == true
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
        let sections = integrationSections(at: place).map { $0.map { json($0, token: token($0)) } }
        return place == .settings ? ["sections": .array(sections.map { ["entries": .array($0)] })] : ["entries": .array(sections.flatMap { $0 })]
    }

    /// Done by the owner, only if the row is still the one shown and was not done since.
    func actIntegration(_ p: CatalogJSON) throws -> CatalogJSON {
        let place = try place(p)
        guard let entry = integrationSections(at: place).joined().first(where: { $0.id == p["id"]?.stringValue }) else { throw Manifest.Failure(code: "entry-missing") }
        guard let request = entry.request else { throw Manifest.Failure(code: "not-a-request") }
        guard p["token"]?.stringValue == token(entry) else { throw Manifest.Failure(code: "stale") }
        integrationTurn += 1
        switch request {
        case .steam(let enabled): try setSteam(enabled)
        case .online(let on): try setOnline(on)
        case .clearOnline: _ = try clearOnline()
        case .refreshSteam, .cancelSteamRefresh, .chooseSteamFolder, .readSteamAgain: throw Manifest.Failure(code: "not-a-request")
        }
        guard case .object(var page) = integrationsPage(at: place) else { return .null }
        // The library shows Steam's games, or no longer does.
        if case .steam = request { page["rescan"] = true }
        return .object(page)
    }

    /// The first steps go on: Steam's switch, as the player left it, is kept if Steam is here and it changes the choice
    /// in force. `rescan` says the library changed.
    func keepSteamChoice(_ p: CatalogJSON) throws -> CatalogJSON {
        guard let shown = p["on"]?.boolValue else { throw Manifest.Failure(code: "on-missing") }
        guard steamSeen() != nil, shown != (choices.steam == true) else { return ["rescan": false] }
        integrationTurn += 1
        try setSteam(shown)
        return ["rescan": true]
    }

    private func json(_ entry: IntegrationEntry, token: String) -> CatalogJSON {
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
        if entry.request != nil { out["token"] = .string(token) }
        return .object(out)
    }

    /// `[key, count?, args…]`: the page's `t(…)` takes them in this order.
    private func words(_ words: IntegrationWords) -> CatalogJSON {
        .array([.string(words.key)] + (words.count.map { [.number($0)] } ?? []) + words.args.map(CatalogJSON.string))
    }

    /// The turn and what the row said and asked (FNV-1a of its JSON): a change of either refuses an old token.
    private func token(_ entry: IntegrationEntry) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(json(entry, token: ""))) ?? Data()
        let digest = data.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        return "\(integrationTurn)." + String(digest, radix: 16)
    }
}
