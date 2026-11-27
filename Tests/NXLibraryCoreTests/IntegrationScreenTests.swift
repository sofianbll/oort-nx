import XCTest
@testable import NXLibraryCore

/// The decisions of Settings › Integrations (from the owners' facts), its template, its four frozen scenarios and its
/// reviewed reference tree. To refresh the two files after a reviewed change, run once:
/// `OORT_WRITE_SCREENS=1 swift test --filter IntegrationScreenTests`, then read their diff.
final class IntegrationScreenTests: XCTestCase {
    /// The Mac's offers, with its settings rows.
    static var mac: IntegrationFacts {
        var facts = IntegrationFacts()
        facts.offers = [.switchGames, .steam, .macApps, .drive, .nextendo, .saves, .images]
        facts.settingsRows = true
        return facts
    }

    private func detail(_ id: IntegrationID, _ facts: IntegrationFacts) throws -> Screen { try XCTUnwrap(IntegrationScreen.detail(id, facts)) }
    private func box(_ screen: Screen, _ id: String) -> [Screen.Node] { screen.blocks.first { $0.id == id }?.items ?? [] }
    private func said(_ screen: Screen, _ box: String) -> String? { self.box(screen, box).first { $0.kind == .text }?.text?.key }

    // MARK: Decisions, from the owners' facts

    func testAnEmptySteamScanIsNotAnUnfinishedOrSuccessfulPlayCheck() {
        var facts = Self.mac
        facts.steam.read = .ready
        XCTAssertEqual(facts.row(.steam)?.status, "No games found")
        facts.steam.read = .scanning
        XCTAssertEqual(facts.row(.steam)?.status, "Reading Steam libraries…")
        facts.steam.read = .failed
        XCTAssertEqual(facts.row(.steam)?.status, "Steam scan failed")
        facts.steam.read = .partial
        XCTAssertEqual(facts.row(.steam)?.status, "Steam scan incomplete")
        facts.steam.read = .ready
        facts.steam.games = 2
        XCTAssertEqual(facts.row(.steam)?.status, "Ready here")
        facts.steam.found = false
        XCTAssertEqual(facts.row(.steam)?.status, "Not found", "a Steam the system looked for and did not find")
    }

    func testOnlyTheOfferedEntriesAreDecidedAndEveryOneSaysWhatItReadsWritesAndSends() {
        let facts = Self.mac
        XCTAssertEqual(facts.sections.map(\.id), [.sources, .engines, .services])
        XCTAssertEqual(facts.sections.map { $0.entries.map(\.id) }, [[.steam, .macApps, .drive], [.switchGames], [.nextendo, .saves, .images]])
        XCTAssertTrue(facts.rows.allSatisfy { !$0.reads.isEmpty && !$0.writes.isEmpty && !$0.sends.isEmpty })
        XCTAssertNil(facts.row(.online), "not offered here")
        var bare = facts
        bare.settingsRows = false
        XCTAssertNil(bare.row(.drive)?.manage, "no settings row, no settings button")
    }

    func testDetailAlwaysShowsTheThreeBoxesAndTheirSentences() throws {
        var facts = Self.mac
        let unlinked = try detail(.drive, facts)
        XCTAssertEqual(unlinked.blocks.map(\.id), ["link", "verify", "next"])
        XCTAssertEqual([said(unlinked, "link"), said(unlinked, "next")], ["Connect your Google Drive to begin.", "Link it first to continue."])
        XCTAssertEqual(unlinked.focusOrder, ["link.manage"])
        facts.drive = .checked
        let date = Date(timeIntervalSince1970: 1)
        facts.driveCheckDate = date
        let drive = try detail(.drive, facts)
        XCTAssertEqual(said(drive, "link"), "Linked to your Google Drive.")
        XCTAssertTrue(box(drive, "verify").contains { $0.text?.date == date })
        XCTAssertEqual(box(drive, "verify").first?.kind, .status, "Verify opens on the status")
        facts.steam = SteamFacts(enabled: true, read: .ready, games: 2)
        let steam = try detail(.steam, facts)
        XCTAssertEqual(steam.focusOrder, ["link.switch", "link.manage", "next.browse"],
                       "Link: its switch (the list's X) and its settings; Continue: its games")
        XCTAssertEqual(steam.initialFocus, "next.browse")
        XCTAssertEqual(steam.node("link.switch")?.a?.intent, .toggle("steam"))
        XCTAssertEqual(try detail(.macApps, facts).focusOrder, ["link.manage"])
        facts.hasSwitchGames = true
        facts.engine = .blocked
        let engine = try detail(.switchGames, facts)
        XCTAssertEqual(engine.focusOrder.compactMap { engine.node($0)?.a?.intent }, [.owner("settings"), .owner("switchGames")])
    }

    /// The engine's checks say what the player needs, not a commit or a compiler number; those stay in its settings.
    func testEngineChecksArePlainWords() throws {
        func checks(_ facts: IntegrationFacts) throws -> [String] { try XCTUnwrap(facts.row(.switchGames)).checks.map(\.key) }
        var facts = Self.mac
        facts.engine = .detected
        facts.engineCommit = "f1c7100fabcdef"
        facts.expectedEngineCommit = "f1c7100f"
        facts.keys = .selected
        facts.xcodeVersion = "Xcode 27"
        facts.metalVersion = "33000.1"
        XCTAssertEqual(try checks(facts), ["Engine up to date", "Switch keys selected", "Apple tools ready"])
        facts.engineCommit = "0123456789"
        facts.metalVersion = nil
        XCTAssertEqual(try checks(facts), ["Engine not the tested version", "Switch keys selected", "Apple tools incomplete"])
        let words = try checks(facts).joined(separator: " ")
        for hidden in ["0123456", "f1c7100", "33000", "Xcode 27"] { XCTAssertFalse(words.contains(hidden)) }
        // A blocked build is said plainly, never « ready », and points at the engine settings.
        facts.metalVersion = "33000.1"
        facts.buildBlock = .appleTools
        XCTAssertEqual(try checks(facts).suffix(2), ["Apple tools not the tested version", "The details are in the engine settings."])
        facts.buildBlock = .buildTools
        XCTAssertEqual(try checks(facts).suffix(3), ["Apple tools ready", "Build tools incomplete", "The details are in the engine settings."])
        facts.engineCommit = "f1c7"
        XCTAssertFalse(try checks(facts).contains("Engine up to date"), "a prefix Git would not accept proves nothing")
        // The untested-toolchain override lets a newer Metal build: still not « ready ».
        facts.buildBlock = nil
        facts.appleToolsTested = false
        XCTAssertTrue(try checks(facts).contains("Apple tools not the tested version"))
    }

    /// The switches are exactly the offered entries the core gives one, said as the owner's choice in force.
    func testSwitchesComingEntriesAndLinkFacts() throws {
        var facts = Self.mac
        let offered = facts.sections.flatMap(\.entries)
        XCTAssertEqual(offered.filter { $0.switchOn != nil }.map(\.id), offered.map(\.id).filter { $0.hasSwitch })
        // Ryujinx-Nextendo is announced only where it will run, and nxnative keeps Engines filled.
        XCTAssertEqual(facts.sections.map { $0.upcoming?.args }, [["Epic Games · GOG · Minecraft · CrossOver"], nil, nil])
        facts.announcesRyujinx = true
        XCTAssertEqual(facts.sections.map { $0.upcoming?.args }, [["Epic Games · GOG · Minecraft · CrossOver"], ["Ryujinx-Nextendo"], nil])
        // On, but the read failed: the switch says on (what X turns off), Link says what happened.
        facts.steam.enabled = true
        facts.steam.read = .failed
        XCTAssertEqual(facts.row(.steam)?.switchOn, true)
        XCTAssertEqual(said(try detail(.steam, facts), "link"), "Steam could not be refreshed. Your library has been kept.")
        facts.steam.found = false
        XCTAssertEqual(said(try detail(.steam, facts), "link"), "Steam was not found on this computer.")
        facts.steam = SteamFacts()
        XCTAssertEqual(facts.row(.steam)?.switchOn, false)
        XCTAssertEqual(said(try detail(.steam, facts), "link"), "Turn on Steam to add the games it installed.")
        // Nextendo is linked only when signed in.
        for (account, words) in [(IntegrationFacts.Account.noLocalProfile, "Sign in to Nextendo to begin."),
                                 (.unchecked, "Account not checked yet: open the Nextendo settings."),
                                 (.connected, "Linked to your Nextendo account."),
                                 (.unavailable, "Nextendo cannot be reached right now.")] {
            facts.nextendo = account
            XCTAssertEqual(said(try detail(.nextendo, facts), "link"), words)
        }
    }

    func testTheListOpensEachRowAndTurnsOnlyItsSwitches() {
        var facts = Self.mac
        facts.steam.enabled = true
        let list = IntegrationScreen.list(facts)
        XCTAssertEqual(list.focusOrder, ["steam", "macApps", "drive", "switchGames", "nextendo", "saves", "images"])
        XCTAssertEqual(list.initialFocus, "steam")
        XCTAssertEqual(list.gesture(.a, at: "macApps")?.intent, .open("macApps"))
        XCTAssertEqual(list.gesture(.x, at: "steam"), .init(.init("Turn off"), .toggle("steam")))
        XCTAssertNil(list.gesture(.x, at: "macApps"))
        XCTAssertEqual(list.back.intent, .back)
    }

    /// Consent: information online, while off, says what it sends on its row and under its switch, never truncated.
    func testOnlineExplainsWhatItSendsBeforeItIsOnAndAsksBeforeDeleting() throws {
        var facts = IntegrationFacts()
        facts.offers = [.steam, .programs, .online]
        let row = try XCTUnwrap(IntegrationScreen.list(facts).nodes.first { $0.id == "online" })
        XCTAssertEqual(row.about, Screen.Text(IntegrationCatalog.onlineAbout.key, whole: true))
        XCTAssertEqual(try detail(.online, facts).node("link.switch")?.about?.whole, true)
        facts.online = OnlineFacts(on: true, known: 2)
        XCTAssertEqual(IntegrationScreen.list(facts).nodes.first { $0.id == "online" }?.about?.key, IntegrationID.online.capabilities.key)
        let online = try detail(.online, facts)
        XCTAssertEqual(online.node("verify.clear")?.question?.choices.map(\.role), [.cancel, .destructive])
        XCTAssertEqual(online.initialFocus, "link.switch", "never on the question")
        XCTAssertEqual(try detail(.programs, facts).focusOrder, ["link.manage"], "nothing added: its page is in Link")
        facts.programs = 1
        XCTAssertEqual(try detail(.programs, facts).focusOrder, ["next.manage"])
        XCTAssertNil(try detail(.steam, facts).node("link.manage"), "no settings row here")
    }

    // MARK: Frozen scenarios and the reviewed reference tree

    /// Four scenarios, each with a working and an attention tone: Steam off, Steam on with 3 games, Steam not found,
    /// information online off then on with 2 known games. Every entry is offered, with settings rows.
    static var scenarios: [(String, IntegrationFacts)] {
        var base = IntegrationFacts()
        base.offers = Set(IntegrationID.allCases)
        base.settingsRows = true
        base.announcesRyujinx = true
        base.engine = .detected
        base.engineCommit = "f1c7100f"
        base.expectedEngineCommit = "f1c7100f"
        base.keys = .selected
        base.xcodeVersion = "Xcode 27"
        base.metalVersion = "33000.1"
        base.hasSwitchGames = true
        base.programs = 1
        base.drive = .transferring
        base.nextendo = .unavailable
        base.steamGridDB = true
        base.igdb = true
        base.saves = .iCloudDrive
        var steamOff = base, steamOn = base, missing = base, onlineOff = base, onlineOn = base
        steamOff.steam = SteamFacts(enabled: false, found: true, read: .disabled)
        steamOn.steam = SteamFacts(enabled: true, found: true, read: .ready, games: 3)
        missing.steam = SteamFacts(enabled: true, found: false, read: .idle)
        onlineOff.steam = steamOn.steam
        onlineOn.steam = steamOn.steam
        onlineOn.online = OnlineFacts(on: true, known: 2)
        return [("steam-off", steamOff), ("steam-on", steamOn), ("steam-missing", missing), ("online-off", onlineOff), ("online-on", onlineOn)]
    }

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Screens")
    static let french = AppLocale(language: .french, region: "FR")

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value) + Data("\n".utf8)
    }

    /// The file is the reviewed one: a different screen makes this test fail until the file is refreshed on purpose.
    private func assertFrozen<T: Encodable>(_ value: T, _ name: String) throws {
        let url = Self.folder.appendingPathComponent(name)
        let data = try Self.encoded(value)
        if ProcessInfo.processInfo.environment["OORT_WRITE_SCREENS"] == "1" { try data.write(to: url) }
        let frozen = try Data(contentsOf: url)
        XCTAssertTrue(frozen == data, "\(name) is out of date: review the change, then refresh it (OORT_WRITE_SCREENS=1)")
    }

    func testTheScenariosAreFrozen() throws {
        let screens = Dictionary(uniqueKeysWithValues: Self.scenarios.map { ($0.0, IntegrationScreen.all($0.1)) })
        try assertFrozen(screens, "integrations.screens.json")
        let tones = Self.scenarios.map { Set(IntegrationScreen.list($0.1).nodes.compactMap(\.status?.tone)) }
        XCTAssertTrue(tones.allSatisfy { $0.isSuperset(of: [.working, .attention]) }, "each scenario has a working and an attention tone")
    }

    func testTheFrenchReferenceTreeIsTheOneReviewed() throws {
        let trees = Dictionary(uniqueKeysWithValues: Self.scenarios.map { name, facts in
            (name, IntegrationScreen.all(facts).map { ScreenTree($0) { L10n.say($0, context: Self.french) } })
        })
        try assertFrozen(trees, "integrations.fr.tree.json")
    }

    /// Rules read on the reviewed file itself, independent of the code that wrote it.
    func testTheReferenceTreeKeepsTheRules() throws {
        let data = try Data(contentsOf: Self.folder.appendingPathComponent("integrations.fr.tree.json"))
        let trees = try JSONDecoder().decode([String: [ScreenTree]].self, from: data)
        XCTAssertEqual(Set(trees.keys), ["steam-off", "steam-on", "steam-missing", "online-off", "online-on"])
        XCTAssertTrue(trees["online-on"]?.contains { $0.structure.focus.contains { $0.a?.intent == "owner clearOnline" } } == true,
                      "the rule on deleting has a node to hold")
        XCTAssertTrue(Self.violations(trees).isEmpty, Self.violations(trees).joined(separator: "\n"))
    }

    /// Each break of a rule, said; empty when the trees keep them all.
    static func violations(_ trees: [String: [ScreenTree]]) -> [String] {
        let sends = L10n.say(IntegrationCatalog.onlineAbout.screen, context: french)
        let delete = ScreenTree.intent(.owner(IntegrationTarget.clearOnline.rawValue))
        let online = L10n.say(IntegrationID.online.title.screen, context: french)
        var problems: [String] = []
        for (scenario, screens) in trees.sorted(by: { $0.key < $1.key }) {
            for tree in screens {
                let at = "\(scenario) \(tree.screen)"
                let s = tree.structure
                // Every status has its dot.
                let dots = s.pieces.filter { $0.piece == .dot }.compactMap(\.text)
                for status in s.texts where status.role == .status && !dots.contains(status.text) {
                    problems.append("\(at): « \(status.text) » without its dot")
                }
                if s.pieces.contains(where: { $0.piece == .dot && $0.tone == nil }) { problems.append("\(at): a dot without tone") }
                // The bar is B on the left, then X and A.
                for bar in tree.hints {
                    if bar.left.map({ $0.prefix(2) }) != ["b "] { problems.append("\(at): the bar's left is not B") }
                    let keys = bar.right.map { String($0.prefix(1)) }
                    if keys != keys.filter({ $0 == "x" }) + keys.filter({ $0 == "a" }) || keys.count > 2 { problems.append("\(at): the bar's right is not X then A") }
                }
                if tree.hints.count != s.focus.count { problems.append("\(at): a bar per focus") }
                guard s.focus.allSatisfy({ s.pieces.indices.contains($0.piece) }), s.initialFocus.map(s.focus.indices.contains) ?? true else {
                    problems.append("\(at): a focus on no piece")
                    continue
                }
                // Information online, off, says what it sends: on its row, and under its switch in its detail.
                if scenario == "online-off", tree.screen.hasSuffix("integrations") || tree.screen.hasSuffix(".online") {
                    let row = s.pieces.first { $0.piece == .row && $0.text == online }
                    if row?.about != sends { problems.append("\(at): off, information online does not say what it sends") }
                    if !s.texts.contains(where: { $0.text == sends && $0.whole == true }) { problems.append("\(at): what it sends may be truncated") }
                    if s.texts.contains(where: { $0.text == sends && $0.role != .body }) { problems.append("\(at): what it sends is not read as body text") }
                }
                // Deleting what was found online asks a question first: Cancel, with the focus, then the destructive choice.
                for focus in s.focus where focus.a?.intent == delete {
                    if focus.question == nil || s.pieces[focus.piece].destructive != true { problems.append("\(at): Delete asks no question") }
                    if focus.question?.dropFirst(2).first?.hasPrefix("cancel ") != true || focus.questionFocus != 0 {
                        problems.append("\(at): the question does not start on Cancel")
                    }
                }
                // The initial focus is never on a node that asks a question.
                if let initial = s.initialFocus, s.focus[initial].question != nil { problems.append("\(at): the initial focus asks a question") }
            }
        }
        return problems
    }

    /// Every word of every scenario's screens is a key of the catalog in its seven languages.
    func testEveryWordOfTheScreensIsInTheCatalog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Sources/NXLibraryCore/Resources/Localizable.xcstrings"))) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        func keys(_ text: Screen.Text?) -> [String] { text.map { [$0.key] + $0.words.flatMap(keys) } ?? [] }
        func keys(_ gesture: Screen.Gesture?) -> [String] { keys(gesture?.title) }
        var all = Set<String>()
        for (_, facts) in Self.scenarios {
            for screen in IntegrationScreen.all(facts) {
                all.formUnion(keys(screen.title) + keys(screen.lead) + keys(screen.back))
                for node in screen.nodes {
                    all.formUnion([node.title, node.about, node.status?.text, node.text, node.note].flatMap(keys) + (node.texts ?? []).flatMap(keys))
                    all.formUnion(keys(node.a) + keys(node.x) + keys(node.question?.title) + keys(node.question?.message)
                                  + (node.question?.choices ?? []).flatMap { keys($0.title) })
                }
            }
        }
        all.remove("%@")
        for key in all.sorted() {
            let languages = ((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?.keys.sorted() ?? []
            XCTAssertEqual(languages, ["de", "en", "es", "fr", "it", "pt-BR", "zh-Hans"], key)
        }
    }

    /// Red examples: each rule refuses a tree that breaks it.
    func testEachRuleRefusesATreeThatBreaksIt() throws {
        let data = try Data(contentsOf: Self.folder.appendingPathComponent("integrations.fr.tree.json"))
        let trees = try JSONDecoder().decode([String: [ScreenTree]].self, from: data)
        func broken(_ scenario: String, _ screen: Int, _ change: (inout ScreenTree) -> Void) -> [String] {
            var copy = trees
            change(&copy[scenario]![screen])
            return Self.violations(copy)
        }
        let list = 0
        let onlineDetail = try XCTUnwrap(trees["online-on"]?.firstIndex { $0.screen == "integrations.online" })
        XCTAssertFalse(broken("steam-on", list) { $0.structure.pieces.removeAll { $0.piece == .dot } }.isEmpty, "a status without its dot")
        XCTAssertFalse(broken("steam-on", list) { $0.hints[0] = .init(left: ["a Ouvrir"], right: ["b Retour"]) }.isEmpty, "the bar out of order")
        XCTAssertFalse(broken("steam-on", list) { tree in
            tree.hints[0] = .init(left: tree.hints[0].left, right: tree.hints[0].right.reversed())
        }.isEmpty, "A before X")
        XCTAssertFalse(broken("online-off", list) { tree in
            for index in tree.structure.pieces.indices where tree.structure.pieces[index].about?.hasPrefix("Oort") == true {
                tree.structure.pieces[index].about = "Jaquettes"
            }
        }.isEmpty, "online off without what it sends")
        XCTAssertFalse(broken("online-off", list) { tree in
            for index in tree.structure.texts.indices where tree.structure.texts[index].whole == true {
                tree.structure.texts[index] = .init(.about, tree.structure.texts[index].text, whole: true)
            }
        }.isEmpty, "what it sends, discreet")
        XCTAssertFalse(broken("online-on", onlineDetail) { tree in
            for index in tree.structure.focus.indices { tree.structure.focus[index].question = nil }
        }.isEmpty, "Delete without its question")
        XCTAssertFalse(broken("online-on", onlineDetail) { tree in
            tree.structure.initialFocus = tree.structure.focus.firstIndex { $0.question != nil }
        }.isEmpty, "the initial focus on the question")
    }
}
