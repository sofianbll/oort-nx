#!/usr/bin/env python3
"""Render cloud and multiplayer views offscreen with synthetic states; never start the launcher."""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

HOST = r'''
import AppKit
import Combine
import CoreText
import SwiftUI
import NXLibraryCore
import ArcanePorting

@main struct CloudScreenProbe {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let font = URL(fileURLWithPath: CommandLine.arguments[2])
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        NSApplication.shared.applicationIconImage = NSImage(contentsOfFile: CommandLine.arguments[3])
        let data = AppData.supportRoot
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        let model = vm.cloudLibrary
        let game = PortedGame(name: "Lunar Observatory", url: data.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000001000")
        model.update(game.id) {
            $0.copies = [.app: .screenFixture(.cloudOnly), .cache: .screenFixture(.synchronized)]
        }
        // CONNECTION_FIXTURE
        try render("panel", output, CloudLibraryPanel(viewModel: vm, model: model, game: game))
        // DISPLAY_FIXTURE
        for (name, locale) in [("rebuild", AppLocale(language: .french, region: "FR")),
                               ("rebuild-de", AppLocale(language: .german, region: "DE"))] {
            L10n.setContext(locale)
            vm.screenRebuildNotice()
            let notice = vm.settingsNotice!
            precondition(notice.choices == ["CACHE_DOWNLOAD_CHOICE", "Rebuild with this Mac’s cache", "Rebuild without cache", "Cancel"])
            precondition(vm.settingsNoticeFocus == 0 && notice.cancelIndex == 3)
            try renderNotice(name, output, notice, width: 1440)
        }
        L10n.setContext(.init(language: .english, region: "US"))
        vm.settingsNotice = nil
        try render("settings", output, SettingsCloudLibrarySection(
            viewModel: vm, model: model, settings: settings, advanced: .constant(false),
            onEdit: {}, onEditSources: {}, onActions: { _ in })
            .padding(24).frame(width: 1040))
        // ADVANCED_SETTINGS
        let assistant = CloudSetupAssistant(viewModel: vm, model: model /* ENTRY */) {}
        // ASSISTANT_CHECK
        try render("assistant", output, assistant
            .environment(\.nxAppLocale, .init(language: .french, region: "FR"))
            .environment(\.seleneButtonNames, .xbox))
        precondition(CloudLibraryTileBadge.artworkOpacity(model.states[game.id]) == 0.55)
        try render("tile", output,
            CollectionCoverRow(games: [.init(nxnative: game)], selectedID: game.id,
                artwork: ArtworkStore(), boxArt: vm.boxArt, boxArtIndexVersion: 0,
                officialName: { _ in nil }, needsMetadata: { _ in }, cloud: model,
                showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in }),
            size: .init(width: 400, height: 440))
        let queuedRequest = CloudLibraryModel.Request(id: game.id, name: game.name, action: .restore(.app),
            storage: model.preference.storage, scope: .init(title: game.titleId!, urls: []),
            importDestination: nil, sourceFiles: nil, onSuccess: nil)
        let addGame = AddGameView(viewModel: vm, router: AppRouter())
        func adoptionRow() -> AddGameRow { addGame.rows(for: 1).first { $0.id == "adoptApp" }! }
        precondition(adoptionRow().enabled)
        vm.isBuilding = true
        precondition(!adoptionRow().enabled && adoptionRow().about == L10n.text("Available after the active build finishes or is cancelled."))
        vm.isBuilding = false
        let activity = ActivityCenterView(viewModel: vm, porting: vm.porting, cloudLibrary: model, focus: .init(),
            onFocus: { _ in }, onOpen: { _ in }, onCancel: { _ in }, /* ACTIVITY_DISMISS */)
        precondition(ActivityCenterView.rows(vm).isEmpty)
        try render("activity-empty", output, activity)
        model.queue = [queuedRequest]
        precondition(!adoptionRow().enabled && adoptionRow().about == L10n.text("Available after the cloud transfers."))
        model.update(game.id) { $0.action = queuedRequest.action; $0.queued = true }
        try render("panel-queued", output, CloudLibraryPanel(viewModel: vm, model: model, game: game))
        let activeGame = PortedGame(name: "Solar Observatory", url: data.appendingPathComponent("Active.app"),
                                  platform: .macApp, sizeBytes: 0, modificationDate: .now, titleId: "0100000000002000")
        let request = CloudLibraryModel.Request(id: activeGame.id, name: activeGame.name, action: .restore(.app),
            storage: model.preference.storage, scope: .init(title: activeGame.titleId!, urls: []),
            importDestination: nil, sourceFiles: nil, onSuccess: nil)
        model.active = (request, Task {})
        model.update(activeGame.id) {
            $0.action = request.action
            $0.progress = .init(.downloading, kind: .app, transfer: .init(bytesTransferred: 42_000_000, totalBytes: 100_000_000))
        }
        try render("activity", output, activity)
        try render("tile-progress", output,
            CollectionCoverRow(games: [.init(nxnative: activeGame)], selectedID: activeGame.id,
                artwork: ArtworkStore(), boxArt: vm.boxArt, boxArtIndexVersion: 0,
                officialName: { _ in nil }, needsMetadata: { _ in }, cloud: model,
                showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in }),
            size: .init(width: 400, height: 440))
        // DOWNLOAD_FILL_CHECK
        // TRANSFER_STATES
        // PLAY_TRANSFER_CHECK
        // TYPED_PATH_CHECK
        // MULTIPLAYER_CHECK
        // REFERENCE_START
        model.active = nil
        model.queue = []
        L10n.setContext(.init(language: .french, region: "FR"))
        model.setReferenceFolder("1-arcane-fixture")
        func referenceSettings() -> some View {
            SettingsCloudLibrarySection(viewModel: vm, model: model, settings: settings, advanced: .constant(false),
                onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
                .environment(\.nxAppLocale, L10n.context)
                .padding(24).frame(width: 1040)
        }
        try await vm.checkReferenceScreen(access: true)
        precondition(model.referenceCheck?.name == "Arcane-nx" && model.referenceCheck?.count == 0)
        try render("reference-settings", output, referenceSettings())
        try await vm.checkReferenceScreen(access: false)
        precondition(model.referenceCheck?.failure == .folderMissing)
        try render("reference-error", output, referenceSettings())
        try render("reference-editor", output, CloudReferenceDialog(viewModel: vm, onClose: {})
            .environment(\.nxAppLocale, L10n.context))
        model.update(game.id) {
            $0.action = nil; $0.queued = false; $0.progress = nil
            $0.copies = [.app: .screenFixture(.newerOnThisMac, hasLocalCopy: true),
                         .cache: .screenFixture(.notInCloud, hasLocalCopy: false)]
            $0.referenceKinds = [.app]
            $0.referenceCopies = [.app: .init(downloadBytes: 45_000_000, totalBytes: 600_000_000,
                                             legacy: false, updatesLocal: true)]
        }
        try render("reference-update", output, CloudLibraryPanel(viewModel: vm, model: model, game: game)
            .environment(\.nxAppLocale, L10n.context))
        precondition(model.states[game.id]?.personalCopyIsOlder(.app) == false)
        model.update(game.id) {
            $0.referenceCopies = [:]
            $0.referenceAvailability[.app] = .screenFixture(.synchronized)
            precondition($0.personalCopyIsOlder(.app) && $0.canUpload(.app))
            precondition(!$0.personalCopyIsOlder(.cache))
        }
        try render("reference-personal-older", output, CloudLibraryPanel(viewModel: vm, model: model, game: game)
            .environment(\.nxAppLocale, L10n.context))
        vm.showSettingsNotice(title: L10n.format("Added %@ to the library.", [game.name]),
                              message: L10n.text("Content not verified"), cancelTitle: L10n.text("Close"))
        try renderNotice("adoption-unverified", output, vm.settingsNotice!, width: 1280)
        // REFERENCE_END
        if CommandLine.arguments.count > 4 {
            try compareDetails(output, baseline: URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true))
        }
    }

    static func compareDetails(_ output: URL, baseline: URL) throws {
        let images = try FileManager.default.contentsOfDirectory(atPath: baseline.path).filter {
            ($0.hasPrefix("state-") || $0.hasPrefix("cloud-button-")) && $0.hasSuffix("-details.png")
        }.sorted()
        precondition(images.count == 12, "Expected six transfer phases and six cloud button states")
        for name in images {
            func bitmap(_ folder: URL) throws -> NSBitmapImageRep {
                guard let image = NSBitmapImageRep(data: try Data(contentsOf: folder.appendingPathComponent(name))),
                      !image.isPlanar && image.bitsPerSample == 8 && image.bitmapData != nil
                else { throw CocoaError(.fileReadCorruptFile) }
                return image
            }
            let before = try bitmap(baseline)
            let after = try bitmap(output)
            precondition(before.pixelsWide == after.pixelsWide && before.pixelsHigh == after.pixelsHigh
                && before.bitsPerPixel == after.bitsPerPixel, "\(name): bitmap format differs")
            let pixelSize = before.bitsPerPixel / 8
            var differentPixels = 0
            for y in 0..<before.pixelsHigh {
                for x in 0..<before.pixelsWide {
                    let a = before.bitmapData! + y * before.bytesPerRow + x * pixelSize
                    let b = after.bitmapData! + y * after.bytesPerRow + x * pixelSize
                    if memcmp(a, b, pixelSize) != 0 { differentPixels += 1 }
                }
            }
            precondition(differentPixels == 0, "\(name): \(differentPixels) different pixels with motion reduced")
            print("\(name): 0 different pixels")
        }
    }

    @MainActor static func renderNotice(_ name: String, _ output: URL, _ notice: SettingsNotice, width: CGFloat) throws {
        try render(name, output, SeleneChoiceDialog(title: notice.title, message: notice.message,
            choices: notice.choices, focus: .constant(notice.initialFocus), /* NOTICE_LAYOUT */
            details: notice.choiceDetails, onChoose: { _ in }).environment(\.nxAppLocale, L10n.context),
            size: .init(width: width, height: 620))
    }

    @MainActor static func render<V: View>(_ name: String, _ output: URL, _ view: V,
                                          size: CGSize = .init(width: 1280, height: 1000)) throws {
        let canvas = SeleneCanvas(size: .init(width: 1920, height: 1080))
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .background(Color(red: 0.09, green: 0.13, blue: 0.20))
            .environment(\.colorScheme, .dark)
            .environment(\.seleneCanvas, canvas)
            .environment(\.seleneReduceMotion, true))
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }
}
'''

DOWNLOAD_FILL = r'''
        let fr = AppLocale(language: .french, region: "FR")
        model.active = nil
        model.queue = []
        func checkDownloadFill(_ expected: Double?) {
            let state = model.states[game.id]!
            precondition(CloudLibraryProgressView.downloadFill(state, item: .app) == expected)
            precondition(CloudLibraryProgressView.downloadFill(state, item: .cache) == nil)
        }
        model.update(game.id) { $0.action = nil; $0.queued = false; $0.progress = nil }
        checkDownloadFill(nil)
        try render("panel-download-idle", output,
            CloudLibraryPanel(viewModel: vm, model: model, game: game).environment(\.nxAppLocale, fr))
        for percent in [0, 40, 100, nil] as [Int?] {
            model.update(game.id) {
                $0.action = .restore(.app)
                $0.progress = .init(.downloading, kind: .app,
                    transfer: percent.map { .init(bytesTransferred: Int64($0) * 1_000_000, totalBytes: 100_000_000) })
            }
            checkDownloadFill(percent.map { Double($0) / 100 })
            let suffix = percent.map(String.init) ?? "unknown"
            if percent == 40 {
                let progress = model.states[game.id]?.progress
                let english = AppLocale(language: .english, region: "US")
                precondition(CloudLibraryProgressView.bytesSummary(progress, context: english) == "40 MB of 100 MB")
                precondition(CloudLibraryProgressView.downloadSummary(progress, context: english) ==
                             "Downloading app · 40 MB of 100 MB")
            }
            try render("panel-download-\(suffix)", output,
                CloudLibraryPanel(viewModel: vm, model: model, game: game).environment(\.nxAppLocale, fr))
            try render("spotlight-download-\(suffix)", output,
                SpotlightGameInfoView(game: game, logo: nil,
                    presentation: .init(game: game, metadata: nil, totalPlaytime: 0, lastPlayed: nil),
                    isRunning: false, focusedPill: 0, onPill: { _ in }, onHoverPill: { _ in },
                    cloud: model, showsCloudPill: true, downloadsApp: true, downloadEnabled: true)
                    .environment(\.nxAppLocale, fr),
                size: .init(width: 1120, height: 460))
            try render("details-download-\(suffix)", output,
                DetailsTopBlock(game: game, logo: nil,
                    presentation: .init(game: game, metadata: nil, totalPlaytime: 0, lastPlayed: nil),
                    isRunning: false, focusedPill: 0, primaryEnabled: true, expanded: .constant(false),
                    onPrimary: {}, onSecondary: {}, onFavorite: {}, onHoverPill: { _ in }, pillSet: .normal,
                    cloud: model, showsCloudPill: true, downloadEnabled: true)
                    .environment(\.nxAppLocale, fr),
                size: .init(width: 1120, height: 460))
        }
        model.update(game.id) { $0.progress = .init(.verifying, kind: .app, downloadComplete: true) }
        checkDownloadFill(1)
        precondition(CloudLibraryProgressView.fraction(model.states[game.id]?.progress) == nil)
        model.update(game.id) { $0.progress = .init(.readyToInstall, kind: .app, downloadComplete: true) }
        checkDownloadFill(1)
        let waiting = CloudLibraryIndicator(state: model.states[game.id]!, item: .app)
        precondition(waiting.status == .queued && !waiting.isTransferring)
        precondition(waiting.label(context: fr) == "WAITING_LABEL_FR")
        try render("panel-update-ready", output,
            CloudLibraryPanel(viewModel: vm, model: model, game: game).environment(\.nxAppLocale, fr))
        model.active = (queuedRequest, Task {})
        try render("activity-update-ready", output, activity.environment(\.nxAppLocale, fr),
            size: .init(width: 1440, height: 800))
        model.active = nil
        model.update(game.id) { $0.queued = true }
        checkDownloadFill(nil)
'''

TRANSFER_STATES = r'''
        let fr = AppLocale(language: .french, region: "FR")
        var installed = game
        installed.status = .builtSourcesMissing
        for phase in ["queued", "running", "verifying", "waiting", "ready", "failed"] {
            vm.clearActivityForProbe(queuedRequest.token)
            model.queue = phase == "queued" ? [queuedRequest] : []
            let live = ["running", "verifying", "waiting"].contains(phase)
            model.active = live ? (queuedRequest, Task {}) : nil
            model.update(game.id) {
                $0.action = live || phase == "queued" ? queuedRequest.action : nil
                $0.queued = phase == "queued"
                $0.progress = switch phase {
                case "running": .init(.downloading, kind: .app,
                    transfer: .init(bytesTransferred: 42_000_000, totalBytes: 100_000_000))
                case "verifying": .init(.verifying, kind: .app, downloadComplete: true)
                case "waiting": .init(.readyToInstall, kind: .app, downloadComplete: true)
                default: nil
                }
                $0.copies[.app] = .screenFixture(phase == "ready" ? .synchronized : .cloudOnly, fileByFile: true)
                $0.issue = phase == "failed" ? (.app, L10n.text("Cloud operation failed", context: fr), true) : nil
                // TRANSFER_TERMINAL
            }
            if phase == "ready" || phase == "failed" {
                vm.recordActivity(queuedRequest.token, job: .cloud(queuedRequest.entry), name: game.name,
                    outcome: phase == "ready" ? .succeeded : .failed(L10n.text("Cloud operation failed", context: fr)))
            }
            let panel = CloudLibraryPanel(viewModel: vm, model: model, game: game)
            let displayedGame = phase == "ready" ? installed : game
            // CHECK_TRANSFER_CONTROLS
            try render("state-\(phase)-panel", output, panel.environment(\.nxAppLocale, fr))
            try render("state-\(phase)-tile", output,
                CollectionCoverRow(games: [.init(nxnative: game)], selectedID: game.id,
                    artwork: ArtworkStore(), boxArt: vm.boxArt, boxArtIndexVersion: 0,
                    officialName: { _ in nil }, needsMetadata: { _ in }, cloud: model,
                    showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in }).environment(\.nxAppLocale, fr),
                size: .init(width: 400, height: 440))
            try render("state-\(phase)-details", output,
                DetailsTopBlock(game: displayedGame, logo: nil,
                    presentation: .init(game: displayedGame, metadata: nil, totalPlaytime: 0, lastPlayed: nil),
                    isRunning: false, focusedPill: 0, primaryEnabled: true, expanded: .constant(false),
                    onPrimary: {}, onSecondary: {}, onFavorite: {}, onHoverPill: { _ in }, pillSet: .normal,
                    cloud: model, showsCloudPill: true, downloadEnabled: true).environment(\.nxAppLocale, fr),
                size: .init(width: 1120, height: 520))
            try render("state-\(phase)-activity", output, activity.environment(\.nxAppLocale, fr),
                size: .init(width: 1440, height: 800))
        }
        model.update(game.id) { $0.issue = nil }
        vm.clearActivityForProbe(queuedRequest.token)
'''

CLOUD_BUTTON = r'''
        var local = game
        local.status = .builtSourcesMissing
        for (name, copy, sending, expected): (String, CloudArtifactStatus.State, Bool, MaterialIcon) in [
            ("synchronized", .synchronized, false, .cloudDone), ("remote-only", .cloudOnly, false, .cloudDownload),
            ("newer-here", .newerOnThisMac, false, .cloudUpload), ("not-in-cloud", .notInCloud, false, .cloud),
            ("unknown", .unknown, false, .cloud), ("sending", .notInCloud, true, .cloudUpload)
        ] {
            model.update(game.id) {
                $0 = .init()
                $0.copies = [.app: .screenFixture(copy, hasLocalCopy: copy != .cloudOnly)]
                if sending {
                    $0.action = .upload(.app)
                    $0.progress = .init(.uploading, kind: .app,
                        transfer: .init(bytesTransferred: 42_000_000, totalBytes: 100_000_000))
                }
            }
            let indicator = CloudLibraryIndicator(state: model.states[game.id]!)
            precondition(indicator.pillIcon == expected && indicator.isTransferring == sending)
            let displayedGame = copy == .cloudOnly ? game : local
            try render("cloud-button-\(name)-details", output,
                DetailsTopBlock(game: displayedGame, logo: nil,
                    presentation: .init(game: displayedGame, metadata: nil, totalPlaytime: 0, lastPlayed: nil),
                    isRunning: false, focusedPill: 2, primaryEnabled: true, expanded: .constant(false),
                    onPrimary: {}, onSecondary: {}, onFavorite: {}, onHoverPill: { _ in }, pillSet: .normal,
                    cloud: model, showsCloudPill: true, downloadEnabled: true).environment(\.nxAppLocale, fr),
                size: .init(width: 1120, height: 520))
        }
        model.update(game.id) { $0 = .init() }
'''

PLAY_TRANSFER = r'''
extension CloudScreenProbe {
    @MainActor static func checkPlayDuringTransfer(in root: URL, output: URL) async throws {
        let fm = FileManager.default
        let folder = root.appendingPathComponent("transfer-fixture")
        let app = folder.appendingPathComponent("Running.app")
        let remote = folder.appendingPathComponent("personal")
        let shared = folder.appendingPathComponent("reference")
        let config = folder.appendingPathComponent("rclone.conf")
        let title = "0100000000009000", bundleID = "local.arcane.screen-game"
        for directory in [app.appendingPathComponent("Contents/MacOS"), remote, shared] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("[fixture]\ntype = alias\nremote = :local:\(shared.path)\n".utf8).write(to: config)
        let rclone = RcloneStorageBackend.findExecutable()!
        // Exercise real local transfers without starting an RC daemon the probe could leave behind.
        let run: RcloneConfiguration.Run = { _, args, _ in
            try await SystemCommandRunner().runCancellable(rclone, args + ["--config", config.path], environment: [:])
        }
        let backend = RcloneStorageBackend(remote: ":local:", root: remote.path, run: run)
        let referenceWrite = RcloneStorageBackend(remote: ":local:", root: shared.path, run: run)
        let referenceRead = RcloneStorageBackend(remote: "fixture", root: "", run: run).reference(folderID: "1-fixture")!
        let plist = app.appendingPathComponent("Contents/Info.plist")
        func sign(_ version: String) throws {
            let info: [String: String] = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "Fixture",
                "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version, "DMTitleID": title]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
            let command = Process()
            command.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            command.arguments = ["--force", "--sign", "-", app.path]
            try command.run()
            command.waitUntilExit()
            precondition(command.terminationStatus == 0)
        }
        func version() throws -> String? {
            let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
            return (info as? [String: String])?["CFBundleShortVersionString"]
        }
        func until(_ predicate: () -> Bool) async throws {
            for _ in 0..<1_000 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw CocoaError(.fileReadUnknown, userInfo: [NSDebugDescriptionErrorKey: "Timed out in play-transfer fixture"])
        }
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/Fixture"))
        try sign("1.0")
        var game = PortedGame(name: "Fixture", url: app, platform: .macApp, sizeBytes: 0,
                              modificationDate: .now, bundleId: bundleID, titleId: title)
        game.status = .builtSourcesMissing
        let repository = CatalogRepository(store: .init(directory: root))
        _ = try repository.mergeNXNative(scanned: [game], enableSource: true)
        let settings = AppSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        func makeModel() throws -> AppViewModel {
            let catalog = try repository.load()
            let vm = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository)
            vm.applyCatalog(catalog)
            vm.cloudLibrary.installScreenArchives(backend)
            return vm
        }

        var vm = try makeModel()
        let monitor = RunningGameMonitor(center: NotificationCenter())
        monitor.setGames([game])
        RunningGameMonitor.screenRunning.withLock { $0 = bundleID }
        monitor.start(sessions: PlaySessionStore(), engineFolder: { "" })
        let watch = monitor.$runningGameIDs.sink { _ in
            // QUEUE_MONITOR_CALLBACK
        }
        defer { watch.cancel(); monitor.stop() }
        precondition(monitor.runningGameIDs == [game.id])
        vm.restoreCloudQueue()
        try await until { vm.cloudLibrary.hasRestoredQueue }
        vm.cloudLibrary.update(game.id) {
            $0.copies = [.app: .screenFixture(.notInCloud, hasLocalCopy: true),
                         .cache: .screenFixture(.notInCloud, hasLocalCopy: false)]
        }
        precondition(vm.canChangeCloudLibrary(.upload(.app), for: game))
        for action: CloudLibraryAction in [.upload(.cache), .upload(nil), .restore(.cache), .free([.app])] {
            precondition(!vm.canChangeCloudLibrary(action, for: game))
        }
        do {
            try vm.porting.beginBuild(for: game)
            preconditionFailure("Rebuild started during play")
        } catch CloudArchiveError.busy {}
        vm.performCloudLibrary(.upload(.app), for: game)
        guard let sending = vm.cloudLibrary.active?.task else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSDebugDescriptionErrorKey: "App upload was not queued"])
        }
        await sending.value
        let archive = vm.cloudLibrary.archive!
        let manifest = try await archive.latest(titleID: title)
        let sentVersion = try version()
        precondition(manifest?.artifacts.map(\.kind) == [.app] && sentVersion == "1.0",
                     vm.cloudLibrary.states[game.id]?.issue?.message ?? "App upload did not publish")
        precondition(monitor.runningGameIDs == [game.id] && !vm.saveGate.isBusy(titleID: title))
        try await until { vm.cloudLibrary.states[game.id]?.refreshing != true }

        // Personal download: the running process can be a Finder copy elsewhere, while this path is absent.
        try fm.removeItem(at: app)
        let offline = RcloneStorageBackend(remote: ":local:", root: remote.path) { _, args, _ in
            if args.first == "copy" { return .init(status: 1, stdout: "", stderr: "connection reset") }
            return try await run(rclone, args, [:])
        }
        vm.cloudLibrary.installScreenArchives(offline)
        vm.cloudLibrary.update(game.id) { $0.copies[.app] = .screenFixture(.cloudOnly) }
        vm.performCloudLibrary(.restore(.app), for: game)
        let interrupted = vm.cloudLibrary.active!.request.token
        await vm.cloudLibrary.active?.task.value
        precondition(vm.cloudLibrary.queue.first?.token == interrupted && vm.settingsNotice != nil)
        vm.settingsNotice = nil
        let row = ActivityCenterFocus.Row.queuedCloud(interrupted)
        var focus = ActivityCenterFocus()
        focus.selected = row
        let fr = AppLocale(language: .french, region: "FR")
        let activity = ActivityCenterView(viewModel: vm, porting: vm.porting, cloudLibrary: vm.cloudLibrary,
            focus: focus, onFocus: { _ in }, onOpen: { _ in }, onCancel: { _ in },
            onBack: {}, onOutside: {})
        try render("transfer-interrupted-activity", output, activity.environment(\.nxAppLocale, fr))
        let panel = CloudLibraryPanel(viewModel: vm, model: vm.cloudLibrary, game: game)
        try render("transfer-interrupted-panel", output, panel.environment(\.nxAppLocale, fr))
        precondition(activity.resumeHintForProbe(row), "The dismissed alert must leave Resume in the Activity center")
        precondition(panel.resumeForProbe(), "The dismissed alert must leave Resume in the cloud panel")
        vm.cloudLibrary.installScreenArchives(backend)
        let unreachable = RcloneStorageBackend(remote: "fixture", root: "Games") { _, _, _ in
            .init(status: 1, stdout: "", stderr: "connection reset")
        }.reference(folderID: "1-fixture")!
        vm.cloudLibrary.installScreenReference(unreachable)
        panel.resumeFromProbe()
        try await until { vm.cloudLibrary.states[game.id]?.progress?.phase == .readyToInstall }
        precondition(vm.cloudLibrary.active?.request.token == interrupted)
        precondition(!fm.fileExists(atPath: app.path))
        let quitting = vm.cloudLibrary.stopForQuit()
        await quitting?.value
        let contents = try fm.contentsOfDirectory(atPath: folder.path)
        precondition(!contents.contains { $0.hasPrefix(".arcane-cloud-") && !$0.hasPrefix(".arcane-cloud-files-") })
        precondition(!fm.fileExists(atPath: app.path))

        // Startup resumes the same queue request without publishing while the game is still running.
        vm = try makeModel()
        vm.cloudLibrary.installScreenReference(unreachable)
        vm.restoreCloudQueue()
        try await until { vm.cloudLibrary.states[game.id]?.progress?.phase == .readyToInstall }
        precondition(!fm.fileExists(atPath: app.path))
        var launchedVersion: String?
        vm.screenPlay = { _ in launchedVersion = try! version() }
        let launchAtSwap = vm.cloudLibrary.$states.sink { states in
            if vm.cloudLibrary.appInstall != nil && states[game.id]?.progress?.phase == .restoring {
                vm.launchGame(game)
                precondition(launchedVersion == nil && vm.cloudLibrary.playAfterAppInstall != nil)
            }
        }
        RunningGameMonitor.screenRunning.withLock { $0 = nil }
        monitor.refresh()
        await vm.cloudLibrary.active?.task.value
        launchAtSwap.cancel()
        precondition(monitor.runningGameIDs.isEmpty && launchedVersion == "1.0")
        try await until { vm.cloudLibrary.states[game.id]?.refreshing != true }

        // Reference may replace an installed, older bundle, but never while it's running.
        let older = folder.appendingPathComponent("previous")
        try fm.copyItem(at: app, to: older)
        try await Task.sleep(for: .seconds(1))
        try sign("2.0")
        _ = try await CloudGameArchive(backend: referenceWrite).upload(.init(titleID: title, locations: [.app: app]), kinds: [.app])
        try fm.removeItem(at: app)
        try fm.moveItem(at: older, to: app)
        vm.cloudLibrary.installScreenReference(referenceRead)
        let selected = vm.libraryGames.first { $0.id == game.id }!
        RunningGameMonitor.screenRunning.withLock { $0 = bundleID }
        monitor.refresh()
        await vm.refreshCloudLibrary(selected)
        L10n.setContext(fr)
        vm.performCloudLibrary(.restore(.app), for: selected)
        guard let refusal = vm.settingsNotice else { preconditionFailure("Download must ask before replacing") }
        precondition(refusal.choices == ["Replace", "Cancel"] && vm.settingsNoticeFocus == refusal.cancelIndex)
        try renderNotice("reference-replacement-confirmation", output, refusal, width: 1280)
        vm.settingsNotice = nil
        refusal.runChoice(refusal.cancelIndex)
        let unchanged = try version()
        precondition(unchanged == "1.0" && vm.cloudLibrary.active == nil)
        vm.performCloudLibrary(.restore(.app), for: selected)
        let approved = vm.settingsNotice!
        vm.settingsNotice = nil
        approved.runChoice(0)
        try await until { vm.cloudLibrary.states[game.id]?.progress?.phase == .readyToInstall }
        let versionDuringPlay = try version()
        precondition(versionDuringPlay == "1.0")
        RunningGameMonitor.screenRunning.withLock { $0 = nil }
        monitor.refresh()
        await vm.cloudLibrary.active?.task.value
        let applied = try version()
        precondition(applied == "2.0")
        let backup = vm.cloudLibrary.states[game.id]!.previousApp!
        let backupPlist = try Data(contentsOf: backup.appendingPathComponent("Contents/Info.plist"))
        let backupInfo = try PropertyListSerialization.propertyList(from: backupPlist, format: nil) as! [String: String]
        precondition(backupInfo["CFBundleShortVersionString"] == "1.0")
        let recoveryPanel = CloudLibraryPanel(viewModel: vm, model: vm.cloudLibrary, game: selected)
        try render("reference-replacement-panel", output, recoveryPanel.environment(\.nxAppLocale, fr))
        L10n.setContext(.init(language: .english, region: "US"))
        // AUDIT_QUEUE
        print("Play during app upload, personal restart and reference swap verified with local fixtures.")
    }
}
'''

AUDIT_QUEUE = r'''
        let package = folder.appendingPathComponent("Source.nsp")
        let approved = Data("first".utf8)
        try approved.write(to: package)
        let withSources = try repository.updateNXNative(id: game.id) {
            $0.sources = [.init(url: package, kind: .base, titleId: title, versionString: "0",
                              sizeBytes: Int64(approved.count))]
        }
        let sourceGame = withSources.nxnativeGames.first { $0.id == game.id }!
        let selection = CloudSourceFiles(sourceGame)!
        let sources = remote.appendingPathComponent("GameFiles")
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        let remotePackage = sources.appendingPathComponent(selection.folderName).appendingPathComponent(package.lastPathComponent)
        func reopen(_ entry: CloudTransferQueue.Entry) async throws -> AppViewModel {
            let restarted = try makeModel()
            restarted.cloudLibrary.installScreenSources(backend, root: sources.path)
            restarted.cloudLibrary.queueStore.save([entry])
            await restarted.cloudLibrary.queueStore.flush()
            restarted.restoreCloudQueue()
            try await until { restarted.cloudLibrary.hasRestoredQueue }
            await restarted.cloudLibrary.active?.task.value
            await restarted.cloudLibrary.queueStore.flush()
            return restarted
        }
        var failures: [String] = []
        let legacy = CloudTransferQueue.Entry(id: game.id, action: .uploadSources)
        vm = try await reopen(legacy)
        if fm.fileExists(atPath: remotePackage.path) {
            let sent = try Data(contentsOf: remotePackage)
            failures.append("Legacy upload wrote \(String(decoding: sent, as: UTF8.self)) to the current destination without approval")
            try fm.removeItem(at: remotePackage)
        } else {
            let entry = vm.activityResults.entries.first!
            vm.retryActivity(entry.id)
            precondition(vm.cloudLibrary.active == nil && vm.settingsNotice?.retry == nil)
            try renderNotice("queue-confirm-again", output, vm.settingsNotice!, width: 1280)
        }
        let expectedStorage = vm.cloudLibrary.storageScope(for: .uploadSources)
        precondition(expectedStorage != nil)
        let interruptedUpload = CloudTransferQueue.Entry(id: game.id, action: .uploadSources, token: UUID(), storage: expectedStorage)
        let replacement = folder.appendingPathComponent("Replacement.nsp")
        try Data("other".utf8).write(to: replacement)
        try fm.removeItem(at: package)
        try fm.moveItem(at: replacement, to: package)
        vm = try await reopen(interruptedUpload)
        if fm.fileExists(atPath: remotePackage.path) {
            let sent = try Data(contentsOf: remotePackage)
            failures.append("Interrupted upload wrote \(String(decoding: sent, as: UTF8.self)) without fresh approval")
            try fm.removeItem(at: remotePackage)
        } else {
            precondition(vm.cloudLibrary.states[game.id]?.issue?.failed == true)
            try render("queue-upload-not-replayed", output, CloudLibraryPanel(viewModel: vm, model: vm.cloudLibrary, game: sourceGame))
        }

        RunningGameMonitor.screenRunning.withLock { $0 = bundleID }
        monitor.refresh()
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        vm = try await reopen(.init(id: game.id, action: .restore(.cache), token: UUID(),
                                    storage: vm.cloudLibrary.storageScope(for: .restore(.cache))))
        precondition(vm.cloudLibrary.queue.count == 1 && vm.cloudLibrary.active == nil,
                     "Cache transfer must be queued until the game closes")
        RunningGameMonitor.screenRunning.withLock { $0 = nil }
        monitor.refresh()
        // The production close callback is dispatched to the main queue.
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        if !vm.cloudLibrary.queue.isEmpty { failures.append("Queued transfer did not wake when the game closed") }
        await vm.cloudLibrary.active?.task.value

        let badTitle = "0100000000008000"
        let invalid = remote.appendingPathComponent("\(badTitle)/manifests/zz-invalid.json")
        try fm.createDirectory(at: invalid.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: invalid)
        let freshRepository = CatalogRepository(store: .init(directory: folder.appendingPathComponent("fresh-catalog")))
        let importer = AppViewModel(settingsStore: settings, catalog: .init(), repository: freshRepository)
        importer.cloudLibrary.installScreenArchives(backend)
        importer.importCloudGames(manually: true)
        await importer.cloudLibrary.importTask?.value
        if try freshRepository.load().nxnativeGames.map(\.titleId) != [title] {
            failures.append("Malformed manifest blocked import of a healthy game")
        } else {
            precondition(importer.settingsNotice?.message.contains(badTitle) == true)
            try renderNotice("import-with-unreadable-title", output, importer.settingsNotice!, width: 1280)
        }
        if !failures.isEmpty {
            FileHandle.standardError.write(Data(failures.joined(separator: "\n").utf8) + Data([10]))
            throw CocoaError(.fileWriteUnknown, userInfo: [NSDebugDescriptionErrorKey: failures.joined(separator: "\n")])
        }
        let emptyCatalog = CatalogRepository(store: .init(directory: folder.appendingPathComponent("empty-catalog")))
        let badOnly = folder.appendingPathComponent("bad-only")
        try fm.createDirectory(at: badOnly, withIntermediateDirectories: true)
        try fm.copyItem(at: remote.appendingPathComponent(badTitle), to: badOnly.appendingPathComponent(badTitle))
        let badImporter = AppViewModel(settingsStore: settings, catalog: .init(), repository: emptyCatalog)
        badImporter.cloudLibrary.installScreenArchives(RcloneStorageBackend(remote: ":local:", root: badOnly.path, run: run))
        badImporter.importCloudGames(manually: true)
        await badImporter.cloudLibrary.importTask?.value
        precondition(badImporter.cloudLibrary.checkFailedDuringImport == true
                     && badImporter.settingsNotice?.message.contains(badTitle) == true)
        badImporter.cloudLibrary.installScreenArchives(RcloneStorageBackend(remote: ":local:", root: remote.path) { _, _, _ in
            .init(status: 1, stdout: "", stderr: "connection reset")
        })
        badImporter.importCloudGames(manually: true)
        await badImporter.cloudLibrary.importTask?.value
        precondition(badImporter.cloudLibrary.connectionCheck?.failure == .offline)
        print("Cloud audit: legacy destination, replaced source, close-game wake, and mixed manifests verified.")
'''

DISPLAY_FIXTURE = r'''
        let displayLocale = AppLocale(language: .french, region: "FR")
        L10n.setContext(displayLocale)
        func displaySettings() -> some View {
            SettingsGamesSection(viewModel: vm, settings: settings, onActions: { _ in })
                .environment(\.nxAppLocale, displayLocale)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(height: 200, alignment: .top).clipped()
        }
        try render("game-display-default", output, displaySettings(), size: .init(width: 960, height: 200))
        var displayGame = game
        displayGame.status = .built
        DisplayScreenProbe.expanded = true // Show Next launch below the fold without opening a window.
        let optionsSize = CGSize(width: 1920, height: 1580)
        func displayOptions() -> some View {
            GameOptionsView(viewModel: vm, game: displayGame, origin: .details,
                            onClose: {}, onShowBuild: {}, onMove: {})
                .environment(\.nxAppLocale, displayLocale)
        }
        try render("game-display-old-host", output, displayOptions(), size: optionsSize)
        // DISPLAY_CAPABLE
        DisplayScreenProbe.expanded = false
'''

DISPLAY_CAPABLE = r'''
        let displayHost = HomeMenu.hostExecutable(in: displayGame.url)
        try FileManager.default.createDirectory(at: displayHost.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("DM_SCREEN\0".utf8).write(to: displayHost)
        let capable = await InstalledEngineCapabilities.shared.supportsGameDisplay(in: displayGame.url)
        precondition(capable)
        DisplayScreenProbe.capable = capable // ImageRenderer doesn't run .task.
        try render("game-display-options", output, displayOptions(), size: optionsSize)
        settings.settings.gameDisplay = "00000000-0000-0000-0000-000000000000"
        try render("game-display-disconnected", output, displaySettings(), size: .init(width: 960, height: 200))
        settings.settings.gameDisplay = ""
        DisplayScreenProbe.capable = false
'''

MULTIPLAYER = r'''
        let frLocale = AppLocale(language: .french, region: "FR")
        L10n.setContext(frLocale)
        let dm = game.url.appendingPathComponent("Contents/Resources/dm")
        try FileManager.default.createDirectory(at: dm, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "local.arcane.screen-multiplayer", "DMSettings": []]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: game.url.appendingPathComponent("Contents/Info.plist"))
        try Data("""
            {"schema":1,"game":"0100000000001000","settings":[
             {"env":"DM_NETWORK","kind":"choice","section":"Game","label":"Network","default":"offline",
              "options":[["offline","Offline"],["ldn","Local communication"],["lan","LAN mode"],["auto","Automatic"],["nextendo","Online (Nextendo)"]]},
             {"env":"DM_NET_VPN","kind":"toggle","section":"Game","label":"Play over a VPN","default":"0","on":"1","off":"0"}]}
            """.utf8).write(to: dm.appendingPathComponent("launcher.json"))
        // MULTIPLAYER_STATES
'''

MULTIPLAYER_STATES = r'''
        settings.settings.multiplayerVPN = .zeroTier
        settings.settings.multiplayerDefault = .local
        func settingsPage() -> some View {
            SettingsView(initialSection: .multiplayer, viewModel: vm, settings: settings,
                         router: AppRouter(), artwork: ArtworkStore())
                .environment(\.nxAppLocale, frLocale)
        }
        ScreenVPN.connected = true
        try render("multiplayer-settings", output, settingsPage(), size: .init(width: 1920, height: 1080))
        ScreenVPN.connected = false
        try render("multiplayer-vpn-disconnected", output, settingsPage(), size: .init(width: 1920, height: 1080))
        for (name, locale) in [("multiplayer-vpn-warning", frLocale),
                               ("multiplayer-vpn-warning-de", AppLocale(language: .german, region: "DE"))] {
            L10n.setContext(locale)
            vm.showMultiplayerVPNFallback {}
            let warning = vm.settingsNotice!
            precondition(warning.choices == ["Play on the local network", "Cancel"])
            precondition(vm.settingsNoticeFocus == 0 && warning.cancelIndex == 1)
            try renderNotice(name, output, warning, width: 1100)
        }
        L10n.setContext(frLocale)
        func gameOptions() -> some View {
            var installed = game
            installed.status = .built
            return GameOptionsView(viewModel: vm, game: installed, origin: .details, onClose: {}, onShowBuild: {}, onMove: {})
                .environment(\.nxAppLocale, frLocale)
        }
        ScreenVPN.connected = true
        try render("multiplayer-game-options", output, gameOptions(),
                   size: .init(width: 1920, height: 1080))
        settings.settings.multiplayerDefault = .online
        ScreenVPN.mods = true
        try render("multiplayer-online-mods", output, gameOptions(),
                   size: .init(width: 1920, height: 1080))
'''

MULTIPLAYER_BEFORE = r'''
        let page = SettingsView(initialSection: .apiServices, viewModel: vm, settings: settings,
                                router: AppRouter(), artwork: ArtworkStore())
        ScreenVPN.connected = true
        try render("multiplayer-settings", output, page.environment(\.nxAppLocale, frLocale),
                   size: .init(width: 1920, height: 1080))
        ScreenVPN.connected = false
        try render("multiplayer-vpn-disconnected", output, page.environment(\.nxAppLocale, frLocale),
                   size: .init(width: 1920, height: 1080))
        try render("multiplayer-game-options", output,
                   MoreSettingsPanel(viewModel: vm, game: game, onClose: {}).environment(\.nxAppLocale, frLocale),
                   size: .init(width: 1920, height: 1080))
        let snapshot = vm.runtimeSettings.settingsSnapshot(for: game)!
        try render("multiplayer-online-mods", output,
                   ModsPanel(viewModel: vm, game: game,
                             settings: .init(settings: snapshot.settings, values: ["DM_NETWORK": "nextendo"], fixed: []),
                             onRebuild: {}, onClose: {}).environment(\.nxAppLocale, frLocale),
                   size: .init(width: 1920, height: 1080))
'''

def multiplayer_fixture(app, host, before):
    settings_view = app / "Views/Settings/SettingsView.swift"
    change(settings_view, r'        ScrollViewReader \{ proxy in\n            ScrollView \{\n', '')
    change(settings_view, r'            }\n            \.scrollIndicators\(\.hidden\).*?(?=\n    }\n\n    private var reduceMotion)', '')
    change(settings_view, r'    private var supportsNextendo: Bool \{ [^\n]* \}', '    private var supportsNextendo: Bool { true }')
    change(settings_view, r'        \.background\(SeleneBackdrop\(\)\.environment[^\n]*\n', '')
    sidebar = app / "Views/Settings/SettingsSidebar.swift"
    change(sidebar, r'            ScrollViewReader \{ proxy in.*?(?=\n        }\n    })', '            groups')
    change(sidebar, r'ForEach\(SettingsSidebarGroup.all\)', 'ForEach(Array(SettingsSidebarGroup.all.prefix(2)))')
    nextendo = app / "ViewModels/NextendoSettings.swift"
    change(nextendo, r'    func check\(clientID: String\?\) \{.*?\n    }', '    func check(clientID: String?) {}')
    if not before:
        change(nextendo, r'    func publishPresence\(clientID: String, eligible: \(\) -> Bool\) async \{.*?\n    }',
               '    func publishPresence(clientID: String, eligible: () -> Bool) async {}')
    model = app / "ViewModels/RuntimeSettingsModel.swift"
    change(model, r'NXNativeGameSettings\.forGame\(game\)', '''NXNativeGameSettings.forGame(game, store: MemorySavedChoices(),
            supportDirectory: AppData.supportRoot, preferences: AppData.preferences)''')
    section = app / "Views/Settings/SettingsAPISection.swift"
    change(section, r'remotePlayAdapters = \.current\(\)', 'remotePlayAdapters = ScreenVPN.adapters')
    # No filesystem-backed credentials, real mods or engine checks during fixture rendering.
    mods_model = app / "ViewModels/AppViewModel+Mods.swift"
    change(mods_model, r'    func modStore\(for game: PortedGame\) -> ModStore\? \{.*?(?=\n    func modsRowValue)',
           '    func modStore(for game: PortedGame) -> ModStore? { nil }\n')
    setup = app / "ViewModels/SetupModel.swift"
    change(setup, r'    func prepareBuildEnvironmentIfNeeded\(\) \{.*?\n    }', '    func prepareBuildEnvironmentIfNeeded() {}')
    with section.open("a") as swift:
        swift.write('''
enum ScreenVPN {
    static var connected = false
    static var mods = false
    static var adapters: RemotePlayAdapters { .screenFixture(connected: connected) }
}
''')
    if before:
        change(section, r'private var remotePlayAdapters = RemotePlayAdapters\(\)', 'private var remotePlayAdapters = ScreenVPN.adapters')
        more = app / "Views/GameOptions/MoreSettingsPanel.swift"
        change(more, r'        ScrollViewReader \{ proxy in\n            ScrollView \{\n                LazyVStack', '        VStack')
        change(more, r'            }\n            \.scrollIndicators\(\.hidden\).*?(?=\n    }\n\n    private func value)', '')
        mods = app / "Views/GameOptions/ModsPanel.swift"
        change(mods, r'private var mods: \[LocalMod\] = \[\]', '''private var mods: [LocalMod] = [
        .init(folderName: "Rules", folder: AppData.supportRoot, romfs: AppData.supportRoot, isOn: true),
        .init(folderName: "Code patch", folder: AppData.supportRoot, romfs: nil, exefs: AppData.supportRoot, isOn: true)
    ]''')
        change(mods, r'        return ScrollViewReader \{ proxy in\n            ScrollView \{\n', '        return Group {\n')
        change(mods, r'            }\n            \.scrollIndicators\(\.hidden\).*?(?=\n        }\n    }\n\n    private func sectionHeader)', '')
        change(mods, r'            sync\(preservingFocus: false\)\n', '')
        return host.replace("// MULTIPLAYER_CHECK", MULTIPLAYER.replace("// MULTIPLAYER_STATES", MULTIPLAYER_BEFORE))
    change(section, r'@State var remotePlayAdapters = RemotePlayAdapters\(\)', '@State var remotePlayAdapters = ScreenVPN.adapters')
    options = app / "Views/GameOptions/GameOptionsView.swift"
    change(options, r'@State var multiplayerAdapters = RemotePlayAdapters\(\)', '@State var multiplayerAdapters = ScreenVPN.adapters')
    change(options, r'            multiplayerAdapters = \.current\(\)', '            multiplayerAdapters = ScreenVPN.adapters')
    change(options, r'@State var onlineRiskMods: \[String: ModFolderScanner.OnlineContent\] = \[:\]',
           '@State var onlineRiskMods: [String: ModFolderScanner.OnlineContent] = ScreenVPN.mods ? ["Rules": .data] : [:]')
    change(options, r'cheatsValue = viewModel.cheats.cheatRowValue\(for: game\)', 'cheatsValue = L10n.text("None")')
    change(options, r'modsValue = viewModel.modsRowValue\(for: game\)', 'modsValue = ScreenVPN.mods ? "2" : L10n.text("None")')
    change(options, r'        \.task\(id: OnlineModsRequest.*?(?=\n        \.task \{)', '')
    rows = app / "Views/GameOptions/GameOptionsView+Rows.swift"
    change(rows, r'            ScrollViewReader \{ proxy in\n                ScrollView \{\n', '')
    change(rows, r'                }\n                \.scrollIndicators\(\.hidden\).*?\n            }\n            \.id\(level\)\n', '')
    change(rows, r'(let entries = p\.entries\(level: level, origin: origin(?:, context: localization)?\))',
           re.search(r'let entries = p\.entries\([^\n]+', rows.read_text())[0]
           + '.prefix(DisplayScreenProbe.expanded ? 13 : (ScreenVPN.mods ? 8 : 7))')
    return host.replace("// MULTIPLAYER_CHECK", MULTIPLAYER.replace("// MULTIPLAYER_STATES", MULTIPLAYER_STATES))


def change(file, old, new):
    text, count = re.subn(old, lambda _: new, file.read_text(), count=1, flags=re.S)
    assert count == 1, (file, old)
    file.write_text(text)


def main():
    # Without a folder, as a release regression, render into a throwaway folder under work/.
    (ROOT / "work").mkdir(exist_ok=True)
    output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="cloud-screens-", dir=ROOT / "work")).resolve()
    output.mkdir(parents=True, exist_ok=True)
    before = len(sys.argv) > 2 and sys.argv[2] == "--before"
    compare = len(sys.argv) > 2 and sys.argv[2] == "--compare-with-5047557"
    if compare:
        pixel_reference = output / "5047557"
        subprocess.run([sys.executable, __file__, str(pixel_reference)], check=True,
                       env=dict(os.environ, ARCANE_CLOUD_SCREEN_BASE="5047557"))
    with tempfile.TemporaryDirectory(prefix="cloud-screen-", dir=output.parent) as temp:
        package = Path(temp)
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        if before:
            archived = subprocess.check_output(["git", "-C", str(ROOT), "archive", "528f4fb", "Sources"])
            subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archived, check=True)
        elif baseline := os.environ.get("ARCANE_CLOUD_SCREEN_BASE"):
            archived = subprocess.check_output(["git", "-C", str(ROOT), "archive", baseline, "Sources"])
            subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archived, check=True)
        else:
            shutil.copytree(ROOT / "Sources", package / "Sources")
        for name in ("NXLibraryCoreTests", "ArcanePortingTests"):
            folder = package / "Tests" / name
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        change(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        change(app / "ViewModels/AppViewModel.swift", r"        applyCatalog\(catalog\).*?\n    }\n\n    // MARK: - Dynamic",
               "    }\n\n    // MARK: - Dynamic")
        change(package / "Sources/NXLibraryCore/App/AppDataProfile.swift",
               r'public static let profile = [^\n]*',
               f'public static let profile = AppDataProfile(home: URL(fileURLWithPath: "{temp}"), isDevelopment: true)')
        change(package / "Sources/NXLibraryCore/App/AppDataProfile.swift",
               r'public static var preferences: UserDefaults \{ \.standard \}',
               'public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        change(app / "ViewModels/AppViewModel+CloudLibrary.swift",
               r'        let defaults = AppData\.preferences.*?(?=        rebuildArchive\(\))',
               '        preference = .init(storage: "fixture:Games", enabled: true, sourcesRoot: nil)\n'
               '        chosenExecutable = nil\n')
        section = app / "Views/Settings/SettingsCloudLibrarySection.swift"
        change(section,
               r'        \.task\(id: Inspection.*?\n        }\n', "")
        change(app / "Views/Detail/CloudLibraryPanel.swift",
               r'        \.task\(id: ReadRequest.*?\n', "")
        if not before:
            change(app / "Views/Settings/CloudReferenceDialog.swift",
                   r'                TextField\(.*?\.onExitCommand\(perform: onClose\)',
                   '                Text(text("Google Drive folder link or ID"))\n'
                   '                    .frame(maxWidth: .infinity, alignment: .leading)')
        assistant = app / "Views/Settings/CloudSetupAssistant.swift"
        change(assistant, r'        \.onAppear \{\s*.*?installAssistantKeys\(\)(?: \}|\n        })\n', "")
        change(assistant, r'@State private var remotes: \[RcloneRemote\]\?', '@State private var remotes: [RcloneRemote]? = []')
        browser = "private var browsingPath" in assistant.read_text()
        if browser:
            change(assistant, r'        self.onClose = onClose', '''        self.onClose = onClose
        _listing = State(initialValue: .screenFixture)''')
            # Render the real breadcrumb and folder rows without AppKit-backed scrolling.
            change(assistant, r'                ScrollView\(\.horizontal\) \{\n(.*?)\n                }\n                if listing != nil',
                   re.search(r'                ScrollView\(\.horizontal\) \{\n(.*?)\n                }\n                if listing != nil',
                             assistant.read_text(), re.S)[1] + '\n                if listing != nil')
            change(assistant, r'                    ScrollViewReader \{ proxy in\n                        ScrollView \{\n'
                   r'                            LazyVStack', '                    VStack')
            change(assistant, r'                        }\n                        \.frame\(height: canvas.u\(CGFloat\(min\(folderNames.count.*?\n'
                   r'                    }\n                    option\(\.newFolder', '                    option(.newFolder')
            with (package / "Sources/ArcanePorting/Library/CloudDriveFolders.swift").open("a") as swift:
                swift.write('''
extension CloudDriveFolders.Listing {
    public static var screenFixture: Self { .init(ticket: UUID(), names: ["Nintendo", "Switch"]) }
}
''')
        else:
            # TextField is AppKit-backed and ImageRenderer shows a placeholder instead of its text.
            change(assistant, r'TextField\(text\("Game files folder"\), text: \$sourcesPath,\s+'
                   r'prompt: Text\(verbatim: [^\n]+\)\)\s+\.focused\([^\n]+',
                   'Text(verbatim: sourcesPath).frame(maxWidth: .infinity, alignment: .leading)')
        change(app / "Views/Components/SwitchBoxArtCover.swift",
               r'        \.task\(id: coverKey.*?\n        \.task\(id: game.id[^\n]*\n', "")
        activity = app / "Views/Shell/ActivityCenterView.swift"
        view = activity.read_text()
        assert 'section("Compilation", empty: "No compilation"' in view
        assert 'section("Cloud", empty: "No cloud transfer"' in view
        assert 'if rows.isEmpty, let empty' in view and 'Text(text(empty))' in view
        # ImageRenderer does not draw AppKit-backed scrolling. Keep the real rows and their layout.
        change(activity, r'                ScrollViewReader \{ scroll in\n                    ScrollView \{\n', "")
        change(activity, r'                    }\n                    \.padding\(EdgeInsets.*?\.onChange\(of: focused\)[^\n]*\n                }\n', "")
        change(activity, r'        LazyVStack\(', '        VStack(')
        with activity.open("a") as swift:
            swift.write("""
extension ActivityCenterView {
    func resumeHintForProbe(_ row: ActivityCenterFocus.Row) -> Bool {
        hints(row).contains { $0.label == "Resume" }
    }
}
""")
        host = HOST.replace("/* NOTICE_LAYOUT */", "vertical: notice.vertical," if before else "cancelIndex: notice.cancelIndex,")
        has_display = (package / "Sources/ArcanePorting/Launch/GameDisplay.swift").is_file()
        if not before:
            host = host.replace("// DISPLAY_FIXTURE", DISPLAY_FIXTURE)
            host += "\n@MainActor enum DisplayScreenProbe { static var capable = false; static var expanded = false }\n"
        if has_display:
            change(app / "Views/GameOptions/GameOptionsView.swift",
                   r"@State private var supportsGameDisplay = false",
                   "@State private var supportsGameDisplay = DisplayScreenProbe.capable")
            host = host.replace("// DISPLAY_CAPABLE", DISPLAY_CAPABLE)
        host = host.replace("/* ACTIVITY_DISMISS */",
                            "onBack: {}, onOutside: {}" if "let onBack:" in view
                            else "onClose: {}")
        unified = (package / "Sources/ArcanePorting/Library/CloudTransferPresentation.swift").exists()
        host = host.replace("CACHE_DOWNLOAD_CHOICE", "Download cache and rebuild" if unified else "Download the cloud cache")
        if not before:
            header = (app / "Views/Detail/DetailsTopBlock.swift").read_text()
            panel = (app / "Views/Detail/CloudLibraryPanel.swift").read_text()
            assert re.search(r"onHoverPill\(1\).*?if showsCloudPill \{ cloudPill \}.*?let favorite", header, re.S)
            assert "CloudLibraryPill(indicator:" in header and "{ onPill(index) }" in header
            assert "SelenePillButton(title: nil, icon: indicator.pillIcon" in panel
            for path in ("Detail/CloudLibraryPanel", "Detail/DetailsPanel", "Shell/ActivityCenterView"):
                view_file = app / f"Views/{path}.swift"
                assert not view_file.exists() or '"Manage game"' not in view_file.read_text(), path
        if before:
            host = re.sub(r'// REFERENCE_START.*?// REFERENCE_END', '', host, flags=re.S)
        if not before:
            change(app / "Views/Components/SwitchBoxArtCover.swift", r'@State private var cover: NSImage\?',
                r'''@State private var cover: NSImage? = {
        let fixture = ImageRenderer(content: VStack(spacing: 0) {
            Color.purple; Color.teal; Color.orange
        }.frame(width: 180, height: 280))
        return fixture.nsImage
    }()''')
            change(app / "ViewModels/AppViewModel+Activity.swift", r'    func clearActivity\(',
                '''    func clearActivityForProbe(_ id: UUID) { activityResults.clear(id) }
    func clearActivity(''')
            gallery = TRANSFER_STATES
            has_replacement = "var previousApp:" in (app / "ViewModels/AppViewModel+CloudLibrary.swift").read_text()
            host = host.replace("// ADVANCED_SETTINGS", '''
        try render("settings-advanced", output, SettingsCloudLibrarySection(
            viewModel: vm, model: model, settings: settings, advanced: .constant(true),
            onEdit: {}, onEditSources: {}, onActions: { _ in })
            .padding(24).frame(width: 1040), size: .init(width: 1280, height: 1440))
''')
            if unified:
                gallery = gallery.replace("// TRANSFER_TERMINAL", '''$0.completedItem = phase == "ready" ? .app : nil
                $0.failedTransferID = phase == "failed" ? queuedRequest.token : nil''')
                gallery = gallery.replace("// CHECK_TRANSFER_CONTROLS",
                    '''panel.checkTransferControls(canCancel: live || phase == "queued", canRetry: phase == "failed")''')
                with (app / "Views/Detail/CloudLibraryPanel.swift").open("a") as file:
                    if has_replacement:
                        file.write('''
extension CloudLibraryPanel {
    func resumeForProbe() -> Bool { controls.contains(.resume) }
    func resumeFromProbe() { choose(.resume) }
}
''')
                    file.write('''
extension CloudLibraryPanel {
    func advancedForProbe() -> Self {
        var copy = self
        copy._advanced = State(initialValue: true)
        return copy
    }

    func checkTransferControls(canCancel: Bool, canRetry: Bool) {
        precondition(Set(controls).count == controls.count)
        precondition(controls.contains(.cancel) == canCancel)
        precondition(controls.contains { if case .retry = $0 { true } else { false } } == canRetry)
        if canRetry { precondition(artifactControl(.app) == nil) }
    }
}
''')
                gallery += r'''
        model.update(game.id) {
            $0.copies = [.app: .screenFixture(.synchronized), .cache: .screenFixture(.synchronized)]
            $0.referenceCopies[.app] = .init(downloadBytes: 26_000_000, totalBytes: 100_000_000,
                legacy: false, updatesLocal: true)
        }
        precondition(model.states[game.id]?.appAvailabilityKeys == ["Copy in your cloud", "Update available"])
        precondition(model.states[game.id]?.canUploadBoth == true && model.states[game.id]?.showsCombinedUpload == false)
        try render("details-playable-update", output,
            DetailsTopBlock(game: installed, logo: nil,
                presentation: .init(game: installed, metadata: nil, totalPlaytime: 0, lastPlayed: nil),
                isRunning: false, focusedPill: 0, primaryEnabled: true, expanded: .constant(false),
                onPrimary: {}, onSecondary: {}, onFavorite: {}, onHoverPill: { _ in }, pillSet: .normal,
                cloud: model, showsCloudPill: true, downloadEnabled: true).environment(\.nxAppLocale, fr),
            size: .init(width: 1120, height: 520))
        model.update(game.id) { $0.referenceCopies = [:] }
        let advanced = CloudLibraryPanel(viewModel: vm, model: model, game: game).advancedForProbe()
        try render("panel-advanced-migration", output, advanced.environment(\.nxAppLocale, fr))
'''
            host = host.replace("// TRANSFER_STATES", "do {\n" + gallery + CLOUD_BUTTON + "\n        }")
            # Capture Spotlight after its entrance, without running the reveal in ImageRenderer.
            change(app / "Views/Spotlight/SpotlightInfoView.swift",
                   r'        \.onAppear \{ reveal\(\) \}\n        \.onChange\(of: game.id\) \{ reveal\(\) \}\n', "")
            waiting_label = ("Mise à jour prête · appliquée quand tu quittes le jeu"
                             if baseline == "5047557" else "Mise à jour prête · appliquée à la fermeture du jeu")
            host = host.replace("// DOWNLOAD_FILL_CHECK",
                                "do {\n" + DOWNLOAD_FILL.replace("WAITING_LABEL_FR", waiting_label) + "\n        }")
            if has_replacement:
                if compare or os.environ.get("ARCANE_CLOUD_SCREEN_BASE"):
                    transfer = PLAY_TRANSFER.replace("// QUEUE_MONITOR_CALLBACK", "vm.cloudLibrary.appInstallWake?.yield(())")
                else:
                    startup = (app / "Views/Shell/AppShellView+Startup.swift").read_text()
                    callback = re.search(r"closeGameWatch = runningGames\.\$runningGameIDs\.sink.*?"
                                         r"(DispatchQueue\.main\.async \{\n.*?\n            \})", startup, re.S)
                    assert callback, "Cannot find the running-game callback"
                    transfer = PLAY_TRANSFER.replace("// QUEUE_MONITOR_CALLBACK", callback[1].replace("viewModel", "vm"))
                    transfer = transfer.replace("// AUDIT_QUEUE", "do {\n" + AUDIT_QUEUE + "\n        }")
                host = host.replace("// PLAY_TRANSFER_CHECK", "try await checkPlayDuringTransfer(in: data, output: output)") + transfer
            monitor = app / "Services/RunningGameMonitor.swift"
            change(monitor, r'import AppKit', "import AppKit\nimport os")
            change(monitor, r'    nonisolated static func runningApplication\(bundleID: String\).*?\n    }', '''
    nonisolated static let screenRunning = OSAllocatedUnfairLock<String?>(initialState: nil)
    nonisolated static func runningApplication(bundleID: String) -> NSRunningApplication? {
        screenRunning.withLock { $0 == bundleID } ? .current : nil
    }'''.lstrip("\n"))
            change(monitor, r'        Set\(NSWorkspace.shared.runningApplications[^\n]*',
                   '        screenRunning.withLock { Set([$0].compactMap { $0 }) }')
            change(app / "ViewModels/AppViewModel.swift", r'    let saveGate =',
                   '    var screenPlay: ((PortedGame) -> Void)?\n    let saveGate =')
            change(app / "ViewModels/AppViewModel+Launch.swift", r'        guard savesPermitPlay\(game\) else \{ return \}',
                   '        if let screenPlay { screenPlay(game); return }\n        guard savesPermitPlay(game) else { return }')
        if "onEditLibrary:" in section.read_text():
            host = host.replace("onEdit: {}, onEditSources:", "onEdit: {}, onEditLibrary: {}, onEditSources:")
            host = host.replace("/* ENTRY */", ", entry: .sources")
            host = host.replace("// CONNECTION_FIXTURE",
                '''model.connectionCheck = .init(date: Date(timeIntervalSince1970: 1_795_000_000), failure: .offline)
        let en = AppLocale(language: .english, region: "US")
        let fr = AppLocale(language: .french, region: "FR")
        var uploading = CloudLibraryState()
        uploading.action = .upload(nil)
        uploading.progress = .init(.uploading, kind: .cache)
        let pendingApp = CloudLibraryIndicator(state: uploading, item: .app)
        precondition(pendingApp.label(context: en) == "''' + ("Sent · published when the upload ends" if before else "App published · sending build cache…") + '''")
        precondition(pendingApp.label(context: fr) == "''' + ("Envoyée · publiée à la fin de l'envoi" if before else "App publiée · envoi du cache…") + '''")
        precondition(CloudLibraryIndicator(state: model.states[game.id]!).label(context: en) == "Cloud only")''')
        if browser:
            host = host.replace("// TYPED_PATH_CHECK", '''
        model.active = nil
        model.queue = []
        let typedPath = CloudSetupAssistant(viewModel: vm, model: model, entry: .sources) {}
        typedPath.checkTypedPath("Arcane/../Sources", expected: nil)
        typedPath.checkTypedPath("  Future/Uncreated files  ", expected: "Future/Uncreated files")
''')
            with assistant.open("a") as swift:
                swift.write('''
extension CloudSetupAssistant {
    @MainActor func checkTypedPath(_ path: String, expected: String?) {
        var view = self
        view._listing = State(initialValue: nil)
        view._enteredSourcesPath = State(initialValue: path)
        precondition(view.focusRows.flatMap { $0 }.contains(.sourcesPath))
        precondition(view.primaryEnabled == (expected != nil))
        let previous = model.preference
        if expected != nil && CHECK_PRIMARY_FIRST {
            precondition(view.focusRows.last == [.primary, .cancel])
            var focus = CloudSetupAssistantFocus()
            precondition(focus.current(in: view.focusRows) == .primary)
            focus.move(.right, in: view.focusRows)
            precondition(focus.current(in: view.focusRows) == .cancel)
            focus.move(.left, in: view.focusRows)
            precondition(focus.current(in: view.focusRows) == .primary)
            view._creation = State(initialValue: "Fixture")
            precondition(view.focusRows == [[.create, .cancel]])
            precondition(CloudSetupAssistantFocus().current(in: view.focusRows) == .cancel)
            view._creation = State(initialValue: nil)
        }
        view.perform(.primary)
        precondition(model.preference.sourcesRootOverride == (expected ?? previous.sourcesRootOverride))
        precondition(model.preference.remote == previous.remote && model.preference.root == previous.root)
    }
}
'''.replace("CHECK_PRIMARY_FIRST", "false" if baseline == "5047557" else "true"))
            host = host.replace("// ASSISTANT_CHECK", r'''
        precondition(assistant.focusedTarget == .primary)
        precondition(CloudLibraryIndicator(state: model.states[game.id]!).status == .pending)
        precondition(CloudLibraryIndicator(state: model.states[game.id]!, item: .cache).status == .synchronized)
        precondition(pendingApp.status == .synchronized && !pendingApp.isTransferring)
        model.update(game.id) { $0 = uploading }
        try render("panel-app-published", output,
            CloudLibraryPanel(viewModel: vm, model: model, game: game).environment(\.nxAppLocale, fr))
        model.update(game.id) {
            $0.action = nil; $0.progress = nil
            $0.copies = [.app: .screenFixture(.cloudOnly), .cache: .screenFixture(.synchronized)]
        }
        let transferring = CloudLibraryIndicator(state: uploading, item: .cache)
        precondition(transferring.status == .pending && transferring.isTransferring)
        uploading.queued = true
        let queued = CloudLibraryIndicator(state: uploading, item: .cache)
        precondition(queued.status.color == SeleneTheme.ink60 && !queued.isTransferring)
        precondition(transferring.status.color == SeleneTheme.statusCloud)
        precondition(CloudLibraryBadge(indicator: queued).isVisibleOnTile)
        precondition(CloudLibraryBadge(indicator: transferring).isVisibleOnTile)
        precondition(CloudLibraryBadge(indicator: .init(state: model.states[game.id]!)).isVisibleOnTile)
        var failed = CloudLibraryState()
        failed.sourceFailure = .offline
        precondition(CloudLibraryIndicator(state: failed, item: .sources).status == .failed)
        precondition(CloudLibraryIndicator(state: failed).status == .unknown)
        var local = CloudLibraryState()
        local.copies[.app] = .screenFixture(.notInCloud, hasLocalCopy: true)
        precondition(CloudLibraryIndicator(state: local).status == .needsUpload)
        precondition(!CloudLibraryBadge(indicator: .init(state: local)).isVisibleOnTile)
        precondition(!CloudLibraryBadge(indicator: .init(state: .init(refreshing: true))).isVisibleOnTile)
''')
        else:
            change(assistant, r'@State private var draft = CloudSetupAssistantDraft\(\)', '''
    @State private var draft: CloudSetupAssistantDraft = {
        var draft = CloudSetupAssistantDraft()
        draft.chooseAccount("fixture")
        draft.browse("Games")
        return draft
    }()
'''.strip())
            change(assistant, r'@State private var selectingSources = false', '@State private var selectingSources = true')
            change(assistant, r'@State private var sourcesPath = ""', '@State private var sourcesPath = "Games/GameFiles"')
        host = multiplayer_fixture(app, host, before)
        adapters = package / "Sources/ArcanePorting/GameSettings/RemotePlayAdapters.swift"
        with adapters.open("a") as swift:
            swift.write('''
extension RemotePlayAdapters {
    public static func screenFixture(connected: Bool) -> Self {
        var adapters = Self()
        if connected { adapters.consider("feth3971", flags: UInt32(IFF_UP), ipv4: 0x0ac7920b) }
        return adapters
    }
}
''')
        (app / "CloudScreenProbe.swift").write_text(host)
        with (app / "ViewModels/AppViewModel+CloudLibrary.swift").open("a") as swift:
            probe = '''
extension AppViewModel {
    @MainActor func checkReferenceScreen(access: Bool) async throws {
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            precondition(args.contains("--drive-root-folder-id") && args[0] == "lsjson")
            if !access { return .init(status: 1, stdout: "", stderr: "googleapi: Error 403: forbidden") }
            let name = #"[{"Name":"Arcane-nx","Path":"Arcane-nx","ID":"1-arcane-fixture","Size":-1}]"#
            let output = args.contains("--drive-shared-with-me") ? name : args.contains("--stat") ? #"{"IsDir":true}"# : "[]"
            return .init(status: 0, stdout: output, stderr: "")
        }
        let reference = backend.reference(folderID: cloudLibrary.preference.referenceFolder!)!
        cloudLibrary.installScreenReference(reference)
        await importCloudReference(archive: cloudLibrary.archive!)
    }

    @MainActor func screenRebuildNotice() {
        let game = PortedGame(name: "Pokémon Legends: Z-A", url: AppData.supportRoot.appendingPathComponent("Fixture.app"),
                             platform: .macApp, sizeBytes: 0, modificationDate: .now)
        let archive = CloudGameArchive(backend: RcloneStorageBackend(remote: "fixture", root: "Games"))
        showCloudBuildNotice(for: game, archive: archive, extraArguments: [], onStarted: nil,
                             canDownload: true, hasLocalCache: true)
    }
}
extension CloudLibraryModel {
    func installScreenSources(_ fixture: RcloneStorageBackend, root: String) {
        sourceArchive = CloudGameSources(backend: fixture, root: root)
    }
    func installScreenArchives(_ fixture: RcloneStorageBackend) {
        backend = fixture
        archive = CloudGameArchive(backend: fixture)
        sourceArchive = nil
        referenceArchive = nil
    }
    func installScreenReference(_ reference: RcloneStorageBackend) {
        referenceBackend = reference
        referenceArchive = CloudGameArchive(backend: reference)
    }
}
'''
            if before:
                probe = re.sub(r'    @MainActor func checkReferenceScreen.*?(?=    @MainActor func screenRebuildNotice)',
                               '', probe, flags=re.S).split('extension CloudLibraryModel')[0]
            swift.write(probe)
        with (package / "Sources/ArcanePorting/Library/CloudGameArchive.swift").open("a") as swift:
            swift.write('''
extension CloudArtifactStatus {
    public static func screenFixture(_ state: State, hasLocalCopy: Bool? = nil, fileByFile: Bool = false) -> Self {
        .init(state: state, hasLocalCopy: hasLocalCopy ?? (state == .synchronized), bytes: 100_000_000,
              uploadedAt: Date(timeIntervalSince1970: 1_795_000_000), skippedRoots: []/* FILE_BY_FILE */)
    }
}
'''.replace("/* FILE_BY_FILE */", "" if before else
            ', remoteFolder: fileByFile ? "Fixture [0100000000001000]/app/version" : nil'))
        font = ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"
        icon = ROOT / "Resources/AppIcon-Light.png"
        subprocess.run(["swift", "run", "--package-path", str(package), "NXLibrary", str(output), str(font), str(icon)]
                       + ([str(pixel_reference)] if compare else []),
                       check=True, env=dict(os.environ, HOME=temp, CFFIXED_USER_HOME=temp))


if __name__ == "__main__":
    main()
