// A whole trial of the app on a simulator, step by step: each step keeps one picture and the screen's accessibility tree.
// Run by scripts/test_app.sh with "OortTrialTests" or one test's name. Invented games only; Fake pad and cut network are
// test libraries inserted into the app on the simulator, never shipped.
import XCTest

final class OortTrialTests: OortCase {
    private let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    private var first: String { CaptureGames.all[0].name }
    private var second: String { CaptureGames.all[1].name }

    // MARK: Helpers

    /// One step: its picture, what a screen reader gets, and every control that has nothing to say.
    private func step(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: Self.out.appendingPathComponent(name + ".png"))
        let trees = Self.out.appendingPathComponent("a11y")
        try? FileManager.default.createDirectory(at: trees, withIntermediateDirectories: true)
        try? app.debugDescription.write(to: trees.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        guard let root = try? app.snapshot() else { return note("\(name): no accessibility snapshot", in: "a11y-findings.txt") }
        var queue: [XCUIElementSnapshot] = [root]
        while let one = queue.popLast() {
            queue += one.children
            guard [.button, .switch, .slider, .textField, .searchField].contains(one.elementType), one.frame.width > 1 else { continue }
            let said = one.label + (one.value as? String ?? "") + (one.placeholderValue ?? "") + one.children.map(\.label).joined()
            if said.isEmpty { note("\(name) | \(one.elementType.rawValue) says nothing | \(one.identifier) | \(one.frame)", in: "a11y-findings.txt") }
        }
    }

    private func appears(_ element: XCUIElement, _ what: String, _ seconds: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForExistence(timeout: seconds) {
            note("\(name) missing \(what)\n\(app.debugDescription)", in: "missing.txt")
            XCTFail("\(what) is not on the screen", file: file, line: line)
        }
    }

    private func eventually(_ what: String, _ seconds: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line, _ check: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if check() { return }; Thread.sleep(forTimeInterval: 0.25) }
        note("\(name) not true: \(what)\n\(app.debugDescription)", in: "missing.txt")
        XCTFail(what, file: file, line: line)
    }

    private func chosen(_ game: String) -> Bool { app.buttons.matching(NSPredicate(format: "label == %@", game)).allElementsBoundByIndex.contains { $0.isSelected } }

    /// Puts away what the system or the app laid over the screen, by its own button when it has one.
    private func putAway() {
        for label in [say("Cancel"), say("Close"), "Cancel", "Annuler", "Close", "Fermer", "close", "xmark"] {
            let button = app.buttons[label].firstMatch
            if button.exists, button.isHittable { button.tap(); Thread.sleep(forTimeInterval: 1); return }
        }
        // A popover closes at a tap beside it, a sheet at a pull.
        if pad { app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap() } else { app.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1)
    }

    /// Brings a row to where it can be touched.
    private func reach(_ element: XCUIElement) {
        for _ in 0..<10 where !(element.exists && element.isHittable) { app.swipeUp(velocity: .slow) }
    }

    private func open(_ key: String) {
        let one = row(key)
        reach(one)
        tap(one, say(key))
    }

    // MARK: First launch

    func test01FirstLaunch() throws {
        // As installed: nothing is written before the first start.
        app.launchArguments = ["-AppleLanguages", "(\(Self.lang))", "-AppleLocale", Self.lang == "fr" ? "fr_FR" : "en_US"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60))
        shows("No game here yet")
        step("01-premier-lancement")
        tab("Library")
        shows("No game here yet")
        step("02-bibliotheque-vide")
        tab("Controllers")
        shows("No controller connected")
        step("03-manettes-aucune")
        tab("Settings")
        shows("Data and saves")
        step("04-reglages-premier-lancement")
        tab("Home")
        tap(button(say("Add a game")), "Add a game")
        Thread.sleep(forTimeInterval: 4)
        step("05-ajouter-un-jeu-fichiers")
        putAway()
        shows("No game here yet")
    }

    func test02AddAGame() throws {
        let game = CaptureGames.all[0]
        let folderName = "DmGame\(game.id)"
        try start(.none) { documents in
            let fm = FileManager.default, data = documents.deletingLastPathComponent()
            try CaptureGames.make(in: data, frameworks: "Documents/Made", marker: Self.marker)
            let code = try XCTUnwrap(Self.bundle.privateFrameworksURL).appendingPathComponent("DmGame.framework/DmGame")
            let made = documents.appendingPathComponent("Made/\(folderName).framework")
            try fm.removeItem(at: made.appendingPathComponent("DmGame"))
            try fm.copyItem(at: code, to: made.appendingPathComponent("DmGame"))
            try fm.moveItem(at: made, to: documents.appendingPathComponent("\(folderName).framework"))
            try fm.removeItem(at: documents.appendingPathComponent("Made"))
        }
        tap(button(say("Add a game")), "Add a game")
        let place = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'Oort NX'")).firstMatch
        let target = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@ OR identifier BEGINSWITH %@", folderName, folderName)).firstMatch
        if !target.waitForExistence(timeout: 20), !place.exists {
            let browse = app.buttons.matching(NSPredicate(format: "label IN {'Browse', 'Explorer', 'Parcourir'}")).firstMatch
            if browse.waitForExistence(timeout: 10) { browse.tap() }
            let device = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'On My' OR label BEGINSWITH 'Sur mon' OR identifier CONTAINS 'LocalStorage'")).firstMatch
            if !place.waitForExistence(timeout: 5), device.waitForExistence(timeout: 5) { device.tap() }
        }
        for _ in 0..<4 where !target.exists {
            if place.waitForExistence(timeout: 15), place.isHittable { place.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap() }
            _ = target.waitForExistence(timeout: 12)
        }
        step("06-choisir-le-dossier-du-jeu")
        appears(target, "the game's folder in Files")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        let action = app.buttons["DOCPicker.actionButton"].firstMatch
        if action.waitForExistence(timeout: 4), action.isEnabled, action.isHittable { action.tap() }
        appears(app.staticTexts[game.name].firstMatch, "the added game", 30)
        step("07-jeu-ajoute")
        // Added without its data: the page says what is missing.
        tap(button(say("Game page")), "the game page")
        step("08-jeu-ajoute-sans-donnees")
    }

    // MARK: Every screen

    func test03Screens() throws {
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        step("10-accueil")
        if pad || app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height { tap(app.buttons[second].firstMatch, second) } else { app.swipeLeft() }
        eventually("the second game is chosen") { chosen(second) }
        step("11-accueil-autre-jeu")
        app.buttons[second].firstMatch.press(forDuration: 1.3)
        step("12-accueil-menu-du-jeu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        Thread.sleep(forTimeInterval: 1)
        tap(button(say("Game page")), "the game page")
        shows("Version")
        step("13-fiche-du-jeu")
        app.swipeUp()
        step("14-fiche-donnees-et-sauvegardes")
        app.swipeUp()
        step("15-fiche-bas")
        open("Remove from this device")
        appears(button(say("Remove the game, keep its saves")), "the removal question")
        step("16-confirmer-la-suppression")
        // Beside the question: nothing is removed.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(button(say("Remove the game, keep its saves")).exists, "the question closes without removing")
        open("Game log")
        step("17-journal-du-jeu")
        putAway()
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        open("Copy the link that starts this game")
        shows("Link copied")
        step("18-lien-copie")
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        open("Choose its picture")
        Thread.sleep(forTimeInterval: 3)
        step("19-choisir-une-image")
        putAway()
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        open("Options")
        step("20-options-du-jeu")
        let toggle = app.switches.firstMatch
        appears(toggle, "a switch in the options")
        let was = toggle.value as? String
        toggle.tap()
        eventually("the option changes") { toggle.value as? String != was }
        step("21-option-modifiee")
        back()
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        open("Buttons for this game")
        step("22-boutons-du-jeu")
        back()
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        open("Cheats")
        step("23-triches")
        back()
    }

    func test04Library() throws {
        try start(.invented)
        tab("Library")
        appears(app.buttons[first].firstMatch, first)
        step("30-bibliotheque")
        if !button(say("Sort")).waitForExistence(timeout: 3) {
            tap(app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'More', 'Plus', 'Autres', 'Autre', 'Suite'} OR identifier CONTAINS 'verflow'")).firstMatch, "the bar's menu")
        }
        tap(button(say("Sort")), "Sort")
        step("31-menu-de-tri")
        tap(button(say("Name")), "by name")
        Thread.sleep(forTimeInterval: 1)
        step("32-tri-par-nom")
        app.buttons[first].firstMatch.press(forDuration: 1.3)
        step("33-menu-d-un-jeu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        Thread.sleep(forTimeInterval: 1)
        if app.buttons[say("Options")].firstMatch.exists, !app.searchFields.firstMatch.exists { back() }
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) {
            let glass = app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'Search', 'Rechercher', 'Recherche'}")).firstMatch
            if glass.waitForExistence(timeout: 2) { glass.tap() } else { app.swipeDown() }
        }
        appears(search, "the search field")
        search.tap()
        search.typeText("Mar")
        appears(app.buttons[second].firstMatch, second)
        step("34-recherche")
        search.typeText("zzz")
        step("35-recherche-sans-resultat")
    }

    func test05ControllersAndSettings() throws {
        try start(.invented)
        tab("Controllers")
        shows("Touch controls")
        step("40-manettes")
        open("What each button sends")
        step("41-correspondance-des-boutons")
        app.swipeUp()
        app.swipeUp()
        step("42-correspondance-bas")
        back()
        tab("Settings")
        shows("Data and saves")
        step("43-reglages")
        app.swipeUp()
        step("44-reglages-suite")
        for _ in 0..<3 { app.swipeUp() }
        step("45-reglages-fin")
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        open("Play time")
        step("46-temps-de-jeu-vide")
        back()
        open("Folder for every game's data")
        Thread.sleep(forTimeInterval: 3)
        step("47-choisir-le-dossier-des-donnees")
        putAway()
        open("Thanks and licences")
        shows("NX2Apple")
        step("48-remerciements")
        open("Every notice, in full")
        shows("Permission is hereby granted")
        step("49-licences")
    }

    func test06PlayAndComeBack() throws {
        try start(.invented)
        tab("Library")
        tap(app.buttons[first].firstMatch, first)
        step("50-avant-de-jouer")
        tap(button(say("Play")), "Play")
        let game = app.staticTexts["Invented game main, save ready"]
        appears(game, "the invented game", 30)
        step("51-jeu-en-cours")
        // Leaving for the Home Screen and coming back keeps the game.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        appears(game, "the game after the background")
        step("52-retour-de-l-arriere-plan")
        tap(button("Quit the invented game"), "Quit")
        appears(button(say("Play")), "the library", 20)
        step("53-retour-dans-oort")
        back()
        tab("Settings")
        open("Play time")
        shows(CaptureGames.all[0].name)
        step("54-temps-de-jeu")
        back()
        // A shortcut starts the game, the app running or not.
        app.terminate()
        XCUIDevice.shared.system.open(URL(string: "oortnx://launch?id=\(CaptureGames.all[0].id)")!)
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(NSPredicate(format: "label IN {'Open', 'Ouvrir'}")).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        appears(game, "the game started by its link", 30)
        step("55-lancement-par-raccourci")
        tap(button("Quit the invented game"), "Quit")
        tab("Library")
        tap(app.buttons[second].firstMatch, second)
        tap(button(say("Play")), "Play")
        let alert = app.alerts.firstMatch
        appears(alert, "the refusal", 30)
        step("56-code-refuse")
        alert.buttons[say("OK")].tap()
    }

    // MARK: On its side, and the largest texts

    func test07OnItsSide() throws {
        try start(.invented)
        appears(button(say("Options")), "the home screen", 20)
        XCUIDevice.shared.orientation = .landscapeLeft
        step("60-paysage-accueil")
        tap(button(say("Game page")), "the game page")
        step("61-paysage-fiche")
        app.swipeUp()
        step("62-paysage-fiche-bas")
        back()
        tap(button(say("Options")), "Options")
        step("63-paysage-options")
        // Turning on a page keeps it.
        XCUIDevice.shared.orientation = .portrait
        shows("Back to the tested settings", 1)
        step("64-options-redressees")
        XCUIDevice.shared.orientation = .landscapeLeft
        back()
        tab("Library")
        step("65-paysage-bibliotheque")
        tab("Controllers")
        step("66-paysage-manettes")
        open("What each button sends")
        step("67-paysage-correspondance")
        back()
        tab("Settings")
        step("68-paysage-reglages")
        XCUIDevice.shared.orientation = .landscapeRight
        open("Thanks and licences")
        step("69-paysage-remerciements")
    }

    func test08LargestText() throws {
        try start(.invented, largest)
        appears(button(say("Options")), "the home screen", 20)
        step("70-grand-texte-accueil")
        tap(button(say("Game page")), "the game page")
        step("71-grand-texte-fiche")
        app.swipeUp()
        step("72-grand-texte-fiche-suite")
        open("Remove from this device")
        step("73-grand-texte-confirmation")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        Thread.sleep(forTimeInterval: 1)
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        back()
        tap(button(say("Options")), "Options")
        step("74-grand-texte-options")
        back()
        tab("Library")
        step("75-grand-texte-bibliotheque")
        tab("Controllers")
        step("76-grand-texte-manettes")
        open("What each button sends")
        step("77-grand-texte-correspondance")
        back()
        tab("Settings")
        step("78-grand-texte-reglages")
        open("Thanks and licences")
        step("79-grand-texte-remerciements")
        XCUIDevice.shared.orientation = .landscapeLeft
        back()
        tab("Home")
        step("80-grand-texte-paysage-accueil")
        tap(button(say("Game page")), "the game page")
        step("81-grand-texte-paysage-fiche")
        try start(.none, largest)
        XCUIDevice.shared.orientation = .portrait
        step("82-grand-texte-sans-jeu")
        reach(button(say("Add a game")))
        XCTAssertTrue(button(say("Add a game")).isHittable, "Add a game can be reached")
        step("83-grand-texte-ajouter")
    }

    // MARK: A controller, a keyboard

    private func inserted(_ library: String) throws -> String {
        try XCTUnwrap(Self.bundle.privateFrameworksURL).appendingPathComponent("\(library).framework/\(library)").path
    }

    private func send(_ command: String, _ pause: TimeInterval = 0.7) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("oort.pad.\(command)" as CFString), nil, nil, true)
        Thread.sleep(forTimeInterval: pause)
    }

    private func press(_ button: String, _ times: Int = 1) { for _ in 0..<times { send("press.\(button)") } }

    func test09Controller() throws {
        app.launchEnvironment = ["DYLD_INSERT_LIBRARIES": try inserted("FakePad")]
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        send("connect", 3)
        press("right")
        eventually("a controller moves to the second game") { chosen(second) }
        step("90-manette-accueil")
        press("down")
        press("left", 2)
        press("right")
        press("a")
        shows("Version")
        step("91-manette-fiche")
        // The page's rows: Play, then Options.
        press("down", 2)
        press("a")
        appears(app.switches.firstMatch, "the options")
        press("down")
        step("92-manette-options")
        let state = app.debugDescription
        press("left")
        eventually("left changes the option") { app.debugDescription != state }
        step("93-manette-option-changee")
        press("b")
        shows("Version")
        press("b")
        appears(button(say("Game page")), "home after B")
        press("r")
        appears(app.buttons[first].firstMatch, "the library")
        press("right")
        press("down")
        step("94-manette-bibliotheque")
        press("a")
        shows("Version")
        press("b")
        press("y")
        shows("Touch controls")
        step("95-manette-manettes")
        press("down")
        press("a")
        shows("Hold the bottom or right button to close.")
        send("hold.x", 0.2)
        send("hold.l", 0.2)
        send("hold.up", 0.6)
        step("96-manette-essai-des-boutons")
        send("release.x", 0.1)
        send("release.l", 0.1)
        send("release.up", 0.3)
        send("hold.b", 2)
        send("release.b", 0.5)
        shows("Touch controls")
        XCTAssertFalse(app.staticTexts[say("Hold the bottom or right button to close.")].exists, "holding B closes the test")
        press("r")
        shows("Data and saves")
        let frames = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", say("Show the frame rate"))).firstMatch
        press("down", 5)
        appears(frames, "the frame rate switch")
        let was = frames.value as? String
        press("a")
        eventually("A turns the switch") { frames.value as? String != was }
        step("97-manette-reglages")
        press("a")
        press("b")
        appears(button(say("Game page")), "home after B")
        // Back on the first game's page, Play with A.
        tab("Home")
        press("down")
        press("left", 3)
        press("a")
        appears(app.staticTexts["Invented game main, save ready"].firstMatch, "A starts the game", 30)
        step("98-manette-jeu-lance")
        tap(button("Quit the invented game"), "Quit")
        appears(button(say("Game page")), "back after the game", 20)
        press("r", 2)
        shows("Touch controls")
        send("disconnect", 3)
        shows("No controller connected")
        step("99-manette-debranchee")
    }

    /// A question over the app answers to the controller, and nothing behind it moves.
    func test13ControllerAndQuestions() throws {
        app.launchEnvironment = ["DYLD_INSERT_LIBRARIES": try inserted("FakePad")]
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        send("connect", 3)
        // The second game's code cannot be loaded: Play says so.
        press("right")
        press("down")
        press("left", 3)
        press("a")
        let alert = app.alerts.firstMatch
        appears(alert, "the refusal", 30)
        step("85-manette-message")
        press("r")
        XCTAssertTrue(app.alerts.firstMatch.exists, "R leaves the message")
        press("b")
        eventually("B closes the message") { !app.alerts.firstMatch.exists }
        appears(button(say("Game page")), "still home, nothing moved behind the message")
        XCTAssertTrue(chosen(second), "the same game is chosen")
        // The removal question of a game's page.
        press("right")
        press("a")
        shows("Version")
        open("Remove from this device")
        let keep = button(say("Remove the game, keep its saves"))
        appears(keep, "the removal question")
        press("down")
        press("b")
        eventually("B closes the question") { !keep.exists }
        shows("Remove from this device")
        step("86-manette-question-fermee")
    }

    func test10Keyboard() throws {
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        func key(_ key: XCUIKeyboardKey, _ times: Int = 1) { for _ in 0..<times { app.typeKey(key, modifierFlags: []); Thread.sleep(forTimeInterval: 0.6) } }
        key(.rightArrow)
        eventually("the right arrow moves to the second game") { chosen(second) }
        step("100-clavier-accueil")
        key(.downArrow)
        key(.leftArrow, 2)
        key(.rightArrow)
        key(.return)
        shows("Version")
        step("101-clavier-fiche")
        key(.escape)
        appears(button(say("Game page")), "home after Escape")
        app.typeKey("y", modifierFlags: [])
        shows("Touch controls")
        key(.downArrow)
        step("102-clavier-manettes")
        app.typeKey(",", modifierFlags: [])
        shows("Data and saves")
        step("103-clavier-reglages")
        key(.escape)
        appears(button(say("Game page")), "home after Escape")
        // Typing in the search field stays typing.
        tab("Library")
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) {
            let glass = app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'Search', 'Rechercher', 'Recherche'}")).firstMatch
            if glass.waitForExistence(timeout: 2) { glass.tap() } else { app.swipeDown() }
        }
        appears(search, "the search field")
        search.tap()
        search.typeText("oy,")
        eventually("the letters go to the field") { (search.value as? String)?.contains("oy,") == true }
        XCTAssertTrue(app.searchFields.firstMatch.exists, "still in the library")
        step("104-clavier-recherche")
    }

    // MARK: Reopening, and no network

    func test11Reopening() throws {
        try start(.invented)
        tab("Library")
        if !button(say("Sort")).waitForExistence(timeout: 3) {
            tap(app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'More', 'Plus', 'Autres', 'Autre', 'Suite'} OR identifier CONTAINS 'verflow'")).firstMatch, "the bar's menu")
        }
        tap(button(say("Sort")), "Sort")
        tap(button(say("Name")), "by name")
        tap(app.buttons[first].firstMatch, first)
        open("Options")
        let option = app.switches.firstMatch
        appears(option, "a switch in the options")
        option.tap()
        Thread.sleep(forTimeInterval: 1)
        let optionNow = option.value as? String
        back()
        back()
        tab("Settings")
        let sounds = app.switches[say("Sounds")].firstMatch
        reach(sounds)
        let soundsWas = sounds.value as? String
        sounds.tap()
        eventually("the sounds switch changes") { sounds.value as? String != soundsWas }
        let soundsNow = sounds.value as? String
        // In the background and back: the same screen.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        appears(sounds, "settings after the background")
        step("110-retour-de-l-arriere-plan")
        // Closed, then opened again: choices are kept.
        app.terminate()
        app.launch()
        appears(button(say("Game page")), "home after reopening", 30)
        step("111-reouverture")
        tab("Library")
        appears(app.buttons[first].firstMatch, first)
        func at(_ name: String) -> CGFloat { let f = app.buttons[name].firstMatch.frame; return f.minY * 10_000 + f.minX }
        XCTAssertLessThan(at("Aimant"), at("Collines rouges"), "still sorted by name")
        step("112-reouverture-tri-garde")
        tap(app.buttons[first].firstMatch, first)
        open("Options")
        XCTAssertEqual(app.switches.firstMatch.value as? String, optionNow, "the game's option is kept")
        step("113-reouverture-option-gardee")
        back()
        back()
        tab("Settings")
        reach(sounds)
        XCTAssertEqual(sounds.value as? String, soundsNow, "the sounds switch is kept")
        step("114-reouverture-reglage-garde")
        sounds.tap()
    }

    func test12NoNetwork() throws {
        let log = Self.out.appendingPathComponent("net.log")
        try? FileManager.default.removeItem(at: log)
        app.launchEnvironment = ["DYLD_INSERT_LIBRARIES": try inserted("NetCut"), "OORT_NET_LOG": log.path]
        try start(.invented)
        appears(button(say("Game page")), "home without network", 30)
        // The cut proves itself first: the library asks for a page and must get nothing.
        eventually("the cut is in place", 30) { (try? String(contentsOf: log, encoding: .utf8))?.contains("PROBE failed") == true }
        step("120-hors-ligne-accueil")
        tap(button(say("Game page")), "the game page")
        step("121-hors-ligne-fiche")
        tap(button(say("Play")), "Play")
        appears(app.staticTexts["Invented game main, save ready"], "the game without network", 30)
        tap(button("Quit the invented game"), "Quit")
        appears(button(say("Play")), "back", 20)
        back()
        tab("Library"); step("122-hors-ligne-bibliotheque")
        tab("Controllers")
        tab("Settings")
        open("Thanks and licences")
        open("Every notice, in full")
        shows("Permission is hereby granted")
        step("123-hors-ligne-licences")
        let said = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let probe = said.components(separatedBy: "PROBE end").first ?? ""
        let after = said.dropFirst(probe.count).components(separatedBy: "\n").filter { $0.hasPrefix("blocked") }
        XCTAssertEqual(after, [], "the app asked for the network")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
