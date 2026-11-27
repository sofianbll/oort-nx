#!/usr/bin/env python3
"""Exercise the actual startup recovery coordinator with isolated catalogs, no windows.

Only profile selection/preparation and shell construction are substituted. The
catalog, conflict candidates, archives and recovery operations are real Core I/O.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json
BIN = ROOT / '.build/debug'
source = (ROOT / 'Sources/NXLibrary/Views/Launch/DevelopmentStartupView.swift').read_text()
start = source.index('@MainActor\nfinal class DevelopmentStartup:')
end = source.index('\nprivate enum DevelopmentStartupFailure:', start)
coordinator = source[start:end]

host = r'''
import Foundation
import AppKit
import Combine
import Darwin
import NXLibraryCore
import ArcanePorting
import os

enum AppData {
    static var supportRoot = URL(fileURLWithPath: "/unused")
    static var rejectPreparation = false
    static var movedProfile: AppDataProfile?
    static var preferences: UserDefaults { UserDefaults(suiteName: supportRoot.appendingPathComponent("fixture-prefs").path)! }
    static var profile: AppDataProfile { movedProfile ?? .init(home: supportRoot, isDevelopment: false) }
    static func prepare(contents: DevelopmentProfileImporter.Contents) throws {
        if rejectPreparation { throw CocoaError(.fileReadNoPermission) }
        if let movedProfile {
            let old = movedProfile.legacySupportRoot
            _ = try LibraryMove(from: old, to: supportRoot).prepare(preferences: { [:] }, savePreferences: { _ in })
            try LibraryPathRepair(from: old, to: supportRoot).prepare(checks: DevelopmentProfileImporter.portingChecks,
                preferences: { [:] }, savePreferences: { _ in })
        }
    }
}
struct NSRunningApplication {
    let processIdentifier: pid_t
    static func runningApplications(withBundleIdentifier _: String) -> [Self] { [] }
}
struct AppSettingsStore {}
final class AppViewModel { var alertMessage: String? }
final class AppShellState {
    let catalog: CatalogDocument
    let viewModel = AppViewModel()
    init(settings: AppSettingsStore, catalog: CatalogDocument, repository: CatalogRepository) {
        self.catalog = catalog
    }
}
enum DevelopmentStartupFailure: Error { case otherCopyRunning }
// ACTUAL_COORDINATOR

@main struct Check {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        AppData.supportRoot = root
        switch CommandLine.arguments.dropFirst(2).first {
        case "copied":
            let profile = AppDataProfile(home: root, isDevelopment: false)
            AppData.movedProfile = profile
            AppData.supportRoot = profile.supportRoot
            let old = profile.legacySupportRoot
            let staging = old.appendingPathComponent("Temp/fixture/Waiting.app")
            let final = root.appendingPathComponent("Fixture.app")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            var game = PortedGame(name: "Fixture", url: final, platform: .macApp, sizeBytes: 0, modificationDate: .now)
            game.pendingInstall = PendingInstall(tempApp: staging, finalApp: final,
                record: BuildRecord(logPath: "", outputPath: final.path), toolchain: .init())
            let catalog = try CatalogRepository(store: CatalogStore(directory: old)).updateNXNativeGames { $0 = [game] }
            let journal = old.appendingPathComponent("catalog-removal-pending.json")
            try Data("{}".utf8).write(to: journal)
            let startup = DevelopmentStartup { _, _ in .ready }
            await startup.prepare()
            precondition(startup.failure == nil && startup.shell?.catalog.games.first?.nxnativeGame?.pendingInstall == nil)
            precondition(startup.shell?.viewModel.alertMessage?.split(separator: "\n").count == 2)
            precondition(FileManager.default.fileExists(atPath: staging.path))
            let kept = try CatalogStore.decode(Data(contentsOf: old.appendingPathComponent("catalog.json")))
            precondition(kept == catalog && FileManager.default.fileExists(atPath: journal.path))
            print("The shell opens and reports both previous-library operations without taking ownership of them.")
            return
        case "concurrency":
            _ = try CatalogStore(directory: root).loadOrMigrate()
            try Data("fixture".utf8).write(to: root.appendingPathComponent("settings.json"))
            var first: DevelopmentStartup? = DevelopmentStartup()
            await first?.prepare()
            precondition(first?.downgradeNotice == .copy([]))
            let second = DevelopmentStartup()
            await second.prepare()
            precondition(second.failure != nil && second.shell == nil && second.downgradeNotice == nil,
                         "another copy cannot advance even while the first waits for approval")
            first = nil
            await second.prepare()
            precondition(second.downgradeNotice == .copy([]))
            await second.prepare(acceptingDowngradeWarning: true)
            precondition(second.shell != nil)
            let third = DevelopmentStartup()
            await third.prepare()
            precondition(third.failure != nil && third.shell == nil, "the lease outlives checkpoint publication")
            print("Profile lease holds through the notice and after opening the shell.")
            return
        case "disk-full":
            let startup = DevelopmentStartup { _, _ in
                throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC)])
            }
            await startup.prepare()
            precondition(String(describing: startup.downgradeNotice).contains("diskFull"),
                         "a wrapped ENOSPC should say the disk is full")
            await startup.continueWithoutCopy()
            precondition(startup.shell != nil)
            print("Wrapped ENOSPC has a distinct notice and does not block startup.")
            return
        case "slow":
            do {
                let fast = DevelopmentStartup { _, _ in .ready }
                await fast.prepare()
                precondition(!fast.showCopyProgress)
            }
            let slow = DevelopmentStartup { _, _ in
                Thread.sleep(forTimeInterval: 1.6)
                return .ready
            }
            let task = Task { await slow.prepare() }
            try await Task.sleep(for: .milliseconds(250))
            precondition(!slow.showCopyProgress, "do not flash progress for a short copy")
            try await Task.sleep(for: .milliseconds(950))
            precondition(slow.showCopyProgress, "show progress after one second")
            await task.value
            precondition(!slow.showCopyProgress && slow.shell != nil)
            print("Progress appears after a second, then clears.")
            return
        default: break
        }
        let store = CatalogStore(directory: root)
        var mixed = try store.loadOrMigrate()
        mixed.games.append(.init(steam: SteamCatalogGame(appID: 42, name: "Fixture")))
        mixed = try store.save(mixed, expectedRevision: mixed.revision)
        let legacy = root.appendingPathComponent("library.json")
        // Older app creates a legacy library after an initially empty migration.
        try Data("older-app bytes".utf8).write(to: legacy)

        do {
            let startup = DevelopmentStartup()
            await startup.prepare()
            precondition(startup.shell == nil && startup.downgradeNotice == .copy([]) && startup.failure == nil,
                         "Expected downgrade warning, got \(String(describing: startup.downgradeNotice)); failure: \(startup.failure ?? "none")")
            precondition(startup.recovery == nil && startup.legacyConflict == nil)
            await startup.prepare(acceptingDowngradeWarning: true)
            precondition(startup.shell == nil && startup.failure != nil)
            precondition(startup.legacyConflict != nil && startup.recovery == nil && !startup.working)
            await startup.keepCurrentLibrary()
            precondition(startup.shell?.catalog.games == mixed.games)
            precondition(startup.failure == nil && startup.legacyConflict == nil && !startup.working)
        }
        let unchangedLegacy = try Data(contentsOf: legacy)
        precondition(unchangedLegacy == Data("older-app bytes".utf8))

        try Data("second edit".utf8).write(to: legacy)
        do {
            let stale = DevelopmentStartup()
            await stale.prepare()
            precondition(stale.legacyConflict != nil && stale.shell == nil)
            try Data("third edit".utf8).write(to: legacy)
            await stale.keepCurrentLibrary()
            precondition(stale.shell == nil && stale.legacyConflict == nil && !stale.working)
            precondition(stale.failure != nil)
            await stale.prepare()
            precondition(stale.legacyConflict != nil)
            await stale.keepCurrentLibrary()
            precondition(stale.shell?.catalog.games == mixed.games)
        }
        do {
            let healthy = DevelopmentStartup()
            await healthy.prepare()
            precondition(healthy.shell != nil && healthy.legacyConflict == nil && healthy.recovery == nil)
        }

        AppData.rejectPreparation = true
        do {
            let blocked = DevelopmentStartup()
            await blocked.prepare()
            precondition(blocked.shell == nil && blocked.failure != nil && !blocked.working)
            precondition(blocked.legacyConflict == nil && blocked.recovery == nil)
            AppData.rejectPreparation = false
            await blocked.prepare()
            precondition(blocked.shell != nil && blocked.failure == nil)
        }

        let checkpoint = root.appendingPathComponent("DowngradeProtection/checkpoint.plist")
        let verified = try Data(contentsOf: checkpoint)
        try Data("damaged checkpoint".utf8).write(to: checkpoint)
        do {
            let withoutCopy = DevelopmentStartup()
            await withoutCopy.prepare()
            precondition(withoutCopy.shell == nil && withoutCopy.failure == nil && withoutCopy.downgradeNotice == .failed)
            precondition(withoutCopy.recovery == nil && withoutCopy.legacyConflict == nil)
            await withoutCopy.prepare()
            precondition(withoutCopy.downgradeNotice == .failed)
            await withoutCopy.continueWithoutCopy()
            precondition(withoutCopy.shell != nil && withoutCopy.downgradeNotice == nil)
        }
        let unchanged = try Data(contentsOf: checkpoint)
        precondition(unchanged == Data("damaged checkpoint".utf8))

        let nextStart = DevelopmentStartup()
        await nextStart.prepare()
        precondition(nextStart.shell == nil && nextStart.downgradeNotice == .failed, "Skipping is only in memory")
        try verified.write(to: checkpoint)
        await nextStart.prepare()
        precondition(nextStart.shell != nil && nextStart.downgradeNotice == nil)
        print("Actual startup recovery checks passed: one-time warning, legacy conflict, retry, and skip for one start only.")
    }
}
'''.replace('// ACTUAL_COORDINATOR', coordinator)

with tempfile.TemporaryDirectory(prefix='catalog-startup-recovery-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    package_name = re.search(r'"SWIFT_PACKAGE_NAME"\s*:\s*"([^"]+)"', (ROOT / '.build/manifest.pif').read_text())[1]
    subprocess.run(['xcrun', 'swiftc', '-j', '4', '-parse-as-library', '-package-name', package_name, '-I', str(BIN), str(swift),
                    *map(str, names.objects(BIN)),
                    '-o', str(executable)], cwd=ROOT, check=True)
    home = scratch / 'home'
    home.mkdir()
    subprocess.run([str(executable), str(scratch / 'profile'), *sys.argv[1:]], check=True,
                   env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
