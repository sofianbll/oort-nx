import XCTest
@testable import OortLibrary

/// Steam's rows on the Mac, decided once: what Settings › Sources, the overview of integrations and the first launch
/// showed before they shared this decision, kept word for word, and the switch rule every app shares.
final class IntegrationEntryTests: XCTestCase {
    private static let every: [CatalogSourceStatus] = [.disabled, .idle, .scanning, .ready, .partial, .cancelled, .failed]

    private func mac(applied: Bool = true, staged: Bool? = nil, _ status: CatalogSourceStatus = .ready, found: Int = 3) -> [IntegrationEntry] {
        SteamSourceEntries.mac(applied: applied, staged: staged, status: status, found: found, root: "/Users/p/Library/Application Support/Steam").all
    }

    /// The words SettingsSourcesSection drew before (its `statusText`, its rows, its buttons), state by state.
    func testSettingsRowsKeepTheirWordsAndIdentityInEveryState() {
        let state: [CatalogSourceStatus: IntegrationWords] = [
            .disabled: .init("Enable Steam to find its installed Mac games."), .idle: .init("Ready to check Steam."),
            .scanning: .init("Checking Steam libraries…"), .ready: .init("%lld Steam installations found", count: 3),
            .partial: .init("Some installations could not be checked. Your library has been kept."),
            .cancelled: .init("Scan stopped. Refresh when you are ready."),
            .failed: .init("Steam could not be refreshed. Your library has been kept."),
        ]
        for status in Self.every {
            let rows = mac(status)
            XCTAssertEqual(rows.map(\.id), ["steamSource", "steamRefresh", "steamFolder"], "\(status)")
            XCTAssertEqual(rows[0].id, SteamSourceEntries.sourceID, "same destination for the row, draft and overview")
            XCTAssertEqual(rows.map(\.rowID), ["Steam", "Refresh Steam", "Steam folder"], "\(status)")
            XCTAssertEqual(rows[0].about, .init("Find installed native Mac games in your Steam libraries."))
            XCTAssertEqual(rows[0].info, .init("Your Steam files stay where they are. Disabling this source keeps its games and personal choices."))
            XCTAssertEqual(rows[0].icon, "Steam")
            XCTAssertEqual(rows[1].about, state[status], "\(status)")
            XCTAssertEqual(rows[1].control, .button(.init(status == .scanning ? "Cancel" : "Refresh")), "\(status)")
            XCTAssertEqual(rows[2].about, .init("Choose the Steam folder containing steamapps."))
            XCTAssertEqual(rows[2].control, .value("/Users/p/Library/Application Support/Steam", button: .init("Change")))
            XCTAssertEqual(rows[2].request, .chooseSteamFolder)
        }
    }

    /// The catalogue's Steam switch asks for the other state of the source in force, same folder, replacing its
    /// generation: a choice made elsewhere since is refused by the repository, never overwritten.
    func testTheCatalogueSwitchAsksForTheOtherStateOfTheSourceInForce() {
        let root = URL(fileURLWithPath: "/fixture/Steam")
        let on = CatalogSourceConfiguration(integration: .steam, isEnabled: true, rootURL: root)
        let off = SteamSourceEntries.flipped(on, root: root)
        XCTAssertFalse(off.enabled)
        XCTAssertEqual(off.root, root)
        XCTAssertEqual(off.replaces, on.generation)
        XCTAssertNotEqual(off.generation, on.generation)
        XCTAssertTrue(SteamSourceEntries.flipped(.init(integration: .steam), root: root).enabled)
    }

    /// `isEnabled: sources.configuration.isEnabled || sources.status == .failed`, and Cancel while it reads.
    func testRefreshNeedsTheSourceInForceUnlessItFailed() {
        for status in Self.every {
            XCTAssertEqual(mac(applied: true, status)[1].request, status == .scanning ? .cancelSteamRefresh : .refreshSteam, "\(status)")
            XCTAssertEqual(mac(applied: false, status)[1].request, status == .failed ? .refreshSteam : nil, "\(status)")
        }
        // A choice waiting in the draft does not refresh what is not in force yet.
        XCTAssertNil(mac(applied: false, staged: true, .disabled)[1].request)
    }

    /// The choice waiting shows over the one in force; A asks for the other state, whatever the app.
    func testTheSwitchShowsTheWaitingChoiceAndAsksForTheOther() {
        for (inForce, waiting, shown) in [(false, nil, false), (true, nil, true), (false, true, true), (true, false, false)] as [(Bool, Bool?, Bool)] {
            for entry in [mac(applied: inForce, staged: waiting)[0],
                          SteamSourceEntries.found(.init(steamGameCount: 2, portedAppCount: 0), inForce: inForce, waiting: waiting)!,
                          SteamSourceEntries.sourceSwitch(id: "steam", inForce: inForce, waiting: waiting)] {
                XCTAssertEqual(entry.control, .toggle(checked: shown), entry.id)
                XCTAssertEqual(entry.request, .steam(enabled: !shown), "A asks for the other state: \(entry.id)")
            }
        }
        let off = SteamSourceEntries.sourceSwitch(id: "steam", inForce: false), on = SteamSourceEntries.sourceSwitch(id: "steam", inForce: true)
        XCTAssertNotEqual(off, on, "two states with opposite gestures are never drawn the same")
        XCTAssertEqual([off.checked, on.checked], [false, true])
    }

    /// While Steam is read the focused row keeps its slot: SettingsView keeps the focus on the same action identity.
    func testTheFocusedRowKeepsItsSlotWhileSteamIsRead() {
        var asked: [IntegrationRequest] = []
        func slots(_ status: CatalogSourceStatus) -> [SettingsRowAction] {
            SettingsRowAction.primaryActions(mac(status).map { SettingsRowAction($0) { asked.append($0.request!) } })
        }
        let before = slots(.idle), during = slots(.scanning), after = slots(.ready)
        for list in [during, after] {
            XCTAssertEqual(list.map(\.id), before.map(\.id))
            XCTAssertEqual(list.map(\.rowID), before.map(\.rowID))
            XCTAssertEqual(list.firstIndex { $0.id == "steamRefresh" }, 1)
            XCTAssertTrue(list[1].isEnabled)
        }
        before[1].activate(); during[1].activate(); after[1].activate()
        XCTAssertEqual(asked, [.refreshSteam, .cancelSteamRefresh, .refreshSteam])
        // Refused, it still has its slot; A does nothing.
        let refused = SettingsRowAction.primaryActions(mac(applied: false, .idle).map { SettingsRowAction($0) { asked.append($0.request!) } })
        XCTAssertEqual(refused.map(\.id), before.map(\.id))
        XCTAssertFalse(refused[1].isEnabled)
        refused[1].activate()
        XCTAssertEqual(asked.count, 3)
    }

    /// One state, said in Settings › Sources and in the overview of integrations: what IntegrationOverview said before.
    func testEachStateSaysTheSameInSettingsAndInTheOverview() {
        let overview: [(CatalogSourceStatus, Int, String, IntegrationEmphasis)] = [
            (.disabled, 3, "Steam source off", .neutral), (.idle, 3, "Steam not scanned yet", .neutral),
            (.scanning, 3, "Reading Steam libraries…", .working), (.ready, 0, "No games found", .neutral),
            (.ready, 3, "Steam library scanned", .neutral), (.partial, 3, "Steam scan incomplete", .attention),
            (.cancelled, 3, "Steam scan cancelled", .attention), (.failed, 3, "Steam scan failed", .attention),
        ]
        for (status, found, summary, emphasis) in overview {
            let state = SteamSourceEntries.state(status, found: found)
            XCTAssertEqual(state.summary, .init(summary), "\(status) \(found)")
            XCTAssertNil(state.summary.count, "the overview's status is a plain key")
            XCTAssertEqual(state.emphasis, emphasis, "\(status)")
            XCTAssertEqual(mac(status, found: found)[1].about, state.detail, "Settings shows the same state: \(status)")
        }
    }

    /// The first launch's `found` page: the switch when Steam was read, Retry when it was not read in full, else nothing.
    func testTheFirstLaunchShowsTheSwitchRetryOrNothing() throws {
        let read = try XCTUnwrap(SteamSourceEntries.found(.init(steamGameCount: 4, portedAppCount: 1), inForce: false, waiting: nil))
        XCTAssertEqual([read.id, read.title.key, read.icon], ["steamToggle", "Steam", "Steam"])
        XCTAssertEqual(read.about, .init("%lld installed Mac games", count: 4))
        XCTAssertEqual(read.control, .toggle(checked: false))
        XCTAssertEqual(read.request, .steam(enabled: true))
        let failed = try XCTUnwrap(SteamSourceEntries.found(.init(steamGameCount: nil, portedAppCount: 0, steamReadFailed: true), inForce: true, waiting: false))
        XCTAssertEqual(failed.about, .init("Steam couldn't be read completely. Try again or continue and check Settings → Sources later."))
        XCTAssertEqual(failed.control, .button(.init("Retry")))
        XCTAssertEqual(failed.request, .readSteamAgain, "Retry reads again and never chooses")
        XCTAssertNil(SteamSourceEntries.found(.init(steamGameCount: nil, portedAppCount: 3), inForce: true, waiting: true), "no Steam, no row")
        XCTAssertNil(SteamSourceEntries.found(nil, inForce: true, waiting: nil), "still reading, no row")
    }

    /// Search and Changed list Steam's rows as SettingsCatalog listed them before, word for word, in the same place.
    func testSearchListsSteamsRowsAsTheyAreDrawn() throws {
        let before: [(String, String, String)] = [
            ("steamSource", "Steam", "Find installed native Mac games in your Steam libraries."),
            ("steamRefresh", "Refresh Steam", "Check enabled Steam libraries without changing your game files."),
            ("steamFolder", "Steam folder", "Choose the Steam folder containing steamapps."),
        ]
        let rows = SteamSourceEntries.searchRows
        XCTAssertEqual(rows.map(\.id), before.map(\.0))
        XCTAssertEqual(rows.map(\.title), before.map(\.1))
        XCTAssertEqual(rows.map(\.about), before.map(\.2))
        XCTAssertEqual(Set(rows.map(\.group)), [.sources])
        XCTAssertNil(rows.compactMap(\.copy).first, "actions copy nothing")
        // Drawn with the same identity and title in every state.
        for status in Self.every { XCTAssertEqual(mac(status).map(\.id), rows.map(\.id)); XCTAssertEqual(mac(status).map(\.title.key), rows.map(\.title)) }
        let ids = SettingsCatalog.baseRows.map(\.id)
        let at = try XCTUnwrap(ids.firstIndex(of: "steamSource"))
        XCTAssertEqual(Array(ids.dropFirst(max(0, at - 2)).prefix(6)), ["integrations", "macShortcutAdd", "steamSource", "steamRefresh", "steamFolder", "steamInBackground"])
        XCTAssertEqual(SettingsCatalog.search("steamapps", in: SettingsCatalog.baseRows).map(\.id), ["steamFolder"])
        // A Steam choice waiting in the draft marks the switch and the folder (SettingsView.pendingRows).
        XCTAssertEqual(SteamSourceEntries.draftRows, ["Steam", "Steam folder"])
    }

    /// The tour's optional services, as OnboardingView said them: words, order, set up or later, and where A goes.
    func testTheTourSaysEachServiceAsBefore() {
        let before: [(String, String, String, MaterialIcon, SettingsSection, String?)] = [
            ("drive", "Google Drive", "Connect your cloud library.", .cloud, .cloudLibrary, nil),
            ("nextendo", "Nextendo", "Connect an account for online play.", .gamepad, .profileNextendo, nil),
            ("steam", "Steam", "Read your installed Mac games from Steam.", .store, .sources, "Steam"),
            ("saves", "Save copies", "Choose if and where to sync ported-game saves.", .sync, .cloudSaves, nil),
        ]
        for set in 0..<16 {
            let on = (0..<4).map { set & (1 << $0) != 0 }
            let services = OptionalServiceEntries.all(driveConnected: on[0], nextendoSignedIn: on[1], steamInForce: on[2], savesOn: on[3])
            XCTAssertEqual(services.count, 4)
            for (index, (service, old)) in zip(services, before).enumerated() {
                XCTAssertEqual(service.id, old.0)
                XCTAssertEqual(service.title, .init(old.1))
                XCTAssertEqual(service.about, .init(old.2))
                XCTAssertEqual(service.icon, old.3)
                XCTAssertEqual(service.value, .init(on[index] ? "Enabled" : "Later"), "\(old.0) \(on[index])")
                XCTAssertEqual(service.section, old.4)
                XCTAssertEqual(service.row, old.5, "the tour opened Sources on Steam's switch (AppShellView)")
            }
        }
        // Sources opens on the switch Settings draws, in every state.
        for status in Self.every { XCTAssertEqual(SteamSourceEntries.sourceRowID, mac(applied: false, status).first?.rowID) }
    }

    /// Every word the Mac rows use is a key of the catalog in its seven languages.
    func testEveryMacWordIsInTheCatalog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Sources/NXLibraryCore/Resources/Localizable.xcstrings"))) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        var entries: [IntegrationEntry] = [true, false].compactMap {
            SteamSourceEntries.found(.init(steamGameCount: $0 ? 2 : nil, portedAppCount: 0, steamReadFailed: !$0), inForce: true, waiting: nil)
        }
        var keys = Set<String>()
        for status in Self.every {
            entries += mac(status)
            keys.formUnion([0, 3].map { SteamSourceEntries.state(status, found: $0).summary.key })
        }
        keys.formUnion([false, true].flatMap { OptionalServiceEntries.all(driveConnected: $0, nextendoSignedIn: $0, steamInForce: $0, savesOn: $0) }
            .flatMap { [$0.title.key, $0.about.key, $0.value.key] })
        keys.formUnion(SteamSourceEntries.searchRows.flatMap { [$0.title, $0.about] })
        for entry in entries {
            keys.formUnion([entry.title, entry.about, entry.info, entry.value].compactMap { $0?.key } + entry.help.map(\.key))
            switch entry.control {
            case .button(let words), .value(_, let words): keys.insert(words.key)
            case .toggle, .row, .open: break
            }
        }
        for key in keys.sorted() {
            let languages = ((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?.keys.sorted() ?? []
            XCTAssertEqual(languages, ["de", "en", "es", "fr", "it", "pt-BR", "zh-Hans"], key)
        }
    }
}
