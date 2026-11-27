#if DEBUG
import AppKit
import CoreText
import SwiftUI
import OortLibrary

enum OortFilePickerProbe {
    @MainActor static func capture(to output: URL) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let font = URL(fileURLWithPath: "design/Selene/Fonts/MaterialIcons-Regular.ttf")
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        let locale = AppLocale(language: .french, region: "FR")
        L10n.setContext(locale)
        let fm = FileManager.default
        guard let home = AppData.integrationFixtureHome else { throw CocoaError(.fileReadNoSuchFile) }
        let games = home.appendingPathComponent("Games", isDirectory: true)
        let inbox = games.appendingPathComponent("Inbox", isDirectory: true)
        for folder in [inbox.appendingPathComponent("Archives", isDirectory: true),
                       inbox.appendingPathComponent("Mises à jour", isDirectory: true),
                       home.appendingPathComponent("Desktop", isDirectory: true),
                       home.appendingPathComponent("Downloads", isDirectory: true),
                       home.appendingPathComponent("Documents", isDirectory: true)] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for (name, size) in [("Course cosmique.xci", 1_400_000), ("Jardin lunaire.nsp", 625_000),
                             ("Station Aurore.nup", 980_000), ("Notes.txt", 38)] {
            fm.createFile(atPath: inbox.appendingPathComponent(name).path, contents: Data(count: size))
        }
        let model = OortFilePickerModel(home: home, choice: .gameFiles(allowFolder: false), start: inbox, recent: [games])
        let load = Task { await model.read(inbox, includeMountedDisks: false) }
        defer { load.cancel() }
        let deadline = Date().addingTimeInterval(5)
        while !model.ready, model.problem == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(model.ready && model.visible.map(\.name) ==
                     ["Archives", "Mises à jour", "Course cosmique.xci", "Jardin lunaire.nsp", "Station Aurore.nup"])
        model.input(.navigateDown)
        model.input(.navigateDown)
        precondition(model.visible[model.index].name == "Course cosmique.xci")
        precondition(model.canPickSeveral && model.backLabel == "Up one folder")
        let top = OortFilePickerModel(home: home, choice: .images, start: home)
        precondition(top.backLabel == "Close" && !top.canPickSeveral)
        top.input(.search)
        precondition(top.backLabel == "Back")

        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, size) in [("grand", CGSize(width: 1440, height: 900)), ("etroit", CGSize(width: 900, height: 660))] {
            let sheet = CGSize(width: min(1020, size.width * 0.94), height: min(670, size.height * 0.88))
            let host = NSHostingView(rootView: ZStack(alignment: .top) {
                // Synthetic bright wallpaper: never load the player's wallpaper or profile.
                OortGalleryWallpaper()
                SeleneTheme.scrim45
                OortFilePicker(model: model, title: L10n.text("Game files"),
                               message: L10n.text("Choose NSP, XCI, NSZ or XCZ files, or one Switch 2 NUP file."),
                               choose: { _ in }, finder: {}, cancel: {})
                    .frame(width: sheet.width, height: sheet.height)
                    .environment(\.seleneCanvas, SeleneCanvas(size: sheet))
                    .clipShape(RoundedRectangle(cornerRadius: SeleneTokens.Radius.card))
                    .padding(.top, SeleneTokens.Space.section)
            }.frame(width: size.width, height: size.height)
                .environment(\.nxAppLocale, locale)
                .environment(\.seleneReduceMotion, true)
                .environment(\.colorScheme, .dark))
            try IntegrationFixtureView.captureWindow(host, size: size,
                to: output.appendingPathComponent("fichiers-fr-\(name).png"))
        }
    }
}
#endif
