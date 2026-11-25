// The app on a simulator, with invented games only: every screen is opened, pictured and audited.
// OORT_OUT (a folder), OORT_LANG (fr or en) and OORT_STILL come from scripts/test_app.sh.
import XCTest

final class OortUITests: XCTestCase {
    private static let env = ProcessInfo.processInfo.environment
    private static let lang = env["OORT_LANG"] ?? "fr"
    private static let out = URL(fileURLWithPath: env["OORT_OUT"] ?? NSTemporaryDirectory())
    private static let bundle = Bundle(for: OortUITests.self)
    private static let marker = "oort_invented_marker"
    private let app = XCUIApplication()
    private var pad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }

    // MARK: Helpers

    /// The app's words in the language under test.
    private func say(_ key: String) -> String {
        let words = Self.bundle.path(forResource: Self.lang, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Self.bundle
        return words.localizedString(forKey: key, value: key, table: nil)
    }

    /// The app's own folder: the simulator's apps sit side by side. The first start makes it.
    private func home() throws -> URL {
        if let found = folder() { return found }
        app.launch()
        app.terminate()
        if let found = folder() { return found }
        let all = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        let seen = (try? FileManager.default.subpathsOfDirectory(atPath: all.path).prefix(60).joined(separator: "\n")) ?? "unreadable"
        throw NoFolder(seen: NSHomeDirectory() + "\n" + seen)
    }
    private struct NoFolder: Error { let seen: String }

    private func folder() -> URL? {
        let all = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        return (try? FileManager.default.contentsOfDirectory(at: all, includingPropertiesForKeys: nil))?.first { one in
            let data = try? Data(contentsOf: one.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist"))
            let plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
            // The app writes its version line at each start.
            return plist?["MCMMetadataIdentifier"] as? String == "io.github.sofianbll.oortnx.mobile"
                || FileManager.default.fileExists(atPath: one.appendingPathComponent("Documents/shell-log.txt").path)
        }
    }

    private enum Games { case none, invented }

    private func start(_ games: Games, _ more: [String] = [], prepare: (URL) throws -> Void = { _ in }) throws {
        app.terminate()
        let fm = FileManager.default, data = try home(), documents = data.appendingPathComponent("Documents")
        try? fm.createDirectory(at: documents, withIntermediateDirectories: true)
        for one in try fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) { try fm.removeItem(at: one) }
        if games == .invented {
            try CaptureGames.make(in: data, frameworks: "Documents/Frameworks", marker: Self.marker)
            // One game has code for the simulator; the others' code cannot be loaded.
            let code = try XCTUnwrap(Self.bundle.privateFrameworksURL).appendingPathComponent("DmGame.framework/DmGame")
            let target = documents.appendingPathComponent("Frameworks/DmGame\(CaptureGames.all[0].id).framework/DmGame")
            try fm.removeItem(at: target)
            try fm.copyItem(at: code, to: target)
        }
        try prepare(documents)
        app.launchArguments = ["-AppleLanguages", "(\(Self.lang))", "-AppleLocale", Self.lang == "fr" ? "fr_FR" : "en_US"] + more
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60))
    }

    private var picture = 0
    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.9)
        let file = "\(Self.lang)-\(pad ? "ipad" : "iphone")-\(name).png"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: Self.out.appendingPathComponent(file))
    }

    private func note(_ text: String, in file: String) {
        let url = Self.out.appendingPathComponent(file)
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + text + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Everything the system's audit finds, written down. What Oort NX answers for fails the test.
    private func audit(_ screen: String) throws {
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            let frame = element.map { "\($0.frame)" } ?? "-"
            self.note("\(Self.lang)-\(self.pad ? "ipad" : "iphone") \(screen) | \(issue.auditType.rawValue) \(issue.compactDescription) | \(element?.label.prefix(60) ?? "-") | \(frame)", in: "audit.txt")
            return true
        }
    }

    private func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }

    private func tap(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 15) else {
            note("\(name) missing \(what)\n\(app.debugDescription)", in: "missing.txt")
            return XCTFail("\(what) is not on the screen", file: file, line: line)
        }
        for _ in 0..<8 where !element.isHittable { app.swipeUp(velocity: .slow) }
        element.tap()
    }

    private func tab(_ key: String) {
        let label = say(key)
        let bar = app.tabBars.buttons[label].firstMatch
        tap(bar.waitForExistence(timeout: 5) ? bar : button(label), "the tab \(label)")
    }

    private func back() {
        let bar = app.navigationBars.buttons.element(boundBy: 0)
        tap(bar, "Back")
    }

    private func shows(_ key: String, _ seconds: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let text = say(key)
        let found = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        if !found.waitForExistence(timeout: seconds) {
            note("\(name) no text \(text)\n\(app.debugDescription)", in: "missing.txt")
            XCTFail("“\(text)” is not shown", file: file, line: line)
        }
    }

    // MARK: Tests

    func test01EmptyLibrary() throws {
        try start(.none)
        XCTAssertEqual(UIAccessibility.isReduceMotionEnabled, Self.env["OORT_STILL"] == "still", "Reduce Motion is as asked")
        shows("No game here yet")
        shot("01-empty-home")
        try audit("empty-home")
        tab("Library")
        shows("No game here yet")
        shot("02-empty-library")
        try audit("empty-library")
    }

    func test02Tour() throws {
        try start(.invented)
        let first = app.staticTexts[CaptureGames.all.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }[0]].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), "the games are listed")
        shot("10-home")
        try audit("home")
        if !pad {
            let before = app.staticTexts.allElementsBoundByIndex.map(\.label)
            app.swipeLeft()
            shot("11-home-swiped")
            XCTAssertNotEqual(before, app.staticTexts.allElementsBoundByIndex.map(\.label), "the carousel changes the game")
            app.swipeRight()
            Thread.sleep(forTimeInterval: 1)
        }
        tap(button(say("Game page")), "the game page")
        shows("Game data")
        shot("12-game")
        try audit("game")
        app.swipeUp()
        shot("13-game-more")
        app.swipeDown(velocity: .fast)
        back()
        tap(button(say("Options")), "Options")
        shot("14-options")
        try audit("options")
        back()
        tab("Library")
        shot("15-library")
        try audit("library")
        tap(button(say("Sort")), "Sort")
        shot("16-sort")
        tap(button(say("Name")), "by name")
        shot("17-library-by-name")
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) { app.swipeDown() }
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("zzz")
            shot("18-search-none")
        } else { XCTFail("no search field") }
        tap(button(say("Sort")).exists ? button(say("Sort")) : app.buttons.firstMatch, "leaving the search")
    }

    func test03ControllersAndSettings() throws {
        try start(.invented)
        tab("Controllers")
        shows("No controller connected")
        shot("20-controllers")
        try audit("controllers")
        tap(button(say("What each button sends")), "the buttons")
        shot("21-mapping")
        try audit("mapping")
        back()
        tab("Settings")
        shows("Data and saves")
        shot("22-settings")
        try audit("settings")
        let sounds = app.switches[say("Sounds")].firstMatch
        for _ in 0..<6 where !(sounds.exists && sounds.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(sounds.exists, "the sounds switch")
        let was = sounds.value as? String
        sounds.tap()
        XCTAssertNotEqual(was, sounds.value as? String, "the switch changes")
        sounds.tap()
        for _ in 0..<4 { app.swipeUp() }
        shows("0.1.0-alpha.1")
        shot("23-settings-end")
        try audit("settings-end")
        tap(button(say("Thanks and licences")), "the credits")
        shows("NX2Apple")
        shows("Selene")
        shot("24-credits")
        try audit("credits")
        tap(button(say("Every notice, in full")), "the notices")
        shows("Permission is hereby granted")
        shot("25-notices")
        try audit("notices")
    }

    func test04Landscape() throws {
        try start(.invented)
        XCTAssertTrue(button(say("Options")).waitForExistence(timeout: 20))
        XCUIDevice.shared.orientation = .landscapeLeft
        shot("30-home-landscape")
        try audit("home-landscape")
        tap(button(say("Game page")), "the game page")
        shot("31-game-landscape")
        try audit("game-landscape")
        back()
        tap(button(say("Options")), "Options")
        shot("32-options-landscape")
        back()
        tab("Library")
        shot("33-library-landscape")
        tab("Controllers")
        shot("34-controllers-landscape")
        tab("Settings")
        shot("35-settings-landscape")
        XCUIDevice.shared.orientation = .landscapeRight
        shot("36-settings-landscape-right")
    }

    func test05LargestText() throws {
        try start(.invented, ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", say("Options"))).firstMatch.waitForExistence(timeout: 20))
        shot("40-home-large")
        app.swipeUp()
        shot("41-home-large-end")
        try audit("home-large")
        tap(button(say("Game page")), "the game page")
        shot("42-game-large")
        app.swipeUp()
        shot("43-game-large-more")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        back()
        tap(button(say("Options")), "Options")
        shot("44-options-large")
        tab("Library")
        shot("45-library-large")
        tab("Controllers")
        shot("46-controllers-large")
        tab("Settings")
        shot("47-settings-large")
        try audit("settings-large")
        XCUIDevice.shared.orientation = .landscapeLeft
        tab("Home")
        shot("48-home-large-landscape")
        try start(.none, ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCUIDevice.shared.orientation = .portrait
        shot("49-empty-large")
    }

    func test06AGameStartsAndComesBack() throws {
        try start(.invented)
        let name = CaptureGames.all[0].name
        tab("Library")
        tap(app.buttons[name].firstMatch, name)
        tap(button(say("Play")), "Play")
        let game = app.staticTexts["Invented game main, save ready"]
        XCTAssertTrue(game.waitForExistence(timeout: 30), "the invented game runs")
        shot("50-invented-game")
        tap(button("Quit the invented game"), "Quit")
        XCTAssertTrue(button(say("Play")).waitForExistence(timeout: 20), "the library is back")
        shot("51-back-in-library")
        tap(button(say("Play")), "Play again")
        XCTAssertTrue(game.waitForExistence(timeout: 30), "it starts a second time")
        tap(button("Quit the invented game"), "Quit")
        XCTAssertTrue(button(say("Play")).waitForExistence(timeout: 20))
    }

    func test07CodeThatCannotBeLoadedIsSaid() throws {
        try start(.invented)
        let name = CaptureGames.all[1].name
        tab("Library")
        tap(app.buttons[name].firstMatch, name)
        tap(button(say("Play")), "Play")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 30), "the refusal is said")
        note("refused start: \(alert.staticTexts.allElementsBoundByIndex.map(\.label))", in: "words.txt")
        shot("52-code-refused")
        alert.buttons[say("OK")].tap()
        XCTAssertTrue(button(say("Play")).waitForExistence(timeout: 10))
    }

    func test08AFolderThatIsNoGameIsRefused() throws {
        try start(.none) { documents in
            let folder = documents.appendingPathComponent("Not a game.framework")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("nothing".utf8).write(to: folder.appendingPathComponent("readme.txt"))
        }
        tap(button(say("Add a game")), "Add a game")
        Thread.sleep(forTimeInterval: 4)
        shot("53-picker")
        note(app.debugDescription, in: "picker.txt")
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Not a game'")).firstMatch
        if !target.waitForExistence(timeout: 5) {
            let browse = app.buttons.matching(NSPredicate(format: "label IN {'Browse', 'Explorer', 'Parcourir'}")).firstMatch
            if browse.waitForExistence(timeout: 5) { browse.tap(); if browse.exists, browse.isHittable { browse.tap() } }
            let device = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'On My' OR label BEGINSWITH 'Sur mon'")).firstMatch
            if device.waitForExistence(timeout: 5), device.isHittable { device.tap() }
            let folder = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Oort NX'")).firstMatch
            if folder.waitForExistence(timeout: 5), folder.isHittable { folder.tap() }
        }
        Thread.sleep(forTimeInterval: 2)
        shot("54-picker-folder")
        note(app.debugDescription, in: "picker.txt")
        guard target.waitForExistence(timeout: 10) else { return XCTFail("the folder is not in the picker") }
        target.tap()
        let open = app.buttons.matching(NSPredicate(format: "label IN {'Open', 'Ouvrir'}")).firstMatch
        if open.waitForExistence(timeout: 5), open.isEnabled, open.isHittable { open.tap() }
        shows("This is not a game built for Oort NX. Pick a folder that ends in .framework.")
        shot("55-import-refused")
        app.alerts.firstMatch.buttons[say("OK")].tap()
        shows("No game here yet")
    }

    func test09ADamagedGameSaysWhy() throws {
        try start(.invented) { documents in
            let manifest = documents.appendingPathComponent("Frameworks/DmGame\(CaptureGames.all[2].id).framework/game.manifest.json")
            try Data("{\"schema\": 99}".utf8).write(to: manifest)
        }
        tab("Library")
        shot("56-library-damaged")
        tab("Home")
        shot("57-home-damaged")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
