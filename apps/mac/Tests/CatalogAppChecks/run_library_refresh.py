#!/usr/bin/env python3
"""One refresh of the whole library, on the real model with a fake rclone: what it asks, what it shows, what it never does.

Optional argument: a new folder for the French captures of the toast and the activity center. No window opens.
"""
import argparse
import json
import os
import plistlib
import stat
import sys
import tempfile
from pathlib import Path
from shutil import copyfile

from audit_probe_host import run_host

HOST = r'''
import AppKit
import ArcanePorting
import Combine
import Darwin
import NXLibraryCore
@testable import NXLibrary
import SwiftUI

@main struct LibraryRefreshProbe {
    static let fake = URL(fileURLWithPath: /* FAKE */, isDirectory: true)
    @MainActor static var failures: [String] = []
    @MainActor static func expect(_ ok: Bool, _ what: String) { print((ok ? "ok   " : "FAIL ") + what); if !ok { failures.append(what) } }
    static func lines(_ name: String) -> [String] {
        ((try? String(contentsOf: fake.appendingPathComponent(name), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }
    static func forget() { for name in ["launches", "calls"] { try? FileManager.default.removeItem(at: fake.appendingPathComponent(name)) } }
    static func drive(_ change: (inout [[String: Any]], inout [String: Any]) -> Void) throws {
        let file = fake.appendingPathComponent("drive.json")
        var d = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var nodes = d["nodes"] as! [[String: Any]], behavior = d["behavior"] as! [String: Any]
        change(&nodes, &behavior)
        d["nodes"] = nodes; d["behavior"] = behavior
        try JSONSerialization.data(withJSONObject: d).write(to: file, options: .atomic)
    }
    static func behave(_ behavior: [String: Any]) throws { try drive { $1 = behavior } }
    static func alive() -> Int { lines("pids").compactMap { Int32($0) }.filter { kill($0, 0) == 0 }.count }

    @MainActor static func checkDaemonLifetime() async throws {
        let ready = fake.appendingPathComponent("daemon-ready")
        for (name, interrupt) in [("normal close", 0), ("crash", SIGABRT), ("SIGKILL", SIGKILL)] {
            try? FileManager.default.removeItem(at: ready)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--daemon-lifetime", "\(interrupt)"]
            let started = lines("pids").count
            try process.run()
            defer {
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            }
            for _ in 0..<150 where !FileManager.default.fileExists(atPath: ready.path) && process.isRunning {
                try await Task.sleep(for: .milliseconds(20))
            }
            let daemon = lines("pids").dropFirst(started).last.flatMap { Int32($0) }
            defer {
                // Keep a failing test isolated too. Only this subprocess's recorded daemon is eligible.
                if let daemon, kill(daemon, 0) == 0 { _ = kill(daemon, SIGKILL) }
            }
            guard let daemon, FileManager.default.fileExists(atPath: ready.path) else {
                expect(false, "daemon never ready before \(name), child status: \(process.isRunning ? -1 : process.terminationStatus)")
                continue
            }
            if interrupt != 0 {
                expect(kill(daemon, 0) == 0 && kill(process.processIdentifier, interrupt) == 0,
                       "a live daemon was running at \(name)")
            }
            for _ in 0..<150 where process.isRunning || kill(daemon, 0) == 0 {
                try await Task.sleep(for: .milliseconds(20))
            }
            expect(!process.isRunning && process.terminationStatus == interrupt && kill(daemon, 0) == -1 && errno == ESRCH,
                   "the daemon exits after \(name) without another Oort launch")
        }
    }

    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        assertFixtureHome()
        if CommandLine.arguments.dropFirst().first == "--daemon-lifetime" {
            signal(SIGABRT, SIG_DFL)
            let backend = RcloneStorageBackend(remote: ":local:", root: fake.path, executable: fake.appendingPathComponent("rclone"),
                                              config: fake.appendingPathComponent("rclone.conf"))
            guard try await backend.rootDirectories().contains("Photos") else { exit(2) }
            try Data().write(to: fake.appendingPathComponent("daemon-ready"), options: .atomic)
            if CommandLine.arguments.last == "0" {
                backend.stopRemoteControl()
                exit(0)
            }
            while true {
                try await Task.sleep(for: .seconds(600))
                withExtendedLifetime(backend) {}
            }
        }
        if ProcessInfo.processInfo.environment["OORT_DAEMON_LIFETIME_ONLY"] == "1" {
            try await checkDaemonLifetime()
            exit(failures.isEmpty ? 0 : 3)
        }
        suppressProbeNotifications()
        let temporary = FileManager.default.temporaryDirectory.path
        func snapshots() -> Set<String> {
            Set(((try? FileManager.default.contentsOfDirectory(atPath: temporary)) ?? []).filter { $0.hasPrefix("arcane-rclone-config-") })
        }
        let earlier = snapshots()
        let home = AppData.profile.home, data = AppData.supportRoot, d = AppData.preferences
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Applications"), withIntermediateDirectories: true)
        let store = CatalogStore(directory: data), repository = CatalogRepository(store: store)
        _ = try store.loadOrMigrate()
        _ = try repository.configureSource(.nxnative, enabled: true, root: nil)
        d.set(home.appendingPathComponent("Applications").path, forKey: "NXLibrary_LibraryFolder")
        d.set("fixture:Games", forKey: CloudLibraryPreference.storageKey)
        d.set(false, forKey: CloudLibraryPreference.enabledKey)
        d.set(fake.appendingPathComponent("rclone").path, forKey: CloudLibraryPreference.executableKey)
        d.set(true, forKey: CloudLibraryPreference.toolChoiceKey)
        d.set(true, forKey: "NXLibrary_SetupCompleted")
        d.set(Data(#"{"remote":"fixture","account":"AccountID","library":{"path":"Games","id":"LibraryID"}}"#.utf8), forKey: "NXLibrary_CloudDriveScope")
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        settings.settings.refreshLibraryAtLaunch = false
        settings.settings.interfaceSounds = false
        settings.settings.soundVolume = 0
        SoundEffectService.shared.bind(to: settings)
        let vm = AppViewModel(settingsStore: settings, catalog: try repository.load(), repository: repository)
        await vm.restoreActivity()
        let cloud = vm.cloudLibrary
        func finish(_ model: LibraryRefreshModel, limit: Double = 20) async throws {
            let end = Date().addingTimeInterval(limit)
            while model.current?.isRunning == true, Date() < end { try await Task.sleep(for: .milliseconds(10)) }
        }
        let online = Online()
        vm.libraryFolder = home.appendingPathComponent("Applications")
        let refresh = LibraryRefreshModel(app: vm, isOnline: { online.value })

        forget()
        refresh.start()
        try await finish(refresh)
        expect(refresh.current?.states.keys.sorted { $0.rawValue < $1.rawValue } == [.apps], "a cloud that is off is not part of the refresh")
        expect(lines("launches").isEmpty, "a cloud that is off starts no rclone")
        expect(refresh.current?.outcome == .upToDate, "the game apps alone are up to date: \(refresh.current!.stale)")

        cloud.useSettingsActivation(cloud.activationChoice(enabled: true))
        let model = cloud
        for _ in 0..<500 where model.archive == nil { try await Task.sleep(for: .milliseconds(10)) }
        expect(model.archive != nil, "the approved library opens")
        vm.restoreCloudQueue()
        for _ in 0..<200 where !cloud.hasRestoredQueue { try await Task.sleep(for: .milliseconds(10)) }
        // The approval's own Drive check is not part of any refresh measured below.
        await cloud.scopeTask?.value

        online.value = false
        forget()
        refresh.start()
        try await finish(refresh)
        expect(lines("launches").isEmpty && lines("calls").isEmpty, "a Mac that is offline asks nothing")
        expect(refresh.current?.outcome == .incomplete && refresh.cloudFailure == .offline, "offline is said, not hidden")
        online.value = true

        forget()
        refresh.start()
        try await finish(refresh)
        expect(refresh.current?.outcome == .changed(3), "three cloud games are added: \(String(describing: refresh.current?.outcome)) \(String(describing: cloud.checkFailure))")
        expect(lines("launches").filter { $0 == "rcd" }.count <= 1, "one rclone at most is started: \(lines("launches"))")
        expect(!lines("launches").contains("lsjson") && !lines("launches").contains("copyto"), "no single command: \(lines("launches"))")
        expect(alive() == 1, "one rclone lives: \(alive())")
        expect(vm.libraryGames.count == 3 && cloud.lastCompleteCheck != nil, "they are in the library")
        let first = lines("calls").count

        forget()
        refresh.start()
        try await finish(refresh)
        expect(refresh.current?.outcome == .upToDate, "a second refresh finds nothing new")
        expect(lines("launches") == ["config"], "it starts nothing but the look at the configuration: \(lines("launches"))")
        expect(!lines("calls").contains { $0.hasPrefix("operations/copyfile") }, "no record is read again")
        expect(lines("calls").count < first, "it asks less than the first: \(lines("calls").count) < \(first)")

        // Pressed again and again: one result, one rclone, nothing left running.
        try behave(["delay": 0.15])
        var ids: [UUID] = []
        for _ in 0..<6 { refresh.start(); ids.append(refresh.current!.id); try await Task.sleep(for: .milliseconds(60)) }
        try await finish(refresh)
        expect(refresh.current?.id == ids.last && refresh.current?.outcome == .upToDate, "the last press is the one that ends: \(String(describing: refresh.current?.outcome))")
        expect(cloud.importTask == nil && cloud.catalogCheck == nil && alive() == 1, "nothing of the others is left")
        expect(vm.libraryGames.count == 3, "no game doubled")

        refresh.start()
        try await Task.sleep(for: .milliseconds(120))
        refresh.cancel()
        expect(refresh.current?.outcome == .cancelled && cloud.importTask == nil, "Cancel stops it at once")
        try await Task.sleep(for: .milliseconds(400))
        expect(refresh.current?.outcome == .cancelled && vm.libraryGames.count == 3, "a late answer changes nothing")
        try behave([:])

        // What was shown stays while the next answer comes, and after one that fails.
        func shownInCloud() -> Int { vm.libraryGames.filter { cloud.downloadItem(for: $0) != nil }.count }
        let before = shownInCloud()
        var least = before
        let watch = cloud.objectWillChange.sink { DispatchQueue.main.async { MainActor.assumeIsolated { least = min(least, shownInCloud()) } } }
        refresh.start(); try await finish(refresh)
        expect(before == 3 && least == 3, "no cloud game leaves the screen during a refresh: \(before) then \(least)")
        let checked = cloud.lastCompleteCheck
        try behave(["error": "googleapi: Error 503: Backend Error"])
        refresh.start(); try await finish(refresh)
        expect(refresh.current?.outcome == .incomplete && refresh.cloudFailure == .offline, "an outage is an outage: \(String(describing: refresh.cloudFailure))")
        expect(shownInCloud() == 3 && cloud.lastCompleteCheck == checked, "the known state stays, with its own date")
        expect(LibraryRefreshModel.detail(refresh.current!)?.contains(checked!.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: L10n.context.formatLocale))) == true, "the date is written")
        expect(vm.settingsNotice == nil && cloud.startupFailure == nil, "a refresh opens no dialog")
        try behave([:])
        refresh.start(); try await finish(refresh)
        expect(refresh.current?.outcome == .upToDate, "and the next refresh recovers")
        watch.cancel()

        // rclone dies while it answers: single commands take over and say what they can; the next refresh is whole again.
        try behave(["die": true])
        refresh.start(); try await finish(refresh)
        expect(refresh.current?.outcome == .incomplete && shownInCloud() == 3, "a dead rclone is not an empty library")
        try behave([:])
        refresh.start(); try await finish(refresh)
        expect(refresh.current?.outcome == .upToDate && alive() == 1, "a new rclone serves the next one: \(String(describing: refresh.current?.outcome)) \(alive())")

        // An rclone too old to group its searches.
        try behave(["old": true])
        refresh.start(); try await finish(refresh)
        expect(refresh.current?.outcome == .upToDate, "an older rclone reads folder by folder")
        try behave([:])

        // Transfers decide alone: nothing the refresh read is at hand.
        let manifest = try? await cloud.archive!.latest(titleID: "0100000000010000")
        expect(manifest == nil, "the archive used for transfers never answers from a refresh")

        // The library folder is replaced between the first proof and the last.
        try drive { nodes, _ in nodes.append(["id": "Late", "name": "Late [0100000000040000]", "parent": "LibraryID"]) }
        try behave(["moves": true])
        refresh.start(); try await finish(refresh)
        expect(refresh.cloudFailure == .scopeChanged && vm.libraryGames.count == 3, "a library replaced while it is read is refused: \(String(describing: refresh.cloudFailure))")

        if let output = /* CAPTURES */ as String? { try capture(vm, to: URL(fileURLWithPath: output, isDirectory: true)) }
        cloud.stopRemoteControl()
        try await Task.sleep(for: .milliseconds(300))
        expect(alive() == 0, "no rclone outlives the connection")
        let kept = snapshots().subtracting(earlier)
        expect(kept.isEmpty, "no private configuration stays on disk: \(kept)")

        // Cancel on the scan's first publication, before its worker can return.
        cloud.useSettingsActivation(cloud.activationChoice(enabled: false))
        let localTitle = "0100000000050000"
        let contents = vm.gameAppsFolder.appendingPathComponent("Local fixture.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["DMTitleID": localTitle], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let revision = try repository.load().revision
        let cancelScan = vm.$isScanningLibrary.filter { $0 }.prefix(1).sink { _ in refresh.cancel() }
        refresh.start()
        try await finish(refresh)
        cancelScan.cancel()
        func waitForScan() async throws {
            for _ in 0..<500 where vm.isScanningLibrary { try await Task.sleep(for: .milliseconds(10)) }
            expect(!vm.isScanningLibrary, "the local scan releases the library")
        }
        try await waitForScan()
        expect(refresh.current?.outcome == .cancelled, "the local refresh is cancelled")
        let cancelledRevision = try repository.load().revision
        expect(cancelledRevision == revision && !vm.libraryGames.contains { $0.titleId == localTitle },
               "the cancelled worker does not publish on disk or in the library")

        vm.loadLibrary()
        try await waitForScan()
        let savedGames = try repository.load().nxnativeGames
        expect(savedGames.contains { $0.titleId == localTitle } && vm.libraryGames.contains { $0.titleId == localTitle },
               "an independent scan still publishes the same fixture")
        try await checkDaemonLifetime()
        exit(failures.isEmpty ? 0 : 3)
    }

    final class Online: @unchecked Sendable {
        private let lock = NSLock(); private var on = true
        var value: Bool { get { lock.withLock { on } } set { lock.withLock { on = newValue } } }
    }

    @MainActor static func capture(_ vm: AppViewModel, to output: URL) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_764_000_000)
        for language in [AppLanguage.french, .english] {
            let locale = AppLocale(language: language, region: language == .french ? "FR" : "US")
            L10n.setContext(locale)
            let code = language == .french ? "fr" : "en"
            let stale = [CloudLibraryFailure.offline.message(context: locale), L10n.format("The cloud games shown are those of %@.",
                [date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale.formatLocale))])].joined(separator: " ")
            func make(_ change: (inout LibraryRefresh) -> Void) -> LibraryRefresh {
                var refresh = LibraryRefresh(parts: [.apps, .steam, .cloud]); change(&refresh); return refresh
            }
            let all: [(String, LibraryRefresh)] = [
                ("en-cours", make { $0.end(.apps, .read) }),
                ("a-jour", make { r in LibraryRefresh.Part.allCases.forEach { r.end($0, .read) } }),
                ("nouveaux-jeux", make { r in LibraryRefresh.Part.allCases.forEach { r.end($0, .read) }; r.noteAdded(3) }),
                ("hors-ligne", make { r in r.end(.apps, .read); r.end(.steam, .read); r.end(.cloud, .stale(stale)) }),
                ("annulee", make { $0.cancel() }),
            ]
            for (name, refresh) in all {
                try image(LibraryRefreshToast(refresh: refresh).padding(60), "toast-\(name)-\(code)", output, .init(width: 1000, height: 300), locale)
                vm.libraryRefresh.preview(refresh, failure: name == "hors-ligne" ? .offline : nil)
                var focus = ActivityCenterFocus(); focus.selected = .refresh(refresh.id)
                try image(ActivityCenterView(viewModel: vm, porting: vm.porting, cloudLibrary: vm.cloudLibrary, focus: focus,
                    onFocus: { _ in }, onOpen: { _ in }, onCancel: { _ in }, onBack: {}, onOutside: {}), "centre-\(name)-\(code)", output,
                    .init(width: 1440, height: 820), locale)
            }
        }
    }

    @MainActor static func image(_ view: some View, _ name: String, _ folder: URL, _ size: CGSize, _ locale: AppLocale) throws {
        SeleneFonts.register()
        let host = NSHostingView(rootView: ZStack { SeleneBackdrop().still(true); view }
            .environment(\.nxAppLocale, locale).environment(\.seleneReduceMotion, true).environment(\.seleneShowButtonHints, true)
            .environment(\.colorScheme, .dark).seleneCanvasRoot().frame(width: size.width, height: size.height))
        host.frame.size = size
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        let end = Date().addingTimeInterval(0.5)
        repeat { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } while Date() < end
        precondition(!window.isVisible)
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        host.cacheDisplay(in: host.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("\(name).png"))
    }
}

'''


def record(title, name):
    import hashlib
    entries = [{"md5": "d41d8cd98f00b204e9800998ecf8427e", "path": "Contents/Info.plist", "size": 3}]
    digest = hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    body = json.dumps({"version": 2, "title_id": title, "created_at": "2026-11-01T00:00:00Z", "game_name": name, "bundle_name": name + ".app",
        "artifacts": [{"kind": "app", "unpacked_size": 3, "entry_count": 1, "inventory_sha256": digest, "options": {},
                       "files": {"folder": f"{name} [{title}]/app/{digest}/{name}.app", "entries": entries}}]}, separators=(",", ":"))
    return f"{1761955200000000:016d}-{hashlib.sha256(body.encode()).hexdigest()}.json", body


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, nargs="?")
    output = parser.parse_args().output
    if output and output.exists():
        parser.error("Choose a new output directory.")
    # A Unix socket path is short: the fake and its socket stay close to the root.
    with tempfile.TemporaryDirectory(prefix="refresh-", dir="/private/tmp") as folder:
        fake = Path(folder)
        nodes = [{"id": "LibraryID", "name": "Games", "parent": "AccountID"}, {"id": "Other", "name": "Photos", "parent": "AccountID"}]
        for i in range(1, 4):
            title, name = f"01000000000{i}0000", f"Game {i}"
            file, body = record(title, name)
            nodes += [{"id": f"Game{i}", "name": f"{name} [{title}]", "parent": "LibraryID"},
                      {"id": f"App{i}", "name": "app", "parent": f"Game{i}"},
                      {"id": f"Records{i}", "name": "manifests", "parent": f"Game{i}"},
                      {"id": f"File{i}", "name": file, "parent": f"Records{i}", "body": body}]
        (fake / "drive.json").write_text(json.dumps({"account": "AccountID", "nodes": nodes, "behavior": {}}))
        (fake / "rclone.conf").write_text("[fixture]\ntype = drive\n")
        (fake / "tmp").mkdir()
        rclone = fake / "rclone"
        copyfile(Path(__file__).with_name("fake_drive_rclone.py"), rclone)
        rclone.write_text(rclone.read_text().replace("#!/usr/bin/env python3", f"#!{sys.executable} -S", 1))
        rclone.chmod(0o700)
        captures = 'home.appendingPathComponent("captures").path' if output else "nil"
        run_host(HOST.replace("/* FAKE */", json.dumps(str(fake))).replace("/* CAPTURES */", captures), save_model=True, capture=output,
                 unix_sockets=True, environment={"TMPDIR": str(fake / "tmp") + "/", "RCLONE_CONFIG": str(fake / "rclone.conf"),
                                                 "RCLONE_CONFIG_PASS": "unused"})


main()
