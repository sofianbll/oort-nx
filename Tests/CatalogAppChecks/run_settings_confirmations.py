#!/usr/bin/env python3
"""Exercise Settings and render its Selene dialogs in an isolated launcher process."""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def prepare(package):
    app = package / "Sources/NXLibrary"
    core = package / "Sources/NXLibraryCore"
    porting = package / "Sources/ArcanePorting"

    def replace(file, old, new):
        text, count = re.subn(old, new if callable(new) else lambda _: new, file.read_text(), count=1, flags=re.S)
        assert count == 1, (file, old)
        file.write_text(text)

    def append(file, text):
        with file.open("a") as output:
            output.write(text)

    def expose(file, *names):
        for name in names:
            replace(file, rf'private func {name}\(', f'func {name}(')

    home = (package / "home").as_posix()
    profile = core / "App/AppDataProfile.swift"
    replace(profile, r'public static let profile = [^\n]*',
            f'public static let profile = AppDataProfile(home: URL(fileURLWithPath: "{home}"), isDevelopment: true)')
    replace(profile, r'public static var preferences: UserDefaults \{ [^\n]+ \}',
            'nonisolated(unsafe) public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("probe-prefs").path)!')
    # This copied package approves the signed fixture bytes, never the user's managed rclone.
    fixture_tool = Path("/usr/bin/true").read_bytes()
    download = core / "Library/RcloneDownload.swift"
    replace(download, r'(private static let executableSHA256 = )"[0-9a-f]{64}"',
            lambda match: match[1] + f'"{hashlib.sha256(fixture_tool).hexdigest()}"')
    replace(download, r'(executableBytes: )88_766_114\)', lambda match: match[1] + f"{len(fixture_tool)})")
    replace(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
    model = app / "ViewModels/AppViewModel.swift"
    replace(model, r'SteamGridDBKey\(\)\.load\(\) != nil', "false")
    replace(model, r'        applyCatalog\(catalog\).*?\n    }\n\n    // MARK: - Dynamic',
            "    }\n\n    // MARK: - Dynamic")
    replace(model, r'engineOverride\?\.commit \?\? Self\.defaultPinnedEngineCommit',
            'SettingsConfirmationProbe.pin ?? Self.defaultPinnedEngineCommit')
    # Direct row actions (without a mounted SwiftUI tree) read EnvironmentKey.defaultValue.
    replace(app / "Views/Theme/AppLocaleEnvironment.swift",
            r'defaultValue = AppLocale\(language: \.english, region: "US"\)', 'defaultValue = L10n.context')

    settings = app / "Views/Settings"
    cloud = settings / "SettingsCloudLibrarySection.swift"
    expose(cloud, "setEnabled", "unfollow", "confirmDisconnect", "confirmTrashTool", "publishActions", "test")
    replace(cloud, r'private var advancedRows:', 'var advancedRows:')
    replace(cloud, r'private var referenceStatus:', 'var referenceStatus:')
    replace(cloud, r'private var tool: URL\?', 'private var tool: URL? = URL(fileURLWithPath: "/fixture/rclone")')
    replace(cloud, r'private var remotes: \[RcloneRemote\]\?', 'private var remotes: [RcloneRemote]? = SettingsConfirmationProbe.remotes')
    replace(cloud, r'private var inspecting = true', 'private var inspecting = false')
    replace(cloud, r'try await RcloneConfiguration\(executable: tool\)\.disconnect\(name\)',
            'try SettingsConfirmationProbe.disconnect(tool, name)')
    replace(app / "ViewModels/AppViewModel+CloudLibrary.swift",
            r'(cloudLibrary.setReferenceFolder\(folder\)\n)            importCloudGames\(\)', lambda m: m[1])
    library_model = app / "ViewModels/AppViewModel+CloudLibrary.swift"
    replace(library_model, r'RcloneStorageBackend\.findExecutable\(\)', 'SettingsConfirmationProbe.availableDriveTool')
    replace(library_model, r'private var scopeTask:', 'private(set) var scopeTask:')
    for _ in range(2):
        replace(library_model,
                r'RcloneStorageBackend\(remote: remote, root: current.root, executable: tool\)',
                'SettingsConfirmationProbe.scopeBackend(remote: remote, root: current.root, tool: tool)')
    replace(library_model,
            r'RcloneConfiguration\.sharesDefaultConfiguration\(tool\)',
            'RcloneConfiguration.sharesDefaultConfiguration(tool, environment: [:])')
    replace(app / "ViewModels/AppViewModel+DriveTool.swift",
            r'            let installer = cloud.driveTool\n', '')
    replace(app / "ViewModels/AppViewModel+DriveTool.swift",
            r'                    _ = try await installer.install \{',
            '                    try await SettingsConfirmationProbe.installTool {')
    for name in ("SettingsAPISection", "SettingsEngineSection"):
        expose(settings / f"{name}.swift", "publishActions")
    expose(settings / "SettingsView.swift", "resetSection")
    replace(settings / "SettingsAPISection.swift", r'@State var remotePlayAdapters = RemotePlayAdapters\(\)',
            '@State var remotePlayAdapters = RemotePlayAdapters.screenFixture')
    append(porting / "GameSettings/RemotePlayAdapters.swift", """
extension RemotePlayAdapters {
    public static var screenFixture: Self {
        var result = Self()
        result.consider("feth3971", flags: UInt32(IFF_UP), ipv4: 0x0ac7920b)
        return result
    }
}
""")
    for name, label in (("CloudReferenceDialog", 'text("Google Drive folder link or ID")'),
                        ("NextendoClientDialog", 'L10n.text("Nextendo client ID", context: localization)')):
        file = settings / f"{name}.swift"
        expose(file, "save")
        # ImageRenderer cannot draw native text fields. Keep the label and synthetic draft.
        replace(file, r'TextField\(.*?\.onExitCommand\(perform: onClose\)',
                f'Text(draft.isEmpty ? {label} : draft)\n                    .frame(maxWidth: .infinity, alignment: .leading)')
        replace(file, r'        \.onAppear \{\n.*?fieldFocused = true\n        \}\n', '')
        append(file, f"""
extension {name} {{
    func screenDraft(_ text: String) -> Self {{
        var view = self
        view._draft = State(initialValue: text)
        return view
    }}
}}
""")
    assistant = settings / "CloudSetupAssistant.swift"
    expose(assistant, "primary")
    replace(assistant, r'        \.onAppear \{ inspect\(\); installAssistantKeys\(\) \}\n', '')
    # The real view's native ScrollView has no content in ImageRenderer.
    replace(assistant, r'                ScrollView\(\.horizontal\) \{\n(.*?)\n                }\n                if listing != nil',
            lambda m: m[1] + '\n                if listing != nil')
    replace(assistant, r'                    ScrollViewReader \{ proxy in\n                        ScrollView \{\n'
            r'                            LazyVStack', '                    VStack')
    replace(assistant, r'                        }\n                        \.frame\(height: canvas.u\(CGFloat\(min\(folderNames.count.*?\n'
            r'                    }\n                    option\(\.newFolder', '                    option(.newFolder')
    append(porting / "Library/CloudDriveFolders.swift", """
extension CloudDriveFolders.Listing {
    public static var screenFixture: Self { .init(ticket: UUID(), names: ["Nintendo", "Switch"]) }
}
""")
    append(assistant, """
extension CloudSetupAssistant {
    func screenFolder(_ path: String) -> Self {
        var view = self
        view._listing = State(initialValue: .screenFixture)
        if entry == .sources {
            view._sourcesPath = State(initialValue: path)
        } else {
            var next = CloudSetupAssistantDraft()
            next.chooseAccount("fixture")
            next.browse(path)
            precondition(next.useFolder())
            next.acceptAccessCheck(next.ticket)
            view._draft = State(initialValue: next)
        }
        return view
    }
}
""")
    setup = app / "ViewModels/SetupModel.swift"
    replace(setup, r'(func selectNxnativeFolder\([^\n]*\) \{\n        guard [^\n]*\n)        let panel = NSOpenPanel\(\).*?'
            r'        if panel.runModal\(\) == \.OK, let url = panel.url \{',
            lambda m: m[1] + '        if let url = SettingsConfirmationProbe.pickedEngine {')
    replace(setup, r'    func refreshCompatibility\(\) \{.*?(?=\n    func |\n\})',
            '    func refreshCompatibility() {}\n')  # The probe switches commits but never evaluates the Mac toolchain.
    replace(setup, r'    func prepareBuildEnvironmentIfNeeded\(\) \{.*?\n    \}',
            '    func prepareBuildEnvironmentIfNeeded() {}')
    replace(app / "Views/GameOptions/SteamOptionsView.swift",
            r'        \.task\(id: game.id\) \{.*?\n        \}', '')
    fixture_support = 'AppData.profile.home.appendingPathComponent("Library/Application Support/nxnative")'
    replace(app / "ViewModels/RuntimeSettingsModel.swift", r'NXNativeGameSettings.forGame\(game\)',
            f'NXNativeGameSettings.forGame(game, store: MemorySavedChoices(), supportDirectory: {fixture_support})')
    replace(app / "Views/GameOptions/GameOptionsView+Actions.swift", r'NXNativeGameSettings.playerEnvironment\(for: current\)',
            f'NXNativeGameSettings.playerEnvironment(for: current, supportDirectory: {fixture_support})')

    shell = (app / "Views/Shell/AppShellView+Overlays.swift").read_text()
    methods = [re.search(rf'    func {name}\(.*?\n    \}}', shell, re.S)[0] for name in
               ("settingsNoticeOverlay", "finishSettingsNotice", "presentLegacyNotice", "settingsNoticeInput")]
    probe = app / "SettingsConfirmationProbe.swift"
    shutil.copyfile(Path(__file__).with_name(probe.name), probe)
    append(probe, "\nextension SettingsConfirmationProbe.Input {\n" + "\n".join(methods) + "\n}\n")


def main():
    base = ROOT / "work"
    base.mkdir(exist_ok=True)
    output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="settings-screens-", dir=base))
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="settings-probe-") as temp:
        package = Path(temp)
        home = package / "home"
        home.mkdir()
        shutil.copytree(ROOT / "Sources", package / "Sources")
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        for target in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            folder = package / "Tests" / target
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        prepare(package)
        env = {key: value for key, value in os.environ.items() if not key.startswith(("GIT_", "RCLONE_"))}
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), RCLONE_CONFIG=str(home / "rclone.conf"),
                   RCLONE_CONFIG_PASS="fixture-only", RCLONE_PASSWORD_COMMAND="/usr/bin/false",
                   GIT_CONFIG_NOSYSTEM="1", GIT_ALLOW_PROTOCOL="file")
        font = ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"
        subprocess.run(["swift", "run", "--jobs", "4", "--package-path", temp, "NXLibrary", str(output), str(font)],
                       env=env, check=True)


if __name__ == "__main__":
    main()
