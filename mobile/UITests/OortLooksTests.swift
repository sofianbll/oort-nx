// What changes on screen: the same walk on the published app and on this one, one picture per place, to be set side by side.
// Only what both versions have is touched; a place that one of them lacks is pictured as it is.
import XCTest

final class OortLooksTests: OortCase {
    private var first: String { CaptureGames.all[0].name }
    private var second: String { CaptureGames.all[1].name }

    private func look(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: Self.out.appendingPathComponent(name + ".png"))
    }

    private func send(_ command: String, _ pause: TimeInterval = 0.9) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("oort.pad.\(command)" as CFString), nil, nil, true)
        Thread.sleep(forTimeInterval: pause)
    }

    private func withController() throws {
        app.launchEnvironment = ["DYLD_INSERT_LIBRARIES": try XCTUnwrap(Self.bundle.privateFrameworksURL).appendingPathComponent("FakePad.framework/FakePad").path]
    }

    private func reach(_ element: XCUIElement) {
        let height = app.windows.firstMatch.frame.height
        for _ in 0..<12 where !(element.exists && element.isHittable && element.frame.midY < height * 0.78) { app.swipeUp(velocity: .slow) }
    }

    private func touch(_ element: XCUIElement) {
        // A long list makes its rows as they come into sight.
        if !element.waitForExistence(timeout: 5) { reach(element) }
        guard element.waitForExistence(timeout: 5) else { return XCTFail("\(element) is not on the screen") }
        reach(element)
        element.tap()
    }

    private func dismiss() {
        for label in [say("Cancel"), say("OK")] where button(label).exists && button(label).isHittable { button(label).tap(); return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)).tap()
        Thread.sleep(forTimeInterval: 1)
    }

    func testL1Touch() throws {
        try start(.none)
        _ = button(say("Add a game")).waitForExistence(timeout: 20)
        look("01-accueil-sans-jeu")
        try start(.invented)
        _ = button(say("Game page")).waitForExistence(timeout: 20)
        look("02-accueil")
        tab("Library")
        look("03-bibliotheque")
        app.buttons[first].firstMatch.press(forDuration: 1.3)
        look("04-menu-d-un-jeu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        Thread.sleep(forTimeInterval: 1)
    }

    func testL2Page() throws {
        try start(.invented)
        tab("Library")
        touch(app.buttons[first].firstMatch)
        look("05-fiche-haut")
        app.swipeUp(velocity: .slow)
        look("06-fiche-jouer")
        for _ in 0..<5 { app.swipeUp() }
        look("07-fiche-bas")
        touch(row("Remove from this device"))
        look("08-question-supprimer")
        dismiss()
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        touch(row("Cheats"))
        look("09-codes-de-triche")
        try start(.invented)
        tab("Library")
        touch(app.buttons[second].firstMatch)
        touch(button(say("Play")))
        _ = waitForQuestion()
        look("10-message-jeu-refuse")
    }

    func testL3Settings() throws {
        try start(.invented)
        tab("Settings")
        look("11-reglages")
        for _ in 0..<4 { app.swipeUp() }
        look("12-reglages-bas")
        touch(row("Thanks and licences"))
        look("13-credits")
        try start(.invented)
        tab("Controllers")
        look("14-manettes")
        app.swipeUp()
        look("15-manettes-bas")
        for _ in 0..<2 { app.swipeDown(velocity: .fast) }
        touch(row("What each button sends"))
        for _ in 0..<6 { app.swipeUp() }
        touch(row("Back to the buttons as printed"))
        look("16-remise-des-boutons")
    }

    func testL4Controller() throws {
        try withController()
        try start(.invented)
        _ = button(say("Game page")).waitForExistence(timeout: 20)
        send("connect", 3)
        send("press.right")
        look("17-manette-accueil")
        send("press.r")
        look("18a-manette-bibliotheque-touches")
        send("press.down")
        look("18-manette-bibliotheque")
        send("press.y", 1.5)
        look("19-manette-touche-y")
        try start(.invented)
        send("connect", 3)
        tab("Settings")
        send("press.down")
        send("press.down")
        look("20-manette-reglages")
        touch(row("Thanks and licences"))
        touch(row("Every notice, in full"))
        send("press.down")
        look("21-manette-licences")
        try start(.invented)
        send("connect", 3)
        tab("Library")
        touch(app.buttons[first].firstMatch)
        send("press.down")
        look("22-manette-fiche")
    }

    func testL5Keyboard() throws {
        try start(.invented)
        _ = button(say("Game page")).waitForExistence(timeout: 20)
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        look("23-clavier-accueil")
    }

    func testL6OnItsSide() throws {
        try start(.invented)
        XCUIDevice.shared.orientation = .landscapeLeft
        touch(button(say("Options")))
        let back = app.navigationBars.buttons["BackButton"]
        _ = back.waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        back.tap()
        look("24-paysage-apres-retour")
    }
}
