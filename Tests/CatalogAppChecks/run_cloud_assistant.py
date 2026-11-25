#!/usr/bin/env python3
"""Render the cloud settings and the setup panel in hidden windows, with synthetic folders. No rclone, Drive or profile.

  run_cloud_assistant.py [OUTPUT] [--before REV]    --before renders the screens of an older revision that still exist
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from run_cloud_screens import ROOT, change, isolate_startup

HOST = r'''
import AppKit
import CoreText
import SwiftUI
import NXLibraryCore
import ArcanePorting

@main struct CloudAssistantProbe {
    @MainActor static func main() async throws {
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!).resolvingSymlinksInPath().path
        precondition(URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path == home)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, .process, nil))
        NSApplication.shared.setActivationPolicy(.prohibited)
        for (suffix, locale) in LOCALES {
            L10n.setContext(locale)
            for connected in [false, true] {
                AppData.preferences.set(connected ? "gdrive:Games/Switch/Oort-nx" : nil, forKey: CloudLibraryPreference.storageKey)
                AppData.preferences.set(connected, forKey: CloudLibraryPreference.enabledKey)
                AppData.preferences.set(connected ? "Games/Switch/Jeux" : nil, forKey: CloudLibraryPreference.sourcesRootKey)
                let chosen = CloudLibraryPreference.SourcesBinding(.init(storage: "gdrive:Games/Switch/Oort-nx", enabled: true, sourcesRoot: "Games/Switch/Jeux"))
                AppData.preferences.set(try JSONEncoder().encode(chosen), forKey: CloudLibraryPreference.sourcesBindingKey)
                let data = AppData.supportRoot
                let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings-\(connected).json"))
                let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
                let model = vm.cloudLibrary
                precondition((model.preference.remote != nil) == connected)
                if connected { model.connectionCheck = .init(date: Date(timeIntervalSince1970: 1_795_000_000), failure: nil); model.screenKnown() }
                for advanced in [false, true] {
                    try render("reglages-\(connected ? "connecte" : "non-connecte")\(advanced ? "-avance" : "")\(suffix)", output, locale,
                        SettingsCloudLibrarySection(viewModel: vm, model: model, settings: SettingsEditor(settings),
                            advanced: .constant(advanced), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
                            .screenReady(connected)
                            .padding(SeleneTokens.Space.section)
                            .frame(width: SeleneTokens.Space.settingsMeasure).frame(maxHeight: .infinity, alignment: .top),
                        size: .init(width: 1200, height: advanced ? 1460 : 1080))
                }
                try await screens(vm, model, connected, output, suffix, locale)
            }
        }
    }

    @MainActor static func screens(_ vm: AppViewModel, _ model: CloudLibraryModel, _ connected: Bool, _ output: URL,
                                   _ suffix: String, _ locale: AppLocale) async throws {
        // SCREENS
    }

    @MainActor static func render<V: View>(_ name: String, _ output: URL, _ locale: AppLocale, _ view: V,
                                          size: CGSize = .init(width: 1920, height: 1080)) throws {
        let canvas = SeleneCanvas(size: .init(width: 1920, height: 1080))
        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)
            .background(Color(red: 0.09, green: 0.13, blue: 0.20))
            .environment(\.colorScheme, .dark).environment(\.seleneCanvas, canvas)
            .environment(\.nxAppLocale, locale).environment(\.seleneReduceMotion, true)))
        host.frame.size = size
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded()
        let end = Date().addingTimeInterval(0.6)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: min(end, .now.addingTimeInterval(0.02)))
        } while Date() < end
        precondition(!window.isVisible)
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
    }
}
'''

AFTER = r'''
        let rom = (0..<12).map { "Games/Switch/Jeux/\(Self.names[$0]) [01000000000\(String(format: "%05X", 0x1000 + $0 * 0x2000))]/Base.nsp" }
        let own = ["Games/Switch/Oort-nx/", "Games/Switch/Oort-nx/Lunar Observatory [0100000000001000]/", "Games/Switch/Oort-nx/Lunar Observatory [0100000000001000]/manifests/",
                   "Games/Switch/", "Games/Switch/Archives/", "Games/Switch/Jeux/"]
        let kept = CloudKeptFolders(account: "account", library: "Games/Switch/Oort-nx", sources: "Games/Switch/Jeux")
        let found = try CloudFolderDiscovery.screenFixture(own + rom, kept: connected ? kept : nil)
        let none = try CloudFolderDiscovery.screenFixture([], kept: nil)
        let romOnly = try CloudFolderDiscovery.screenFixture(["Games/Switch/", "Games/Switch/Jeux/"] + rom, kept: nil)
        func assistant(_ entry: CloudSetupAssistant.Entry = .account) -> CloudSetupAssistant {
            CloudSetupAssistant(viewModel: vm, model: model, entry: entry) {}
        }
        func save(_ name: String, _ view: CloudSetupAssistant) throws { try render(name + suffix, output, locale, view) }
        if connected {
            try save("compte-garder", try assistant(.credentials).screenAccount(.choose, existing: true))
            try save("dossiers-gardes", assistant(.credentials).screenFolders(found, onboarding: false))
            try save("dossiers-inverses", assistant(.credentials).screenFolders(found, onboarding: false, swapped: true))
            try save("navigateur-rom", assistant(.credentials).screenBrowser(found, .sources, "Games/Switch", ["Archives", "Jeux", "Oort-nx"]))
            try save("navigateur-mauvais", assistant(.credentials).screenBrowser(found, .sources, "Games/Switch/Oort-nx", ["Lunar Observatory [0100000000001000]"]))
            try save("mauvais-dossier", assistant(.credentials).screenDoubt(found, .sources, "Games/Switch/Oort-nx"))
            var direct = CloudSetupAssistant(viewModel: vm, model: model, entry: .sources) {}
            precondition(direct.browsing == .sources && direct.focusRail.isEmpty, "Change opens the browser at once")
            direct = assistant(.library)
            precondition(direct.browsing == .library)
            let right = assistant(.credentials).screenFolders(found, onboarding: false)
            precondition(right.primaryEnabled && right.focusedTarget == .primary, "Folders found: Continue is the first key")
            precondition(right.advice(.sources, "Games/Switch/Jeux") == nil)
        } else {
            let first = try assistant().screenAccount(.choose, existing: false)
            precondition(first.focusRows.first == [.haveClient] && !first.showsPrimary)
            try save("compte-choix", first)
            let have = try assistant().screenAccount(.have, existing: false)
            precondition(!have.primaryEnabled)
            try save("compte-identifiant", have)
            let typed = try assistant().screenAccount(.have, existing: false, client: "1234-fixture.apps.googleusercontent.com", secret: "fixture-only")
            precondition(typed.primaryEnabled)
            try save("compte-identifiant-valide", typed)
            try save("compte-identifiant-faux", try assistant().screenAccount(.have, existing: false, client: "1234"))
            try save("compte-aide", try assistant().screenAccount(.help, existing: false))
            try save("compte-navigateur", try assistant().screenWaiting())
            try save("dossiers-recherche", try assistant().screenWaiting(folders: true))
            let seen = assistant().screenFolders(found, onboarding: true)
            precondition(seen.primaryEnabled && seen.sourcesOverride == "Games/Switch/Jeux")
            try save("dossiers-trouves", seen)
            let empty = assistant().screenFolders(none, onboarding: true, creates: true)
            precondition(empty.primaryEnabled, "Nothing to know: Continue offers Oort's own folder")
            try save("dossiers-rien", empty)
            try save("dossiers-rom-seules", assistant().screenFolders(romOnly, onboarding: true, creates: true))
            try save("dossiers-creer", assistant().screenFolders(none, onboarding: true, creates: true, confirming: true))
        }
    }

    static let names = ["Aurora Village", "Comet Racers", "Dust Pilgrim", "Eclipse Tactics", "Halo Garden", "Ion Riders", "Lunar Observatory",
                        "Meteor Kitchen", "Nebula Golf", "Orbit Garden", "Pulsar Quest", "Saturn Express"]

    @MainActor static func unused() {
'''

BEFORE = r'''
        func assistant(_ entry: CloudSetupAssistant.Entry = .account) -> CloudSetupAssistant {
            CloudSetupAssistant(viewModel: vm, model: model, entry: entry) {}
        }
        if connected {
            try render("compte-garder" + suffix, output, locale, try assistant().screenAccount(existing: true))
            try render("dossiers" + suffix, output, locale, assistant(.library).screenFolder("Games/Switch", false))
            try render("dossier-rom" + suffix, output, locale, assistant(.sources).screenFolder("Games/Switch", true))
        } else {
            try render("compte-identifiant" + suffix, output, locale, try assistant().screenAccount(existing: false))
        }
'''

AFTER_STATE = '''
extension CloudSetupAssistant {
    private func base(_ page: AccountPage, existing: Bool) throws -> Self {
        var view = self
        view._tool = State(initialValue: URL(fileURLWithPath: "/fixture/tool"))
        view._remotes = State(initialValue: try JSONDecoder().decode([RcloneRemote].self, from: Data(existing
            ? #"[{"name":"gdrive","type":"drive","source":"file"}]"#.utf8 : "[]".utf8)))
        view._accountPage = State(initialValue: page)
        // Where opening the page puts the focus.
        var focus = CloudSetupAssistantFocus()
        if page != .choose { focus.select(page == .have ? .client : .link(0)) }
        view._focus = State(initialValue: focus)
        return view
    }
    func screenAccount(_ page: AccountPage, existing: Bool, client: String = "", secret: String = "") throws -> Self {
        var view = try base(page, existing: existing)
        view._client = State(initialValue: client)
        view._secret = State(initialValue: secret)
        return view
    }
    func screenWaiting(folders: Bool = false) throws -> Self {
        var view = try base(.have, existing: false)
        if folders {
            var draft = CloudSetupAssistantDraft()
            draft.chooseAccount("gdrive")
            view._draft = State(initialValue: draft)
        }
        view._work = State(initialValue: (UUID(), folders ? .discover : .connect, Task {}))
        return view
    }
    func screenFolders(_ found: CloudFolderDiscovery, onboarding: Bool, swapped: Bool = false, creates: Bool = false,
                       confirming: Bool = false) -> Self {
        var view = self
        func choice(_ folder: CloudFolderDiscovery.Folder?) -> Choice? {
            folder.map { .init(path: $0.path, games: $0.games, names: $0.names, origin: onboarding ? .found : .current) }
        }
        var draft = CloudSetupAssistantDraft()
        draft.chooseAccount("gdrive")
        let own = swapped ? choice(found.sources) : choice(found.library), rom = swapped ? choice(found.library) : choice(found.sources)
        draft.browse(own?.path ?? "")
        view._draft = State(initialValue: draft)
        view._onboarding = State(initialValue: onboarding)
        view._library = State(initialValue: own)
        view._sources = State(initialValue: rom)
        view._sourcesOverride = State(initialValue: rom?.path)
        view._index = State(initialValue: found.index)
        if creates, own == nil { view._newLibrary = State(initialValue: (CloudFolderDiscovery.newLibrary, "", .init(account: "account", id: "account"))) }
        view._confirmingLibrary = State(initialValue: confirming)
        return view
    }
    func screenBrowser(_ found: CloudFolderDiscovery, _ folder: Folder, _ path: String, _ names: [String]) -> Self {
        var view = screenFolders(found, onboarding: false)
        view._browsing = State(initialValue: folder)
        view._browserPath = State(initialValue: path)
        view._listing = State(initialValue: .screenFixture(names))
        return view
    }
    func screenDoubt(_ found: CloudFolderDiscovery, _ folder: Folder, _ path: String) -> Self {
        var view = screenBrowser(found, folder, path, [])
        view._doubt = State(initialValue: view.advice(folder, path).map { (folder, path, $0) })
        precondition(view.doubt != nil && view.doubtChoices.count == 3)
        return view
    }
}
'''

BEFORE_STATE = '''
extension CloudSetupAssistant {
    func screenAccount(existing: Bool) throws -> Self {
        var view = self
        view._tool = State(initialValue: URL(fileURLWithPath: "/fixture/tool"))
        view._version = State(initialValue: "v1.75.2")
        view._remotes = State(initialValue: try JSONDecoder().decode([RcloneRemote].self, from: Data(existing
            ? #"[{"name":"gdrive","type":"drive","source":"file"}]"#.utf8 : "[]".utf8)))
        return view
    }
    func screenFolder(_ path: String, _ sources: Bool) -> Self {
        var view = self
        var draft = CloudSetupAssistantDraft()
        draft.chooseAccount("gdrive")
        draft.browse(path)
        view._draft = State(initialValue: draft)
        view._sourcesPath = State(initialValue: path)
        view._listing = State(initialValue: .screenFixture(["Archives", "Jeux", "Oort-nx"]))
        return view
    }
}
'''


def main():
    arguments = sys.argv[1:]
    before = arguments[arguments.index("--before") + 1] if "--before" in arguments else None
    (ROOT / "work").mkdir(exist_ok=True)
    output = Path(arguments[0] if arguments and not arguments[0].startswith("--")
                  else tempfile.mkdtemp(prefix="cloud-assistant-", dir=ROOT / "work")).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cloud-assistant-") as temp:
        package = Path(temp).resolve()
        if before:
            archived = subprocess.check_output(["git", "-C", str(ROOT), "archive", before, "Sources", "Package.swift"])
            subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archived, check=True)
        else:
            shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
            shutil.copytree(ROOT / "Sources", package / "Sources")
        for name in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            folder = package / "Tests" / name
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        change(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        isolate_startup(app)
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, r'public static let profile = [^\n]*',
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(profile, r'public static var preferences: UserDefaults \{ [^\n]+ \}',
               'nonisolated(unsafe) public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        cloud = app / "ViewModels/AppViewModel+CloudLibrary.swift"
        # No tool: nothing can start a process.
        change(cloud, r'var resolvedDriveTool: URL\? \{.*?\n    }', 'var resolvedDriveTool: URL? { nil }')
        change(cloud, r'var needsDriveTool: Bool \{[^\n]*', 'var needsDriveTool: Bool { false }')
        with cloud.open("a") as swift:
            swift.write('\nextension CloudLibraryModel {\n    func screenKnown() {\n'
                        '        lastKnown = .init(scope: [], personalApps: [UUID()], personalFiles: Set((0..<15).map { _ in UUID() }), verifiedAt: Date(timeIntervalSince1970: 1_795_000_000))\n    }\n}\n')
        section = app / "Views/Settings/SettingsCloudLibrarySection.swift"
        change(section, r'        \.task\(id: Inspection.*?\n        }\n', "")
        with section.open("a") as swift:
            swift.write('''
extension SettingsCloudLibrarySection {
    func screenReady(_ connected: Bool) -> Self {
        var view = self
        view._inspecting = State(initialValue: false)
        view._remotes = State(initialValue: try! JSONDecoder().decode([RcloneRemote].self, from: Data(connected
            ? #"[{"name":"gdrive","type":"drive","source":"file"}]"#.utf8 : "[]".utf8)))
        return view
    }
}
''')
        assistant = app / "Views/Settings/CloudSetupAssistant.swift"
        change(assistant, r'        \.onAppear \{\s*.*?installAssistantKeys\(\)(?: \}|\n        })\n', "")
        with assistant.open("a") as swift:
            swift.write(BEFORE_STATE if before else AFTER_STATE)
        porting = package / "Sources/ArcanePorting/Library"
        with (porting / "CloudDriveFolders.swift").open("a") as swift:
            swift.write('\nextension CloudDriveFolders.Listing {\n    public static func screenFixture(_ names: [String]) -> Self { .init(ticket: UUID(), names: names) }\n}\n')
        if not before:
            with (porting / "CloudFolderDiscovery.swift").open("a") as swift:
                swift.write('''
extension CloudFolderDiscovery {
    public static func screenFixture(_ paths: [String], kept: CloudKeptFolders?) throws -> Self {
        try .init(entries: paths.map { .init(path: $0.hasSuffix("/") ? String($0.dropLast()) : $0, isDirectory: $0.hasSuffix("/")) }, kept: kept)
    }
}
''')
        locales = '[("-fr", AppLocale(language: .french, region: "FR"))' + (
            ', ("-en", AppLocale(language: .english, region: "US")), ("-de", AppLocale(language: .german, region: "DE"))' if "--languages" in arguments else "") + "]"
        (app / "CloudAssistantProbe.swift").write_text(HOST.replace("LOCALES", locales).replace("        // SCREENS", BEFORE if before else AFTER))
        home = package / "home"
        home.mkdir()
        env = {key: value for key, value in os.environ.items() if not key.startswith(("GIT_", "RCLONE_"))}
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), RCLONE_CONFIG=str(home / "rclone.conf"), RCLONE_PASSWORD_COMMAND="/usr/bin/false")
        subprocess.run(["swift", "run", "--jobs", "4", "--package-path", str(package), "NXLibrary", str(output),
                        str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf")], env=env, check=True)


if __name__ == "__main__":
    main()
