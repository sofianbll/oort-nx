#!/usr/bin/env python3
"""Exercise the app's removal actions with a real catalog and an isolated Trash double."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

HOST = r'''
import Foundation
import AppKit
import SwiftUI
import NXLibraryCore
import ArcanePorting

@main struct RemovalProbe {
    @MainActor static func main() throws {
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
                    let saved = try repo.load().nxnativeGames.first
                    check(removal == "game" ? saved == nil : saved?.sources.isEmpty == true,
                          "Trash ran before publication (\(removal), \(fault))")
                }
                if removal == "game" { model.deletePortedGame(game) } else { model.removeSources(for: game) }
                let stored = try repo.load()
                let traces = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("catalog-removal-") }
                let mustRecover = fault == "rollback catalog"
                if mustRecover {
                    check(traces.count == 1, "Failed rollback must retain one recovery record")
                    if let trace = traces.first {
                        let data = try Data(contentsOf: trace)
                        let record = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        check(record?["game"] != nil && (record?["trashed"] as? [Any])?.count == 1,
                              "Recovery record must include the game and the Trash location")
                        check(model.alertMessage?.contains(trace.lastPathComponent) == true,
                              "The error must show where to recover: \(model.alertMessage ?? "none")")
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

DOUBLE = r'''
import Foundation

package enum RemovalFixture {
    package static var failPublication = false
    package static var failTrash = 0
    package static var failRollback = false
    package static var calls = 0
    package static var beforeTrash: (() throws -> Void)?
    package static func reset() { failPublication = false; failTrash = 0; failRollback = false; calls = 0; beforeTrash = nil }
    package static func trashItem(at url: URL, resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        calls += 1
        try beforeTrash?()
        if calls == failTrash {
            failPublication = failRollback
            throw CocoaError(.fileWriteNoPermission)
        }
        let trash = url.deletingLastPathComponent().appendingPathComponent("Fixture Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = trash.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        resultingItemURL?.pointee = destination as NSURL
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
            f'public static let profile = AppDataProfile(home: URL(fileURLWithPath: "{temp}"), isDevelopment: true)')
    replace(core / "App/AppDataProfile.swift", r"public static var preferences: UserDefaults \{ \.standard \}",
            f'public static let preferences = UserDefaults(suiteName: "local.arcane.{package.name}")!')
    replace(core / "Catalog/CatalogStore.swift", r"try publication\.publish\(candidate,",
            "if RemovalFixture.failPublication { throw CocoaError(.fileWriteNoPermission) }\n        try publication.publish(candidate,")
    hooks = [app / "ViewModels/AppViewModel+GameFiles.swift", *list((core / "Catalog").glob("*.swift"))]
    substitutions = 0
    for file in hooks:
        text, count = re.subn(r"(?:FileManager\.default|fm)\.trashItem\(", "RemovalFixture.trashItem(", file.read_text())
        if count:
            file.write_text(text)
            substitutions += count
    assert substitutions > 0
    (core / "RemovalFixture.swift").write_text(DOUBLE)
    (app / "RemovalProbe.swift").write_text(HOST)
    args = sys.argv[1:2]
    if args:
        Path(args[0]).mkdir(parents=True, exist_ok=True)
        args = [str(Path(args[0]).resolve())]
    subprocess.run(["swift", "run", "-j", "6", "--package-path", str(package), "NXLibrary", *args], check=True,
                   env=dict(os.environ, HOME=temp, CFFIXED_USER_HOME=temp))
