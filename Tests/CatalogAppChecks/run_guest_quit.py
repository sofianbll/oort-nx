#!/usr/bin/env python3
"""Execute the delegate's quit path with synthetic guest and activity state."""
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
delegate = (ROOT / 'Sources/NXLibrary/AppDelegate.swift').read_text()
queue = (ROOT / 'Sources/ArcanePorting/Library/CloudTransferQueue.swift').read_text()
decision = queue[queue.index('public enum CloudQuitDecision'):queue.index('/// Profile-local snapshot')]
methods = delegate[delegate.index('    func applicationShouldTerminate('):
                   delegate.index('    func applicationShouldHandleReopen(')]
properties = '\n'.join(line for line in delegate.splitlines() if '@MainActor static var' in line
                       or '@MainActor static weak var' in line or '@MainActor private static var' in line)
overlays = (ROOT / 'Sources/NXLibrary/Views/Shell/AppShellView+Overlays.swift').read_text()
cloud_quit = overlays[overlays.index('    func finishCloudQuit('):overlays.index('    // MARK: - Retry')]
dialog = overlays[overlays.index('    func cloudQuitOverlay('):overlays.index('    func finishCloudQuit(')]
copy = (
    "Quitting stops the transfer. Your files and cloud copies stay intact. The next time you open Arcane, "
    "confirm uploads again from the game pages."
)
assert f'L10n.text("{copy}")' in dialog, "Quit must not promise that uploads resume automatically"
catalog = json.loads((ROOT / "Sources/NXLibraryCore/Resources/Localizable.xcstrings").read_text())["strings"]
expected = {"en": "confirm uploads again", "fr": "confirmez à nouveau les envois", "it": "conferma di nuovo gli invii",
            "de": "Uploads erneut", "es": "vuelve a confirmar las subidas",
            "pt-BR": "confirme os envios novamente", "zh-Hans": "重新确认上传"}
assert set(catalog[copy]["localizations"]) == set(expected)
for language, phrase in expected.items():
    assert phrase in catalog[copy]["localizations"][language]["stringUnit"]["value"], language
host = '''
import Foundation
@MainActor final class NSApplication {
    enum TerminateReply { case terminateNow, terminateCancel }
    static let shared = NSApplication()
    var quits = 0
    func terminate(_ sender: Any?) {
        if AppDelegate().applicationShouldTerminate(self) == .terminateNow { quits += 1 }
    }
}
final class NSWindow {
    var isKeyWindow = true
    func makeKeyAndOrderFront(_ sender: Any?) {}
}
final class AppSettingsStore {}
@MainActor final class CloudLibraryModel {
    var isWorking = false
    var hasQueueWrites = false
    var isQuitting = false
    var driveToolTask: Task<Void, Never>?
    func stopForQuit() -> Task<Void, Never>? {
        isQuitting = true
        driveToolTask?.cancel()
        return Task { await driveToolTask?.value }
    }
}
final class Store { func flush() async {} }
final class AppViewModel {
    var hasActivityWrites = false
    var porting = Porting()
    let buildQueue: [Int] = []
    let activityResults = (entries: [1], unused: false)
    let activityStore = Store()
    let localProfiles: Profiles? = Profiles()
    func restoreActivity() async {}
    struct Profiles { var guest: Int? = 1 }
    struct Porting {
        let hasBuildQueueWrites = false
        let buildQueueStore = Store()
        var isAdoptingBuildCache = false
    }
}
@MainActor final class AppDelegate {
    // PRODUCTION
}
@MainActor struct Shell {
    enum Focus { case cancel }
    var cloudQuitFocus = Focus.cancel
    let viewModel: Model
    var NSApp: NSApplication { .shared }
    @MainActor final class Model {
        let cloudLibrary: CloudLibraryModel
        var cloudQuitRequested = true
        init(_ cloud: CloudLibraryModel) { cloudLibrary = cloud }
    }
    // CLOUD_QUIT
}
@main struct Check {
    @MainActor static func main() async {
        let owner = AppViewModel()
        let cloud = CloudLibraryModel()
        let window = NSWindow()
        defer { withExtendedLifetime(window) {} }
        AppDelegate.activityOwner = owner
        AppDelegate.cloudLibrary = cloud
        AppDelegate.shellWindow = window
        var guestPrompts = 0
        AppDelegate.requestGuestQuit = { guestPrompts += 1 }
        let app = NSApplication.shared
        owner.porting.isAdoptingBuildCache = true
        var afterSettings: (() -> Void)?
        AppDelegate.requestSettingsQuit = { proceed in
            afterSettings = proceed
            return true
        }
        app.terminate(nil)
        guard afterSettings != nil, guestPrompts == 0, !cloud.isQuitting, app.quits == 0 else { exit(7) }
        AppDelegate.requestSettingsQuit = nil
        afterSettings?() // After Save/Discard, run the original delegate checks again.
        guard guestPrompts == 0, !cloud.isQuitting, app.quits == 0 else { exit(6) }
        owner.porting.isAdoptingBuildCache = false
        app.terminate(nil)
        guard guestPrompts == 1, !cloud.isQuitting else {
            print("FAIL: quit drained the activity history before asking the guest")
            exit(1)
        }
        // The guest stays; another attempt must ask again, still without draining.
        app.terminate(nil)
        guard guestPrompts == 2, !cloud.isQuitting else { exit(2) }
        cloud.isWorking = true
        var cloudPrompts = 0
        AppDelegate.showCloudQuit = { cloudPrompts += 1 }
        AppDelegate.quitAfterGuestConfirmation()
        guard cloudPrompts == 1, !cloud.isQuitting else { exit(3) }
        var shell = Shell(viewModel: .init(cloud))
        shell.finishCloudQuit(false)
        cloud.isWorking = false
        cloud.driveToolTask = Task { try? await Task.sleep(for: .seconds(30)) }
        app.terminate(nil)
        guard guestPrompts == 3, !cloud.isQuitting, cloud.driveToolTask?.isCancelled == false else { exit(4) }
        AppDelegate.quitAfterGuestConfirmation()
        for _ in 0..<100 where app.quits == 0 { try? await Task.sleep(for: .milliseconds(1)) }
        guard cloud.isQuitting, cloud.driveToolTask?.isCancelled == true, app.quits == 1, guestPrompts == 3 else { exit(5) }
        print("Guest quit: cancellation doesn't start shutdown; confirmation drains and quits once")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='oort-guest-quit-') as directory:
    source = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// PRODUCTION', properties + '\n' + methods)
                      .replace('// CLOUD_QUIT', cloud_quit.replace('func finishCloudQuit', 'mutating func finishCloudQuit')) + decision)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', source, '-o', executable], check=True)
    subprocess.run([executable], check=True)
