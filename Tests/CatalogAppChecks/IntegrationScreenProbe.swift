import AppKit
import SwiftUI
@testable import NXLibrary
import NXLibraryCore
import ArcanePorting

/// Draws every frozen screen of Settings › Integrations (integrations.screens.json) with ScreenView, in French, and
/// reads back what the Selene pieces drew (their trace: pieces, texts with their role, the question's keys), what the
/// real input asks (ScreenView.keyAction and handle, with a spy effects table) and which texts are seen (the PDF and
/// assertVisible). The result must equal the reviewed reference tree (integrations.fr.tree.json). Two deliberate gaps
/// of the renderer must each make it fail. Then the Mac's own effects table (IntegrationsPage.perform) is driven.
@MainActor final class TraceBox { var pieces: [ScreenTracePiece] = [] }

@MainActor struct MacScreen {
    let screen: Screen
    var locale = AppLocale(language: .french, region: "FR")
    var showsHints = true
    let size = CGSize(width: 1440, height: 900)
    var height: CGFloat = 2600

    func content(_ view: ScreenView, trace: Bool, box: TraceBox?) -> some View {
        view
            .frame(width: size.width, height: height)
            .environment(\.screenTrace, trace)
            .environment(\.oortPageUnscrolled, !trace)
            .onPreferenceChange(ScreenTraceKey.self) { pieces in MainActor.assumeIsolated { box?.pieces = pieces } }
            .environment(\.seleneCanvas, SeleneCanvas(size: size))
            .environment(\.nxAppLocale, locale)
            .environment(\.locale, locale.formatLocale)
            .environment(\.seleneButtonNames, .xbox)
            .environment(\.seleneReduceMotion, true)
            .environment(\.colorScheme, .dark)
    }

    /// Lays the view out in a window never ordered onscreen and returns what its pieces drew.
    func trace(_ view: ScreenView) -> [ScreenTracePiece] {
        let box = TraceBox()
        let host = NSHostingView(rootView: content(view, trace: true, box: box))
        host.frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: height))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        window.layoutIfNeeded()
        // As IntegrationFixtureView.captureWindow lets a capture settle.
        for _ in 0..<10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
        }
        precondition(!window.isVisible)
        return box.pieces
    }

    /// The Mac's tree of the screen: its pieces and texts in drawing order, the focus walked with Up and Down, what
    /// A, X and B ask at each focus, the question A draws first, and the hints bar drawn at each focus.
    func tree() -> ScreenTree {
        var focus: String?
        var asked: [Screen.Intent] = []
        let question = ScreenQuestion()
        func view() -> ScreenView {
            ScreenView(screen: screen, focus: Binding(get: { focus }, set: { focus = $0 }), question: question,
                       showsHints: showsHints, platform: IntegrationsPage.platform, perform: { asked.append($0); return .done })
        }
        func press(_ key: UInt16) { view().handle(ScreenView.keyAction(key)!) }
        func page(_ trace: [ScreenTracePiece]) -> [ScreenTracePiece] {
            Array(trace.prefix { $0.kind != .question }).filter { ![.hint, .question].contains($0.kind) }
        }
        func bar(_ trace: [ScreenTracePiece]) -> [ScreenTracePiece] { trace.filter { $0.kind == .hint } }
        func top() { for _ in 0..<64 { let before = focus; press(126); if focus == before { break } } }
        let first = trace(view())
        let drawn = page(first)
        let controls = drawn.filter { $0.kind != .text }
        let pieces = controls.map { piece -> ScreenTree.Piece in
            switch piece.kind {
            case .row: .init(.row, text: piece.text, about: piece.about)
            case .dot: .init(.dot, text: piece.text, tone: piece.tone)
            case .switch: .init(.switch, on: piece.on)
            default: .init(.pill, text: piece.text, destructive: piece.destructive)
            }
        }
        // Every text the pieces drew, with the role of the piece that drew it.
        let texts = drawn.flatMap { piece -> [ScreenTree.Words] in
            switch piece.kind {
            case .text: [.init(piece.role ?? .body, piece.text ?? "")]
            case .row: [.init(.row, piece.text ?? "")] + (piece.about.map { [.init(piece.role ?? .about, $0)] } ?? [])
            case .dot: [.init(.status, piece.text ?? "")]
            case .pill: [.init(.button, piece.text ?? "")]
            default: []
            }
        }
        let initial = controls.firstIndex { $0.focused == true }
        // To the top, then down through every focusable piece.
        var walked: [(piece: Int, bar: [ScreenTracePiece])] = []
        top()
        for _ in 0..<64 {
            let now = trace(view())
            guard let piece = page(now).filter({ $0.kind != .text }).firstIndex(where: { $0.focused == true }) else { break }
            if walked.last?.piece == piece { break }
            walked.append((piece, bar(now)))
            press(125)
        }
        var focusList: [ScreenTree.Focus] = []
        for (index, step) in walked.enumerated() {
            top()
            for _ in 0..<index { press(125) }
            func said(_ key: String, _ code: UInt16) -> ScreenTree.Said? {
                guard let title = step.bar.first(where: { $0.key == key && $0.left == false })?.text else { return nil }
                asked.removeAll()
                press(code)
                return asked.first.map { ScreenTree.Said(title, ScreenTree.intent($0)) }
            }
            var entry = ScreenTree.Focus(piece: step.piece, x: said("x", 7))
            asked.removeAll()
            press(36)
            if question.asking != nil {
                // The question as the dialog drew it: its title and message, then its keys in drawing order.
                let dialog = Array(trace(view()).drop { $0.kind != .question })
                var keys = dialog.dropFirst().filter { $0.kind == .pill }
                if keys.count.isMultiple(of: 2), Array(keys.prefix(keys.count / 2)) == Array(keys.suffix(keys.count / 2)) {
                    keys = Array(keys.prefix(keys.count / 2)) // ViewThatFits lays out both of its candidates.
                }
                entry.question = [dialog.first?.text ?? "", dialog.first?.about ?? ""]
                    + keys.map { "\($0.destructive == true ? "destructive" : "cancel") \($0.text ?? "")" }
                entry.questionFocus = keys.firstIndex { $0.focused == true }
                press(53)
                precondition(question.asking == nil && asked.isEmpty, "B cancels the question and asks nothing")
                press(36)
                press(124)
                press(36)
            }
            if let title = step.bar.first(where: { $0.key == "a" && $0.left == false })?.text, let intent = asked.first {
                entry.a = .init(title, ScreenTree.intent(intent))
            }
            focusList.append(entry)
        }
        asked.removeAll()
        press(53)
        let backTitle = bar(first).first { $0.key == "b" && $0.left == true }?.text ?? ""
        let back = ScreenTree.Said(backTitle, asked.first.map(ScreenTree.intent) ?? "")
        let structure = ScreenTree.Structure(pieces: pieces, texts: texts, focus: focusList,
                                             initialFocus: initial.flatMap { piece in walked.firstIndex { $0.piece == piece } },
                                             back: back)
        let hints = walked.map { step in
            ScreenTree.Bar(left: step.bar.filter { $0.left == true }.map { "\($0.key ?? "?") \($0.text ?? "")" },
                           right: step.bar.filter { $0.left == false }.map { "\($0.key ?? "?") \($0.text ?? "")" })
        }
        return ScreenTree(screen: screen.id, structure: structure, hints: hints)
    }

    /// Saves the PNG, the PDF and the frames of the screen at its initial focus, for readProbeText and assertVisible.
    func render(to output: URL, name: String) throws {
        let view = ScreenView(screen: screen, focus: .constant(nil), question: ScreenQuestion(), showsHints: showsHints,
                              platform: IntegrationsPage.platform, perform: { _ in .done })
        let shown = content(view, trace: false, box: nil)
        let renderer = ImageRenderer(content: shown)
        let image = output.appendingPathComponent(name + ".png")
        guard let png = renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: image)
        try saveProbeText(renderer, hidden: ImageRenderer(content: shown.redacted(reason: .placeholder)), beside: image)
    }
}

/// What differs between the Mac's tree and the reference, said; empty when they are equal. Texts are compared in
/// drawing order with their role (only the no-break space is normalized); `whole` is the renderer's own rule.
func differences(_ mac: ScreenTree, _ reference: ScreenTree) -> [String] {
    var found: [String] = []
    let (m, r) = (mac.structure, reference.structure)
    func plain(_ texts: [ScreenTree.Words]) -> [String] {
        texts.map { "\($0.role.rawValue) \($0.text.replacingOccurrences(of: "\u{00A0}", with: " "))" }
    }
    if m.pieces != r.pieces { found.append("pieces: Mac \(m.pieces.map(show)) ≠ \(r.pieces.map(show))") }
    if plain(m.texts) != plain(r.texts) {
        found.append("texts: Mac has \(plain(m.texts).filter { !plain(r.texts).contains($0) }), lacks \(plain(r.texts).filter { !plain(m.texts).contains($0) })"
                     + (Set(plain(m.texts)) == Set(plain(r.texts)) ? " (order)" : ""))
    }
    if m.focus != r.focus { found.append("focus: Mac \(m.focus) ≠ \(r.focus)") }
    if m.initialFocus != r.initialFocus { found.append("initial focus: Mac \(String(describing: m.initialFocus)) ≠ \(String(describing: r.initialFocus))") }
    if m.back != r.back { found.append("back: Mac \(m.back) ≠ \(r.back)") }
    if mac.hints != reference.hints { found.append("hints: Mac \(mac.hints) ≠ \(reference.hints)") }
    return found
}

func show(_ piece: ScreenTree.Piece) -> String {
    [piece.piece.rawValue, piece.text, piece.about.map { "(\($0.prefix(24))…)" }, piece.tone?.rawValue, piece.on.map { "\($0)" },
     piece.destructive.map { _ in "destructive" }].compactMap { $0 }.joined(separator: " ")
}

/// The PDF's words are read with their spaces collapsed (readProbeText): the texts are searched the same way.
func words(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

/// The Mac's effects table, driven for real: each intent does its effect on the router, or is refused.
@MainActor func effectsTable() -> [String] {
    var problems: [String] = []
    func expect(_ condition: Bool, _ what: String) { if !condition { problems.append("effects: \(what)") } }
    var facts = IntegrationOverview.mac
    facts.steam = SteamFacts(enabled: true, read: .ready, games: 3)
    facts.hasSwitchGames = true
    let router = AppRouter()
    var toggles: [IntegrationID] = [], refuses = false
    let page = IntegrationsPage(facts: facts, router: router, question: ScreenQuestion(),
                                toggle: { toggles.append($0); return !refuses })
    router.openIntegrations()
    expect(page.perform(.open("online")) == .refused(nil) && router.integrationDetail == nil, "an entry the Mac does not offer is refused")
    expect(page.perform(.toggle("steam")) == .done && toggles == [.steam], "X turns Steam through its owner")
    refuses = true
    expect(page.perform(.toggle("steam")) == .refused(nil), "the owner's refusal is said (a settings draft waits)")
    expect(page.perform(.toggle("macApps")) == .refused(nil) && toggles == [.steam, .steam], "no switch, nothing asked")
    expect(page.perform(.owner("settings")) == .refused(nil), "settings need an open entry")
    expect(page.perform(.open("steam")) == .done && router.integrationDetail == .steam, "A opens the entry")
    for target in ["programs", "clearOnline", "leave"] {
        expect(page.perform(.owner(target)) == .refused(nil) && router.route == .integrations, "\(target) is refused on the Mac")
    }
    expect(page.perform(.owner("settings")) == .done && router.route == .settings(.sources) && router.settingsRowID == "steamSource",
           "Steam's settings open on its source row")
    router.back()
    expect(router.route == .integrations && router.integrationDetail == .steam, "back from Settings to the detail")
    expect(page.perform(.back) == .done && router.integrationDetail == nil && router.integrationFocus == .steam, "B back to the row")
    expect(page.perform(.open("switchGames")) == .done, "nxnative opens")
    expect(page.perform(.owner("switchGames")) == .done && router.takeIntegrationLibraryPlatform() == .nxnative, "its games open")
    return problems
}

@main struct IntegrationScreenProbe {
    @MainActor static func main() throws {
        assertFixtureHome()
        suppressProbeNotifications()
        SeleneFonts.register()
        let output = AppData.profile.home.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        L10n.setContext(AppLocale(language: .french, region: "FR"))
        let folder = URL(fileURLWithPath: "Tests/NXLibraryCoreTests/Screens")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let screens = try decoder.decode([String: [Screen]].self, from: Data(contentsOf: folder.appendingPathComponent("integrations.screens.json")))
        let trees = try decoder.decode([String: [ScreenTree]].self, from: Data(contentsOf: folder.appendingPathComponent("integrations.fr.tree.json")))
        precondition(Set(screens.keys) == Set(trees.keys) && !screens.isEmpty)
        var failures: [String] = [], count = 0
        for (scenario, list) in screens.sorted(by: { $0.key < $1.key }) {
            precondition(list.count == trees[scenario]?.count)
            for (index, screen) in list.enumerated() {
                let reference = trees[scenario]![index]
                let probe = MacScreen(screen: screen, height: screen.id == IntegrationScreen.listID ? 2600 : 1700)
                let at = "\(scenario) \(screen.id)"
                failures += differences(probe.tree(), reference).map { "\(at): \($0)" }
                // Every text the screen asks for is in the PDF (drawn) and stands out from what is behind it (seen).
                let name = "\(scenario)-\(screen.id)"
                try probe.render(to: output, name: name)
                let pdf = try readProbeText(output, name: name)
                let bar = reference.structure.initialFocus.map { [reference.hints[$0]] } ?? []
                let texts = Set(reference.structure.texts.map { words($0.text) }
                                + bar.flatMap { $0.left + $0.right }.map { words(String($0.dropFirst(2))) }).sorted()
                failures += texts.filter { !pdf.contains($0) }.map { "\(at): « \($0) » is not drawn" }
                let hidden = assertVisible(output, name: name, texts)
                failures += hidden.map { "\(at): \($0)" }
                count += 1
            }
        }
        // Red examples: the renderer saying its words in another language, or drawing no hints bar, must be found.
        let steamOn = screens["steam-on"]![0], reference = trees["steam-on"]![0]
        if differences(MacScreen(screen: steamOn, locale: AppLocale(language: .english, region: "US")).tree(), reference).isEmpty {
            failures.append("red example not found: words said in English")
        }
        if differences(MacScreen(screen: steamOn, showsHints: false).tree(), reference).isEmpty {
            failures.append("red example not found: no hints bar")
        }
        failures += effectsTable()
        guard failures.isEmpty else {
            FileHandle.standardError.write(Data((failures.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("Mac: \(count) écrans dessinés par ScreenView égaux à l'arbre de référence (pièces, textes et rôles, focus, gestes, question, barre), textes dessinés et visibles ; 2 écarts volontaires du rendu trouvés ; table d'effets du Mac vérifiée")
    }
}
