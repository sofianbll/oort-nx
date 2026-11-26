#!/usr/bin/env python3
"""Render cloud and multiplayer views offscreen with synthetic states; never start the launcher."""
import os
import pwd
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
import CryptoKit
import SwiftUI
import NXLibraryCore
import ArcanePorting

@main struct CloudScreenProbe {
    @MainActor static func main() async throws {
        let fixtureHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!, isDirectory: true)
            .resolvingSymlinksInPath().path
        precondition(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path == fixtureHome
            && URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath().path == fixtureHome,
            "The cloud probe cannot run outside its temporary home")
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let font = URL(fileURLWithPath: CommandLine.arguments[2])
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        NSApplication.shared.applicationIconImage = NSImage(contentsOfFile: CommandLine.arguments[3])
        let data = AppData.supportRoot
        // SCENARIO
        let settings = AppSettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: .init(), repository: .init(store: .init(directory: data)))
        let model = vm.cloudLibrary
        // SCOPED_FIXTURE
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
            precondition(notice.choices == [CACHE_ORDER])
            precondition(vm.settingsNoticeFocus == CACHE_FOCUS && notice.cancelIndex == CACHE_BACK)
            try renderNotice(name, output, notice, width: 1440)
        }
        L10n.setContext(.init(language: .english, region: "US"))
        vm.settingsNotice = nil
        try render("settings", output, SettingsCloudLibrarySection(
            viewModel: vm, model: model, settings: /* CLOUD_SETTINGS */ SettingsEditor(settings), advanced: .constant(false),
            onEdit: {}, onEditSources: {}, onActions: { _ in })
            .padding(24).frame(width: 1040))
        // ADVANCED_SETTINGS
        let assistant = CloudSetupAssistant(viewModel: vm, model: model /* ENTRY */) {}
        // ASSISTANT_CHECK
        try render("assistant", output, assistant
            .environment(\.nxAppLocale, .init(language: .french, region: "FR"))
            .environment(\.seleneButtonNames, .xbox))
        // ACCOUNT_SCOPE
        // QUIT_COPY
        precondition(vm.portingTileLook(game) == .toDownload)
        try render("tile", output,
            CollectionCoverRow(games: [.init(nxnative: game)], selectedID: game.id,
                artwork: ArtworkStore(), boxArt: vm.boxArt, boxArtIndexVersion: 0,
                officialName: { _ in nil }, needsMetadata: { _ in }, cloud: model,
                showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in }),
            size: .init(width: 400, height: 440))
        // Every resting look, with its corner mark.
        let looks: [PortingTileLook] = [.normal, .toDownload, .toBuild, .toDownloadFiles, .unchecked, .missing]
        let shelf = looks.enumerated().map { index, look in
            PortedGame(name: ["Ready", "App in cloud", "Files here", "Files in cloud", "Not checked", "Not found"][index],
                       url: URL(fileURLWithPath: "/fixture/\(index).app"), platform: .macApp, sizeBytes: 0, modificationDate: .now)
        }
        let lookByID = Dictionary(uniqueKeysWithValues: zip(shelf.map(\.id), looks))
        for position in TileBadgePosition.allCases {
        try render("tile-looks-\(position.rawValue)", output,
            CollectionCoverRow(games: shelf.map { .init(nxnative: $0) }, selectedID: shelf[0].id,
                artwork: ArtworkStore(), boxArt: vm.boxArt, boxArtIndexVersion: 0,
                officialName: { _ in nil }, needsMetadata: { _ in },
                tileLook: { lookByID[$0.id] ?? .normal }, cloud: model,
                showsCloudBadges: true, badgePosition: position, onSelect: { _ in }, onActivate: { _ in }),
            size: .init(width: 1500, height: 440))
        }
        // ENGINE_VERSION
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
            SettingsCloudLibrarySection(viewModel: vm, model: model, settings: SettingsEditor(settings), advanced: .constant(false),
                onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
                .environment(\.nxAppLocale, L10n.context)
                .padding(24).frame(width: 1040)
        }
        try await vm.checkReferenceScreen(access: true)
        precondition(model.referenceCheck?.name == nil && model.referenceCheck?.count == 0)
        try render("reference-settings", output, referenceSettings())
        try await vm.checkReferenceScreen(access: false)
        precondition(model.referenceCheck?.failure == .unavailable)
        try render("reference-error", output, referenceSettings())
        // CLOUD_REVIEW_START
        try await vm.checkManifestOnlyReferenceSelection()
        // CLOUD_REVIEW_END
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
        // SOURCE_ONLY_CHECK
        // SWITCH_GAMES_SOURCES
        // MOVE_RECOVERY
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

ENGINE_VERSION = r'''
    @MainActor static func checkEngineVersion(_ vm: AppViewModel, _ output: URL, _ settings: AppSettingsStore) async throws {
        let root = AppData.supportRoot.appendingPathComponent("engine-screen")
        let repo = root.appendingPathComponent("engine")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        func git(_ args: [String], day: String = "23") throws -> String {
            var env = ProcessInfo.processInfo.environment
            env["GIT_AUTHOR_DATE"] = "2026-11-\(day)T12:00:00Z"
            env["GIT_COMMITTER_DATE"] = env["GIT_AUTHOR_DATE"]
            let result = try SystemCommandRunner().run(URL(fileURLWithPath: "/usr/bin/git"),
                ["-C", repo.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@users.noreply.github.com",
                 "-c", "commit.gpgsign=false"] + args, environment: env, currentDirectory: nil)
            precondition(result.status == 0, result.stderr)
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try git(["init", "-q"])
        _ = try git(["commit", "-qm", "older", "--allow-empty"], day: "21")
        let old = try git(["rev-parse", "HEAD"])
        _ = try git(["commit", "-qm", "selected", "--allow-empty"])
        let current = try git(["rev-parse", "HEAD"])
        func fixture(_ name: String, _ commit: String?, number: Int, localFiles: Bool = false) throws -> PortedGame {
            let bundle = root.appendingPathComponent(name + ".app")
            let title = "010000000000100\(number)"
            var game = PortedGame(name: name, url: bundle, platform: .macApp, sizeBytes: 2_000_000_000,
                                  modificationDate: .now, titleId: title, versionString: "1.0")
            game.toolchain.engineCommit = current // Deliberately wrong for the older fixtures.
            game.status = commit == nil ? .appMissing : .built
            let file = root.appendingPathComponent(name + ".nsp")
            game.sources = [.init(url: file, kind: .base, titleId: title, sizeBytes: 1)]
            if localFiles { try Data([0]).write(to: file) }
            if let commit {
                let plist = bundle.appendingPathComponent("Contents/Info.plist")
                try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: ["DMCommit": String(commit.prefix(12))],
                                                               format: .binary, options: 0)
                try data.write(to: plist)
            }
            return game
        }
        let local = try fixture("Fichiers sur le Mac", old, number: 1, localFiles: true)
        let cloud = try fixture("Fichiers dans le cloud", old, number: 2)
        let missing = try fixture("Fichiers manquants", old, number: 3)
        let updated = try fixture("App à jour", current, number: 4, localFiles: true)
        let blocked = try fixture("App à télécharger", nil, number: 5, localFiles: true)
        let games = [local, cloud, missing, updated, blocked]
        let oldPath = vm.setup.nxnativePath
        let oldChoice = vm.setup.newestEngineChoice
        let oldCatalog = vm.catalogSnapshot
        defer {
            vm.setup.nxnativePath = oldPath
            vm.setup.newestEngineChoice = oldChoice
            vm.applyCatalog(oldCatalog)
        }
        vm.setup.nxnativePath = repo.path
        vm.setup.newestEngineChoice = .init(commit: current, aheadBy: 1, turnedOnOverride: false)
        vm.applyCatalog(.init(games: games.map { .init(nxnative: $0) }))
        await vm.refreshInstalledEngineVersions().value
        vm.cloudLibrary.update(local.id) { $0.copies[.app] = .screenFixture(.synchronized) }
        vm.cloudLibrary.update(cloud.id) { $0.sourceAvailability = .versionFixture(cloud.sources[0].url) }
        // A previous cloud observation for a different selection must not offer an update.
        vm.cloudLibrary.update(missing.id) { $0.sourceAvailability = .versionFixture(cloud.sources[0].url) }
        vm.cloudLibrary.update(blocked.id) { $0.copies[.app] = .screenFixture(.cloudOnly) }
        precondition(games.map(vm.portingTileLook) == [.engineUpdate, .engineUpdate, .normal, .normal, .toDownload])

        let previousLocale = L10n.context
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        defer { L10n.setContext(previousLocale) }
        let expected = ["mise à jour possible", "mise à jour possible", "fichiers du jeu requis pour la mise à jour",
                        "à jour", "Aucune app installée"]
        let art = ArtworkStore()
        let history = PlaySessionStore()
        let running = RunningGameMonitor()
        for (index, game) in games.enumerated() {
            let details = GameDetailView(viewModel: vm, setup: vm.setup, store: vm.store, router: AppRouter(),
                            settings: settings, playSessions: history, runningGames: running, artwork: art, game: game)
            let facts = details.model.facts
            precondition(facts.first(where: { $0.kind == .engine })?.value.hasSuffix(expected[index]) == true)
            try render("engine-details-\(index)", output,
                DetailsPanel(facts: facts, links: [], focusedLink: nil, onHoverLink: { _ in }, onPressLink: { _ in },
                             width: index == 2 ? DetailsPanel.narrowWidth : DetailsPanel.wideWidth)
                    .environment(\.nxAppLocale, fr),
                size: .init(width: 1200, height: 260))
        }
        for position in TileBadgePosition.allCases {
            try render("engine-collection-\(position.rawValue)", output,
                CollectionCoverRow(games: games.map { .init(nxnative: $0) }, selectedID: local.id,
                    artwork: art, boxArt: vm.boxArt, boxArtIndexVersion: 0, officialName: { _ in nil },
                    needsMetadata: { _ in }, tileLook: vm.portingTileLook, cloud: vm.cloudLibrary, showsCloudBadges: true,
                    badgePosition: position, onSelect: { _ in }, onActivate: { _ in })
                    .environment(\.onlinePlayersByTitle, [local.titleId!.lowercased(): 8, updated.titleId!.lowercased(): 5])
                    .environment(\.nxAppLocale, fr),
                size: .init(width: 1340, height: 440))
        }
        let items = games.map { SpotlightItem.game($0.id) }
        vm.cloudLibrary.update(cloud.id) {
            $0.action = .downloadSources
            $0.progress = .init(.downloading, transfer: .init(bytesTransferred: 42, totalBytes: 100))
        }
        try render("engine-spotlight", output,
            SpotlightRowView(items: items, gamesByID: Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) }),
                selectedKey: items[0].key, isEmptyFilter: nil, artwork: art, tileLook: vm.portingTileLook,
                cloud: vm.cloudLibrary, showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in })
                .environment(\.nxAppLocale, fr),
            size: .init(width: 1180, height: 325))
        print("Engine version from DMCommit, files local/cloud/missing, Details and both tile rows verified.")
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
                    cloud: model, showsCloudPill: true, downloadEnabled: true)
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

SOURCE_ONLY = r'''
extension CloudScreenProbe {
    @MainActor static func checkSourceOnly(in root: URL, output: URL) async throws {
        let folder = root.appendingPathComponent("source-only-catalog")
        let repo = CatalogRepository(store: .init(directory: folder))
        let settings = AppSettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
        // The headless SwiftPM executable has no notification bundle.
        settings.settings.notifyPortingEnds = false
        let title = "0100000000006000", referenceID = "source-reference-fixture"
        let folderName = "Lunar Observatory [\(title)]"
        let anchor = "fixture:Games/GameFiles/" + folderName
        let xml = Data("<ContentMeta><Type>Application</Type><Id>0x\(title)</Id><Version>0</Version></ContentMeta>".utf8)
        let name = Data("meta.cnmt.xml\0".utf8)
        func le32(_ n: Int) -> Data { var v = UInt32(n).littleEndian; return Data(bytes: &v, count: 4) }
        func le64(_ n: Int) -> Data { var v = UInt64(n).littleEndian; return Data(bytes: &v, count: 8) }
        let payload = Data("PFS0".utf8) + le32(1) + le32(name.count) + le32(0)
            + le64(0) + le64(xml.count) + le32(0) + le32(0) + name + xml
        let checksum = Insecure.MD5.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let localRoot = root.path + "/"
        func newModel() throws -> AppViewModel {
            let catalog = try repo.load()
            let vm = AppViewModel(settingsStore: settings, catalog: catalog, repository: repo)
            vm.applyCatalog(catalog) // The harness disables startup services.
            return vm
        }
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            precondition(args.contains("--drive-skip-shortcuts"))
            let scope = args.contains("--drive-root-folder-id=\(referenceID)")
            let root = scope ? "fixture:" : "fixture:Games"
            let files = scope ? "fixture:GameFiles" : "fixture:Games/GameFiles"
            func entries(_ names: [String], dir: Bool) -> String {
                let rows: [[String: Any]] = names.map { ["Name": $0, "Path": $0, "Size": dir ? -1 : 1, "IsDir": dir] }
                return String(decoding: try! JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
            }
            let node = #"{"Name":"Game.nsp","Path":"Game.nsp","Size":\#(payload.count),"IsDir":false,"Hashes":{"md5":"\#(checksum)"}}"#
            switch (args[0], args[1]) {
            case ("lsjson", root):
                if args.contains("--stat") { return .init(status: 0, stdout: #"{"Name":"Reference fixture","IsDir":true}"#, stderr: "") }
                return .init(status: 0, stdout: entries(["GameFiles"], dir: true), stderr: "")
            case ("lsjson", files):
                let names = scope ? ["Aube [0100000000007000]"] : [folderName, "Dossier ambigu", "Sans identifiant"]
                return .init(status: 0, stdout: entries(names, dir: true), stderr: "")
            case ("lsjson", anchor), ("lsjson", "fixture:GameFiles/Aube [0100000000007000]"):
                return .init(status: 0, stdout: "[\(node)]", stderr: "")
            case ("lsjson", "fixture:Games/GameFiles/Dossier ambigu"):
                return .init(status: 0, stdout: entries(["Two [0100000000008000].nsp", "One [0100000000009000].nsp"], dir: false), stderr: "")
            case ("lsjson", "fixture:Games/GameFiles/Sans identifiant"):
                return .init(status: 0, stdout: entries(["Unknown.nsp"], dir: false), stderr: "")
            case ("lsjson", anchor + "/Game.nsp"):
                precondition(args.contains("--stat"))
                return .init(status: 0, stdout: node, stderr: "")
            case ("copyto", anchor + "/Game.nsp"):
                precondition(args[2].hasPrefix(localRoot))
                try payload.write(to: URL(fileURLWithPath: args[2]))
                return .init(status: 0, stdout: "", stderr: "")
            default: preconditionFailure("Unexpected remote operation: \(args.prefix(2))")
            }
        }
        let fr = AppLocale(language: .french, region: "FR")
        L10n.setContext(fr)
        var vm = try newModel()
        let model = vm.cloudLibrary
        model.configure(remote: "fixture", root: "PreviousGames", enabled: true, sourcesRoot: nil)
        model.chooseSourcesRoot("Games/GameFiles")
        precondition(!model.sourcesNeedConfirmation)
        model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: "Games/GameFiles")
        precondition(model.sourcesNeedConfirmation && model.sourceArchive == nil)
        let sourceSettings = SettingsCloudLibrarySection(viewModel: vm, model: model, settings: SettingsEditor(settings),
            advanced: .constant(false), onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
        try render("settings-sources-confirmation-fr", output, sourceSettings.environment(\.nxAppLocale, fr)
            .padding(24).frame(width: 1040))
        sourceSettings.requestSourceConfirmationForProbe()
        guard let notice = vm.settingsNotice else { preconditionFailure("No source confirmation") }
        precondition(notice.choices == ["Cancel", "Use default", "Keep this folder"] && notice.initialFocus == notice.cancelIndex)
        try renderNotice("settings-sources-question-fr", output, notice, width: 1120)
        vm.settingsNotice = nil
        notice.runAnswer(.back)
        precondition(model.sourcesNeedConfirmation && model.sourceArchive == nil)
        sourceSettings.requestSourceConfirmationForProbe()
        vm.settingsNotice?.runAnswer(.alternative(0))
        vm.settingsNotice = nil
        precondition(!model.sourcesNeedConfirmation && model.preference.sourcesRootOverride == "Games/GameFiles")
        print("Changed library: Cancel kept source downloads blocked; Keep this folder confirmed Games/GameFiles.")
        vm.cloudLibrary.installScreenArchives(backend)
        vm.cloudLibrary.installScreenSources(backend, root: "Games/GameFiles")
        vm.importCloudGames(manually: true)
        await vm.cloudLibrary.importTask?.value
        let game = vm.libraryGames.first { $0.titleId == title }!
        precondition(vm.libraryGames.count == 1 && game.isCloudSourcePlaceholder)
        precondition(vm.cloudLibrary.downloadItem(for: game) == .sources && vm.portingTileLook(game) == .toDownloadFiles)
        precondition(!GameResourceState.sourcesAvailable(for: game))
        precondition(vm.settingsNotice?.message.contains("Dossier ambigu") == true)
        precondition(vm.settingsNotice?.message.contains("Sans identifiant") == true)
        precondition(vm.cloudLibrary.lastCompleteCheck == nil && vm.cloudLibrary.connectionCheck?.failure == .incomplete)
        vm.checkPartialCloudReview(game)
        try renderNotice("cloud-only-import-fr", output, vm.settingsNotice!, width: 1120)

        let png = try Data(contentsOf: output.appendingPathComponent("tile.png"))
        let pick = try ArtworkPicks.shared.save(png, titleID: vm.personalizationKey(for: game), slot: .icon)
        precondition(ArtworkPicks.shared.url(titleID: vm.personalizationKey(for: game), slot: .icon) == pick)
        vm.applyCatalog(try repo.updateNXNative(id: game.id) { $0.isFavorite = true })
        let selected = vm.libraryGames.first { $0.id == game.id }!
        precondition(selected.isFavorite && !GameResourceState.sourcesAvailable(for: selected))
        let results = vm.queryLibrary(.init(filter: .cloud), history: NoPlayHistory())
        precondition(results.map(\.id) == [game.id])
        let cover = CollectionCoverRow(games: results, selectedID: selected.id,
            artwork: ArtworkStore(), boxArt: vm.boxArt, boxArtIndexVersion: 0,
            officialName: { _ in nil }, needsMetadata: { _ in }, tileLook: vm.portingTileLook,
            cloud: vm.cloudLibrary, showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in })
        try render("cloud-only-tile-fr", output, cover, size: .init(width: 400, height: 440))
        try render("cloud-only-filter-fr", output, VStack(spacing: 0) {
            SpotlightTopBar(filter: .cloud, sort: .name, showClock: false)
            cover
        }.environment(\.nxAppLocale, fr), size: .init(width: 1400, height: 580))
        func details(_ game: PortedGame, vm: AppViewModel) -> some View {
            let model = vm.cloudLibrary
            return DetailsTopBlock(game: game, logo: nil,
                presentation: .init(game: game, metadata: nil, totalPlaytime: 0, lastPlayed: nil),
                isRunning: false, focusedPill: 0, primaryEnabled: true, expanded: .constant(false),
                onPrimary: {}, onSecondary: {}, onFavorite: {}, onHoverPill: { _ in },
                pillSet: vm.portingPills(game).detailsPresentation(cloudOnly: model.downloadItem(for: game) != nil),
                cloud: model, showsCloudPill: true, downloadEnabled: true).environment(\.nxAppLocale, fr)
        }
        try render("cloud-only-details-fr", output, details(selected, vm: vm), size: .init(width: 1120, height: 470))

        // Recreate the app model from disk before connecting the unavailable backend.
        vm = try newModel()
        let offline = RcloneStorageBackend(remote: "fixture", root: "Games") { _, _, _ in
            .init(status: 1, stdout: "", stderr: "connection reset")
        }
        vm.cloudLibrary.installScreenArchives(offline)
        vm.cloudLibrary.installScreenSources(offline, root: "Games/GameFiles")
        vm.importCloudGames(manually: true)
        await vm.cloudLibrary.importTask?.value
        precondition(vm.cloudLibrary.connectionCheck?.failure == .offline)
        precondition(vm.portingTileLook(selected) == .toDownloadFiles)
        precondition(vm.cloudLibrary.states[game.id]?.copy(.sources) != .synchronized)
        precondition(vm.queryLibrary(.init(filter: .cloud), history: NoPlayHistory()).map(\.id) == [game.id])

        vm = try newModel()
        vm.cloudLibrary.installScreenArchives(backend)
        vm.cloudLibrary.installScreenSources(backend, root: "Games/GameFiles")
        vm.cloudLibrary.hasRestoredQueue = true
        precondition(vm.cloudLibrary.matchesPersistedStorage(), "The isolated fixture must own its source root")
        vm.downloadCloudGame(selected)
        let task = vm.cloudLibrary.active?.task
        precondition(task != nil, "Download game files must go through the transfer queue")
        await task?.value
        let bytes = try? Data(contentsOf: selected.sources[0].url)
        let state = vm.cloudLibrary.states[game.id]
        precondition(bytes == payload,
                     "Source download failed: \(state?.issue?.message ?? "no issue"); \(String(describing: vm.cloudLibrary.queuePause))")
        precondition(vm.portingTileLook(selected) == .toBuild)
        precondition(vm.cloudLibrary.downloadItem(for: selected) == nil)
        precondition(vm.queryLibrary(.init(filter: .cloud), history: NoPlayHistory()).isEmpty)
        print("Download files: verified fixture bytes; tile changed to Build.")
        try render("cloud-only-build-fr", output, details(selected, vm: vm), size: .init(width: 1120, height: 470))
        try await checkBuildAndPlay(vm, game: selected, in: root, output: output)

        // Build completion starts a catalog scan; imports are refused until it finishes.
        let scanDeadline = ContinuousClock.now + .seconds(10)
        while vm.isScanningLibrary && ContinuousClock.now < scanDeadline {
            try await Task.sleep(for: .milliseconds(15))
        }
        precondition(!vm.isScanningLibrary, "The post-build catalog scan did not finish")
        vm.cloudLibrary.setReferenceFolder(referenceID)
        vm.cloudLibrary.installScreenArchives(backend)
        vm.cloudLibrary.installScreenSources(backend, root: "Games/GameFiles")
        vm.cloudLibrary.installScreenReference(backend.reference(folderID: referenceID)!, sourceRoot: "GameFiles")
        vm.importCloudGames(manually: true)
        guard let referenceImport = vm.cloudLibrary.importTask else { preconditionFailure("Reference import did not start") }
        await referenceImport.value
        guard let shared = vm.libraryGames.first(where: { $0.cloudSourcesReferenceFolder == referenceID }) else {
            preconditionFailure("No shared fixture after import: \(vm.settingsNotice?.message ?? "no notice")")
        }
        precondition(vm.portingTileLook(shared) == .toDownloadFiles && !GameResourceState.sourcesAvailable(for: shared))
        vm.applyCatalog(try repo.forgetCloudReference(referenceID))
        precondition(!vm.libraryGames.contains { $0.id == shared.id })
        print("Cloud-only: changed library confirmation, discovery, restart offline, Download files, synthetic Build, and Play dispatch verified.")
    }

    @MainActor static func checkBuildAndPlay(_ vm: AppViewModel, game: PortedGame, in root: URL, output: URL) async throws {
        let fm = FileManager.default
        let apps = root.appendingPathComponent("FixtureApps", isDirectory: true)
        let engine = root.appendingPathComponent("SyntheticEngine", isDirectory: true)
        for dir in [apps, engine.appendingPathComponent("scripts"), engine.appendingPathComponent(".venv/bin")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // The system launcher resolves by the link's name ("python"), not by "/usr/bin/python3".
        let python = ProcessInfo.processInfo.environment["OORT_CLOUD_PROBE_PYTHON"]!
        try fm.createSymbolicLink(at: engine.appendingPathComponent(".venv/bin/python"),
                                  withDestinationURL: URL(fileURLWithPath: python))
        try """
        import pathlib, plistlib, shutil, subprocess, sys
        args = sys.argv
        workspace = pathlib.Path(args[1])
        assert (workspace / "Game.nsp").read_bytes().startswith(b"PFS0")
        app = pathlib.Path(args[args.index("-o")+1])
        exe = app / "Contents/MacOS/Fixture"
        exe.parent.mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", exe)
        exe.chmod(0o755)
        contents = dict(CFBundleIdentifier="local.oort.cloud-proof", CFBundleExecutable="Fixture",
                        CFBundlePackageType="APPL", CFBundleShortVersionString="1.0", DMTitleID="0100000000006000")
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(contents, stream)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True)
        """.write(to: engine.appendingPathComponent("scripts/build_ipa_from_nsp.py"), atomically: true, encoding: .utf8)
        vm.libraryFolder = apps
        vm.setup.nxnativePath = engine.path
        vm.setup.isNxnativeValid = true
        vm.setup.environmentStatus = .screenCloudFixture(engine)
        vm.porting.restoreBuildQueue([])
        vm.settingsNotice = nil
        vm.porting.startBuild(for: game)
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline,
              vm.libraryGames.first(where: { $0.id == game.id })?.isPlayableLocally != true {
            if vm.settingsNotice != nil || vm.porting.buildError != nil { break }
            await Task.yield()
        }
        guard let ready = vm.libraryGames.first(where: { $0.id == game.id }), ready.isPlayableLocally,
              ready.isFavorite, ready.url.path.hasPrefix(apps.path + "/"),
              fm.fileExists(atPath: ready.url.appendingPathComponent("Contents/MacOS/Fixture").path)
        else { preconditionFailure("Synthetic build failed: \(vm.settingsNotice?.message ?? vm.porting.buildError ?? "no result"); \(vm.logs.suffix(8))") }
        print("Build: synthetic app installed in FixtureApps and catalog marked it playable; favorite preserved.")
        var launched: URL?
        vm.screenPlay = { launched = $0.url }
        vm.launchGame(ready)
        precondition(launched == ready.url && vm.portingTileLook(ready) == .normal)
        print("Play: routed to the newly built fixture app (launch intercepted).")
        try render("cloud-only-play-fr", output, DetailsTopBlock(game: ready, logo: nil,
            presentation: .init(game: ready, metadata: nil, totalPlaytime: 0, lastPlayed: nil),
            isRunning: false, focusedPill: 0, primaryEnabled: true, expanded: .constant(false),
            onPrimary: {}, onSecondary: {}, onFavorite: {}, onHoverPill: { _ in }, pillSet: .normal,
            cloud: vm.cloudLibrary, showsCloudPill: true, downloadEnabled: true)
            .environment(\.nxAppLocale, L10n.context), size: .init(width: 1120, height: 470))
    }
}
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
        vm.cloudLibrary.setReferenceFolder("1-fixture")
        vm.cloudLibrary.installScreenArchives(backend)
        vm.cloudLibrary.installScreenReference(referenceRead)
        let selected = vm.libraryGames.first { $0.id == game.id }!
        RunningGameMonitor.screenRunning.withLock { $0 = bundleID }
        monitor.refresh()
        await vm.refreshCloudLibrary(selected)
        L10n.setContext(fr)
        vm.performCloudLibrary(.restore(.app), for: selected)
        guard let refusal = vm.settingsNotice else { preconditionFailure("Download must ask before replacing") }
        precondition(refusal.choices == ["Cancel", "Replace"] && vm.settingsNoticeFocus == refusal.cancelIndex)
        try renderNotice("reference-replacement-confirmation", output, refusal, width: 1280)
        vm.settingsNotice = nil
        refusal.runAnswer(.back)
        let unchanged = try version()
        precondition(unchanged == "1.0" && vm.cloudLibrary.active == nil)
        vm.performCloudLibrary(.restore(.app), for: selected)
        let approved = vm.settingsNotice!
        vm.settingsNotice = nil
        approved.runAnswer(.retry)
        precondition(vm.cloudLibrary.active?.request.sourceReference == "1-fixture",
                     "The confirmed replacement must retain its reference provider")
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
        let movedUpload = CloudTransferQueue.Entry(id: game.id, action: .uploadSources, token: UUID(), storage: "old-drive:Old folder")
        vm = try await reopen(movedUpload)
        await vm.restoreActivity()
        await vm.activityStore.flush()
        let savedReconfirmation = await vm.activityStore.load()
        if let moved = savedReconfirmation.first(where: { $0.id == movedUpload.token }) {
            precondition(moved.job == .cloud(movedUpload))
            vm.retryActivity(moved.id)
            precondition(vm.settingsNotice?.message.contains("old-drive:Old folder") == true)
            try renderNotice("queue-previous-destination", output, vm.settingsNotice!, width: 1280)
            let restarted = try makeModel()
            await restarted.restoreActivity()
            precondition(restarted.activityResults.entries.filter { $0.id == moved.id }.count == 1)
        } else {
            failures.append("Changed upload destination silently removed the original queue token")
        }
        precondition(!fm.fileExists(atPath: remotePackage.path) && vm.cloudLibrary.active == nil)
        for file in ["activity-results.json", "cloud-transfer-queue.json"] {
            for stage in ["before", "after"] {
                let request = CloudTransferQueue.Entry(id: game.id, action: .uploadSources, token: UUID(), storage: expectedStorage)
                let failing = try makeModel()
                failing.cloudLibrary.installScreenSources(backend, root: sources.path)
                failing.cloudLibrary.queueStore.save([request])
                await failing.cloudLibrary.queueStore.flush()
                CloudWriteFault.arm(file, stage)
                failing.restoreCloudQueue()
                try await until { !failing.cloudLibrary.isRestoringQueue }
                await failing.cloudLibrary.queueStore.flush()
                await failing.activityStore.flush()
                let hit = CloudWriteFault.disarm()
                let queue = await failing.cloudLibrary.queueStore.load()
                let history = await failing.activityStore.load()
                let leftInQueue = queue.contains(request)
                let visibleInHistory = history.contains { $0.id == request.token && $0.job == .cloud(request) }
                if !hit || !(leftInQueue || visibleInHistory)
                    || (file == "activity-results.json" && !leftInQueue) {
                    failures.append("Reconfirmation publication: incorrect recovery after \(file) \(stage) write")
                }
                let restarted = try makeModel()
                restarted.cloudLibrary.installScreenSources(backend, root: sources.path)
                restarted.restoreCloudQueue()
                try await until { restarted.cloudLibrary.hasRestoredQueue }
                await restarted.cloudLibrary.queueStore.flush()
                await restarted.restoreActivity()
                await restarted.activityStore.flush()
                let recovered = await restarted.activityStore.load()
                if recovered.filter({ $0.id == request.token && $0.job == .cloud(request) }).count != 1 {
                    failures.append("Reconfirmation publication: missing or duplicated token after \(file) \(stage) restart")
                }
                precondition(!fm.fileExists(atPath: remotePackage.path))
            }
        }
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
                                    storage: vm.cloudLibrary.storageScope(for: .restore(.cache)),
                                    toolIdentity: vm.cloudLibrary.transferToolIdentity!))
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
        let freshCatalog = try freshRepository.load()
        let importer = AppViewModel(settingsStore: settings, catalog: freshCatalog, repository: freshRepository)
        importer.applyCatalog(freshCatalog)
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
        let observedEmpty = try emptyCatalog.load()
        let badImporter = AppViewModel(settingsStore: settings, catalog: observedEmpty, repository: emptyCatalog)
        badImporter.applyCatalog(observedEmpty)
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
            SettingsGamesSection(viewModel: vm, settings: SettingsEditor(settings), onActions: { _ in })
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
            precondition(warning.choices == ["Cancel", "Play on the local network"])
            precondition(vm.settingsNoticeFocus == 1 && warning.cancelIndex == 0)
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
    if "OortSettingsShell(" in settings_view.read_text():
        change(settings_view, r'        return ScrollViewReader \{ proxy in\n            ScrollView \{(.*?)\n'
               r'            }\n            \.scrollIndicators\(\.hidden\).*?\n        }\n    }',
               lambda m: "        return Group {" + m[1] + "\n        }\n    }")
        sidebar = app / "Views/OortUI/OortSettingsShell.swift"
        change(sidebar, r'            ScrollViewReader \{ proxy in\n                ScrollView \{(.*?)\n'
               r'                }\n                \.scrollIndicators\(\.hidden\).*?\n            }',
               lambda m: "            Group {" + m[1] + "\n            }")
    else:
        change(settings_view, r'        ScrollViewReader \{ proxy in\n            ScrollView \{\n', '')
        change(settings_view, r'            }\n            \.scrollIndicators\(\.hidden\).*?(?=\n    }\n\n    private var reduceMotion)', '')
        sidebar = app / "Views/Settings/SettingsSidebar.swift"
        change(sidebar, r'            ScrollViewReader \{ proxy in.*?(?=\n        }\n    })', '            groups')
        change(sidebar, r'ForEach\(SettingsSidebarGroup.all\)', 'ForEach(Array(SettingsSidebarGroup.all.prefix(2)))')
    change(settings_view, r'    private var supportsNextendo: Bool \{ [^\n]* \}', '    private var supportsNextendo: Bool { true }')
    change(settings_view, r'        \.background\(SeleneBackdrop\(\)\.environment[^\n]*\n', '')
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
    text, count = re.subn(old, new if callable(new) else lambda _: new, file.read_text(), count=1, flags=re.S)
    assert count == 1, (file, old)
    file.write_text(text)


def isolate_startup(app, *, keep_catalog=False):
    """Stub startup side effects only in a probe's copied app sources."""
    model = app / "ViewModels/AppViewModel.swift"
    anchor = r"        setup\.restoreBuildInputs\(automatic: true\b" if keep_catalog else r"        applyCatalog\(catalog\)"
    change(model, anchor + r".*?\n    }\n\n    // MARK: - Dynamic Dock Icon",
           "    }\n\n    // MARK: - Dynamic Dock Icon")


def capture_destination(prefix):
    return Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix=prefix)).resolve()


def isolated_home_env(home):
    home = home.resolve()
    real_home = Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()
    assert not home.is_relative_to(real_home)
    assert not os.environ.get("ORIGINAL_HOME") or not home.is_relative_to(Path(os.environ["ORIGINAL_HOME"]).resolve())
    return dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))


def isolate_cloud_init(model, fixture):
    change(model, r"(    init\((?:activation: CloudLibraryActivation\? = nil)?\) \{\n)"
           r"        let defaults = AppData\.preferences.*?(?=        rebuildArchive\(\))",
           lambda match: match[1] + fixture)


def cloud_settings_fixture(app, host):
    section = (app / "Views/Settings/SettingsCloudLibrarySection.swift").read_text()
    settings = "SettingsEditor(settings)" if "var settings: SettingsEditor" in section else "settings"
    return host.replace("/* CLOUD_SETTINGS */ SettingsEditor(settings)", settings)


def install_settings_reset_fixture(app):
    with (app / "Views/Settings/SettingsView.swift").open("a") as swift:
        swift.write("""
extension SettingsView {
    func pressScreenFixtureReset() {
        guard section == .library else { pressReset(); return }
        precondition(settings.draft == nil)
        settings.beginDraft(fields: SettingsDraftFields.fields(profiles: nil, languages: viewModel.availableLanguages))
        let originalInbox = settings.settings.gameInboxEnabled
        let pending = router.hasPendingSettings
        defer { settings.endDraft(); router.hasPendingSettings = pending }
        router.hasPendingSettings = { [weak settings] in settings?.draft?.hasChanges == true }
        pressReset()
        precondition(settings.settings.gameInboxEnabled == originalInbox)
        handleGamepad(.contextAction)
        precondition(router.settingsDecision == .save)
        // This view is not mounted: its @State focus cannot be moved by a synthetic key.
        decide(.save)
        precondition(router.settingsDecision == nil, "Reset must save the draft")
    }
    /// X only asks, on Cancel; leaving changes nothing and Reset runs from the question.
    private func pressReset() {
        viewModel.settingsNotice = nil // An unanswered one would own the input.
        let before = settings.editingSettings
        handleGamepad(.secondaryAction)
        guard let notice = viewModel.settingsNotice else { return precondition(section == .profileSecurity, "Reset must ask") }
        precondition(notice.choices.count == 2 && notice.initialFocus == notice.cancelIndex)
        precondition(settings.editingSettings == before, "Nothing changes before the answer")
        viewModel.settingsNotice = nil
        notice.runAnswer(notice.answers.first { $0.role == .destructive }!.id)
    }
}
""")


def main():
    # Without a folder, as a release regression, render into a throwaway folder under work/.
    (ROOT / "work").mkdir(exist_ok=True)
    output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="cloud-screens-", dir=ROOT / "work")).resolve()
    output.mkdir(parents=True, exist_ok=True)
    before = len(sys.argv) > 2 and sys.argv[2] == "--before"
    baseline = os.environ.get("ARCANE_CLOUD_SCREEN_BASE")
    compare = len(sys.argv) > 2 and sys.argv[2] == "--compare-with-5047557"
    if compare:
        pixel_reference = output / "5047557"
        subprocess.run([sys.executable, __file__, str(pixel_reference)], check=True,
                       env=dict(os.environ, ARCANE_CLOUD_SCREEN_BASE="5047557"))
    with tempfile.TemporaryDirectory(prefix="cloud-screen-", dir=output.parent) as temp:
        package = Path(temp)
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        if before:
            archived = subprocess.check_output(["git", "-C", str(ROOT), "archive", "528f4fb", "Sources", "Package.swift"])
            subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archived, check=True)
        elif baseline:
            archived = subprocess.check_output(["git", "-C", str(ROOT), "archive", baseline, "Sources", "Package.swift"])
            subprocess.run(["tar", "-xf", "-", "-C", str(package)], input=archived, check=True)
        else:
            shutil.copytree(ROOT / "Sources", package / "Sources")
        for name in ("NXLibraryCoreTests", "ArcanePortingTests", "OortCoreTests"):
            folder = package / "Tests" / name
            folder.mkdir(parents=True)
            (folder / "Empty.swift").touch()
        app = package / "Sources/NXLibrary"
        if not before and not baseline:
            queue_file = package / "Sources/ArcanePorting/Library/ActivityQueueFile.swift"
            write = 'try JSONEncoder().encode(WriteSnapshot(entries: entries)).write(to: self.file, options: .atomic)'
            change(queue_file, re.escape(write),
                   f'try CloudWriteFault.check(self.file, "before")\n        {write}\n'
                   '        try CloudWriteFault.check(self.file, "after")')
            with queue_file.open("a") as swift:
                swift.write(r'''
import os
package enum CloudWriteFault {
    private static let state = OSAllocatedUnfairLock(initialState: (file: "", stage: "", hit: false))
    package static func arm(_ file: String, _ stage: String) {
        state.withLock { $0 = (file, stage, false) }
    }
    package static func disarm() -> Bool {
        state.withLock { let hit = $0.hit; $0 = ("", "", false); return hit }
    }
    static func check(_ file: URL, _ stage: String) throws {
        if state.withLock({ value in
            guard !value.hit, value.file == file.lastPathComponent, value.stage == stage else { return false }
            value.hit = true
            return true
        }) { throw CocoaError(.fileWriteUnknown) }
    }
}
''')
        change(app / "NXLibraryApp.swift", r"@main\nstruct", "struct")
        change(app / "ViewModels/AppViewModel.swift", r"SteamGridDBKey\(\)\.load\(\) != nil", "false")
        isolate_startup(app)
        change(package / "Sources/NXLibraryCore/App/AppDataProfile.swift",
               r'public static let profile = [^\n]*',
               'public static let profile = AppDataProfile(home: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!), isDevelopment: true)')
        change(package / "Sources/NXLibraryCore/App/AppDataProfile.swift",
               r'public static var preferences: UserDefaults \{ [^\n]+ \}',
               'nonisolated(unsafe) public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        if before or baseline:
            isolate_cloud_init(app / "ViewModels/AppViewModel+CloudLibrary.swift",
                   '        preference = .init(storage: "fixture:Games", enabled: true, sourcesRoot: nil)\n'
                   '        AppData.preferences.set(preference.storage, forKey: CloudLibraryPreference.storageKey)\n'
                   '        AppData.preferences.set(preference.enabled, forKey: CloudLibraryPreference.enabledKey)\n'
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
        # The large panel has its own probe, run_cloud_assistant.py: here it only has to keep the moves and the settings whole.
        panel = (app / "Views/Settings/CloudSetupAssistant+Browser.swift").is_file()
        change(assistant, r'@State (private )?var remotes: \[RcloneRemote\]\?', '@State var remotes: [RcloneRemote]? = []' if panel
               else '@State private var remotes: [RcloneRemote]? = []')
        account_fixture = ""
        if not before and ("New connections request full Google Drive access." in assistant.read_text()
                           or baseline == "5070a5ec"):
            with assistant.open("a") as swift:
                swift.write('''
extension CloudSetupAssistant {
    func screenAccount() throws -> Self {
        var view = self
        view._tool = State(initialValue: URL(fileURLWithPath: "/fixture/rclone"))
        view._version = State(initialValue: "v1.75.2")
        view._remotes = State(initialValue: try JSONDecoder().decode([RcloneRemote].self,
            from: Data(#"[{"name":"fixture","type":"drive","source":"file"}]"#.utf8)))
        return view
    }
}
''')
            account_fixture = '''
        let account = try CloudSetupAssistant(viewModel: vm, model: model, onClose: {}).screenAccount()
        for (name, locale) in [("en", AppLocale(language: .english, region: "US")),
                               ("fr", AppLocale(language: .french, region: "FR"))] {
            try render("assistant-account-" + name, output, account.environment(\\.nxAppLocale, locale))
        }
'''
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
        elif not panel:
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
        host = HOST.replace("/* NOTICE_LAYOUT */", "vertical: notice.vertical," if before else "cancelIndex: notice.cancelIndex, destructive: notice.destructiveIndexes,")
        if not before and not baseline:
            host = host.replace("// SCENARIO", '''
        AppData.preferences.set("fixture:Games", forKey: CloudLibraryPreference.storageKey)
        AppData.preferences.set(true, forKey: CloudLibraryPreference.enabledKey)
        switch ProcessInfo.processInfo.environment["OORT_CLOUD_PROBE_CASE"] {
        case "play": try await checkPlayDuringTransfer(in: data, output: output); return
        case "sources": try await checkSourceOnly(in: data, output: output); return
        case "results": try await checkCloudResults(in: data, output: output); return
        default: break
        }
''')
            host = host.replace("// SCOPED_FIXTURE", '''
        model.installScreenArchives(RcloneStorageBackend(remote: "fixture", root: "Games") { _, _, _ in
            .init(status: 1, stdout: "", stderr: "connection reset")
        })
''')
            host += SOURCE_ONLY
            source_catalog = package / "Sources/ArcanePorting/Catalog/CatalogRepository+Porting.swift"
            change(source_catalog, r'(        return try transactionIfChanged \{ draft in\n            try Task\.checkCancellation\(\))',
                   lambda match: '        precondition(!Thread.isMainThread, "Cloud import catalog disk work ran on the UI thread")\n'
                                 + match[1])
            with section.open("a") as swift:
                swift.write("\nextension SettingsCloudLibrarySection {\n"
                            "    func requestSourceConfirmationForProbe() { confirmSourcesFolder() }\n"
                            "    var referenceStatusForProbe: String { referenceStatus }\n}\n")
            build = app / "ViewModels/PortingModel+Build.swift"
            change(build, r'        if requiresKeys \{\n', '''        let syntheticEngine = ProcessInfo.processInfo.environment["OORT_CLOUD_PROBE_CASE"] == "sources"
        if requiresKeys && !syntheticEngine {
''')
            change(build, r'        \} else if !app\.setup\.engineSourceCapabilities\.extractedFolders \{',
                   '        } else if !requiresKeys && !app.setup.engineSourceCapabilities.extractedFolders {')
            change(build, r'        let report = try\? checker\.check\(expectedEngineCommit: app\.setup\.activeEngineCommit\)',
                   '        let report = syntheticEngine ? nil : try? checker.check(expectedEngineCommit: app.setup.activeEngineCommit)')
            change(build, r'        if report\?\.ok != true && !app\.setup\.allowUntestedToolchain \{',
                   '        if !syntheticEngine && report?.ok != true && !app.setup.allowUntestedToolchain {')
            change(build, r'        NotificationService\.shared\.requestAuthorization\(\)',
                   '        if !syntheticEngine { NotificationService.shared.requestAuthorization() }')
            with (package / "Sources/ArcanePorting/Setup/NXNativeEnvironment.swift").open("a") as swift:
                swift.write('''
extension EnvironmentStatus {
    public static func screenCloudFixture(_ repo: URL) -> Self {
        .init(repoURL: repo, pythonURL: nil, developerDir: nil, metalVersion: nil, xcodeVersion: nil, tools: [], issues: [])
    }
}
''')
        elif baseline:
            host = re.sub(r'// CLOUD_REVIEW_START.*?// CLOUD_REVIEW_END', '', host, flags=re.S)
            host = host.replace('model.referenceCheck?.name == nil', 'model.referenceCheck?.name == "Arcane-nx"')
            host = host.replace('model.referenceCheck?.failure == .unavailable', 'model.referenceCheck?.failure == .folderMissing')
        if not before and not baseline:
            overlays = (app / "Views/Shell/AppShellView+Overlays.swift").read_text()
            copy = re.search(r': (L10n\.text\("Quitting stops the transfer[^"]+"\))', overlays)
            if copy:
                host = host.replace("// QUIT_COPY", r'''
        for (name, locale) in [("en", AppLocale(language: .english, region: "US")),
                               ("fr", AppLocale(language: .french, region: "FR"))] {
            L10n.setContext(locale)
            try render("quit-uploads-\(name)", output, SeleneConfirmDialog(title: "A cloud transfer is in progress",
                message: QUIT_MESSAGE, confirmTitle: "Quit", cancelTitle: "Stay", focus: .constant(.cancel),
                onCancel: {}, onConfirm: {}).environment(\.nxAppLocale, locale), size: .init(width: 1280, height: 620))
        }
        L10n.setContext(.init(language: .english, region: "US"))
'''.replace("QUIT_MESSAGE", copy[1]))
        host = host.replace("// ACCOUNT_SCOPE", account_fixture)
        if "private var shouldSuggestSources:" in assistant.read_text():
            host = host.replace("// SWITCH_GAMES_SOURCES", r'''
        let savedSources = model.preference.sourcesRootOverride
        let suggestion = CloudDriveFolders.Sources.switchGamesScreenFixture
        for (name, locale) in [("en", AppLocale(language: .english, region: "US")),
                               ("fr", AppLocale(language: .french, region: "FR"))] {
            model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: nil)
            let unset = CloudSetupAssistant(viewModel: vm, model: model, entry: .sources) {}
            try render("assistant-sources-found-" + name, output,
                       unset.screenSources(suggestion).environment(\.nxAppLocale, locale))
            precondition(model.preference.sourcesRootOverride == nil, "Suggesting must not save the path")
            model.chooseSourcesRoot("Games/My sources")
            let kept = CloudSetupAssistant(viewModel: vm, model: model, entry: .sources) {}
            try render("assistant-sources-kept-" + name, output,
                       kept.screenSources(suggestion).environment(\.nxAppLocale, locale))
            precondition(model.preference.sourcesRootOverride == "Games/My sources")
        }
        model.configure(remote: "fixture", root: "Games", enabled: true, sourcesRoot: savedSources)
''')
            with assistant.open("a") as swift:
                swift.write('''
extension CloudSetupAssistant {
    func screenSources(_ suggestion: CloudDriveFolders.Sources) -> Self {
        var view = self
        if shouldSuggestSources {
            precondition(sourcesPath == "Games/GameFiles")
            view._sourcesSuggestion = State(initialValue: suggestion)
        } else {
            precondition(sourcesPath == "Games/My sources")
        }
        return view
    }
}
''')
            with (package / "Sources/ArcanePorting/Library/CloudDriveFolders.swift").open("a") as swift:
                swift.write('''
extension CloudDriveFolders.Sources {
    public static var switchGamesScreenFixture: Self { .init(path: "Games/Switch/Games", games: 1) }
}
''')
        if not before and not baseline:
            host = host.replace("// ENGINE_VERSION", "try await checkEngineVersion(vm, output, settings)")
            host = host.replace("    static func compareDetails", ENGINE_VERSION + "\n    static func compareDetails")
            with (package / "Sources/ArcanePorting/Library/CloudGameSources.swift").open("a") as swift:
                swift.write('''
extension CloudSourcesStatus {
    public static func versionFixture(_ url: URL) -> Self {
        .init(files: [.init(url: url, state: .cloudOnly, localBytes: nil, remoteBytes: 1)],
              state: .cloudOnly, localBytes: 0, remoteBytes: 1)
    }
}
''')
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
        download = "Download cache and rebuild" if unified else "Download the cloud cache"
        cache_order = [download, "Rebuild with this Mac’s cache", "Rebuild without cache", "Cancel"]
        host = (host.replace("CACHE_ORDER", ", ".join(f'"{title}"' for title in (cache_order[::-1] if before else cache_order)))
                .replace("CACHE_FOCUS", "3" if before else "0").replace("CACHE_BACK", "0" if before else "3"))
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
            viewModel: vm, model: model, settings: /* CLOUD_SETTINGS */ SettingsEditor(settings), advanced: .constant(true),
            onEdit: {}, onEditSources: {}, onActions: { _ in })
            .padding(24).frame(width: 1040), size: .init(width: 1280, height: 1440))
''')
            if unified:
                gallery = gallery.replace("// TRANSFER_TERMINAL", '''$0.completedItem = phase == "ready" ? .app : nil
                $0.failedTransferID = phase == "failed" ? queuedRequest.token : nil''')
                cancellable = 'phase == "running"' if "canCancelCloud(" in panel else "live"
                gallery = gallery.replace("// CHECK_TRANSFER_CONTROLS",
                    f'''panel.checkTransferControls(canCancel: {cancellable} || phase == "queued",
                        canRetry: phase == "failed")''')
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
        precondition(controls.contains(.cancel) == canCancel,
                     "phase \(String(describing: state.progress?.phase)), action \(String(describing: state.action)), controls \(controls)")
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
                    if not baseline:
                        transfer = transfer.replace("// AUDIT_QUEUE", "do {\n" + AUDIT_QUEUE + "\n        }")
                call = "try await checkPlayDuringTransfer(in: data, output: output)" if baseline else ""
                host = host.replace("// PLAY_TRANSFER_CHECK", call) + transfer
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
            launch = app / "ViewModels/AppViewModel+Launch.swift"
            change(launch, r'(        guard savesPermitPlay\((game|requested)\) else \{ return( \.refused\(\.savesUnavailable\))? \})',
                   lambda match: f'        if let screenPlay {{ screenPlay({match[2]}); return{match[3] or ""} }}\n{match[1]}')
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
        if browser or panel:
            host = host.replace("// ASSISTANT_CHECK", ("precondition(assistant.browsing == .sources)" if panel
                                else "precondition(assistant.focusedTarget == .primary)") + r'''
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
        (app / "CloudScreenProbe.swift").write_text(cloud_settings_fixture(app, host))
        if "func recoverPendingMove()" in (app / "ViewModels/AppViewModel+CloudLibrary.swift").read_text():
            with assistant.open("a") as swift:
                swift.write('''
extension CloudSetupAssistant {
    func screenPausedMove() -> Self {
        var view = self
        view._issue = State(initialValue: "Move paused. Close this window and choose Retry in Activity.")
        return view
    }
    func screenMoveConflict() -> Self {
        var view = self
        view._moveFailure = State(initialValue: CloudDriveFolders.MoveFailure.sourceNotEmpty.localizedDescription)
        return view
    }
    func screenMoveConfirm(_ plan: CloudDriveFolders.MovePlan) -> Self {
        var view = self
        var newDraft = CloudSetupAssistantDraft()
        newDraft.chooseAccount("fixture")
        newDraft.browse("New Library")
        view._draft = State(initialValue: newDraft)
        view._movePlan = State(initialValue: plan)
        view._confirmingMove = State(initialValue: true)
        return view
    }
}
''')
            with activity.open("a") as swift:
                swift.write('''
extension ActivityCenterView {
    func checkMoveHints(_ id: UUID) {
        precondition(hints(.result(id)).map(\\.label) == ["Retry"])
    }
}
''')
            host = host.replace("// MOVE_RECOVERY", '''
        let archiveKey = "0100000000001000/app/" + String(repeating: "a", count: 64) + ".aar"
        let moveData = Data(#"{"source":"Games","remote":"fixture","games":1,"bytes":1,"binding":{"account":"accountA","sourceID":"gamesID","destinationID":"newID","destination":"New Library"},"entries":[{"file":{"key":{"value":"\#(archiveKey)"},"size":1,"hashes":{"md5":"c4ca4238a0b923820dcc509a6f75849b"}},"dependencies":[]}]}"#.utf8)
        let movePlan = try JSONDecoder().decode(CloudDriveFolders.MovePlan.self, from: moveData)
        let pending = LibraryMoveJournal.Pending(id: UUID(), request: .init(plan: movePlan, destination: "New Library"),
                                                 sourcesRoot: "Games/GameFiles")
        try model.moveJournal.begin(pending)
        model.recoverPendingMove()
        precondition(model.archive == nil && model.pendingMove == pending)
        precondition(!vm.canConfigureCloudLibrary)
        L10n.setContext(.init(language: .french, region: "FR"))
        await vm.restoreActivity()
        precondition(vm.activityResults.entries.first?.id == pending.id)
        vm.clearActivity()
        precondition(vm.activityResults.entries.first?.id == pending.id)
        precondition(ActivityCenterView.rows(vm).contains(.result(pending.id)))
        precondition(!ActivityCenterView.rows(vm).contains(.clearAll))
        activity.checkMoveHints(pending.id)
        for (name, locale) in [("en", AppLocale(language: .english, region: "US")),
                               ("fr", AppLocale(language: .french, region: "FR"))] {
            L10n.setContext(locale)
            vm.recordActivity(pending.id, job: .move(pending.request), name: pending.request.destination,
                              outcome: .failed(CloudDriveFolders.MoveFailure.accountChanged.localizedDescription))
            try render("activity-move-retry-" + name, output, activity.environment(\\.nxAppLocale, locale))
            let paused = CloudSetupAssistant(viewModel: vm, model: model, entry: .library, onClose: {})
            try render("assistant-move-paused-" + name, output, paused.screenPausedMove().environment(\\.nxAppLocale, locale))
            try render("assistant-move-conflict-" + name, output, paused.screenMoveConflict().environment(\\.nxAppLocale, locale))
            try render("assistant-move-confirm-" + name, output, paused.screenMoveConfirm(movePlan).environment(\\.nxAppLocale, locale))
        }
''')
            (app / "CloudScreenProbe.swift").write_text(cloud_settings_fixture(app, host))
        with (app / "ViewModels/AppViewModel+CloudLibrary.swift").open("a") as swift:
            probe = r'''
import CryptoKit

extension AppViewModel {
    @MainActor static func cloudResultsFixture(in root: URL) throws -> AppViewModel {
        let repository = CatalogRepository(store: .init(directory: root))
        let catalog = try repository.load()
        let settings = AppSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        let vm = AppViewModel(settingsStore: settings, catalog: catalog, repository: repository)
        vm.applyCatalog(catalog)
        vm.cloudLibrary.setReferenceFolder("1-arcane-fixture")
        return vm
    }

    @MainActor func checkZeroReadableReferenceTitles(_ output: URL) async throws -> Bool {
        let reference = cloudLibrary.preference.referenceFolder!
        let title = "0100000000004000"
        for sourceFailure in [true, false] {
            let fixture = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
                if sourceFailure {
                    if args[1] == "fixture:" {
                        return .init(status: 0, stdout: #"[{"Name":"GameFiles","Path":"GameFiles","Size":-1,"IsDir":true}]"#, stderr: "")
                    }
                    if args[1] == "fixture:GameFiles" {
                        return .init(status: 1, stdout: "", stderr: "connection reset")
                    }
                }
                if !sourceFailure {
                    if args[1] == "fixture:" {
                        return .init(status: 0, stdout: #"[{"Name":"\#(title)","Path":"\#(title)","Size":-1,"IsDir":true}]"#, stderr: "")
                    }
                    if args[1] == "fixture:\(title)" {
                        return .init(status: 0, stdout: #"[{"Name":"manifests","Path":"manifests","Size":-1,"IsDir":true}]"#, stderr: "")
                    }
                    if args[1] == "fixture:\(title)/manifests" {
                        return .init(status: 0, stdout: #"[{"Name":"bad.json","Path":"bad.json","Size":1,"IsDir":false}]"#, stderr: "")
                    }
                }
                return .init(status: 0, stdout: args.contains("--stat") ? #"{"IsDir":true}"# : "[]", stderr: "")
            }
            cloudLibrary.installScreenArchives(fixture)
            cloudLibrary.installScreenReference(fixture.reference(folderID: reference)!, sourceRoot: "GameFiles")
            let result = await importCloudReference(archive: cloudLibrary.archive!)
            guard !result.added, !result.warnings.isEmpty, cloudLibrary.referenceCheck?.count == 0,
                  cloudLibrary.referenceCheck?.incomplete == true else { return false }
        }
        let settings = AppSettingsStore(fileURL: AppData.supportRoot.appendingPathComponent("reference-settings-fixture.json"))
        let section = SettingsCloudLibrarySection(viewModel: self, model: cloudLibrary, settings: SettingsEditor(settings), advanced: .constant(false),
            onEdit: {}, onEditLibrary: {}, onEditSources: {}, onActions: { _ in })
        try CloudScreenProbe.render("reference-incomplete", output, section
            .environment(\.nxAppLocale, .init(language: .french, region: "FR")).padding(24).frame(width: 1040))
        return section.referenceStatusForProbe == CloudLibraryFailure.incomplete.messageKey
    }

    @MainActor func checkReferenceDetailFailureKeepsLastKnownOffer(_ output: URL) async throws -> Bool {
        let title = "0100000000004000", reference = cloudLibrary.preference.referenceFolder!
        let manifest = try JSONDecoder().decode(CloudGameManifest.self, from: Data(
            #"{"version":1,"title_id":"\#(title)","created_at":0,"artifacts":[{"kind":"app","size":4,"sha256":"fixture","md5":"fixture","unpacked_size":4,"entry_count":1,"inventory_sha256":"fixture","options":{}}]}"#.utf8))
        let repository = catalogRepository, apps = gameAppsFolder
        let catalog = try await Task.detached {
            try repository.importCloudGames([manifest], in: apps, referenceFolder: reference)
        }.value
        applyCatalog(catalog)
        let game = libraryGames.first { $0.titleId == title }!
        let fixture = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            if args.contains("--drive-root-folder-id=\(reference)") {
                return .init(status: 1, stdout: "", stderr: "connection reset")
            }
            return .init(status: 0, stdout: args.contains("--stat") ? #"{"IsDir":true}"# : "[]", stderr: "")
        }
        cloudLibrary.installScreenArchives(fixture)
        cloudLibrary.installScreenReference(fixture.reference(folderID: reference)!)
        cloudLibrary.referenceManifests[title] = manifest
        cloudLibrary.update(game.id) {
            $0.referenceKinds = [.app]
            $0.referenceAvailability[.app] = manifest.cloudOnlyApp
            $0.referenceSourceBytes = 4
        }
        await refreshCloudLibrary(game)
        let state = cloudLibrary.states[game.id]!
        try CloudScreenProbe.render("reference-unverified-offer", output,
            CloudLibraryPanel(viewModel: self, model: cloudLibrary, game: game)
                .environment(\.nxAppLocale, .init(language: .french, region: "FR")))
        return state.referenceKinds == [.app] && state.referenceAvailability[.app]?.state == .cloudOnly
            && state.referenceSourceBytes == 4 && state.referenceUnverified && state.referenceSourcesUnverified
    }

    @MainActor func checkRebuildQueuesPricedReference() async throws -> Bool {
        let title = "0100000000004000", folder = "Orbit [0100000000004000]"
        let reference = cloudLibrary.preference.referenceFolder!
        func selection(_ filename: String, bytes: Int64) -> CloudGameSources.ArchivedSelection {
            let item = GameFileItem(url: URL(fileURLWithPath: "/fixture/\(filename)"), kind: .base,
                                    titleId: title, sizeBytes: bytes)
            return .init(folder: folder, files: [item], titleID: title)!
        }
        func manifest(_ filename: String, bytes: Int64, date: String) throws -> Data {
            let encoded = try JSONEncoder().encode(selection(filename, bytes: bytes))
            return Data(#"{"version":2,"title_id":"\#(title)","created_at":"\#(date)","artifacts":[],"game_name":"Orbit","source_selection":\#(String(decoding: encoded, as: UTF8.self))}"#.utf8)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let personal = try decoder.decode(CloudGameManifest.self,
            from: manifest("Personal.nsp", bytes: 4, date: "2026-01-01T00:00:00Z"))
        let repository = catalogRepository, apps = gameAppsFolder
        let catalog = try await Task.detached { try repository.importCloudGames([personal], in: apps) }.value
        applyCatalog(catalog)
        let game = libraryGames.first { $0.titleId == title }!
        func payload(_ file: String, day: Int) throws -> (name: String, data: Data) {
            let data = try manifest(file, bytes: 7, date: "2026-01-0\(day)T00:00:00Z")
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return ("000000000000000\(day)-\(sha).json", data)
        }
        let quoted = try payload("Shared.nsp", day: 2), changed = try payload("Changed.nsp", day: 3)
        actor Revision {
            var isChanged = false
            var readChangedManifest = false
            var changedSelectionReads = 0
            func advance() { isChanged = true }
            func readManifest() { readChangedManifest = isChanged }
            func readSelection() { if isChanged { changedSelectionReads += 1 } }
        }
        let revision = Revision()
        let fixture = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            let (name, data) = await revision.isChanged ? changed : quoted
            let isReference = args.contains("--drive-root-folder-id=\(reference)")
            switch (args[0], args[1]) {
            case ("lsjson", "fixture:") where isReference:
                return .init(status: 0, stdout: #"[{"Name":"\#(folder)","Path":"\#(folder)","Size":-1,"IsDir":true}]"#, stderr: "")
            case ("lsjson", "fixture:\(folder)") where isReference:
                return .init(status: 0, stdout: #"[{"Name":"manifests","Path":"manifests","Size":-1,"IsDir":true}]"#, stderr: "")
            case ("lsjson", "fixture:\(folder)/manifests") where isReference:
                return .init(status: 0, stdout: #"[{"Name":"\#(name)","Path":"\#(name)","Size":\#(data.count),"IsDir":false}]"#, stderr: "")
            case ("lsjson", "fixture:\(folder)/manifests/\(name)") where isReference:
                return .init(status: 0, stdout: #"{"Name":"\#(name)","Path":"\#(name)","Size":\#(data.count),"IsDir":false}"#, stderr: "")
            case ("copyto", "fixture:\(folder)/manifests/\(name)") where isReference:
                await revision.readManifest()
                try data.write(to: URL(fileURLWithPath: args[2]))
                return .init(status: 0, stdout: "", stderr: "")
            case ("lsjson", "fixture:GameFiles/\(folder)") where isReference:
                await revision.readSelection()
                return .init(status: 0, stdout: #"[{"Name":"Shared.nsp","Path":"Shared.nsp","Size":7,"IsDir":false,"Hashes":{"md5":"b4a1b45d938819f647fcbacc3fce7a4d"}}]"#, stderr: "")
            case ("lsjson", "fixture:Games"):
                return .init(status: 0, stdout: args.contains("--stat") ? #"{"IsDir":true}"# : "[]", stderr: "")
            default: throw StorageBackendError.invalidConfiguration
            }
        }
        cloudLibrary.installScreenArchives(fixture)
        cloudLibrary.installScreenSources(fixture, root: "Games/GameFiles")
        cloudLibrary.installScreenReference(fixture.reference(folderID: reference)!, sourceRoot: "GameFiles")
        cloudLibrary.hasRestoredQueue = true
        cloudLibrary.queuePause = .offline
        try await confirmCloudSourcesDownload(for: game, archive: cloudLibrary.archive!, extraArguments: [],
            onStarted: nil, withoutCache: false, afterSourcesDownloaded: nil, request: nil)
        precondition(cloudLibrary.states[game.id]?.referenceSourceBytes == nil)
        settingsNotice?.runAnswer(.retry)
        guard let queued = cloudLibrary.queue.first, queued.sourceReference == reference,
              queued.rebuildSources?.referenceSelection == selection("Shared.nsp", bytes: 7),
              queued.rebuildSources?.bytes == 7 else {
            print("Rebuild fixture: the quoted selection did not reach the in-memory queue")
            return false
        }
        await cloudLibrary.queueStore.flush()
        let persisted = await cloudLibrary.queueStore.load()
        guard persisted.first?.rebuildSources == queued.rebuildSources else {
            print("Rebuild fixture: the quote was not saved while the queue was paused")
            return false
        }
        await revision.advance()
        cloudLibrary.queuePause = nil
        startNextCloudOperation()
        guard let transfer = cloudLibrary.active?.task else {
            print("Rebuild fixture: the queued transfer did not start after resume")
            return false
        }
        await transfer.value
        let readManifest = await revision.readChangedManifest
        let sourceReads = await revision.changedSelectionReads
        let failed = cloudLibrary.states[game.id]?.issue?.failed == true
        if !readManifest || sourceReads != 0 || !failed {
            print("Rebuild fixture: revised manifest=\(readManifest), source listings=\(sourceReads), refused=\(failed)")
        }
        return readManifest && sourceReads == 0 && failed
    }

    @MainActor func checkManifestOnlyReferenceSelection() async throws {
        let title = "0100000000004000", folder = "Orbit [0100000000004000]"
        let referenceFolder = cloudLibrary.preference.referenceFolder!
        let fixture = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            precondition(args[0] == "lsjson" && args[1] == "fixture:GameFiles/" + folder)
            precondition(args.contains("--drive-root-folder-id=\(referenceFolder)"))
            return .init(status: 0, stdout: #"[{"Path":"Orbit.nsp","Name":"Orbit.nsp","Size":7,"IsDir":false,"Hashes":{"md5":"b4a1b45d938819f647fcbacc3fce7a4d"}}]"#, stderr: "")
        }
        cloudLibrary.installScreenReference(fixture.reference(folderID: referenceFolder)!, sourceRoot: "GameFiles")
        let id = UUID(), root = CloudGameSources.importedFolder(for: id)
        let source = GameFileItem(url: root.appendingPathComponent(folder).appendingPathComponent("Orbit.nsp"),
                                  kind: .base, titleId: title, sizeBytes: 7)
        let selection = CloudGameSources.ArchivedSelection(folder: folder, files: [source], titleID: title)!
        let data = try JSONEncoder().encode(selection)
        let manifest = try JSONDecoder().decode(CloudGameManifest.self, from:
            Data(#"{"version":2,"title_id":"\#(title)","created_at":0,"artifacts":[],"source_selection":\#(String(decoding: data, as: UTF8.self))}"#.utf8))
        var game = PortedGame(id: id, name: "Orbit", url: root, platform: .macApp, sizeBytes: 0,
                              modificationDate: .now, titleId: title)
        game.status = .notBuilt
        game.cloudImportPending = true
        game.sources = [source]
        let remote = try await referenceSourceStatus(for: game, reference: manifest, own: nil)
        precondition(remote?.bytes == 7 && remote?.urls == [source.url],
                     "The placeholder's own source folder is not an app or an overlapping destination")
    }

    @MainActor func checkPartialCloudReview(_ game: PortedGame) {
        cloudLibrary.remember { $0.personalApps.insert(game.id) }
        recordCloudListing(.init(invalidTitles: [game.titleId!], unlistedSources: true),
                           catalog: catalogSnapshot, statuses: [:], reference: false)
        precondition(cloudLibrary.lastKnown.personalApps.contains(game.id), "An incomplete manifest must keep the earlier presence")
        cloudLibrary.remember { $0.personalApps.remove(game.id) }
    }

    @MainActor func checkReferenceScreen(access: Bool) async throws {
        let folder = cloudLibrary.preference.referenceFolder!
        let backend = RcloneStorageBackend(remote: "fixture", root: "Games") { _, args, _ in
            precondition(args.contains("--drive-root-folder-id=\(folder)") && args[0] == "lsjson")
            precondition(args.contains("--drive-shared-with-me=false") && args.contains("--drive-skip-shortcuts"))
            if !access { return .init(status: 1, stdout: "", stderr: "googleapi: Error 403: forbidden") }
            let output = args.contains("--stat") ? #"{"IsDir":true}"# : "[]"
            return .init(status: 0, stdout: output, stderr: "")
        }
        let reference = backend.reference(folderID: folder)!
        if cloudLibrary.archive == nil { cloudLibrary.installScreenArchives(backend) }
        cloudLibrary.installScreenReference(reference)
        _ = await importCloudReference(archive: cloudLibrary.archive!)
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
        scopeTask?.cancel()
        backend = fixture
        archive = CloudGameArchive(backend: fixture)
        sourceArchive = nil
        referenceArchive = nil
    }
    func installScreenReference(_ reference: RcloneStorageBackend, sourceRoot: String? = nil) {
        referenceBackend = reference
        referenceArchive = CloudGameArchive(backend: reference)
        if let sourceRoot { referenceSourceArchive = CloudGameSources(backend: reference, root: sourceRoot, usesDefaultRoot: true) }
    }
}
'''
            if before:
                probe = re.sub(r'    @MainActor func checkManifestOnlyReferenceSelection.*?(?=    @MainActor func screenRebuildNotice)',
                               '', probe, flags=re.S).split('extension CloudLibraryModel')[0]
            elif baseline:
                probe = re.sub(r'    @MainActor func checkManifestOnlyReferenceSelection.*?(?=    @MainActor func checkReferenceScreen)',
                               '', probe, flags=re.S)
                probe = probe.replace('        scopeTask?.cancel()\n', '')
                probe = probe.replace('args.contains("--drive-root-folder-id=\\(folder)")', 'args.contains("--drive-root-folder-id")')
                probe = probe.replace('            precondition(args.contains("--drive-shared-with-me=false") && args.contains("--drive-skip-shortcuts"))\n', '')
                probe = probe.replace('            let output = args.contains("--stat") ? #"{"IsDir":true}"# : "[]"',
                                      '            let name = #"{"Name":"Arcane-nx","ID":"1-arcane-fixture","IsDir":true}"#\n'
                                      '            let output = args.contains("--drive-shared-with-me") ? "[\\(name)]" : args.contains("--stat") ? name : "[]"')
            swift.write(probe)
        if not before and not baseline:
            with (app / "CloudScreenProbe.swift").open("a") as swift:
                swift.write(r'''
extension CloudScreenProbe {
    @MainActor static func checkCloudResults(in root: URL, output: URL) async throws {
        var failures: [String] = []
        let empty = try AppViewModel.cloudResultsFixture(in: root.appendingPathComponent("empty-reference"))
        if try await !empty.checkZeroReadableReferenceTitles(output) { failures.append("Zero readable reference titles must be incomplete") }
        let detail = try AppViewModel.cloudResultsFixture(in: root.appendingPathComponent("reference-detail"))
        if try await !detail.checkReferenceDetailFailureKeepsLastKnownOffer(output) { failures.append("Reference read failure must keep the last offer") }
        let rebuild = try AppViewModel.cloudResultsFixture(in: root.appendingPathComponent("reference-rebuild"))
        if try await !rebuild.checkRebuildQueuesPricedReference() { failures.append("Rebuild must queue the reference it priced") }
        guard failures.isEmpty else {
            FileHandle.standardError.write(Data((failures.map { "FAIL: " + $0 }.joined(separator: "\n") + "\n").utf8))
            throw CocoaError(.fileReadUnknown, userInfo: [NSDebugDescriptionErrorKey: failures.joined(separator: "; ")])
        }
        print("Incomplete reference, last-known detail and Rebuild source scope verified.")
    }
}
''')
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
        scenarios = ("results",) if "--results-only" in sys.argv[2:] else \
            ("screens",) if before or baseline else ("results", "screens", "play", "sources")
        for index, scenario in enumerate(scenarios):
            home = package / f"probe-home-{scenario}"
            home.mkdir()
            command = ["swift", "run", "--jobs", "4", "--package-path", str(package)]
            if index:
                command += ["--skip-build"]
            command += ["NXLibrary", str(output), str(font), str(icon)]
            if compare and scenario == "screens":
                command.append(str(pixel_reference))
            subprocess.run(command, check=True, env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                                                         OORT_CLOUD_PROBE_CASE=scenario,
                                                         OORT_CLOUD_PROBE_PYTHON=str(Path(sys.executable).resolve())))


if __name__ == "__main__":
    main()
