#!/usr/bin/env python3
"""Exercise the app's removal actions with a real catalog and an isolated Trash double."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter

ROOT = Path(__file__).resolve().parents[2]

HOST = r'''
import Foundation
import Darwin
import AppKit
import SwiftUI
import NXLibraryCore
import ArcanePorting

@main struct RemovalProbe {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 5 {
            try await cutProbe()
            return
        }
        let root = AppData.supportRoot
        let fm = FileManager.default
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: \(message)") }
        }
        for removal in ["game", "sources"] {
            for fault in ["catalog", "second trash", "rollback catalog", "none"] {
                let folder = root.appendingPathComponent(UUID().uuidString)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                RemovalFixture.reset()
                let repo = CatalogRepository(store: .init(directory: folder))
                try RemovalFixture.setUpTrash(in: folder)
                let app = folder.appendingPathComponent("Fixture.app")
                try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
                try Data("synthetic app".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
                let files = (1...2).map { folder.appendingPathComponent("fixture\($0).nsp") }
                for url in files { try Data(url.lastPathComponent.utf8).write(to: url) }
                var game = PortedGame(name: "Fixture", url: app, platform: .macApp, sizeBytes: 1,
                                      modificationDate: .now, titleId: "0100123456789ABC")
                game.sources = files.map { .init(url: $0, kind: .base, titleId: game.titleId, sizeBytes: 12) }
                let staged = folder.appendingPathComponent(".nxlibrary-build/workspaces/\(game.titleId!)")
                try fm.createDirectory(at: staged, withIntermediateDirectories: true)
                let cache = staged.appendingPathComponent("cache")
                try Data("synthetic cache".utf8).write(to: cache)
                game.workspacePath = staged.path
                game.buildCachePath = cache.path
                let base = try repo.updateNXNativeGames { $0 = [game] }
                let model = AppViewModel(settingsStore: .init(fileURL: folder.appendingPathComponent("settings.json")),
                                         catalog: base, repository: repo)
                RemovalFixture.failPublication = fault == "catalog"
                RemovalFixture.failTrash = ["second trash", "rollback catalog"].contains(fault) ? 2 : 0
                RemovalFixture.failRollback = fault == "rollback catalog"
                RemovalFixture.beforeTrash = {
                    let saved = try rawCatalog(in: folder).nxnativeGames.first
                    check(removal == "game" ? saved == nil : saved?.sources.isEmpty == true,
                          "Trash ran before publication (\(removal), \(fault))")
                }
                if removal == "game" { model.deletePortedGame(game) } else { model.removeSources(for: game) }
                let stored = try rawCatalog(in: folder)
                let traces = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("catalog-removal-") }
                let mustRecover = fault == "rollback catalog"
                if mustRecover {
                    check(traces.count == 1, "Failed rollback must retain one recovery record")
                    if let trace = traces.first {
                        let data = try Data(contentsOf: trace)
                        let record = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        check(record?["record"] != nil && (record?["items"] as? [Any])?.count == (removal == "game" ? 2 : 3),
                              "Recovery record must include the game and the intended Trash paths")
                        check(model.alertMessage?.contains(trace.lastPathComponent) == true,
                              "The error must show where to recover: \(model.alertMessage ?? "none")")
                        RemovalFixture.failPublication = false
                        check(try repo.load().games == base.games, "Startup must finish rollback after the obstruction is lifted")
                    }
                } else { check(traces.isEmpty, "Resolved operations must not leave a recovery record") }
                if fault == "none" {
                    check(removal == "game" ? stored.nxnativeGames.isEmpty : stored.nxnativeGames.first?.sources.isEmpty == true,
                          "Successful removal was not saved (\(removal))")
                    check(fm.fileExists(atPath: app.path) == (removal != "game"), "Wrong app state")
                    check(files.allSatisfy { fm.fileExists(atPath: $0.path) == (removal != "sources") }, "Wrong source state")
                    check(!fm.fileExists(atPath: staged.path), "Managed workspace remained after success")
                } else {
                    if !mustRecover {
                        check(stored.games == base.games, "The original record was not kept/restored (\(removal), \(fault))")
                        check(stored.cloudImportExclusions == base.cloudImportExclusions, "Cloud exclusion was not rolled back")
                    }
                    check(fm.fileExists(atPath: app.path), "The original app was not kept/restored (\(fault))")
                    check(try Data(contentsOf: cache) == Data("synthetic cache".utf8), "The workspace was not kept/restored")
                    for url in files {
                        check((try? Data(contentsOf: url)) == Data(url.lastPathComponent.utf8),
                              "Source bytes were not kept/restored (\(fault))")
                    }
                    if fault == "catalog" { check(RemovalFixture.calls == 0, "Publication failure must not use Trash") }
                }
                if CommandLine.arguments.count == 2, removal == "sources", fault == "catalog" {
                    for (name, language) in [("en", AppLanguage.english), ("fr", AppLanguage.french)] {
                        L10n.setContext(.init(language: language, region: language == .french ? "FR" : "US"))
                        model.removeSources(for: game)
                        try render(model.alertMessage!, name: name)
                    }
                }
            }
        }
        if failures > 0 { exit(1) }
        print("Catalog removal: publication comes first, publication failure leaves files, Trash failure restores files and catalog.")
    }

    static func rawCatalog(in folder: URL) throws -> CatalogDocument {
        try CatalogStore.decode(Data(contentsOf: folder.appendingPathComponent("catalog.json")), kinds: .standard)
    }

    @MainActor static func cutProbe() async throws {
        let args = CommandLine.arguments
        let mode = args[1]
        let upgrading = mode.hasPrefix("upgrade-")
        let folder = upgrading ? AppData.supportRoot : URL(fileURLWithPath: args[2], isDirectory: true)
        let fm = FileManager.default
        let repository = CatalogRepository(store: .init(directory: folder))
        let files = [folder.appendingPathComponent("Fixture.app"), folder.appendingPathComponent("fixture.nsp")]
        let marker = folder.appendingPathComponent("catalog-removal-pending.json")
        let setup = AppSettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
        if upgrading {
            AppData.preferences.set(true, forKey: AppViewModel.StorageKeys.setupCompleted)
            setup.settings.checkEngineAtLaunch = false
            setup.settings.refreshLibraryAtLaunch = false
        }
        if mode == "upgrade-open" {
            precondition(fm.fileExists(atPath: marker.path) == (args[3] == "first"))
            let initial = try repository.load()
            precondition(!fm.fileExists(atPath: marker.path) && initial.nxnativeGames.count == 2)
            for source in files {
                let contents = try Data(contentsOf: source)
                precondition(contents == Data(source.lastPathComponent.utf8), "Interrupted removal must recover the original bytes")
            }
            let profiles = LocalProfileStore(directory: folder, settings: setup.settings, name: "Unexpected")
            precondition(profiles.active?.name == "Fixture 0.3.0")
            let model = AppViewModel(settingsStore: setup, catalog: initial, repository: repository, localProfiles: profiles)
            model.cloudLibrary.installUpgradeArchive()
            model.installPendingBuilds()
            model.restoreCloudQueue()
            for _ in 0..<400 where model.cloudLibrary.isRestoringQueue { try await Task.sleep(for: .milliseconds(10)) }
            precondition(model.cloudLibrary.hasRestoredQueue && model.cloudLibrary.active == nil)
            let history = await model.activityStore.load()
            let queue = await model.cloudLibrary.queueStore.load()
            let pending = try repository.load().nxnativeGames.first { $0.name == "Pending" }?.pendingInstall
            let token = UUID(uuidString: "7E9792C9-6A86-4F6E-A26D-0F1B67D28C6A")!
            let reconfirmed = history.filter { $0.id == token }
            precondition(queue.isEmpty && reconfirmed.count == 1, "Exactly one durable reconfirmation must replace the old queue row")
            guard case .cloud(let saved) = reconfirmed[0].job else { preconditionFailure("Wrong history entry") }
            precondition(saved.storage == "old-drive:Old folder" && saved.action == .upload(.app))
            precondition(pending?.expectedDestination == nil && model.gameWithInstallFailure != nil)
            precondition(BuildOutputInstaller.version(of: pending!.finalApp) == "9.0")
            precondition(BuildOutputInstaller.version(of: pending!.tempApp) == "1.2")
            print("0.3.0 startup \(args[3]): recovered Trash, retained old cloud destination once, kept staged build and foreign app")
            return
        }
        if mode == "restart" {
            let current = try repository.load()
            let committed = args[3] == "committed"
            let kept = try fm.contentsOfDirectory(at: folder.appendingPathComponent("Fixture Trash"), includingPropertiesForKeys: nil)
            precondition(current.nxnativeGames.count == (committed ? 0 : 1))
            precondition((current.cloudImportExclusions?.count ?? 0) == (committed ? 1 : 0))
            precondition(!fm.fileExists(atPath: marker.path))
            for file in files {
                let matchingTrash = kept.map { $0.appendingPathComponent(file.lastPathComponent) }
                    .compactMap { try? Data(contentsOf: $0) }
                let source = try? Data(contentsOf: file)
                let fixture = Data(file.lastPathComponent.utf8)
                precondition(committed ? (source == nil && matchingTrash == [fixture]) : (source == fixture && matchingTrash.isEmpty))
            }
            return
        }
        if mode == "collision" {
            let log = try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as! [String: Any]
            let items = log["items"] as! [[String: Any]]
            let target = URL(string: items[0]["target"] as! String)!
            let preserved = folder.appendingPathComponent("preserved")
            try fm.moveItem(at: target, to: preserved)
            try Data("replacement".utf8).write(to: target)
            do { _ = try repository.load(); fatalError("replacement was accepted") }
            catch is CatalogRemovalRecovery {}
            let replacementBytes = try Data(contentsOf: target)
            let originalBytes = try Data(contentsOf: preserved)
            precondition(replacementBytes == Data("replacement".utf8))
            precondition(originalBytes == Data(files[0].lastPathComponent.utf8))
            precondition(!fm.fileExists(atPath: files[0].path) && fm.fileExists(atPath: marker.path))
            return
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try RemovalFixture.setUpTrash(in: folder)
        for file in files { try Data(file.lastPathComponent.utf8).write(to: file) }
        let game = PortedGame(name: "Synthetic", url: files[0], platform: .macApp, sizeBytes: 7,
                              modificationDate: .now, titleId: "0100123456789ABC")
        var games = [game]
        if mode == "upgrade-seed" {
            _ = LocalProfileStore(directory: folder, settings: setup.settings, name: "Fixture 0.3.0")
            let final = folder.appendingPathComponent("Occupied.app")
            let staged = folder.appendingPathComponent("staging/New.app")
            for (app, version) in [(final, "9.0"), (staged, "1.2")] {
                let plist = app.appendingPathComponent("Contents/Info.plist")
                try fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version],
                                                               format: .xml, options: 0)
                try data.write(to: plist)
            }
            var other = PortedGame(name: "Pending", url: final, platform: .macApp, sizeBytes: 1,
                                   modificationDate: .now, titleId: "0100123456789ABD")
            let record = BuildRecord(startedAt: .now, endedAt: .now, exitCode: 0, outputPath: final.path,
                                     toolchainVerified: true)
            // Omitting the optional identity writes exactly the legacy PendingInstall JSON shape.
            other.pendingInstall = PendingInstall(tempApp: staged, finalApp: final, record: record, toolchain: .init())
            games.append(other)
            let oldQueue = CloudTransferQueue()
            oldQueue.save([.init(id: other.id, action: .upload(.app),
                                 token: UUID(uuidString: "7E9792C9-6A86-4F6E-A26D-0F1B67D28C6A")!,
                                 storage: "old-drive:Old folder")])
            await oldQueue.flush()
        }
        let initial = try repository.updateNXNativeGames { $0 = games }
        RemovalFixture.cut = Int(args[4])!
        if args[3] == "rollback" { RemovalFixture.failTrash = 2 }
        do {
            _ = try repository.removeNXNativeFiles(id: game.id, from: initial, files: files, keeping: nil) {
                try RemovalFixture.checkTrash()
                if args[3] == "concurrent" {
                    let second = CatalogRepository(store: .init(directory: folder))
                    do { _ = try second.configureSource(.nxnative, enabled: true, root: nil); fatalError("second writer entered") }
                    catch CatalogStoreError.busy {}
                    throw CocoaError(.fileWriteNoPermission)
                }
            }
            precondition(!["rollback", "concurrent"].contains(args[3]))
        } catch CatalogRemovalFailure.writeFailed {
            precondition(["rollback", "concurrent"].contains(args[3]))
        }
    }

    @MainActor static func render(_ message: String, name: String) throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("catalog-removal-\(name).png")
        let view = SeleneChoiceDialog(title: AppIdentity.displayName, message: message, choices: ["Back"],
            focus: .constant(0), onChoose: { _ in })
            .environment(\.nxAppLocale, L10n.context)
            .frame(width: 1440, height: 900)
            .background(Color(red: 0.09, green: 0.13, blue: 0.20))
            .environment(\.colorScheme, .dark)
            .environment(\.seleneCanvas, SeleneCanvas(size: .init(width: 1920, height: 1080)))
        let renderer = ImageRenderer(content: view)
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: destination)
    }
}
'''

UPGRADE_CLOUD = r'''
extension CloudLibraryModel {
    func installUpgradeArchive() {
        let local = RcloneStorageBackend(remote: "fixture", root: "New folder") { _, args, _ in
            precondition(args.first == "lsjson", "A legacy upload must never write to the remote")
            return .init(status: 0, stdout: "[]", stderr: "")
        }
        backend = local
        archive = CloudGameArchive(backend: local)
    }
}
'''

DOUBLE = r'''
import Foundation
import Darwin

package enum RemovalFixture {
    package static var failPublication = false
    package static var failTrash = 0
    package static var failRollback = false
    package static var calls = 0
    package static var cut = -1
    private static var count = 0
    private static var trash: URL!
    package static var beforeTrash: (() throws -> Void)?
    package static func reset() { failPublication = false; failTrash = 0; failRollback = false; calls = 0; beforeTrash = nil }
    package static func setUpTrash(in folder: URL) throws {
        trash = folder.appendingPathComponent("Fixture Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
    }
    package static func trashDirectory() throws -> URL {
        guard let trash else { throw CocoaError(.fileNoSuchFile) }
        return trash
    }
    package static func checkpoint(_ name: String) {
        guard cut >= 0 else { return }
        count += 1
        try! FileHandle.standardOutput.write(contentsOf: Data("\(count) \(name)\n".utf8))
        if count == cut { _exit(79) }
    }
    package static func checkTrash() throws {
        calls += 1
        try beforeTrash?()
        if calls == failTrash {
            failPublication = failRollback
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}
'''


def replace(file, old, new):
    text, count = re.subn(old, lambda _: new, file.read_text(), count=1, flags=re.S)
    assert count == 1, (file, old)
    file.write_text(text)


with tempfile.TemporaryDirectory(prefix="catalog-removal-") as temp:
    package = Path(temp)
    shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
    shutil.copytree(ROOT / "Sources", package / "Sources")
    for name in ("NXLibraryCoreTests", "ArcanePortingTests"):
        folder = package / "Tests" / name
        folder.mkdir(parents=True)
        (folder / "Empty.swift").touch()
    sources = package / "Sources"
    app = sources / "NXLibrary"
    core = sources / "NXLibraryCore"
    replace(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
    replace(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
    replace(app / "ViewModels/AppViewModel.swift", r"        applyCatalog\(catalog\).*?\n    }\n\n    // MARK: - Dynamic",
            "        applyCatalog(catalog)\n    }\n\n    // MARK: - Dynamic")
    replace(core / "App/AppDataProfile.swift", r"public static let profile = [^\n]*",
            f'''public static let profile = {{
        let args = CommandLine.arguments
        if args.count == 5, args[1].hasPrefix("upgrade-") {{
            return AppDataProfile(home: URL(fileURLWithPath: args[2]), isDevelopment: false)
        }}
        return AppDataProfile(home: URL(fileURLWithPath: "{temp}"), isDevelopment: true)
    }}()''')
    replace(core / "App/AppDataProfile.swift", r"public static var preferences: UserDefaults \{ configuredPreferences\(\) \}",
            'public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("fixture-prefs").path)!')
    cloud = app / "ViewModels/AppViewModel+CloudLibrary.swift"
    with cloud.open("a") as swift:
        swift.write(UPGRADE_CLOUD)
    replace(core / "Catalog/CatalogStore.swift", r"try publication\.publish\(candidate,",
            "if RemovalFixture.failPublication { throw CocoaError(.fileWriteNoPermission) }\n        try publication.publish(candidate,")
    removal = core / "Catalog/CatalogStore+Removal.swift"
    replace(removal, r"try removalTrashDirectory\(source\)", "try RemovalFixture.trashDirectory()")
    models = app / "ViewModels/AppViewModel+GameFiles.swift"
    text, substitutions = re.subn(r"(guard RunningGameMonitor.runningApplication\(for: (?:updated|current)\) == nil else \{ throw CatalogRemovalFailure.gameBusy \})",
                                  r"\1\n                try RemovalFixture.checkTrash()", models.read_text())
    assert substitutions == 2
    models.write_text(text)
    for file, anchor, event in [
        (removal, r"try CatalogPublication.atomic.publish\(stage, removalJournal, false\) \{\}", "intent-link"),
        (removal, r"guard mkdir\(item.bucket.path, 0o700\) == 0 else \{ throw CatalogRemovalFailure.trashUnavailable \}", "trash-mkdir"),
        (removal, r"try FileManager.default.removeItem\(at: removalJournal\)", "journal-unlink"),
        (removal, r"throw CatalogRemovalFailure.trashUnavailable\n            \}\n            (?=try CatalogPublication.synchronize\(bucket\))", "file-renamed"),
        (core / "Catalog/CatalogPublication.swift", r"try handle.write\(contentsOf: data\)", "stage-write"),
        (core / "Catalog/CatalogPublication.swift", r"try handle.close\(\)\n            (?=return url)", "stage-sync"),
        (core / "Catalog/CatalogPublication.swift", r"guard fsync\(fd\) == 0 else \{ throw POSIXError\(POSIXErrorCode\(rawValue: errno\) \?\? \.EIO\) \}", "directory-sync"),
        (core / "Catalog/CatalogPublication.swift", r"guard result == 0 else \{ throw POSIXError\(POSIXErrorCode\(rawValue: errno\) \?\? \.EIO\) \}", "publish"),
    ]:
        matched = re.search(anchor, file.read_text(), re.S)
        assert matched, (file, anchor)
        replace(file, anchor, matched.group() + f'\n            RemovalFixture.checkpoint("{event}")\n            ')
    replace(removal, r"if rmdir\(item.bucket.path\) == 0 \{",
            'if rmdir(item.bucket.path) == 0 { RemovalFixture.checkpoint("trash-rmdir");')
    (core / "RemovalFixture.swift").write_text(DOUBLE)
    (app / "RemovalProbe.swift").write_text(HOST)
    args = sys.argv[1:2]
    if args:
        Path(args[0]).mkdir(parents=True, exist_ok=True)
        args = [str(Path(args[0]).resolve())]
    env = dict(os.environ, HOME=temp, CFFIXED_USER_HOME=temp, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    command = ["swift", "build", "-j", "5", "--package-path", str(package)]
    subprocess.run(command, check=True, env=env)
    build = Path(subprocess.check_output(command + ["--show-bin-path"], env=env, text=True).strip())
    app_probe = build / "NXLibrary"
    subprocess.run([app_probe, *args], check=True, env=env)
    coverage = Counter()
    for trial in ("success", "rollback"):
        trace = subprocess.check_output([app_probe, "cut", package / trial, trial, "0"], env=env, text=True)
        for line in trace.splitlines():
            step, name = line.split()
            fixture = package / f"{trial}-{step}"
            cut = subprocess.run([app_probe, "cut", fixture, trial, step], env=env, capture_output=True, text=True)
            assert cut.returncode == 79 and cut.stdout.splitlines()[-1] == line, (cut.stdout, cut.stderr)
            published = trial == "success" and not (fixture / "catalog-removal-pending.json").exists() and (
                name == "journal-unlink" or "journal-unlink" in cut.stdout
            )
            subprocess.run([app_probe, "restart", fixture, "committed" if published else "undone", "0"], check=True, env=env)
            coverage[(trial, name)] += 1
    concurrent = package / "concurrent"
    subprocess.run([app_probe, "cut", concurrent, "concurrent", "-1"], check=True, env=env)
    subprocess.run([app_probe, "restart", concurrent, "undone", "0"], check=True, env=env)
    first_rename = next(line.split()[0] for line in trace.splitlines() if "file-renamed" in line)
    fixture = package / "collision"
    assert subprocess.run([app_probe, "cut", fixture, "rollback", first_rename], env=env, capture_output=True).returncode == 79
    subprocess.run([app_probe, "collision", fixture, "undone", "0"], check=True, env=env)
    home = package / "upgrade"
    profile = home / "Library/Application Support/NXLibrary"
    profile.mkdir(parents=True)
    cut = subprocess.run([app_probe, "upgrade-seed", home, "success", first_rename], capture_output=True, env=env)
    assert cut.returncode == 79, (cut.stdout, cut.stderr)
    for launch in ("first", "second"):
        subprocess.run([app_probe, "upgrade-open", home, launch, "0"], check=True, env=env)
    print(f"{sum(coverage.values())} forced process exits at write boundaries: {dict(coverage)}; competing writer and substituted Trash path rejected.")
