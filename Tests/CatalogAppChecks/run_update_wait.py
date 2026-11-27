#!/usr/bin/env python3
"""Check the real update coordinator against an offline, synthetic release bundle."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
import sys  # noqa: E402
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json
BIN = ROOT / ".build/debug"
HOST = r'''
import AppKit
import Combine
import NXLibraryCore

enum SeleneConfirmButton { case confirm, cancel }
enum AppDelegate { @MainActor static var relaunchScheduled = false }

@main struct UpdateWaitProbe {
    @MainActor static func main() async throws {
        let scratch = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let folder = scratch.appendingPathComponent("Update")
        let staged = folder.appendingPathComponent("unpacked/Oort NX.app")
        let zip = folder.appendingPathComponent("Oort-NX-9.0.0.zip")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("verified fixture".utf8).write(to: zip)
        let release = AppUpdate.parseRelease(Data("""
        {"tag_name":"v9.0.0","assets":[{"name":"Oort-NX-9.0.0.zip","size":16,
          "browser_download_url":"https://github.com/Bium23/NxLibrary/releases/download/v9.0.0/Oort-NX-9.0.0.zip",
          "digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000"}]}
        """.utf8))!
        let updater = AppUpdater()
        precondition(updater.installation == .ok)
        updater.blockedReason = { "Fixture game is running" }
        updater.acquireInstallLease = { fatalError("The game is running; do not acquire a lease") }
        updater.install(staged: staged, folder: folder, release: release)
        guard FileManager.default.fileExists(atPath: zip.path) else {
            fputs("FAIL: a game blocked installation and the verified archive was deleted.\n", stderr)
            exit(1)
        }
        precondition(updater.state == .readyToInstall(release) && updater.canInstallRelease)
        updater.checkNow()
        precondition(updater.state == .readyToInstall(release))
        updater.confirmDialog() // Still blocked. No download, verification or swap.
        precondition(FileManager.default.fileExists(atPath: zip.path))
        updater.blockedReason = { nil }
        updater.acquireInstallLease = { nil } // Another operation wins the lease.
        updater.install(staged: staged, folder: folder, release: release)
        precondition(updater.state == .readyToInstall(release))
        precondition(FileManager.default.fileExists(atPath: zip.path))
        updater.acquireInstallLease = { fatalError("A changed archive must not reach installation") }
        updater.confirmDialog()
        precondition(updater.state == .verifying, "retry uses the existing archive, not a new download")
        for await state in updater.$state.values {
            if case .failed = state { break }
        }
        precondition(!FileManager.default.fileExists(atPath: zip.path))
        print("Verified update survives a running game and lease contention; retry rejects a changed ZIP: PASS")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="oort-update-wait-") as path:
    scratch = Path(path).resolve()
    app = scratch / "Fixture.app/Contents"
    executable = app / "MacOS/probe"
    executable.parent.mkdir(parents=True)
    (app / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "invalid.oort.update-fixture",
        "CFBundleExecutable": "probe", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0.0", "NXLibraryRelease": True,
    }))
    main = scratch / "Probe.swift"
    main.write_text(HOST)
    updater = scratch / "AppUpdater.swift"
    # Expose only the already-verified boundary in this test copy.
    source = (ROOT / "Sources/NXLibrary/Services/AppUpdater.swift").read_text()
    updater.write_text(source.replace("private func install(staged:", "func install(staged:")
                       .replace('AppData.supportRoot.appendingPathComponent("Temp/Update")',
                                'URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Update")'))
    env = dict(os.environ, HOME=str(scratch), CFFIXED_USER_HOME=str(scratch), PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN))
    subprocess.run(["xcrun", "swiftc", "-j", "1", "-parse-as-library", "-I", str(BIN),
                    str(main), str(updater), *map(str, names.objects(BIN)),
                    "-o", str(executable)], cwd=ROOT, env=env, check=True)
    subprocess.run([str(executable), str(scratch)], cwd=scratch, env=env, check=True, timeout=30)
