#if DEBUG
import AppKit
import SwiftUI
import NXLibraryCore

struct OortUIGallery: View {
    enum Sheet: String, CaseIterable { case rows, states, dialogs, page }

    private static let palettes = ["oort", "catppuccin-latte", "vantablack"]
    @State private var palette = SelenePaletteCatalog.defaultID
    @State private var french = true
    @State private var sheet = Sheet.rows

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Palette", selection: $palette) {
                    ForEach(Self.palettes, id: \.self) { Text($0) }
                }
                Toggle("FR / DE", isOn: $french)
                Picker("Specimens", selection: $sheet) {
                    ForEach(Sheet.allCases, id: \.self) { Text($0.rawValue) }
                }
            }
            .padding()
            specimen(sheet: sheet, locale: Self.locale(french))
                .seleneCanvasRoot()
        }
        .onChange(of: palette, initial: true) { ThemeStore.shared.apply(id: palette) }
        .onChange(of: french, initial: true) { L10n.setContext(Self.locale(french)) }
    }

    private static func locale(_ french: Bool) -> AppLocale {
        french ? .init(language: .french, region: "FR") : .init(language: .german, region: "DE")
    }

    private func specimen(sheet: Sheet, locale: AppLocale) -> some View {
        GallerySpecimen(sheet: sheet)
            .environment(\.nxAppLocale, locale)
            .environment(\.locale, locale.formatLocale)
            .environment(\.seleneButtonNames, .xbox)
            .environment(\.seleneReduceMotion, true)
            .environment(\.seleneSharesBackdrop, true)
            .background(OortGalleryWallpaper())
    }

    @MainActor static func capture(to output: URL) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        SeleneFonts.register()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let size = CGSize(width: 1440, height: 900)
        for palette in palettes {
            precondition(ThemeStore.shared.palettes.contains { $0.id == palette }, "Missing gallery palette \(palette)")
            ThemeStore.shared.apply(id: palette)
            for french in [true, false] {
                let locale = locale(french)
                L10n.setContext(locale)
                for sheet in Sheet.allCases {
                    let host = NSHostingView(rootView: Self().specimen(sheet: sheet, locale: locale)
                        .frame(width: size.width, height: size.height)
                        .environment(\.seleneCanvas, SeleneCanvas(size: size)))
                    try IntegrationFixtureView.captureWindow(host, size: size, to: output
                        .appendingPathComponent("\(palette)-\(locale.language.rawValue)-\(sheet.rawValue).png"))
                }
            }
        }
    }
}

private struct GallerySpecimen: View {
    @Environment(\.nxAppLocale) private var locale
    @Environment(\.seleneCanvas) private var canvas
    @State private var enabled = true
    @State private var volume = 0.65
    @State private var query = ""
    @State private var confirmation = SeleneConfirmButton.cancel
    @State private var choice = 0
    let sheet: OortUIGallery.Sheet

    private func text(_ key: String) -> String { L10n.text(key, context: locale) }

    var body: some View {
        OortPage<Int, _>(title: "Oort UI  /  " + sheet.rawValue,
                         preset: sheet == .page ? .standard : .legacyBackdrop,
                         back: HintItem(.b, text("Back")), confirm: HintItem(.a, text("Select"))) {
            switch sheet {
            case .rows:
                OortSection(title: text("Settings")) {
                    OortRow(title: "Nintendo Switch 2", platform: .switch2, status: text("Engine folder found"),
                            focused: true, preset: .navigation(label: text("Open"), action: {}))
                    OortRow(title: "Google Drive", platform: .drive, status: text("Drive not connected"), preset: .info)
                    SeleneToggleRow("Interface sounds", isOn: $enabled)
                    SeleneToggleRow("Quiet launch screen", isOn: .constant(false))
                    SeleneValueRow("Sound volume", info: "How loud the interface sounds are.", value: "65%")
                    SeleneCycleRow("Back", value: "Automatic") { _ in }
                    SeleneButtonRow("Integrations", buttonTitle: "Open") {}
                    OortSliderRow(title: "Sound volume", subtitle: "How loud the interface sounds are.",
                                  value: $volume, range: 0...1, step: 0.05, displayValue: "\(Int(volume * 100))%")
                }
            case .states:
                OortCard("Integrations") {
                    HStack {
                        OortButton(title: "Open") {}
                        OortButton(title: "Open", focused: true) {}
                        OortButton(title: "Unavailable", focused: true, state: .blocked, preset: .compact) {}
                        OortButton(title: "Checking…", state: .busy, preset: .compact) {}
                    }
                    HStack {
                        OortStatus(text: text("Drive not connected"))
                        OortStatus(text: text("Drive transfer in progress"), tone: .working)
                        OortStatus(text: text("Drive check failed"), tone: .attention)
                        OortStatus(text: text("Last Drive check succeeded"), tone: .ready)
                        SeleneValueChip(text: "65%")
                    }
                    TextField(text("Find a game"), text: $query)
                        .modifier(OortField(focused: true))
                }
                HStack(spacing: canvas.u(SeleneTokens.Space.large)) {
                    OortGameTile(title: "Lunar Observatory", selected: true, preset: .spotlight,
                                 select: {}, activate: {}) { sampleArt(.switch2) }
                    OortGameTile(title: "Lunar Observatory", selected: false, preset: .spotlight,
                                 select: {}, activate: {}) { sampleArt(.steam) }
                    OortGameTile(title: "Lunar Observatory", selected: true, preset: .collection,
                                 select: {}, activate: {}) { sampleArt(.mac) }
                }
            case .dialogs:
                HStack(alignment: .top) {
                    SeleneConfirmDialog(title: "Remove", message: text("No incoming files"), confirmTitle: "Remove",
                                        warningIcon: true, focus: $confirmation, onCancel: {}, onConfirm: {})
                    SeleneChoiceDialog(title: "Integrations", message: text("Find installed Mac games and open them in Steam."),
                                       choices: ["Open", "Cancel"], focus: $choice, cancelIndex: 1, onCancel: {}) { _ in }
                }
                SeleneSuccessNotice(title: "Done", message: text("Last Drive check succeeded"))
            case .page:
                OortSection(title: text("Integrations")) {
                    OortEmptyState(title: text("No incoming files"))
                    OortCard("Integrations") {
                        OortRow(title: text("Artwork and scores"), platform: .images,
                                status: text("No provider credentials"), preset: .info)
                    }
                }
                OortSegmented(selection: $enabled, options: [(true, text("On")), (false, text("Off"))],
                              preset: .modeBar, focused: false)
                HStack {
                    OortPlayerSlot(title: "P1", detail: text("Empty place"), accessibilityTitle: "P1",
                               accessibilityValue: text("Empty place"), focused: false, selected: false,
                               marked: false, action: {}) { PlatformMark(kind: .switch1) }
                    OortPlayerSlot(title: "P2 · Lunar Observatory", detail: text("On hold while controllers are combined"),
                               accessibilityTitle: "P2", accessibilityValue: "Lunar Observatory", focused: true,
                               selected: true, marked: true, action: {}) { PlatformMark(kind: .switch2) }
                }
            }
        }
    }

    private func sampleArt(_ platform: PlatformKind) -> some View {
        RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous)
            .fill(SeleneTheme.pageSurface)
            .overlay { PlatformMark(kind: platform).foregroundStyle(SeleneTheme.ink) }
    }
}

/// Fixed synthetic wallpaper, deliberately harsh under transparent surfaces.
struct OortGalleryWallpaper: View {
    var body: some View {
        LinearGradient(colors: [.white, Color(hex: SeleneTokens.Palette.glyph),
                                Color(hex: SeleneTokens.Palette.success), .white],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
#endif
