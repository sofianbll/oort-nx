import XCTest
@testable import OortLibrary

final class PaletteActionTests: XCTestCase {
    func testEverySectionHoldsFiveAtMostAndThereAreFive() {
        let sections = Dictionary(grouping: PaletteAction.allCases, by: \.section)
        XCTAssertEqual(sections.count, 5)
        for (section, actions) in sections { XCTAssertLessThanOrEqual(actions.count, 5, "\(section)") }
    }

    func testSectionsAreDeclaredTogether() {
        var order: [PaletteAction.Section] = []
        for action in PaletteAction.allCases where order.last != action.section { order.append(action.section) }
        XCTAssertEqual(order, PaletteAction.Section.allCases)
    }

    func testNoShortcutOpensTwoThings() {
        let shortcuts = PaletteAction.allCases.compactMap(\.shortcut) + [PaletteAction.paletteShortcut]
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
    }

    func testWhatEndsTheSessionIsNeverOfferedFirst() {
        for action in [PaletteAction.sleep, .hide, .relaunch, .quit] {
            XCTAssertFalse(action.item().isRemembered, "\(action)")
            XCTAssertFalse(PaletteAction.suggested.contains(action), "\(action)")
        }
        XCTAssertTrue(PaletteAction.theme.item().isRemembered)
    }

    func testEveryMenuEntryAndPowerChoiceIsInThePalette() {
        let titles = Set(PaletteAction.allCases.map(\.title))
        for entry in MenuEntry.allCases { XCTAssertTrue(titles.contains(entry.title), entry.title) }
        for power in PowerAction.allCases { XCTAssertTrue(titles.contains(power.title), power.title) }
    }

    func testTheEnglishNameFindsAnActionInFrench() {
        let french = AppLocale(language: .french, region: "FR")
        let items = PaletteAction.allCases.map { $0.item(in: french) }
        XCTAssertEqual(Palette.groups(query: "sleep", in: items).first?.items.first?.title, "Mettre le Mac en veille")
        XCTAssertEqual(Palette.groups(query: "veile", in: items).first?.items.first?.title, "Mettre le Mac en veille")
        XCTAssertEqual(Palette.groups(query: "theme", in: items).first?.items.first?.title, "Thème")
        XCTAssertEqual(Palette.groups(query: "aide", in: items).first?.items.isEmpty, false)
    }

    func testEveryTitleAndSectionIsTranslated() {
        for language in AppLanguage.allCases where language != .english {
            let context = AppLocale(language: language, region: "FR")
            for key in PaletteAction.Section.allCases.map(\.key) + PaletteAction.allCases.map(\.key) {
                XCTAssertFalse(L10n.text(key, context: context).isEmpty, key)
            }
        }
    }

    func testRecentsFollowTheProfileAndForgetUnknownOnes() throws {
        let suite = "palette-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID()
        let store = PaletteRecentsStore(defaults: defaults)
        store.save(["game:a"], for: first, known: [first, second])
        store.save(["action:theme"], for: second, known: [first, second])
        XCTAssertEqual(store.load(for: first), ["game:a"])
        XCTAssertEqual(store.load(for: second), ["action:theme"])
        store.save(["game:b"], for: second, known: [second])
        XCTAssertEqual(store.load(for: first), [])
        XCTAssertEqual(store.load(for: UUID()), [])
    }

    func testDamagedRecentsAreEmpty() throws {
        let suite = "palette-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["x": 3], forKey: PaletteRecentsStore.key)
        XCTAssertEqual(PaletteRecentsStore(defaults: defaults).load(for: UUID()), [])
    }
}
