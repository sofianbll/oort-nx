#!/usr/bin/env python3
"""Exercise the real setup persistence and notification request sites without windows.

Only the surrounding app and notification transport are substituted. The plist
lives in the probe's temporary directory; no player profile or game data is read.
"""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json
source = ''.join(p.read_text() for p in sorted((ROOT / 'Sources/NXLibrary/ViewModels').glob('AppViewModel*.swift')))


def declaration(signature, text=None):
    text = source if text is None else text
    start = text.index(signature)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


initial = declaration('    init(settingsStore:')
restore = initial[initial.index('        let didCompleteSetup = '):initial.index('        // 1. Resolve safe root')]
startup_requests = '\n'.join(line for line in initial.splitlines() if 'NotificationService.shared' in line)
porting_source = ''.join(p.read_text() for p in sorted((ROOT / 'Sources/NXLibrary/ViewModels').glob('PortingModel*.swift')))
build = declaration('    func beginBuild(for game:', porting_source)
accepted = build[build.index('        app.isBuilding = true'):build.index('        self.buildState = .running')]
shell = ''.join(p.read_text() for p in sorted((ROOT / 'Sources/NXLibrary/Views/Shell').glob('AppShellView*.swift')))
start = shell.index('.onChange(of: viewModel.setupCompleted)')
opening = shell.index('{ _, done in', start)
depth, end = 1, opening + 1
while depth:
    depth += (shell[end] == '{') - (shell[end] == '}')
    end += 1
finish = shell[opening + len('{ _, done in'):end - 1]
found = (ROOT / 'Sources/NXLibrary/Views/Setup/FoundGamesSetupView.swift').read_text()
start = found.index('.onChange(of: findings)')
opening = found.index('{ _, found in', start)
depth, end = 1, opening + 1
while depth:
    depth += (found[end] == '{') - (found[end] == '}')
    end += 1
findings_changed = found[opening + len('{ _, found in'):end - 1]

host = '''
import Foundation
import Combine
import NXLibraryCore
import ArcanePorting

enum AppData {
    static let domain = CommandLine.arguments[1]
    static let preferences = UserDefaults(suiteName: domain)!
}
enum NotificationRegistration { static var registered = false }
final class NotificationService {
    static let shared = NotificationService()
    var requests = 0
    init() { NotificationRegistration.registered = true }
    func requestAuthorization() { requests += 1 }
}
final class Host {
    // KEYS
    // SETUP
    var showSetupCheck = false
    var isBuilding = false
    var isCancellingBuild = false
    var isInstallingBuild = false
    let registerNotifications = true
    var app: Host { self }
    let gameAppsFolder = URL(fileURLWithPath: "/synthetic/apps")
    init() {
        // RESTORE
        // STARTUP_REQUESTS
    }
    func chooseSteamOnFound(_ value: Bool) { firstRunSetup.chooseSteam(value) }
    func choose(_ value: Bool) { firstRunSetup.chooseSteam(value) }
    func openPorting() { firstRunSetup.openPorting() }
    func openPortingFromFound() { firstRunSetup.openPorting() }
    // MOVE
    // FINISH_TOUR
    func finish() { firstRunSetup.finish() }
    func acceptBuild() {
        // ACCEPTED_BUILD
    }
}
final class Sources {
    struct Configuration { var isEnabled: Bool }
    var configuration: Configuration
    let discoveryRoot: URL
    var applied: [(Bool, URL?)] = []
    init(enabled: Bool, root: URL) { configuration = .init(isEnabled: enabled); discoveryRoot = root }
    func configure(enabled: Bool, root: URL?) { applied.append((enabled, root)); configuration.isEnabled = enabled }
}
final class Settings { var settings = AppSettings() }
final class Shell {
    let viewModel: Host
    let sources: Sources
    let settings = Settings()
    var showsWelcome = false
    init(model: Host, sources: Sources) { viewModel = model; self.sources = sources }
    func complete(_ done: Bool) {
        // FINISH
    }
}
struct NativeApp { var modalWindow: Int? }
var NSApp = NativeApp()
final class SoundEffectService {
    enum Cue { case click, key, error }
    static let shared = SoundEffectService()
    func play(_ cue: Cue) {}
}
final class FindingsReader {
    var cancellations = 0
    func cancel() { cancellations += 1 }
    func start(steamRoot: URL, appsFolder: URL) {}
}
final class FoundHost {
    let viewModel: Host
    var findings: FirstRunFindings?
    var focus = FirstRunSetup.Focus.initialOnFound
    let reader = FindingsReader()
    let steamRoot = URL(fileURLWithPath: "/synthetic/Steam")
    var opened: [(ported: Bool, cancelled: Bool)] = []
    var steamCount: Int? { findings?.steamGameCount }
    let steamEnabled: Bool
    // STEAM_ON
    var portedCount: Int { findings?.portedAppCount ?? 0 }
    var isReading: Bool { findings == nil }
    func onOpenLibrary(_ ported: Bool) { opened.append((ported, reader.cancellations > 0)) }
    // ACTIVATE_FOUND
    var hasSteam: Bool { findings?.steamGameCount != nil || findings?.steamReadFailed == true }
    init(_ viewModel: Host, steamEnabled: Bool = false) {
        self.viewModel = viewModel; self.steamEnabled = steamEnabled
    }
    func move(to next: FirstRunSetup.Focus) { focus = next }
    func receive(_ found: FirstRunFindings?) {
        findings = found
        // FINDINGS_CHANGED
    }
}
var failures = 0
func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { failures += 1; print("FAIL: " + message) }
}
let initialBoot = Host()
require(NotificationRegistration.registered, "Startup registers notification click handling without requesting authorization")
require(initialBoot.firstRunSetup.page == .welcome, "New profiles start with welcome and language")
for page in FirstRunSetup.Page.tour {
    require(Host().firstRunSetup.page == page, "A fresh host resumes at \\(page)")
    _ = initialBoot.moveOnboarding(1)
}
initialBoot.finishOnboarding()
require(Host().firstRunSetup.isCompleted, "Tour completion survives quit")
require(AppData.preferences.bool(forKey: Host.StorageKeys.onboardingNewsSeen), "A fresh player does not receive news")
for savedPage in ["found", "requirements", "games"] {
    for enabled in [false, true] {
        for oldChoice in [true, false] {
            AppData.preferences.removePersistentDomain(forName: AppData.domain)
            AppData.preferences.set(savedPage, forKey: "NXLibrary_SetupPage")
            AppData.preferences.set(oldChoice, forKey: "NXLibrary_SetupSteamChoice")
            let model = Host()
            let sources = Sources(enabled: enabled, root: URL(fileURLWithPath: "/synthetic/Steam"))
            let page = FoundHost(model, steamEnabled: enabled)
            require(page.steamOn == (oldChoice && enabled), "Legacy true reflects the configured source, legacy false stays off")
            model.finish()
            Shell(model: model, sources: sources).complete(true)
            require(sources.configuration.isEnabled == (oldChoice && enabled),
                    "Legacy automatic true never enables Steam or removes an already visible library")
            require(AppData.preferences.object(forKey: "NXLibrary_SetupSteamChoice") == nil, "Finish retires the legacy key")
        }
    }
}
for value in [true, false] {
    AppData.preferences.removePersistentDomain(forName: AppData.domain)
    let before = Host()
    before.choose(value)
    before.openPorting()
    require(AppData.preferences.synchronize(), "Preferences sync to the probe plist")
    require(FileManager.default.fileExists(atPath: AppData.domain + ".plist"), "The plist stays in the probe directory")
    let resumed = Host()
    require(resumed.firstRunSetup.steamChoice == value, "Steam choice survives quit: \\(value)")
    require(resumed.firstRunSetup.page == .requirements, "Porting page survives quit")
    resumed.finish()
    require(resumed.firstRunSetup.steamChoice == value, "Shell can still apply the finishing choice")
    require(AppData.preferences.object(forKey: "NXLibrary_SetupSteamChoice") == nil, "Finishing removes saved choice")
    require(AppData.preferences.object(forKey: "NXLibrary_SetupSteamExplicitChoice") == nil, "Finishing removes the new choice")
    require(Host().firstRunSetup.steamChoice == nil, "Completed setup does not inherit a stale choice")
}
for enabled in [true, false] {
    for choice: Bool? in [true, false, nil] {
        AppData.preferences.removePersistentDomain(forName: AppData.domain)
        AppData.preferences.set("found", forKey: Host.StorageKeys.setupPage)
        let model = Host()
        if let choice { model.choose(choice) }
        let custom = URL(fileURLWithPath: "/synthetic/Custom Steam")
        let sources = Sources(enabled: enabled, root: custom)
        let page = FoundHost(model, steamEnabled: enabled)
        require(page.steamOn == (choice ?? enabled), "The switch reflects the saved choice or existing source")
        let shell = Shell(model: model, sources: sources)
        shell.complete(false)
        require(sources.applied.isEmpty, "Incomplete setup does not apply the switch")
        model.finish()
        shell.complete(true)
        require(sources.configuration.isEnabled == (choice ?? enabled), "Finishing applies on and off, nil preserves the source")
        require(sources.applied.allSatisfy { $0.1 == custom }, "Opt-in uses the same custom root as discovery")
        require(sources.applied.count == ((choice ?? enabled) == enabled ? 0 : 1),
                "Only a changed choice writes the source")
    }
}
for count in [0, 2] {
    for optIn in [false, true] {
        AppData.preferences.removePersistentDomain(forName: AppData.domain)
        AppData.preferences.set("found", forKey: Host.StorageKeys.setupPage)
        let model = Host()
        model.showSetupCheck = true
        let page = FoundHost(model)
        let sources = Sources(enabled: false, root: page.steamRoot)
        let shell = Shell(model: model, sources: sources)
        let completedRead = FirstRunFindings(steamGameCount: count, portedAppCount: 0)
        page.receive(completedRead)
        require(!page.steamOn && model.firstRunSetup.steamChoice == nil, "Detection with \\(count) games never chooses Steam")
        require(page.focus == .openLibrary, "Detection does not steal the initial Open library focus")
        if optIn { page.activate(.steamToggle) }
        page.activate(.openLibrary)
        model.finish()
        shell.complete(true)
        require(sources.applied.count == (optIn ? 1 : 0) && sources.configuration.isEnabled == optIn,
                "Only a user's gesture activates Steam")
        require(sources.applied.allSatisfy { $0.1 == page.steamRoot }, "Apply the root the player saw")
    }
}
AppData.preferences.removePersistentDomain(forName: AppData.domain)
let retryModel = Host()
retryModel.choose(false)
let retry = FoundHost(retryModel)
retry.focus = .steamToggle
retry.receive(FirstRunFindings(steamGameCount: nil, portedAppCount: 0, steamReadFailed: true))
require(retry.focus == .steamToggle, "Retry row keeps focus while the read is incomplete")
retry.receive(nil)
retry.receive(FirstRunFindings(steamGameCount: nil, portedAppCount: 0))
require(retry.focus == .openLibrary, "Retry that finds no Steam leaves no invisible focused row")
retry.receive(FirstRunFindings(steamGameCount: 2, portedAppCount: 0))
require(retryModel.firstRunSetup.steamChoice == false, "Retry never resets an explicit off choice")
AppData.preferences.removePersistentDomain(forName: AppData.domain)
AppData.preferences.set("found", forKey: Host.StorageKeys.setupPage)
let waitingModel = Host()
waitingModel.showSetupCheck = true
let waiting = FoundHost(waitingModel)
waiting.activate(.openLibrary)
require(waiting.opened.count == 1 && waiting.opened.first?.ported == false,
        "A pending read does not block Open library or invent ported results")
require(waiting.opened.first?.cancelled == true, "Cancel the pending request before leaving the found page")
require(waitingModel.firstRunSetup.steamChoice == nil, "No unread source is opted in")
waiting.receive(FirstRunFindings(steamGameCount: nil, portedAppCount: 0, steamReadFailed: true))
require(waitingModel.firstRunSetup.steamChoice == nil, "A partial read does not choose Steam")
waiting.receive(FirstRunFindings(steamGameCount: 2, portedAppCount: 3))
require(waitingModel.firstRunSetup.steamChoice == nil, "A late read does not choose Steam")
waiting.activate(.openLibrary)
require(waiting.opened.last?.ported == true, "A completed read still imports found apps")
NSApp.modalWindow = 1
waiting.activate(.openLibrary)
require(waiting.opened.count == 2, "A native modal still owns input")
NSApp.modalWindow = nil
waitingModel.showSetupCheck = false
waiting.activate(.openLibrary)
require(waiting.opened.count == 2, "A departed setup does not finish again")
NotificationService.shared.requests = 0
let steamOnly = Host()
require(NotificationService.shared.requests == 0, "Startup and Steam-only use never request notifications")
NotificationService.shared.requests = 0
steamOnly.acceptBuild()
require(NotificationService.shared.requests == 1, "Accepted porting requests notifications")
if failures > 0 { exit(1) }
print("Onboarding persistence and notification timing: PASS")
'''
host = host.replace('// ACTIVATE_FOUND', declaration('    func activate(', (ROOT / 'Sources/NXLibrary/Views/Setup/FoundGamesSetupView+Input.swift').read_text()))
host = host.replace('// KEYS', declaration('    enum StorageKeys'))
host = host.replace('// SETUP', declaration('    @Published private(set) var firstRunSetup ='))
host = host.replace('// MOVE', '@discardableResult ' + declaration('func moveOnboarding('))
host = host.replace('// FINISH_TOUR', declaration('    func finishOnboarding('))
host = host.replace('// FINDINGS_CHANGED', findings_changed)
host = host.replace('// STEAM_ON', declaration('    var steamOn:', found))
host = host.replace('// FINISH', finish)
host = host.replace('// RESTORE', restore).replace('// STARTUP_REQUESTS', startup_requests)
host = host.replace('// ACCEPTED_BUILD', accepted)
with tempfile.TemporaryDirectory(prefix='arcane-onboarding-check-') as scratch:
    scratch = Path(scratch)
    main = scratch / 'main.swift'
    main.write_text(host)
    binary = scratch / 'onboarding'
    library = ROOT / '.build/debug'
    subprocess.run(['xcrun', 'swiftc', '-I', str(library), str(main),
                    *map(str, names.objects(library)),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(scratch / 'test-preferences')],
                   env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(library)), check=True)
if len(sys.argv) > 1:
    with tempfile.TemporaryDirectory(prefix='oort-onboarding-render-') as scratch:
        bundle = Path(scratch) / 'Onboarding Probe.app' / 'Contents'
        resources = bundle / 'Resources' / 'Selene'
        resources.mkdir(parents=True)
        executable = bundle / 'MacOS' / names.APP
        executable.parent.mkdir()
        shutil.copy2(library / names.APP, executable)
        shutil.copytree(ROOT / 'Resources/Selene/Fonts', resources / 'Fonts')
        shutil.copy2(ROOT / 'Resources/Selene/palettes.json', resources)
        (bundle / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'local.oort.onboarding.probe', 'CFBundleExecutable': executable.name,
            'CFBundlePackageType': 'APPL',
        }))
        subprocess.run([str(executable), '--render-onboarding-fixture', sys.argv[1]],
                       env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(library.resolve())), check=True)
