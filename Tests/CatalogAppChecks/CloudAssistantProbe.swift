import AppKit
import CoreText
import SwiftUI
import NXLibraryCore
import ArcanePorting

@main struct CloudAssistantProbe {
    /// The live assistant, captured as its body is drawn: the probe presses the same view a player would.
    @MainActor static var mounted: CloudSetupAssistant?
    @MainActor static var frames: [AnyHashable: CGRect] = [:]
    @MainActor static var tool: URL?
    @MainActor static var opened: [URL] = []

    static let names = ["Aurora Village", "Comet Racers", "Dust Pilgrim", "Eclipse Tactics", "Halo Garden", "Ion Riders", "Lunar Observatory",
                        "Meteor Kitchen", "Nebula Golf", "Orbit Garden", "Pulsar Quest", "Saturn Express"]
    static let french = AppLocale(language: .french, region: "FR")

    @MainActor static func main() async throws {
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!).resolvingSymlinksInPath().path
        precondition(URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path == home)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, .process, nil))
        NSApplication.shared.setActivationPolicy(.prohibited)
        // SwiftUI builds the tree VoiceOver reads only when an assistive client asks: the probe is that client.
        (NSApp as NSObject).perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true, with: "AXEnhancedUserInterface")
        let full = CommandLine.arguments.contains("--full")
        for (suffix, locale) in [("-fr", french)] + (full ? [("-en", AppLocale(language: .english, region: "US")), ("-de", AppLocale(language: .german, region: "DE"))] : []) {
            try await gallery(output, suffix, locale)
        }
        if full {
            for (suffix, zoom, size) in [("-fr-80", CGFloat(0.8), CGSize(width: 1920, height: 1080)), ("-fr-125", 1.25, CGSize(width: 1920, height: 1080)),
                                         ("-fr-petite", 1, CGSize(width: 1024, height: 640)), ("-fr-petite-125", 1.25, CGSize(width: 1024, height: 640))] {
                try await gallery(output, suffix, french, zoom: zoom, size: size, settings: false)
            }
        }
        L10n.setContext(french)
        try await checkBar()
        for driver in Driver.allCases {
            try await checkWholePath(driver)
            try await checkFirstTime(driver)
        }
        try await checkReconnection()
        try await checkVoiceOver()
        print("Cloud assistant: \(Driver.allCases.map(\.rawValue).joined(separator: ", ")) each reach the games alone; folders kept, created and explained.")
    }

    // MARK: - Pictures

    @MainActor static func fixture(_ connected: Bool) throws -> (AppViewModel, AppSettingsStore) {
        AppData.preferences.set(connected ? "gdrive:Games/Switch/Oort-nx" : nil, forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(connected, forKey: CloudLibraryPreference.enabledKey)
        AppData.preferences.set(connected ? "Games/Switch/Jeux" : nil, forKey: CloudLibraryPreference.sourcesRootKey)
        AppData.preferences.set(true, forKey: CloudLibraryPreference.toolChoiceKey)
        let chosen = CloudLibraryPreference.SourcesBinding(.init(storage: "gdrive:Games/Switch/Oort-nx", enabled: true, sourcesRoot: "Games/Switch/Jeux"))
        AppData.preferences.set(try JSONEncoder().encode(chosen), forKey: CloudLibraryPreference.sourcesBindingKey)
        let data = AppData.supportRoot
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings-\(connected).json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        precondition((vm.cloudLibrary.preference.remote != nil) == connected)
        return (vm, settings)
    }

    @MainActor static func gallery(_ output: URL, _ suffix: String, _ locale: AppLocale, zoom: CGFloat = 1,
                                   size: CGSize = .init(width: 1920, height: 1080), settings drawsSettings: Bool = true) async throws {
        L10n.setContext(locale)
        tool = nil
        for connected in [false, true] {
            let (vm, settings) = try fixture(connected)
            let model = vm.cloudLibrary
            if connected { model.connectionCheck = .init(date: Date(timeIntervalSince1970: 1_795_000_000), failure: nil); model.screenKnown() }
            for advanced in drawsSettings ? [false, true] : [] {
                let picture = CGSize(width: 1200, height: advanced ? 1460 : 1080)
                try save("reglages-\(connected ? "connecte" : "non-connecte")\(advanced ? "-avance" : "")\(suffix)", output,
                    Host(SettingsCloudLibrarySection(viewModel: vm, model: model, settings: SettingsEditor(settings),
                        advanced: .constant(advanced), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
                        .screenReady(connected)
                        .padding(SeleneTokens.Space.section)
                        .frame(width: SeleneTokens.Space.settingsMeasure).frame(maxHeight: .infinity, alignment: .top),
                        size: picture, canvas: .init(size: .init(width: 1920, height: 1080)), locale: locale))
            }
            let rom = (0..<12).map { "Games/Switch/Jeux/\(names[$0]) [01000000000\(String(format: "%05X", 0x1000 + $0 * 0x2000))]/Base.nsp" }
            let own = ["Games/Switch/", "Games/Switch/Oort-nx/", "Games/Switch/Oort-nx/Lunar Observatory [010000000000D000]/",
                       "Games/Switch/Oort-nx/Lunar Observatory [010000000000D000]/manifests/", "Games/Switch/Archives/", "Games/Switch/Jeux/"]
            let kept = CloudKeptFolders(account: "account", library: "Games/Switch/Oort-nx", sources: "Games/Switch/Jeux")
            let found = try CloudFolderDiscovery.screenFixture(own + rom, kept: connected ? kept : nil)
            let none = try CloudFolderDiscovery.screenFixture([], kept: nil)
            let romOnly = try CloudFolderDiscovery.screenFixture(["Games/Switch/", "Games/Switch/Jeux/"] + rom, kept: nil)
            precondition(romOnly.newLibrary == "Games/Switch/Oort-nx" && none.newLibrary == "Games/Switch/Jeux")
            func assistant(_ entry: CloudSetupAssistant.Entry = .account) -> CloudSetupAssistant {
                CloudSetupAssistant(viewModel: vm, model: model, entry: entry) {}
            }
            func picture(_ name: String, _ view: CloudSetupAssistant) throws {
                try save(name + suffix, output, Host(view.screenStill(), size: size, canvas: .init(size: size, zoom: zoom), locale: locale))
            }
            if connected {
                let keep = try assistant(.credentials).screenAccount(.choose, existing: true)
                precondition(keep.focusedTarget == .primary)
                try picture("compte-garder", keep)
                try picture("dossiers-gardes", assistant(.credentials).screenFolders(found, onboarding: false))
                let swapped = assistant(.credentials).screenFolders(found, onboarding: false, swapped: true)
                precondition(swapped.focusedTarget == .swap && swapped.focusRows.last == [.cancel, .keep, .swap], "Swapping is the way forward")
                try picture("dossiers-inverses", swapped)
                try picture("navigateur-rom", assistant(.credentials).screenBrowser(found, .sources, "Games/Switch", ["Archives", "Jeux", "Oort-nx"]))
                try picture("navigateur-mauvais", assistant(.credentials).screenBrowser(found, .sources, "Games/Switch/Oort-nx", ["Lunar Observatory [010000000000D000]"]))
                let doubt = assistant(.credentials).screenDoubt(found, .sources, "Games/Switch/Oort-nx")
                precondition(doubt.focusRows == [[.cancel, .keep, .accept(.sources)]] && doubt.focusedTarget == .accept(.sources))
                try picture("mauvais-dossier", doubt)
                try picture("pret", assistant(.credentials).screenReady(found, verified: true))
                try picture("pret-verification", assistant(.credentials).screenReady(found, verified: false, working: true))
                let move = assistant(.library).screenMove(try plan())
                precondition(move.focusRows == [[.cancel, .confirmMove]] && move.focusedTarget == .cancel, "Moving games is never the lit key")
                try picture("deplacer", move)
                precondition(assistant(.sources).browsing == .sources && assistant(.sources).focusRail.isEmpty, "Change opens the browser at once")
                precondition(assistant(.library).browsing == .library)
            } else {
                let first = try assistant().screenAccount(.choose, existing: false)
                precondition(first.focusedTarget == .haveClient && !first.showsPrimary, "The first useful choice is lit")
                try picture("compte-choix", first)
                let have = try assistant().screenAccount(.have, existing: false)
                precondition(!have.primaryEnabled && have.focusedTarget == .client)
                try picture("compte-identifiant", have)
                let typed = try assistant().screenAccount(.have, existing: false, client: "1234-fixture.apps.googleusercontent.com", secret: "fixture-only")
                precondition(typed.primaryEnabled)
                try picture("compte-identifiant-valide", typed)
                try picture("compte-identifiant-faux", try assistant().screenAccount(.have, existing: false, client: "1234"))
                try picture("compte-aide", try assistant().screenAccount(.help, existing: false))
                try picture("compte-navigateur", try assistant().screenWaiting())
                try picture("dossiers-recherche", try assistant().screenWaiting(folders: true))
                let seen = assistant().screenFolders(found, onboarding: true)
                precondition(seen.focusedTarget == .primary && seen.sourcesOverride == "Games/Switch/Jeux")
                try picture("dossiers-trouves", seen)
                let empty = assistant().screenFolders(none, onboarding: true, creates: true)
                precondition(empty.focusedTarget == .primary, "Nothing to know: Continue offers Oort's own folders")
                try picture("dossiers-rien", empty)
                try picture("dossiers-rom-seules", assistant().screenFolders(romOnly, onboarding: true, creates: true))
                let create = assistant().screenFolders(none, onboarding: true, creates: true, confirming: true)
                precondition(create.focusRows == [[.cancel, .create]] && create.focusedTarget == .create)
                try picture("dossiers-creer", create)
            }
        }
    }

    static func plan() throws -> CloudDriveFolders.MovePlan {
        let key = "0100000000001000/app/" + String(repeating: "a", count: 64) + ".aar"
        return try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: Data(
            #"{"source":"Games","remote":"gdrive","games":1,"bytes":1000,"entries":[{"file":{"key":{"value":"\#(key)"},"size":1000,"hashes":{"md5":"c4ca4238a0b923820dcc509a6f75849b"}},"dependencies":[]}]}"#.utf8))
    }

    @MainActor static func save(_ name: String, _ output: URL, _ host: Host) throws {
        host.settle(0.35)
        try host.picture().write(to: output.appendingPathComponent(name + ".png"))
    }

    @MainActor final class Host {
        let view: NSHostingView<AnyView>
        let window: NSWindow
        let size: CGSize

        init<V: View>(_ content: V, size: CGSize, canvas: SeleneCanvas, locale: AppLocale) {
            self.size = size
            view = NSHostingView(rootView: AnyView(content.frame(width: size.width, height: size.height)
                .background(Color(red: 0.09, green: 0.13, blue: 0.20))
                .environment(\.colorScheme, .dark).environment(\.seleneCanvas, canvas)
                .environment(\.nxAppLocale, locale).environment(\.seleneReduceMotion, true)))
            view.frame.size = size
            window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.layoutIfNeeded()
        }

        func settle(_ seconds: Double = 0.05) {
            let end = Date().addingTimeInterval(seconds)
            repeat {
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: min(end, .now.addingTimeInterval(0.01)))
            } while Date() < end
        }

        func picture() throws -> Data {
            precondition(!window.isVisible)
            guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: image)
            return image.representation(using: .png, properties: [:])!
        }

        func close() { window.contentView = nil; window.close() }
    }

    // MARK: - The bar

    /// What is drawn is in the agreed order: erase, back, others, forward.
    @MainActor static func checkBar() async throws {
        func action(_ title: String, _ role: ActionBarRole) -> OortActionBar.Action { .init(id: AnyHashable(title), title: title, role: role) {} }
        for width in [1100.0, 420] {
            frames = [:]
            let host = Host(OortActionBar(actions: [action("Forward", .primary), action("Back", .back), action("Other", .secondary), action("Erase", .destructive)],
                                          focused: AnyHashable("Forward"), onFocus: { _ in }).padding(), size: .init(width: width, height: 260),
                            canvas: .init(size: .init(width: 1920, height: 1080)), locale: french)
            host.settle(0.2)
            let x = ["Erase", "Back", "Other", "Forward"].map { frames[AnyHashable($0)]!.midX }
            precondition(x[0] < x[1] && x[2] < x[3], "Order in \(width): \(x)")
            precondition(x[1] < x[3], "Back is left of the way forward")
            let forward = frames[AnyHashable("Forward")]!, erase = frames[AnyHashable("Erase")]!
            precondition(abs(forward.maxX - (width - 16)) < 4 && abs(erase.minX - 16) < 4, "The ends are used: \(forward) \(erase)")
            host.close()
        }
    }

    // MARK: - One way at a time

    enum Driver: String, CaseIterable { case keyboard, mouse, controller }

    @MainActor final class Session {
        let vm: AppViewModel
        let router = AppRouter()
        let host: Host
        let driver: Driver
        var closed = false
        var presses = 0

        init(_ driver: Driver, entry: CloudSetupAssistant.Entry = .account, vm: AppViewModel) {
            self.driver = driver
            self.vm = vm
            vm.router = router
            mounted = nil
            frames = [:]
            let done = Box()
            let size = CGSize(width: 1920, height: 1080)
            host = Host(AssistantHost(box: done, make: { close in
                CloudSetupAssistant(viewModel: vm, model: vm.cloudLibrary, entry: entry, onClose: close)
            }), size: size, canvas: .init(size: size), locale: french)
            box = done
            host.settle(0.1)
        }
        private let box: Box
        var isClosed: Bool { box.closed }
        var view: CloudSetupAssistant { CloudAssistantProbe.mounted! }

        func wait(_ what: String, _ condition: (CloudSetupAssistant) -> Bool) async throws {
            let deadline = Date().addingTimeInterval(25)
            while Date() < deadline {
                host.settle(0.02)
                try await Task.sleep(for: .milliseconds(15))
                if isClosed || condition(view) { host.settle(0.05); return }
            }
            preconditionFailure("\(driver.rawValue): \(what) never came. Step \(view.draft.step), work \(String(describing: view.work?.kind)), issue \(view.issue ?? "-"), rows \(view.focusRows)")
        }

        func press(_ target: CloudSetupAssistant.Target) {
            presses += 1
            switch driver {
            case .mouse: click(target)
            case .keyboard:
                reach(target) { key(48) }
                key(presses.isMultiple(of: 2) ? 36 : 49) // Return and Space both press what is lit.
            case .controller:
                travel(to: target)
                post(.confirm)
            }
            host.settle(0.08)
        }

        func back() {
            switch driver {
            case .mouse: click(.cancel)
            case .keyboard: key(53)
            case .controller: post(.cancel)
            }
            host.settle(0.08)
        }

        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], typing: Bool = false) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            precondition(view.handleKey(event, typing: typing))
            host.settle(0.03)
        }

        func post(_ action: GamepadAction) {
            NotificationCenter.default.post(name: .nxSettingsGamepadAction, object: action)
            host.settle(0.03)
        }

        private func reach(_ target: CloudSetupAssistant.Target, _ step: () -> Void) {
            let count = view.focusRows.joined().count + view.focusRail.count + 1
            for _ in 0..<count where view.focusedTarget != target { step() }
            precondition(view.focusedTarget == target, "\(driver.rawValue) cannot reach \(target) among \(view.focusRows) \(view.focusRail)")
        }

        /// Directions only, as a pad has them.
        private func travel(to target: CloudSetupAssistant.Target) {
            if view.focusRail.contains(target) {
                for _ in 0..<8 where !view.focusRail.contains(view.focusedTarget) { post(.navigateLeft) }
                reach(target) { post(.navigateUp) }
                return
            }
            for _ in 0..<40 where view.focusedTarget != target {
                let rows = view.focusRows
                guard let to = rows.firstIndex(where: { $0.contains(target) }) else { break }
                guard let from = rows.firstIndex(where: { $0.contains(view.focusedTarget) }) else { post(.navigateRight); continue }
                if from != to { post(from < to ? .navigateDown : .navigateUp) }
                else { post(rows[to].firstIndex(of: view.focusedTarget)! < rows[to].firstIndex(of: target)! ? .navigateRight : .navigateLeft) }
            }
            precondition(view.focusedTarget == target, "The pad cannot reach \(target) from \(view.focusedTarget) among \(view.focusRows)")
        }

        /// A hidden window receives no pointer events. What lies under the pointer is found by a hit test, as a click would,
        /// must be the control drawn there with nothing over it, and is pressed.
        func click(_ target: CloudSetupAssistant.Target) {
            guard let frame = CloudAssistantProbe.frames[AnyHashable(target)] else { preconditionFailure("Nothing to click for \(target)") }
            precondition(host.view.bounds.contains(frame.insetBy(dx: 1, dy: 1)), "\(target) is off the stage: \(frame)")
            precondition(min(frame.width, frame.height) >= 28, "\(target) is too small to click: \(frame)")
            let under = element(at: CGPoint(x: frame.midX, y: frame.midY))
            let role = under.flatMap { Spoken($0).role } ?? "-"
            if [.client, .secret, .folderName, .typedPath].contains(target) {
                precondition(role == "AXTextField", "\(target): \(role) is under the pointer")
                return
            }
            precondition(role == "AXButton", "\(target): \(role) is under the pointer at \(frame)")
            precondition(Spoken(under!).press(), "\(target) cannot be pressed")
            host.settle(0.05)
        }

        private func element(at point: CGPoint) -> NSObject? {
            let inWindow = NSPoint(x: point.x, y: host.size.height - point.y)
            return host.view.accessibilityHitTest(host.window.convertPoint(toScreen: inWindow)) as? NSObject
        }

        /// Types into the real field, whichever way it was reached.
        func type(_ text: String, into target: CloudSetupAssistant.Target, secret: Bool) {
            if driver == .mouse { click(target) } else if driver == .keyboard { reach(target) { key(48, typing: true) } } else { travel(to: target) }
            precondition(driver == .mouse || view.focusedTarget == target)
            func fields(_ view: NSView) -> [NSTextField] { (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields) }
            let all = fields(host.view).filter(\.isEditable).sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
            guard let field = all.first(where: { ($0 is NSSecureTextField) == secret }) else { preconditionFailure("No field for \(target)") }
            precondition(host.window.makeFirstResponder(field))
            (host.window.firstResponder as! NSTextView).insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            host.settle(0.1)
        }

        func end() { host.close(); mounted = nil }
    }

    final class Box { var closed = false }
    struct AssistantHost: View {
        let box: Box
        let make: (@escaping () -> Void) -> CloudSetupAssistant
        @State private var shown = true
        var body: some View { ZStack { if shown { make { box.closed = true; shown = false } } } }
    }

    @MainActor static func drive(_ name: String, empty: Bool = false, _ entries: [String]) throws -> URL {
        let root = AppData.supportRoot.appendingPathComponent("drive-\(name)-\(UUID().uuidString.prefix(6))")
        let files = root.appendingPathComponent("drive"), log = root.appendingPathComponent("log")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try Data().write(to: log)
        for entry in entries {
            let url = files.appendingPathComponent(entry)
            if entry.hasSuffix("/") { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
        let config = root.appendingPathComponent("rclone.conf")
        try Data("# Encrypted rclone configuration File\n".utf8).write(to: config)
        let script = root.appendingPathComponent("rclone")
        let fake = ProcessInfo.processInfo.environment["OORT_FAKE_RCLONE"]!
        try Data("#!/bin/sh\nFAKE_REMOTE=gdrive FAKE_CONFIG='\(config.path)' \(empty ? "FAKE_EMPTY=1" : "") FAKE_DRIVE='\(files.path)' FAKE_LOG='\(log.path)' FAKE_DELAY=0.01 exec /usr/bin/python3 '\(fake)' \"$@\"\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        tool = script
        return root
    }

    static func rom(_ index: Int, in folder: String) -> String {
        "\(folder)/\(names[index]) [01000000000\(String(format: "%05X", 0x1000 + index * 0x2000))]/Base.nsp"
    }

    @MainActor static func freshPreferences() {
        for key in [CloudLibraryPreference.storageKey, CloudLibraryPreference.sourcesRootKey, CloudLibraryPreference.enabledKey, CloudLibraryPreference.sourcesBindingKey,
                    CloudKeptFolders.preferenceKey, CloudRecentFolders.preferenceKey, "NXLibrary_CloudDriveScope"] { AppData.preferences.removeObject(forKey: key) }
        AppData.preferences.set(true, forKey: CloudLibraryPreference.toolChoiceKey)
    }

    @MainActor static func model() -> AppViewModel {
        let data = AppData.supportRoot.appendingPathComponent(UUID().uuidString)
        return AppViewModel(settingsStore: .init(fileURL: data.appendingPathComponent("settings.json")), catalog: .init(), repository: .init(store: .init(directory: data)))
    }

    /// An account already connected: look in the browser, take a wrong folder, be told, come back, go on to the games.
    @MainActor static func checkWholePath(_ driver: Driver) async throws {
        freshPreferences()
        let root = try drive("whole", (0..<3).map { rom($0, in: "Games/Switch/Jeux") } + ["Games/Switch/Archives/", "Photos/Summer/"])
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = model(), session = Session(driver, vm: vm)
        try await session.wait("the account") { $0.remotes != nil && $0.work == nil }
        precondition(session.view.focusedTarget == .primary)
        session.press(.primary)
        try await session.wait("both folders") { $0.draft.step == .folder && $0.work == nil }
        precondition(session.view.sources?.path == "Games/Switch/Jeux" && session.view.sources?.games == 3)
        precondition(session.view.library == nil && session.view.newLibrary?.path == "Games/Switch/Oort-nx", "Jeux holds ROMs: never proposed")

        session.press(.change(.sources))
        try await session.wait("the browser") { $0.browsing == .sources && $0.listing != nil && $0.work == nil }
        session.press(.breadcrumb("Games/Switch"))
        try await session.wait("Games/Switch") { $0.browserPath == "Games/Switch" && $0.listing != nil && $0.work == nil }
        session.press(.folder("Archives"))
        try await session.wait("Archives") { $0.browserPath == "Games/Switch/Archives" && $0.listing != nil && $0.work == nil }
        session.press(.primary)
        precondition(session.view.doubt?.advice.reason == .nothingHere, "A wrong folder is explained")
        precondition(session.view.focusedTarget == .accept(.sources))
        session.back()
        precondition(session.view.doubt == nil && session.view.browsing == .sources, "Escape answers no")
        session.press(.breadcrumb(""))
        try await session.wait("My Drive") { $0.browserPath.isEmpty && $0.listing != nil && $0.work == nil }
        session.press(.refresh)
        try await session.wait("the refresh") { $0.listing != nil && $0.work == nil && $0.index != nil }
        session.press(.folder("Games"))
        try await session.wait("Games") { $0.browserPath == "Games" && $0.listing != nil && $0.work == nil }
        session.press(.primary)
        precondition(session.view.doubt?.advice.reason == .further && session.view.doubt?.advice.instead == "Games/Switch/Jeux")
        session.press(.accept(.sources))
        precondition(session.view.browsing == nil && session.view.sources?.path == "Games/Switch/Jeux" && session.view.sources?.games == 3)
        session.press(.change(.sources))
        try await session.wait("the browser again") { $0.listing != nil && $0.work == nil }
        precondition(CloudRecentFolders.load(for: "gdrive") == ["Games/Switch/Jeux"])
        session.back()
        precondition(session.view.browsing == nil)
        if driver != .keyboard || session.view.focusRail.contains(.step(0)) {
            session.press(.step(0))
            precondition(session.view.draft.step == .account, "A step done opens again")
            session.press(.primary)
            try await session.wait("the folders again") { $0.draft.step == .folder && $0.work == nil && $0.newLibrary != nil }
        }
        session.press(.primary)
        precondition(session.view.confirmingNew && session.view.focusedTarget == .create, "Creating is asked")
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("drive/Games/Switch/Oort-nx").path), "Nothing is created before the answer")
        session.press(.create)
        try await session.wait("the check") { $0.draft.step == .verify && $0.draft.verified && $0.work == nil }
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent("drive/Games/Switch/Oort-nx").path))
        precondition(session.view.focusedTarget == .primary)
        precondition(vm.cloudLibrary.preference.remote == nil, "Nothing is saved before the last key")
        session.press(.primary)
        precondition(session.isClosed)
        let saved = vm.cloudLibrary.preference
        precondition(saved.remote == "gdrive" && saved.root == "Games/Switch/Oort-nx" && saved.sourcesRoot == "Games/Switch/Jeux" && saved.enabled)
        precondition(session.router.route == .collection && vm.librarySelection.query.filter == .cloud, "See my games opens the cloud shelf")
        session.end()
    }

    /// Nothing known: sign in, then three presses.
    @MainActor static func checkFirstTime(_ driver: Driver) async throws {
        freshPreferences()
        let root = try drive("first", empty: true, ["Photos/"])
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = model(), session = Session(driver, vm: vm)
        try await session.wait("the account") { $0.remotes != nil && $0.work == nil }
        precondition(session.view.focusedTarget == .haveClient, "Never Cancel first")
        session.press(.helpCreate)
        precondition(session.view.accountPage == .help)
        opened = []
        session.press(.link(4))
        precondition(opened.count == 1 && opened[0].host == "console.cloud.google.com", "Each step opens its own page")
        session.back()
        precondition(session.view.accountPage == .choose)
        session.press(.haveClient)
        precondition(session.view.accountPage == .have)
        session.type("not-an-id", into: .client, secret: false)
        precondition(!session.view.validID && !session.view.primaryEnabled)
        session.type("1234-fixture.apps.googleusercontent.com", into: .client, secret: false)
        precondition(session.view.validID, "The ID is checked while typing: \(session.view.client)")
        session.type("fixture-only", into: .secret, secret: true)
        precondition(session.view.validSecret && session.view.primaryEnabled)
        session.press(.primary)
        try await session.wait("the folders") { $0.draft.step == .folder && $0.work == nil && $0.newLibrary != nil && $0.newSources != nil }
        precondition(session.view.secret.isEmpty, "The secret is not kept")
        let before = session.presses
        session.press(.primary)
        session.press(.create)
        try await session.wait("the check") { $0.draft.verified && $0.work == nil }
        session.press(.primary)
        precondition(session.isClosed && session.presses - before == 3, "Three presses after signing in")
        let saved = vm.cloudLibrary.preference
        precondition(saved.root == "Games/Switch/Jeux" && saved.sourcesRoot == "Games/Switch/ROM", "\(saved)")
        let log = try String(contentsOf: root.appendingPathComponent("log"), encoding: .utf8)
        precondition(!log.contains("fixture-only") && !log.contains("1234-fixture"), "No credential in a command")
        session.end()
    }

    /// The maintainer's own mishap: disconnect, reconnect, and the ROM folder is still theirs.
    @MainActor static func checkReconnection() async throws {
        freshPreferences()
        let root = try drive("again", (0..<2).map { rom($0, in: "Games/ROM de Sofian") } + (2..<8).map { rom($0, in: "Games/Switch/Oort-nx/GameFiles") })
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = model(), cloud = vm.cloudLibrary
        cloud.configure(remote: "gdrive", root: "Games/Switch/Oort-nx", enabled: true, sourcesRoot: "Games/ROM de Sofian")
        let deadline = Date().addingTimeInterval(20)
        while cloud.driveScope == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        precondition(cloud.driveScope?.account == "account")
        cloud.keepFolders()
        cloud.configure(remote: nil, root: cloud.preference.root, enabled: false, sourcesRoot: cloud.preference.sourcesRootOverride)
        precondition(cloud.preference.remote == nil)
        for (account, expected) in [("account", "Games/ROM de Sofian"), ("another", "Games/Switch/Oort-nx/GameFiles")] {
            AppData.preferences.set(try JSONEncoder().encode(CloudKeptFolders(account: account, library: "Games/Switch/Oort-nx", sources: "Games/ROM de Sofian")),
                                    forKey: CloudKeptFolders.preferenceKey)
            let session = Session(.controller, vm: vm)
            try await session.wait("the account") { $0.remotes != nil && $0.work == nil }
            session.press(.primary)
            try await session.wait("the folders") { $0.draft.step == .folder && $0.work == nil }
            precondition(session.view.sources?.path == expected, "\(account): \(session.view.sources?.path ?? "-")")
            session.end()
        }
    }

    /// An element as VoiceOver meets it. SwiftUI's nodes answer the accessibility selectors without the Swift protocol.
    @MainActor struct Spoken {
        let object: NSObject
        init(_ object: NSObject) { self.object = object }
        private func value(_ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }
        var role: String? { value("accessibilityRole") as? String }
        var label: String { (value("accessibilityLabel") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (value("accessibilityTitle") as? String) ?? "" }
        var text: String { (value("accessibilityValue") as? String) ?? "" }
        var isEnabled: Bool { (value("accessibilityEnabled") as? Bool) ?? true }
        var children: [Spoken] { ((value("accessibilityChildren") as? [NSObject]) ?? []).map(Spoken.init) }
        var all: [Spoken] { [self] + children.flatMap(\.all) }
        func press() -> Bool {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            guard isEnabled, object.responds(to: selector) else { return false }
            typealias Press = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(object.method(for: selector), to: Press.self)(object, selector)
        }
    }

    /// Every control has a name, and the questions, folders and states are spoken.
    @MainActor static func checkVoiceOver() async throws {
        freshPreferences()
        let root = try drive("voice", (0..<3).map { rom($0, in: "Games/Switch/Jeux") })
        defer { try? FileManager.default.removeItem(at: root) }
        let session = Session(.keyboard, vm: model())
        func check(_ page: String, _ wanted: [String]) {
            let all = Spoken(session.host.view).all
            let controls = all.filter { ["AXButton", "AXTextField"].contains($0.role ?? "") }
            precondition(!controls.isEmpty, "\(page): VoiceOver finds no control")
            for control in controls { precondition(!control.label.isEmpty, "\(page): a \(control.role!) has no name, value \(control.text)") }
            let spoken = all.map { $0.label + " " + $0.text }.joined(separator: "\n")
            for text in wanted { precondition(spoken.contains(text), "\(page): “\(text)” is not spoken in\n\(spoken)") }
            precondition(!spoken.lowercased().contains("rclone") && !spoken.contains("GameFiles"), "\(page): a technical word is spoken")
        }
        try await session.wait("the account") { $0.remotes != nil && $0.work == nil }
        check("account", ["Connecte ton Google Drive", "Étape 1 sur 3", "Garder ce compte", "J’ai un identifiant", "Annuler"])
        session.press(.haveClient)
        check("client", ["Identifiant Google", "Secret Google", "Se connecter", "Retour"])
        session.back()
        session.press(.primary)
        try await session.wait("the folders") { $0.draft.step == .folder && $0.work == nil && $0.newLibrary != nil }
        check("folders", ["Où sont tes ROM ?", "Où ranger tes jeux ?", "3 jeux trouvés", "Changer · Où sont tes ROM ?", "Continuer"])
        session.press(.change(.sources))
        try await session.wait("the browser") { $0.listing != nil && $0.work == nil }
        session.press(.breadcrumb("Games/Switch"))
        try await session.wait("Switch") { $0.browserPath == "Games/Switch" && $0.listing != nil && $0.work == nil }
        check("browser", ["Mon Drive", "Jeux", "3 jeux", "Choisir ce dossier", "Nouveau dossier"])
        session.press(.primary)
        check("question", ["Où sont tes ROM ?", "Utiliser le dossier « Jeux »", "Garder ce dossier", "Annuler"])
        session.back(); session.back()
        session.press(.primary)
        check("creation", ["Créer ce dossier ?", "Games › Switch › Oort-nx", "Annuler", "Créer"])
        session.press(.create)
        try await session.wait("ready") { $0.draft.verified && $0.work == nil }
        check("ready", ["Bibliothèque de ROM", "Bibliothèque de jeux", "3 jeux à compiler", "Voir mes jeux"])
        session.end()
    }
}

struct ProbeFrame: ViewModifier {
    let id: AnyHashable
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { CloudAssistantProbe.frames[id] = $0 }
    }
}
