import XCTest

/// Screens read the keyboard through their own `NSEvent` monitors. A shell overlay drawn on top of them
/// (the update offer, the welcome) must make every such monitor let the key go, or Return reaches the screen
/// underneath: a game starts instead of the overlay's button.
final class ShellOverlayInputTests: XCTestCase {
    private var views: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NXLibrary/Views")
    }

    func testEveryMonitorThatYieldsToAShellDialogYieldsToTheWelcome() throws {
        let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var missing: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let offer = text.components(separatedBy: "!viewModel.shellDialogOwnsInput").count - 1
            let welcome = text.components(separatedBy: "!viewModel.isWelcomeOpen").count - 1
            if offer != welcome { missing.append("\(file.lastPathComponent): \(offer) vs \(welcome)") }
        }
        XCTAssertFalse(files.isEmpty)
        XCTAssertEqual(missing.sorted(), [])
    }
}

/// The command palette takes every key while it is open: the screens' monitors yield through `shellDialogOwnsInput`,
/// the assistant (which has no such test) asks the router.
final class PaletteInputTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/NXLibrary/\(path)"), encoding: .utf8)
    }

    func testScreensYieldToThePalette() throws {
        let model = try source("ViewModels/AppViewModel.swift")
        let line = try XCTUnwrap(model.components(separatedBy: "\n").first { $0.contains("var shellDialogOwnsInput") })
        XCTAssertTrue(line.contains("router?.isPalettePresented == true"))
        XCTAssertTrue(try source("Views/Settings/CloudSetupAssistant+Input.swift").contains("viewModel.router?.isPalettePresented != true"))
    }

    func testOnlyThePaletteAnswersToCommandK() throws {
        let app = try source("NXLibraryApp.swift")
        XCTAssertEqual(app.components(separatedBy: ".keyboardShortcut(\"k\", modifiers: [.command])").count, 2)
        XCTAssertTrue(app.contains(".keyboardShortcut(\"k\", modifiers: [.command, .shift])"))
    }

    func testShellDialogsComeBeforeThePaletteAndThePaletteBeforeTheScreens() throws {
        let startup = try source("Views/Shell/AppShellView+Startup.swift")
        let palette = try XCTUnwrap(startup.range(of: "if router.isPalettePresented"))
        for dialog in ["cloudQuitInput(action)", "settingsNoticeInput(action)", "removeGameInput(action)", "updateOfferInput(action)"] {
            XCTAssertLessThan(try XCTUnwrap(startup.range(of: dialog)).lowerBound, palette.lowerBound, dialog)
        }
        for screen in ["menuInput(action)", "nxFindGameGamepadAction", "switch router.route"] {
            let range = try XCTUnwrap(startup.range(of: screen, range: palette.upperBound..<startup.endIndex))
            XCTAssertGreaterThan(range.lowerBound, palette.lowerBound, screen)
        }
    }
}

/// The screens under the control center or the profile screen step aside from their hints: the shell marks each
/// full-page layer (screen, Add game, console) covered, and every `SeleneHintsBar` honours the mark.
final class ShellOverlayHintsTests: XCTestCase {
    private var views: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NXLibrary/Views")
    }

    private func source(_ path: String) throws -> String { try String(contentsOf: views.appendingPathComponent(path), encoding: .utf8) }

    func testEveryFullPageLayerUnderAnOverlayIsMarkedCovered() throws {
        let layers = try source("Shell/AppShellView+Layers.swift")
        for (start, end) in [("\n            content\n", "if router.route == .addGame"),
                             ("AddGameView(", "if router.route == .console"),
                             ("ConsoleView(", "if router.isSearchPresented")] {
            let first = try XCTUnwrap(layers.range(of: start))
            let last = try XCTUnwrap(layers.range(of: end, range: first.upperBound..<layers.endIndex))
            let layer = layers[first.upperBound..<last.lowerBound]
            XCTAssertTrue(layer.contains(".seleneOverlayOwnership("), start)
            XCTAssertTrue(layer.contains("!router.isMenuPresented"), start)
            XCTAssertTrue(layer.contains("profileFlow == nil"), start)
            XCTAssertTrue(layer.contains("!router.isPalettePresented"), start)
        }
        let overlay = try source("Components/SeleneOverlay.swift")
        XCTAssertTrue(overlay.contains(".transformEnvironment(\\.seleneHintsCovered) { $0 = $0 || !ownsInput }"))
        XCTAssertTrue(try source("OortUI/SeleneHintsBar.swift").contains(".seleneOverlaidHints(covered)"))
    }

    func testTheProfilePickerHidesItsSelectorAndHintsUnderTheWizard() throws {
        let picker = try source("Shell/ProfilePickerView.swift")
        XCTAssertTrue(picker.contains(".opacity(layers.showsSelector ? 1 : 0)"))
        XCTAssertTrue(picker.contains(".seleneOverlaidHints(!layers.isTop(.selector))"))
        XCTAssertTrue(picker.contains("layers.top != .editor"))
    }
}
