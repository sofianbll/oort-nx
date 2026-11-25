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

    /// Brings a row to where it can be touched: clear of the bars and of the key that stays at the bottom.
    private func reach(_ element: XCUIElement) {
        let height = app.windows.firstMatch.frame.height
        func clear() -> Bool { element.exists && element.isHittable && element.frame.midY < height * 0.78 }
        for _ in 0..<10 where !clear() {
            // A short screen or large texts: the list may already be at its end.
            let before = element.exists ? element.frame.minY : -1
            app.swipeUp(velocity: .slow)
            if element.exists, element.isHittable, element.frame.minY == before { return }
        }
    }

    /// The game the home screen has chosen.
    private var chosenGame: String { CaptureGames.all.map(\.name).first(where: chosen) ?? "" }

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
        shows("Touch controls")
        step("03-manettes")
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
        let target = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@ OR identifier BEGINSWITH %@", folderName, folderName)).firstMatch
        if !target.waitForExistence(timeout: 8) {
            // A touch from the test does not open a folder of Files: its search finds the game's by name.
            let search = app.searchFields.firstMatch
            appears(search, "the search of Files", 20)
            search.tap()
            search.typeText("DmGame")
            _ = target.waitForExistence(timeout: 15)
        }
        step("06-choisir-le-dossier-du-jeu")
        appears(target, "the game's folder in Files")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        // A folder is entered, then opened.
        Thread.sleep(forTimeInterval: 4)
        step("07-ouvrir-le-dossier")
        let action = app.buttons["DOCPicker.actionButton"].firstMatch
        let words = app.buttons.matching(NSPredicate(format: "label IN {'Open', 'Ouvrir'}")).firstMatch
        if action.exists, action.isEnabled, action.isHittable { action.tap() } else if words.exists { words.tap() }
        appears(app.staticTexts[game.name].firstMatch, "the added game", 30)
        step("08-jeu-ajoute")
        tap(button(say("Game page")), "the game page")
        step("09-fiche-du-jeu-ajoute")
    }

    // MARK: Every screen

    func test03Screens() throws {
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        step("10-accueil")
        let at = chosenGame
        if pad || app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height {
            let other = CaptureGames.all.map(\.name).first { $0 != at && app.buttons[$0].firstMatch.isHittable } ?? second
            tap(app.buttons[other].firstMatch, other)
        } else { app.swipeLeft() }
        eventually("another game is chosen") { !chosenGame.isEmpty && chosenGame != at }
        let other = chosenGame
        step("11-accueil-autre-jeu")
        app.buttons[other].firstMatch.press(forDuration: 1.3)
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
        XCTAssertTrue(waitForQuestion(), "the refusal is said")
        step("56-code-refuse")
        agree()
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
        tap(button(say("Game page")), "the game page")
        // Brought above the tab bar, which floats over the list on a phone on its side.
        open("Options")
        appears(app.switches.firstMatch, "the options")
        step("63-paysage-options")
        // Turning on a page keeps it.
        XCUIDevice.shared.orientation = .portrait
        appears(app.switches.firstMatch, "the options, upright")
        step("64-options-redressees")
        XCUIDevice.shared.orientation = .landscapeLeft
        back()
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
        // The way out is at the bottom of the question, however large its words.
        let out = button(say("Cancel"))
        for _ in 0..<6 where !(out.exists && out.isHittable) { app.swipeUp() }
        step("73-grand-texte-confirmation-fin")
        tap(out, "Cancel")
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
        let at = chosenGame
        press("right")
        eventually("a controller moves to the next game") { chosenGame != at }
        step("90-manette-accueil")
        press("down")
        press("left", 2)
        press("right")
        press("a")
        shows("Version")
        step("91-manette-fiche")
        // The page's rows: Play is chosen, then Options.
        press("down")
        press("a")
        appears(app.switches.firstMatch, "the options")
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
        press("r")
        shows("Touch controls")
        step("95-manette-manettes")
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
        press("down", 4)
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
        press("up", 2)
        press("left", 6)
        for _ in 0..<6 where chosenGame != first { press("right") }
        press("down")
        press("left", 3)
        press("a")
        appears(app.staticTexts["Invented game main, save ready"].firstMatch, "A starts the game", 30)
        step("98-manette-jeu-lance")
        // The game's presses are its own: none is played back in the library.
        press("r", 2)
        press("y")
        press("a")
        tap(button("Quit the invented game"), "Quit")
        appears(button(say("Game page")), "back after the game", 20)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(button(say("Game page")).isHittable && !app.staticTexts[say("Touch controls")].exists, "nothing pressed in the game acts after it")
        press("r", 2)
        shows("Touch controls")
        let virtual = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Touch Controller'"))
        XCTAssertGreaterThan(virtual.count, 0, "the test's controller is listed")
        send("disconnect", 3)
        eventually("the controller leaves the list") { virtual.count == 0 }
        step("99-manette-debranchee")
    }

    /// A question over the app answers to the controller, and nothing behind it moves.
    func test13ControllerAndQuestions() throws {
        app.launchEnvironment = ["DYLD_INSERT_LIBRARIES": try inserted("FakePad")]
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        send("connect", 3)
        // Every invented game but one has code that cannot be loaded: Play says so.
        press("right")
        for _ in 0..<6 where [first, "Aimant"].contains(chosenGame) { press("right") }
        let broken = chosenGame
        press("down")
        press("left", 3)
        press("a")
        XCTAssertTrue(waitForQuestion(), "the refusal is said")
        step("85-manette-message")
        press("r")
        XCTAssertTrue(asked, "R leaves the message")
        press("b")
        eventually("B closes the message") { !asked }
        appears(button(say("Game page")), "still home, nothing moved behind the message")
        XCTAssertEqual(chosenGame, broken, "the same game is chosen")
        // The removal question of a game's page, by the controller alone: the last line of the page.
        press("right")
        press("a")
        shows("Version")
        press("down", 14)
        press("a")
        let keep = button(say("Remove the game, keep its saves"))
        appears(keep, "the removal question")
        step("86-manette-confirmer-suppression")
        // The way out is chosen first.
        press("a")
        eventually("A on the first choice keeps the game") { !keep.exists }
        shows("Remove from this device")
        press("a")
        appears(keep, "asked again")
        press("b")
        eventually("B closes the question") { !keep.exists }
        press("a")
        appears(keep, "asked once more")
        press("up", 2)
        step("87-manette-choix-supprimer")
        press("a")
        appears(button(say("Game page")), "home after the removal")
        press("r")
        appears(app.buttons[first].firstMatch, "the library")
        eventually("the game is gone") { !app.buttons[broken].exists }
        step("88-manette-jeu-supprime")
    }

    /// X opens a game's page and + its options; a favorite is marked, kept in its tab, and seen on its picture.
    func test16DetailsOptionsAndFavorites() throws {
        app.launchEnvironment = ["DYLD_INSERT_LIBRARIES": try inserted("FakePad")]
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        send("connect", 3)
        press("right")
        press("x")
        shows("Version")
        step("150-manette-x-details")
        press("b")
        press("plus")
        appears(app.switches.firstMatch, "+ opens the options")
        step("151-manette-plus-options")
        press("b")
        appears(button(say("Game page")), "home")
        tab("Library")
        appears(app.buttons[first].firstMatch, "the library")
        step("152-bibliotheque-onglets")
        tap(button(say("Favorites")), "the favorites")
        shows("No favorite yet")
        step("153-aucun-favori")
        tap(button(say("All games")), "all the games")
        tap(app.buttons[first].firstMatch, first)
        let favorite = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", say("Favorite"))).firstMatch
        reach(favorite)
        favorite.tap()
        eventually("the game is marked") { favorite.value as? String == "1" }
        step("154-fiche-favori")
        back()
        tap(button(say("Favorites")), "the favorites")
        eventually("only the favorite is listed") { app.buttons[first].exists && !app.buttons[second].exists }
        step("155-onglet-favoris")
        app.buttons[first].firstMatch.press(forDuration: 1.3)
        appears(button(say("Remove from Favorites")), "the menu of a favorite")
        step("156-menu-favori")
        button(say("Remove from Favorites")).tap()
        shows("No favorite yet")
        tap(button(say("All games")), "all the games")
    }

    /// Searching, sorting and adding with the controller alone.
    func test14ControllerInTheLibrary() throws {
        app.launchEnvironment = ["DYLD_INSERT_LIBRARIES": try inserted("FakePad")]
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        send("connect", 3)
        // The first press shows the ring and opens nothing.
        tab("Library")
        appears(app.buttons[first].firstMatch, "the library")
        press("a")
        XCTAssertTrue(app.buttons[second].exists && !app.staticTexts[say("Version")].exists, "the first A only shows what is chosen")
        step("130-manette-premier-appui")
        press("a")
        shows("Version")
        press("b")
        press("up", 2)
        press("a")
        step("131-manette-lettres")
        // M, A, R on the letters.
        press("down"); press("left", 6); press("right", 5); press("a")
        press("up"); press("left", 6); press("a")
        press("down", 2); press("left", 6); press("right", 3); press("a")
        eventually("the search leaves one game") { app.buttons[second].exists && !app.buttons[first].exists }
        step("132-manette-recherche")
        press("x")
        press("b")
        press("b")
        eventually("B clears the search") { app.buttons[first].exists }
        press("up", 5)
        press("right")
        press("a")
        step("133-manette-tri")
        press("right")
        press("a", 1)
        Thread.sleep(forTimeInterval: 3)
        step("134-manette-ajouter-fichiers")
        press("down")
        press("a")
        press("b")
        Thread.sleep(forTimeInterval: 2)
        appears(app.buttons[first].firstMatch, "B closes Files")
        XCTAssertTrue(app.buttons[first].isHittable, "nothing covers the library")
        step("135-manette-fichiers-fermes")
        // Y from anywhere searches.
        tab("Home")
        press("y")
        eventually("Y opened the letters in the library") { app.buttons[say("Done")].exists }
        step("136-manette-y-recherche")
    }

    /// Long texts move with the controller, a swipe takes the ring away, a reset is asked first.
    func test15ControllerReadsAndConfirms() throws {
        app.launchEnvironment = ["DYLD_INSERT_LIBRARIES": try inserted("FakePad")]
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        send("connect", 3)
        tab("Settings")
        open("Thanks and licences")
        press("down")
        press("down", 5)
        step("140-manette-credits-defiles")
        open("Every notice, in full")
        shows("Permission is hereby granted")
        let top = app.debugDescription
        press("down", 3)
        eventually("down scrolls the notices") { app.debugDescription != top }
        step("141-manette-licences-defilees")
        press("b")
        shows("With the work of")
        press("b")
        tab("Controllers")
        press("down")
        let picked = app.cells.descendants(matching: .any).matching(NSPredicate(format: "isSelected == true"))
        eventually("a line is chosen") { picked.count > 0 }
        app.swipeUp()
        eventually("a swipe takes the ring away") { picked.count == 0 }
        step("142-manette-balayage-sans-anneau")
        open("What each button sends")
        let reset = row("Back to the buttons as printed")
        reach(reset)
        reset.tap()
        XCTAssertTrue(waitForQuestion(8), "the reset is asked first")
        step("143-confirmer-remise-des-boutons")
        press("b")
        eventually("B keeps the buttons") { !asked }
        back()
        tab("Library")
        tap(app.buttons[first].firstMatch, first)
        open("Game log")
        step("144-manette-journal")
        press("down")
        press("b")
        Thread.sleep(forTimeInterval: 1)
        eventually("B closes the log") { row("Game log").isHittable }
    }

    /// XCUITest sends Return as a line feed ("\r" reaches no one), and never sends Escape: Back is tapped.
    func test10Keyboard() throws {
        try start(.invented)
        appears(button(say("Game page")), "the home screen", 20)
        func key(_ key: String, _ times: Int = 1) { for _ in 0..<times { app.typeKey(key, modifierFlags: []); Thread.sleep(forTimeInterval: 0.6) } }
        func arrow(_ arrow: XCUIKeyboardKey, _ times: Int = 1) { key(arrow.rawValue, times) }
        let onPage = app.navigationBars.buttons["BackButton"]
        let at = chosenGame
        arrow(.rightArrow)
        eventually("the right arrow moves to the next game") { chosenGame != at }
        step("100-clavier-accueil")
        arrow(.downArrow)
        arrow(.leftArrow, 2)
        arrow(.rightArrow)
        XCTAssertFalse(onPage.exists, "still home")
        step("101-clavier-fiche-choisie")
        key("\n")
        appears(onPage, "Return opens the game page")
        step("102-clavier-fiche")
        back()
        key("o")
        appears(app.switches.firstMatch, "O opens the options")
        back()
        key(",")
        shows("Data and saves")
        arrow(.downArrow)
        key("\n")
        shows("Days played")
        step("103-clavier-temps-de-jeu")
        back()
        // Y opens the library's search, and what is typed there stays typing.
        key("y")
        let search = app.searchFields.firstMatch
        appears(search, "the search field")
        Thread.sleep(forTimeInterval: 1)
        app.typeText("oy,")
        eventually("the letters go to the field") { (search.value as? String)?.contains("oy,") == true }
        XCTAssertTrue(app.searchFields.firstMatch.exists, "still in the library")
        step("104-clavier-recherche")
    }

    /// On a phone on its side, Back really goes back: the whole app's controller handling once took the bar's touches.
    func test17BackOnItsSide() throws {
        let back = app.navigationBars.buttons["BackButton"]
        for (from, open) in [("home", "Options"), ("home", "Game page"), ("library", "")] {
            try start(.invented)
            XCUIDevice.shared.orientation = .landscapeLeft
            if from == "library" { tab("Library"); tap(app.buttons[first].firstMatch, first) } else { tap(button(say(open)), open) }
            appears(back, "the page's Back, \(from) \(open)")
            Thread.sleep(forTimeInterval: 1.5)
            step("170-paysage-retour-\(from)\(open.isEmpty ? "" : "-" + open.prefix(4).lowercased())")
            back.tap()
            eventually("Back goes back, \(from) \(open)") { !back.exists }
        }
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
        let after = said.dropFirst(probe.count).components(separatedBy: "\n").filter { $0.hasPrefix("blocked") }   // refused, or a connection merely seen ("blocked?")
        XCTAssertEqual(after, [], "the app asked for the network")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
