#!/usr/bin/env python3
"""The cloud settings and the setup panel, in hidden windows, on a synthetic Drive.

It draws every screen, then goes from the account to the games with the keyboard alone, the mouse alone and a controller
alone, on a live view whose rclone is fake_rclone.py. No real rclone, Drive, network, window or profile.

  run_cloud_assistant.py [OUTPUT] [--full]    --full adds English, German, 80 and 125 %, and a small window
  run_cloud_assistant.py OUTPUT --focus-proof  only the compact account form and the move confirmation
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from run_cloud_screens import ROOT, build_probe, change, isolate_startup

STATE = '''
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
    /// A still picture: nothing is read, nothing is started.
    func screenStill() -> Self {
        var view = self
        view.still = true
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
        view._focus = State(initialValue: CloudSetupAssistantFocus())
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
        view._browsing = State(initialValue: nil)
        view._onboarding = State(initialValue: onboarding)
        view._library = State(initialValue: own)
        view._sources = State(initialValue: rom)
        view._sourcesOverride = State(initialValue: rom?.path)
        view._index = State(initialValue: found.index)
        if creates {
            func new(_ path: String?) -> NewFolder? { path.map { .init(path: $0, below: "", parent: .init(account: "account", id: "account")) } }
            if own == nil { view._newLibrary = State(initialValue: new(found.newLibrary)) }
            if rom == nil { view._newSources = State(initialValue: new(found.newSources)) }
        }
        view._confirmingNew = State(initialValue: confirming)
        return view
    }
    func screenBrowser(_ found: CloudFolderDiscovery, _ folder: Folder, _ path: String, _ names: [String]) -> Self {
        var view = screenFolders(found, onboarding: false)
        view._browsing = State(initialValue: folder)
        view._browserPath = State(initialValue: path)
        view._listing = State(initialValue: .screenFixture(names))
        view._recents = State(initialValue: ["Games/Switch/Jeux", "Games/Switch/Archives"])
        return view
    }
    func screenDoubt(_ found: CloudFolderDiscovery, _ folder: Folder, _ path: String) -> Self {
        var view = screenBrowser(found, folder, path, [])
        view._doubt = State(initialValue: view.advice(folder, path).map { (folder, path, $0) })
        precondition(view.doubt != nil)
        return view
    }
    func screenReady(_ found: CloudFolderDiscovery, verified: Bool, working: Bool = false) -> Self {
        var view = screenFolders(found, onboarding: true)
        var draft = view.draft
        precondition(draft.useFolder())
        if verified { draft.acceptAccessCheck(draft.ticket) }
        view._draft = State(initialValue: draft)
        if working { view._work = State(initialValue: (UUID(), .verify, Task {})) }
        return view
    }
    func screenMove(_ plan: CloudDriveFolders.MovePlan) -> Self {
        var view = self
        var draft = CloudSetupAssistantDraft()
        draft.chooseAccount("gdrive")
        draft.browse("New Library")
        view._browsing = State(initialValue: nil)
        view._draft = State(initialValue: draft)
        view._movePlan = State(initialValue: plan)
        view._confirmingMove = State(initialValue: true)
        return view
    }
}
'''


def append(file, text):
    with file.open("a") as swift:
        swift.write(text)


def main():
    arguments = sys.argv[1:]
    (ROOT / "work").mkdir(exist_ok=True)
    output = Path(arguments[0] if arguments and not arguments[0].startswith("--")
                  else tempfile.mkdtemp(prefix="cloud-assistant-", dir=ROOT / "work")).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cloud-assistant-") as temp:
        package = Path(temp).resolve()
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        shutil.copytree(ROOT / "Sources", package / "Sources")
        for name in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            folder = package / "Tests" / name
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        change(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        sound = app / "Services/SoundEffectService.swift"
        change(sound, r"\bplayer\.play\(\)", "player.volume = 0")
        change(sound, r"\bchosen\.play\(\)", "chosen.volume = 0")
        isolate_startup(app)
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, r'public static let profile = [^\n]*',
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(profile, r'public static var preferences: UserDefaults \{ [^\n]+ \}',
               'nonisolated(unsafe) public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        cloud = app / "ViewModels/AppViewModel+CloudLibrary.swift"
        # The only tool is the probe's own: none while drawing, fake_rclone.py on a live path.
        change(cloud, r'var resolvedDriveTool: URL\? \{.*?\n    }', 'var resolvedDriveTool: URL? { MainActor.assumeIsolated { CloudAssistantProbe.tool } }')
        change(cloud, r'var needsDriveTool: Bool \{[^\n]*', 'var needsDriveTool: Bool { false }')
        append(cloud, """
extension CloudLibraryModel {
    func screenKnown() {
        lastKnown = .init(scope: [], personalApps: [UUID()], personalFiles: Set((0..<15).map { _ in UUID() }), verifiedAt: Date(timeIntervalSince1970: 1_795_000_000))
    }
}
""")
        views = app / "Views/Settings"
        section = views / "SettingsCloudLibrarySection.swift"
        change(section, r'        \.task\(id: Inspection.*?\n        }\n', "")
        append(section, """
extension SettingsCloudLibrarySection {
    func screenReady(_ connected: Bool) -> Self {
        var view = self
        view._inspecting = State(initialValue: false)
        view._remotes = State(initialValue: try! JSONDecoder().decode([RcloneRemote].self, from: Data(connected
            ? #"[{"name":"gdrive","type":"drive","source":"file"}]"#.utf8 : "[]".utf8)))
        return view
    }
}
""")
        assistant = views / "CloudSetupAssistant.swift"
        change(assistant, r'    let onClose: \(\) -> Void\n', '    let onClose: () -> Void\n    var still = false\n')
        change(assistant, r'\.onAppear \{ inspect\(\); installAssistantKeys\(\) \}', '.onAppear { if !still { inspect() } }')
        change(assistant, r'    var body: some View \{\n        ZStack', '    var body: some View {\n        let _ = (CloudAssistantProbe.mounted = self)\n        ZStack')
        # Where each target is, for a pointer.
        text = assistant.read_text()
        assert text.count(".seleneHover { if enabled { focus.select(target) } }") == 4
        assistant.write_text(text.replace(".seleneHover { if enabled { focus.select(target) } }",
            ".seleneHover { if enabled { focus.select(target) } }.modifier(ProbeFrame(id: AnyHashable(target)))")
            .replace("font: .row))\n    }", "font: .row)).modifier(ProbeFrame(id: AnyHashable(target)))\n    }", 1))
        assert assistant.read_text().count("ProbeFrame") == 5
        change(app / "Views/OortUI/OortActionBar.swift", r'(\.seleneHover \{ if action\.enabled \{ onFocus\(action\.id\) \} \})',
               lambda match: match[1] + '.modifier(ProbeFrame(id: action.id))')
        change(app / "Views/OortUI/OortAssistantPanel.swift", r'        \.disabled\(!canOpen\(step\.id\)\)',
               '        .disabled(!canOpen(step.id)).modifier(ProbeFrame(id: AnyHashable(CloudSetupAssistantFocus.Target.step(step.id))))')
        account = views / "CloudSetupAssistant+Account.swift"
        change(account, r'NSWorkspace\.shared\.open\(url\)', 'CloudAssistantProbe.opened.append(url)')
        append(assistant, STATE)
        porting = package / "Sources/ArcanePorting/Library"
        append(porting / "CloudDriveFolders.swift",
               "\nextension CloudDriveFolders.Listing {\n    public static func screenFixture(_ names: [String]) -> Self { .init(ticket: UUID(), names: names) }\n}\n")
        append(porting / "CloudFolderDiscovery.swift", """
extension CloudFolderDiscovery {
    public static func screenFixture(_ paths: [String], kept: CloudKeptFolders?) throws -> Self {
        try .init(entries: paths.map { .init(path: $0.hasSuffix("/") ? String($0.dropLast()) : $0, isDirectory: $0.hasSuffix("/")) }, kept: kept)
    }
}
""")
        shutil.copyfile(Path(__file__).with_name("CloudAssistantProbe.swift"), app / "CloudAssistantProbe.swift")
        home = package / "home"
        home.mkdir()
        env = {key: value for key, value in os.environ.items() if not key.startswith(("GIT_", "RCLONE_"))}
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), RCLONE_CONFIG=str(home / "rclone.conf"), RCLONE_PASSWORD_COMMAND="/usr/bin/false",
                   OORT_FAKE_RCLONE=str(Path(__file__).with_name("fake_rclone.py").resolve()))
        subprocess.run([str(build_probe(package)), str(output),
                        str(ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"),
                        *(a for a in arguments if a in {"--full", "--focus-proof"})], env=env, check=True)


if __name__ == "__main__":
    main()
