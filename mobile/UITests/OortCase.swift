// What every simulator test does: start the app with invented games, find its words, picture a screen.
// OORT_OUT (a folder), OORT_LANG (fr or en) and OORT_STILL come from scripts/test_app.sh.
import XCTest

class OortCase: XCTestCase {
    static let env = ProcessInfo.processInfo.environment
    static let lang = env["OORT_LANG"] ?? "fr"
    static let out = URL(fileURLWithPath: env["OORT_OUT"] ?? NSTemporaryDirectory())
    static let bundle = Bundle(for: OortUITests.self)
    static let marker = "oort_invented_marker"
    let app = XCUIApplication()
    var pad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

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
    func say(_ key: String) -> String {
        let words = Self.bundle.path(forResource: Self.lang, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Self.bundle
        return words.localizedString(forKey: key, value: key, table: nil)
    }

    /// The app's own folder: the simulator's apps sit side by side. The first start makes it.
    func home() throws -> URL {
        if let found = folder() { return found }
        app.launch()
        app.terminate()
        if let found = folder() { return found }
        let all = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        let seen = (try? FileManager.default.subpathsOfDirectory(atPath: all.path).prefix(60).joined(separator: "\n")) ?? "unreadable"
        throw NoFolder(seen: NSHomeDirectory() + "\n" + seen)
    }
    struct NoFolder: Error { let seen: String }

    func folder() -> URL? {
        let all = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        return (try? FileManager.default.contentsOfDirectory(at: all, includingPropertiesForKeys: nil))?.first { one in
            let data = try? Data(contentsOf: one.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist"))
            let plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
            // The app writes its version line at each start.
            return plist?["MCMMetadataIdentifier"] as? String == "io.github.sofianbll.oortnx.mobile"
                || FileManager.default.fileExists(atPath: one.appendingPathComponent("Documents/shell-log.txt").path)
        }
    }

    enum Games { case none, invented }

    func start(_ games: Games, _ more: [String] = [], prepare: (URL) throws -> Void = { _ in }) throws {
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

    func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.9)
        let file = "\(Self.lang)-\(pad ? "ipad" : "iphone")-\(name).png"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: Self.out.appendingPathComponent(file))
    }

    func note(_ text: String, in file: String) {
        let url = Self.out.appendingPathComponent(file)
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + text + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }

    /// Oort NX's question over the app, or one of the system's.
    var question: XCUIElement { app.descendants(matching: .any).matching(identifier: "oort.question").firstMatch }
    var asked: Bool { question.exists || app.alerts.firstMatch.exists }
    func waitForQuestion(_ seconds: TimeInterval = 30) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if asked { return true }; Thread.sleep(forTimeInterval: 0.25) }
        return false
    }
    /// What the question says, and its way out.
    var questionWords: [String] { (question.exists ? question : app.alerts.firstMatch).staticTexts.allElementsBoundByIndex.map(\.label) }
    func agree() { (question.exists ? app.buttons : app.alerts.firstMatch.buttons)[say("OK")].firstMatch.tap() }

    /// A row reads its value after its name.
    func row(_ key: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", say(key))).firstMatch }

    func tap(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 15) else {
            note("\(name) missing \(what)\n\(app.debugDescription)", in: "missing.txt")
            return XCTFail("\(what) is not on the screen", file: file, line: line)
        }
        for _ in 0..<8 where !element.isHittable { app.swipeUp(velocity: .slow) }
        element.tap()
    }

    func tab(_ key: String) {
        let label = say(key)
        let bar = app.tabBars.buttons[label].firstMatch
        tap(bar.waitForExistence(timeout: 5) ? bar : button(label), "the tab \(label)")
    }

    func back() {
        let bar = app.navigationBars.buttons.element(boundBy: 0)
        tap(bar, "Back")
    }

    func shows(_ key: String, _ seconds: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let text = say(key)
        let found = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        if !found.waitForExistence(timeout: seconds) {
            note("\(name) no text \(text)\n\(app.debugDescription)", in: "missing.txt")
            XCTFail("“\(text)” is not shown", file: file, line: line)
        }
    }
}
