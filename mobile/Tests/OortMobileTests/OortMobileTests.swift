import Foundation
import ShellHost
import ShellModel
import Testing
@testable import OortMobile

@MainActor struct OortMobileTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("oort-mobile-\(UUID().uuidString)")
    private var installed: URL { root.appendingPathComponent("Documents/Frameworks") }

    private func framework(id: String = "0100000000010000", named: String? = nil, executable: String = "DmGame") throws -> URL {
        let name = named ?? "DmGame\(id).framework"
        let url = root.appendingPathComponent("picked/\(UUID().uuidString)/\(name)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["schema": 1, "title_id": id, "name": "Orbit", "display_version": "1", "package_version": "1", "modules": ["main"], "nro_count": 0,
            "chain": "b-abc", "loader": "FH", "framework": name, "framework_executable": executable, "image_marker": "m", "profile": "p", "shader_map": "s",
            "launcher": "l", "romfs_marker": "r", "romfs_identity": "i", "min_os": "26.0"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url.appendingPathComponent("game.manifest.json"))
        try Data("code".utf8).write(to: url.appendingPathComponent("DmGame"))
        return url
    }

    @Test func aGameIsCopiedThenReplacedWhole() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try framework()
        #expect(try FrameworkImport.run(first, into: installed, check: { _ in nil }) == "0100000000010000")
        let target = installed.appendingPathComponent("DmGame0100000000010000.framework")
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("DmGame").path))
        let second = try framework()
        try Data("newer".utf8).write(to: second.appendingPathComponent("DmGame"))
        try FrameworkImport.run(second, into: installed, check: { _ in nil })
        #expect(try String(contentsOf: target.appendingPathComponent("DmGame"), encoding: .utf8) == "newer")
        #expect(try FileManager.default.contentsOfDirectory(atPath: installed.path) == ["DmGame0100000000010000.framework"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path) == ["Frameworks"], "no half copy is left")
    }

    @Test func whatIsNotAGameOrNotOursIsRefusedAndNothingChanges() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        func refused(_ url: URL, free: Int64 = .max, check: (URL) -> String? = { _ in nil }) -> FrameworkImport.Failure? {
            do { try FrameworkImport.run(url, into: installed, freeSpace: { _ in free }, check: check); return nil } catch { return error as? FrameworkImport.Failure }
        }
        let folder = root.appendingPathComponent("picked/Photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(refused(folder) == .notAGame)
        #expect(refused(try framework(named: "../../evil.framework")) != nil)
        #expect(refused(try framework(named: "Other.framework")) == .notAGame)
        #expect(refused(try framework(executable: "../DmGame")) == .notAGame)
        let linked = try framework()
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("out"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        #expect(refused(linked) == .foreignFiles)
        #expect(refused(try framework(), check: { _ in "another team" }) == .wrongSigner("another team"))
        #expect(refused(try framework(), free: 1000) == .noSpace)
        #expect(!FileManager.default.fileExists(atPath: installed.path))
    }

    @Test func leftAndRightChangeARowAndStopAtItsEnds() {
        var got: [String] = []
        let choice = OortRow(id: "c", title: "", kind: .choice([SettingOption("a", "A"), SettingOption("b", "B")], "a") { got.append($0) })
        #expect(choice.step(1) && !choice.step(-1))
        let range = OortRow(id: "r", title: "", kind: .range(0.5...1, step: 0.05, unit: "×", "0.95") { got.append($0) })
        #expect(range.step(1))
        #expect(!OortRow(id: "r", title: "", kind: .range(0.5...1, step: 0.05, unit: "", "1.0") { _ in }).step(1))
        let toggle = OortRow(id: "t", title: "", kind: .toggle(false) { got.append("\($0)") })
        #expect(toggle.step(1) && !toggle.step(-1))
        #expect(got == ["b", "1.00", "true"])
        #expect(OortRow.number(0.5, step: 0.1) == "0.5" && OortRow.number(1, step: 1) == "1.0")
    }

    @Test func onlyTheScreenOnTopReadsTheControllerAndTheRestOpensTabs() {
        let sounds = OortSounds(defaults: TestDefaults.make("sounds"))
        sounds.isOn = false
        let nav = OortNav(sounds: sounds), below = UUID(), top = UUID()
        nav.appeared(below)
        nav.appeared(top)
        var log = ShellInputLog(), read: [ShellInput.Action] = []
        log.append(.up)
        log.append(.activate)
        log.append(.activate, released: true)
        nav.read(log, as: below) { read.append($0); return true }
        #expect(read.isEmpty)
        nav.read(log, as: top) { read.append($0); return true }
        #expect(read == [.up, .activate], "every press once, releases ignored")
        log.append(.nextTab)
        log.append(.previousTab)
        log.append(.previousTab)
        nav.read(log, as: top) { _ in false }
        #expect(nav.tab == .settings, "the tabs wrap")
        nav.open(.credits)
        log.append(.back)
        nav.read(log, as: top) { _ in false }
        #expect(nav.paths[.settings] == [] && nav.tab == .settings)
        log.append(.back)
        nav.read(log, as: top) { _ in false }
        #expect(nav.tab == .home)
    }

    @Test func aLoadFailureNamesTheSignatureOnlyWhenTheSystemDoes() {
        let damaged = OortLaunchWords.why("The game's code could not be loaded: dlopen(DmGame, 0x0005): tried: 'DmGame' (not a mach-o file)")
        let signed = OortLaunchWords.why("The game's code could not be loaded: dlopen(DmGame, 0x0005): code signature not valid for use in process")
        #expect(damaged == Oort.text("This game's code could not be loaded. Build it again on your Mac, then add it again."))
        #expect(signed != damaged)
        #expect(OortLaunchWords.why("A game is already running.") == localizeEngineLaunchError("A game is already running."))
    }

    @Test func aNoticeRunsOnAndKeepsItsLists() {
        let long = String(repeating: "word ", count: 12).trimmingCharacters(in: .whitespaces)
        #expect(NoticesScreen.flow(long + "\n  of it\n- one") == long + " of it\n- one")
        #expect(NoticesScreen.flow("Copyright (c) A\nCopyright (c) B") == "Copyright (c) A\nCopyright (c) B")
    }

    @Test func everyTextHasItsFrench() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OortMobile")
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("Resources/Localizable.xcstrings"))) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let pattern = try Regex(#"Oort\.text\("((?:[^"\\]|\\.)*)""#)
        var used = 0
        for file in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
            for match in try String(contentsOf: file, encoding: .utf8).matches(of: pattern) {
                let key = String(match.output[1].substring ?? "")
                used += 1
                guard !key.contains("\\(") else { continue }
                let fr = ((strings[key]?["localizations"] as? [String: Any])?["fr"] as? [String: Any])?["stringUnit"] as? [String: String]
                #expect(fr?["value"]?.isEmpty == false, "\(key)")
            }
        }
        #expect(used > 120)
    }

    @Test func theCloudDrawsItsSunAndNothingElseIsGold() throws {
        guard let engine = OortCloudEngine.shared else { return }
        let image = try #require(engine.snapshot(width: 480, height: 320))
        let data = try #require(image.dataProvider?.data as Data?)
        func gold(_ x: Int, _ y: Int) -> Bool {
            let i = (y * 480 + x) * 4
            return Int(data[i + 2]) - Int(data[i]) > 60
        }
        // The Sun is at 71% of the width, half the height.
        #expect(gold(Int(0.71 * 480), 160))
        var far = 0
        for y in 0..<320 { for x in 0..<480 where hypot(Double(x) - 0.71 * 480, Double(y) - 160) > 16 && gold(x, y) { far += 1 } }
        #expect(far == 0)
    }
}
