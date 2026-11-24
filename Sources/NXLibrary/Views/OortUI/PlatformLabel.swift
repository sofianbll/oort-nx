import AppKit
import SwiftUI
import NXLibraryCore

enum PlatformKind: String, CaseIterable {
    case library = "All"
    case switch1 = "Nintendo Switch"
    case switch2 = "Nintendo Switch 2"
    case steam = "Steam"
    case mac = "Mac app"
    case epic = "Epic Games"
    case gog = "GOG"
    case minecraft = "Minecraft"
    case crossover = "CrossOver"
    case ryujinx = "Ryujinx-Nextendo"
    case support = "Buy Me a Coffee"
    case drive = "Google Drive"
    case nextendo = "Nextendo"
    case images = "Artwork and scores"
    case saves = "iCloud saves"

    static let upcoming: [Self] = [.epic, .gog, .minecraft, .crossover, .ryujinx]

    var asset: String {
        switch self {
        case .library: "library"
        case .switch1, .switch2, .ryujinx: "gamepad-2"
        case .steam: "disc-3"
        case .mac: "laptop"
        case .epic: "shield"
        case .gog: "package"
        case .minecraft: "boxes"
        case .crossover: "arrow-left-right"
        case .support: "coffee"
        case .drive: "hard-drive"
        case .nextendo: "network"
        case .images: "image"
        case .saves: "cloud"
        }
    }

    var fallback: String {
        switch self {
        case .library: "square.grid.2x2"
        case .switch1, .switch2, .ryujinx: "gamecontroller"
        case .steam: "opticaldisc"
        case .mac: "laptopcomputer"
        case .epic: "shield"
        case .gog: "shippingbox"
        case .minecraft: "cube"
        case .crossover: "arrow.left.arrow.right"
        case .support: "cup.and.saucer"
        case .drive: "externaldrive"
        case .nextendo: "network"
        case .images: "photo"
        case .saves: "icloud"
        }
    }
}

/// A platform takes the ink of the surrounding row; only the name is spoken.
struct PlatformLabel: View {
    enum Preset {
        case heading, row, summary, caption, setup, listing

        var font: (SeleneTokens.Text, Font.Weight) {
            switch self {
            case .heading: (.row, .semibold)
            case .row: (.row, .medium)
            case .summary: (.text, .semibold)
            case .caption: (.text, .semibold)
            case .setup: (.row, .semibold)
            case .listing: (.text, .regular)
            }
        }
    }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    let kind: PlatformKind
    let title: String?
    let preset: Preset

    init(_ kind: PlatformKind, title: String? = nil, preset: Preset = .heading) {
        self.kind = kind
        self.title = title
        self.preset = preset
    }

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            PlatformMark(kind: kind)
            Text(verbatim: title ?? L10n.text(kind.rawValue, context: locale))
                .seleneFont(preset.font.0, preset.font.1)
        }
    }
}

struct PlatformMark: View {
    @Environment(\.seleneCanvas) private var canvas
    let kind: PlatformKind

    private static let showsBrandMarks = true

    private static let artwork: [PlatformKind: (image: NSImage, isBrand: Bool)] = {
        let folder = Bundle.main.resourceURL?.appendingPathComponent("Brands/Platforms", isDirectory: true)
        var images: [PlatformKind: (NSImage, Bool)] = [:]
        for kind in PlatformKind.allCases {
            if showsBrandMarks, let url = folder?.appendingPathComponent("Marks/\(kind.rawValue).svg"),
               let image = NSImage(contentsOf: url) {
                images[kind] = (image, true)
                continue
            }
            guard let url = folder?.appendingPathComponent("\(kind.asset).svg"),
                  let image = NSImage(contentsOf: url) else { continue }
            images[kind] = (image, false)
        }
        return images
    }()

    var body: some View {
        let side = canvas.u(SeleneTokens.Space.large)
        let mark = Self.artwork[kind]
        let isSecond = kind == .switch2 && mark?.isBrand != true
        let drawnHeight: CGFloat = if mark?.isBrand == true {
            // Compensate for the transparent margins in the original SVG artboards.
            switch kind {
            case .switch1: side * 0.94
            case .switch2: side * 0.89
            case .drive: side * 0.96
            case .crossover: side * 1.08
            case .steam, .epic, .gog, .support: side * 0.84
            default: side
            }
        } else { side }
        let drawnWidth = mark.map { drawnHeight * $0.image.size.width / $0.image.size.height } ?? side
        return VStack(spacing: 0) {
            Group {
                if let mark {
                    Image(nsImage: mark.image).renderingMode(.template).resizable()
                } else {
                    Image(systemName: kind.fallback).resizable()
                }
            }
            .scaledToFit()
            .frame(width: isSecond ? side * 0.87 : drawnWidth, height: isSecond ? side * 0.65 : drawnHeight)
            if isSecond {
                Text(verbatim: "2")
                    .font(.system(size: side * 0.44, weight: .bold, design: .monospaced))
                    .fixedSize()
                    .frame(height: side * 0.35)
            }
        }
        .frame(width: kind == .switch2 ? max(side, drawnWidth) : side, height: side)
        .accessibilityHidden(true)
    }
}
