#!/usr/bin/env python3
"""Render the real Inbox content and Selene confirmation offscreen, using fake packages."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

HOST = r'''
import AppKit
import ArcanePorting
import CoreText
import NXLibraryCore
import SwiftUI

@main struct InboxProbe {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, .process, nil))
        let locale = AppLocale(language: .french, region: "FR")
        L10n.setContext(locale)
        let support = AppData.supportRoot
        let settings = AppSettingsStore(fileURL: support.appendingPathComponent("settings.json"))
        let app = AppViewModel(settingsStore: settings,
                               catalog: .init(), repository: .init(store: .init(directory: support)))
        let model = app.gameInbox
        let router = AppRouter(settings: settings)
        router.openGameInbox()
        router.pressMenuIcon(.library)
        precondition(router.route == .gameInbox && router.menuSelection.entries.contains(.gameInbox))
        let view = GameInboxView(model: model, router: router)
        let root = GameInboxModel.gamesRoot
        app.showSetupCheck = true
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let rejected = support.appendingPathComponent("rejected.keys")
        try "# Empty key file".write(to: rejected, atomically: true, encoding: .utf8)
        app.setup.importKeys(from: rejected)
        let setup = app.setupCheck
        setup.apply(SetupFacts(xcodeStatus: nil, metalVersion: nil, certifiedMetal: "1", allowUntested: false,
                               engine: .missing, engineFolder: support, pinnedCommit: app.pinnedEngineCommit,
                               runtimeProblem: nil, keys: nil, keysError: nil, libraryReadable: nil))
        precondition(setup.items.first { $0.id == .keys }?.inlineError == "Le fichier de clés ne contient pas de header_key.")
        precondition(app.settingsNotice == nil && !FileManager.default.fileExists(atPath: app.setup.keyStore.keyURL.path))
        try render("06-rejected-keys", page: SetupCheckView(viewModel: app, isFirstRun: true), to: output, locale: locale,
                   showsHints: false)
        app.showSetupCheck = false
        try render("01-empty", page: view.page, to: output, locale: locale)
        AppData.preferences.set(root.path, forKey: PortingModel.savedGameFolderKey)
        try FileManager.default.createDirectory(at: model.folder, withIntermediateDirectories: true)
        let title: UInt64 = 0x0100000000004000
        let files = try ["lunar-base.nsp", "lunar-update.nsz", "lunar-expansion.xci"].map { name in
            let url = model.folder.appendingPathComponent(name)
            try Data([1, 2, 3]).write(to: url)
            return url
        }
        model.refresh()
        let deadline = ContinuousClock.now + .seconds(5)
        while model.busy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.entries.count == files.count && model.entries.allSatisfy {
            $0.needsKeys && $0.destination == nil && $0.issue == "Clés manquantes : importez-les pour identifier ce fichier"
        })
        try render("07-inbox-missing-keys", page: view.page, to: output, locale: locale)
        let inputs = GameInbox.inputs(files)
        let metadata: [URL: PackageReading] = [
            files[0]: .contents([.init(kind: .base, titleId: title, version: 0)]),
            files[1]: .contents([.init(kind: .update, titleId: title + 0x800, version: 65536)]),
            files[2]: .contents([.init(kind: .dlc, titleId: title + 0x1001, version: 1)])
        ]
        func plan(_ readings: [URL: PackageReading]) -> [GameInbox.Entry] {
            GameInbox.plan(inputs: inputs, readings: readings, root: root) {
                $0 == title ? "Lunar Observatory" : "Far Side Expansion"
            }
        }
        model.entries = plan(metadata)
        precondition(model.entries.allSatisfy { $0.destination != nil })
        try render("02-three-files", page: view.page, to: output, locale: locale)
        model.entries = plan(metadata.filter { $0.key != files[2] })
        precondition(model.entries.filter { $0.issue != nil }.count == 1)
        model.confirm(model.entries.filter { $0.destination != nil })
        let notice = app.settingsNotice!
        precondition(notice.choices.count == 2 && notice.cancelIndex == 1 && notice.initialFocus == 0)
        try render("03-ambiguous", page: view.page, to: output, locale: locale)
        try render("04-confirmation", page: ZStack {
            view.page.blur(radius: 20)
            Color.black.opacity(0.55)
            SeleneChoiceDialog(title: notice.title, message: notice.message, choices: notice.choices,
                focus: .constant(notice.initialFocus), cancelIndex: notice.cancelIndex) { _ in }
        }, to: output, locale: locale)
        let artwork = ArtworkStore()
        let spotlight = SpotlightView(viewModel: app, router: router, settings: settings,
                                      playSessions: PlaySessionStore(), runningGames: RunningGameMonitor(),
                                      artwork: artwork, storeHost: ModStoreHost())
        let readMarker = model.folder.appendingPathComponent(".probe-read")
        precondition(FileManager.default.fileExists(atPath: readMarker.path))
        try FileManager.default.removeItem(at: readMarker)
        let card = SpotlightItem.card(.inbox)
        router.openSettings(.library)
        settings.settings.gameInboxEnabled = false
        let coldRouter = AppRouter(settings: settings)
        coldRouter.navigate(to: .gameInbox)
        coldRouter.setInitialRoute(.gameInbox)
        precondition(coldRouter.route == .library)
        await model.updateAvailability()
        model.refresh()
        precondition(!model.busy && !FileManager.default.fileExists(atPath: readMarker.path))
        precondition(!router.menuSelection.entries.contains(.gameInbox))
        router.openGameInbox()
        precondition(router.route == .settings(.library))
        router.back()
        precondition(router.route == .library, "Back must not reopen the disabled Inbox")
        try render("06-settings-inbox-off", page: folders(app, settings), to: output, locale: locale)
        SoundEffectService.shared.isSoundEnabled = false
        router.openSettings(.library)
        SettingsView(initialSection: .library, viewModel: app, settings: settings, router: router, artwork: artwork)
            .pressInboxFixtureReset()
        precondition(settings.settings.gameInboxEnabled)
        precondition(app.porting.gameFilesFolder?.path == root.path)
        await model.updateAvailability()
        precondition(FileManager.default.fileExists(atPath: readMarker.path), "Positive control for the read marker")
        precondition(spotlight.items.contains(card) && router.menuSelection.entries.contains(.gameInbox))
        try render("07-settings-inbox-on", page: folders(app, settings), to: output, locale: locale)
        try render("05-spotlight-card", page: VStack(alignment: .leading, spacing: 24) {
            SpotlightRowView(items: [card, .card(.addGame)], gamesByID: [:], selectedKey: card.key,
                isEmptyFilter: nil, artwork: artwork, cloud: app.cloudLibrary, showsCloudBadges: false,
                onSelect: { _ in }, onActivate: { _ in })
                .frame(height: 190)
            SpotlightCardInfoView(card: .inbox, gameCount: 0, installedCount: 0, poolLabel: "",
                activity: ActivitySummary(), topGames: [], focusedTop: nil, artwork: artwork, onTopGame: { _ in })
                .padding(.leading, 58)
        }.padding(.top, 90), to: output, locale: locale)
        settings.settings.gameInboxEnabled = false
        precondition(model.hasWaitingFiles && !spotlight.items.contains(card), "Stale availability must not show the card")
        try render("08-spotlight-inbox-off", page:
            SpotlightRowView(items: spotlight.items, gamesByID: [:], selectedKey: spotlight.items.first?.key,
                isEmptyFilter: nil, artwork: artwork, cloud: app.cloudLibrary, showsCloudBadges: false,
                onSelect: { _ in }, onActivate: { _ in })
                .frame(height: 190)
                .padding(.top, 90), to: output, locale: locale)
        router.pressMenuIcon(.library)
        if !router.menuSelection.isEntryOpen { router.openEntryMenu() }
        try render("09-library-menu-inbox-off", page:
            MenuOverlayView(router: router, cloudLibrary: app.cloudLibrary, hasBuildActivity: false,
                onSelect: { _ in }, onSelectPower: { _ in }, onTab: { _ in }), to: output, locale: locale)
        print("Inbox: route, menu, Spotlight, disabled reads and settings verified offscreen.")
    }

    @MainActor static func folders(_ app: AppViewModel, _ settings: AppSettingsStore) -> some View {
        VStack(alignment: .leading) {
            Text(SettingsSection.library.place)
                .seleneFont(.inboxTitle, .semibold)
                .foregroundStyle(SeleneTheme.ink)
            SettingsLibrarySection(viewModel: app, porting: app.porting, settings: settings, onActions: { _ in })
        }
        .frame(width: 820)
        .padding(.top, 38)
    }

    @MainActor static func render(_ name: String, page: some View, to output: URL, locale: AppLocale,
                                  showsHints: Bool = true) throws {
        let size = CGSize(width: 1344, height: 756)
        let canvas = SeleneCanvas(size: size)
        let scene = ZStack(alignment: .top) {
            Rectangle().fill(SeleneTheme.baseGradient)
            page
            SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"))],
                           right: [HintItem(.a, L10n.text("Select"))])
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(showsHints && ["01-empty", "02-three-files", "03-ambiguous"].contains(name) ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.seleneCanvas, canvas)
        .environment(\.nxAppLocale, locale)
        .environment(\.seleneReduceMotion, true)
        let renderer = ImageRenderer(content: scene)
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }
}
'''


def change(path, previous, replacement):
    text = path.read_text()
    assert text.count(previous) == 1, (path, previous)
    path.write_text(text.replace(previous, replacement))


def main():
    with tempfile.TemporaryDirectory(prefix="inbox-probe-") as temp:
        package = Path(temp).resolve()
        home = package / "Player"
        home.mkdir()
        output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "work/screens-inbox"
        output.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "Package.swift", package / "Package.swift")
        shutil.copytree(ROOT / "Sources", package / "Sources")
        for target in ("NXLibraryCoreTests", "ArcanePortingTests"):
            stub = package / "Tests" / target / "Empty.swift"
            stub.parent.mkdir(parents=True)
            stub.touch()
        app = package / "Sources/NXLibrary"
        change(app / "NXLibraryApp.swift", "@main\nstruct", "struct")
        model = app / "ViewModels/AppViewModel.swift"
        change(model, "SteamGridDBKey().load() != nil", "false")
        # Omit startup scans, key access and the bundle-only notification service.
        text = model.read_text()
        first = text.index("        applyCatalog(catalog)")
        last = text.index("    }\n\n    // MARK: - Dynamic", first)
        model.write_text(text[:first] + text[last:])
        change(app / "ViewModels/GameInboxModel.swift", "private(set) var entries:", "var entries:")
        change(app / "ViewModels/SetupCheckModel.swift", "private func apply(", "func apply(")
        setup = app / "Views/Setup/SetupCheckView.swift"
        # The fixture already applied deterministic facts; do not probe real tools or animate in.
        change(setup, """        .onAppear {
            model.startRechecking()
            withAnimation(nil) { risen = false }
            DispatchQueue.main.async { risen = true }
        }
        .onDisappear {
            model.stopRechecking()
            model.rememberStates()
        }
""", "")
        change(setup, "@State private var risen = false", "@State private var risen = true")
        change(setup, "@State var focus: SetupFocus = .carryOn", "@State var focus: SetupFocus = .card(4)")
        # ImageRenderer needs a still SwiftUI image rather than the hosted Metal view.
        change(app / "Views/Theme/SeleneBackdrop.swift", "tint: modsTint ? 1 : 0, moving: moving,\n",
               "tint: modsTint ? 1 : 0, moving: false, asImage: true,\n")
        change(app / "Views/Theme/MoonlightRenderer.swift", "                if let image {\n",
               "                if let image = engine.snapshot(width: max(w, 1), height: max(h, 1), colors: colors) {\n")
        change(app / "Views/Shell/MenuOverlayView.swift", "var presented = false", "var presented = true")
        with (app / "Views/Settings/SettingsView.swift").open("a") as swift:
            swift.write("\nextension SettingsView {\n    func pressInboxFixtureReset() { handleGamepad(.secondaryAction) }\n}\n")
        # Observe the actual directory reader in the copied target, not just the resulting availability.
        change(package / "Sources/ArcanePorting/Library/GameInbox.swift",
               "    public static func files(in folder: URL) throws -> [URL] {\n",
               "    public static func files(in folder: URL) throws -> [URL] {\n"
               '        if folder.lastPathComponent == "Inbox" {\n'
               '            try Data().write(to: folder.appendingPathComponent(".probe-read"))\n'
               "        }\n")
        # SwiftUI's AppKit-backed drop wrapper produces a placeholder in ImageRenderer.
        change(app / "Views/Porting/GameInboxView.swift",
               "            .dropDestination(for: URL.self) { urls, _ in model.accept(urls) } isTargeted: { dropTarget = $0 }\n",
               "")
        profile = package / "Sources/NXLibraryCore/App/AppDataProfile.swift"
        change(profile, 'AppDataProfile(isDevelopment: Bundle.main.object(forInfoDictionaryKey: "NXLibraryDevelopmentProfile") as? Bool == true)',
               f'AppDataProfile(home: URL(fileURLWithPath: {json.dumps(str(home))}), isDevelopment: true)')
        change(profile, "public static var preferences: UserDefaults { configuredPreferences() }",
               'public static let preferences = UserDefaults(suiteName: profile.home.appendingPathComponent("test-preferences").path)!')
        (app / "InboxProbe.swift").write_text(HOST)
        font = ROOT / "Resources/Selene/Fonts/MaterialIcons-Regular.ttf"
        subprocess.run(["swift", "run", "--package-path", str(package), "NXLibrary", str(output), str(font)],
                       env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)), check=True)


if __name__ == "__main__":
    main()
