import AppKit
import SwiftUI
import NXLibraryCore

enum PlatformKind: String, CaseIterable {
    case switch1 = "Nintendo Switch"
    case switch2 = "Nintendo Switch 2"
    case steam = "Steam"
    case mac = "Mac app"
    case epic = "Epic Games"
    case gog = "GOG"
    case minecraft = "Minecraft"
    case crossover = "CrossOver"
    case support = "Buy Me a Coffee"
    case drive = "Google Drive"

    static let upcoming: [Self] = [.epic, .gog, .minecraft, .crossover, .mac]

    var asset: String {
        switch self {
        case .switch1, .switch2: "gamepad-2"
        case .steam: "disc-3"
        case .mac: "laptop"
        case .epic: "shield"
        case .gog: "package"
        case .minecraft: "boxes"
        case .crossover: "arrow-left-right"
        case .support: "coffee"
        case .drive: "hard-drive"
        }
    }

    var fallback: String {
        switch self {
        case .switch1, .switch2: "gamecontroller"
        case .steam: "opticaldisc"
        case .mac: "laptopcomputer"
        case .epic: "shield"
        case .gog: "shippingbox"
        case .minecraft: "cube"
        case .crossover: "arrow.left.arrow.right"
        case .support: "cup.and.saucer"
        case .drive: "externaldrive"
        }
    }
}

/// A platform takes the ink of the surrounding row; only the name is spoken.
struct PlatformLabel: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    let kind: PlatformKind
    var title: String? = nil
    var size: SeleneTokens.Text = .rowTitle
    var weight: Font.Weight = .semibold

    init(_ kind: PlatformKind, title: String? = nil, size: SeleneTokens.Text = .rowTitle, weight: Font.Weight = .semibold) {
        self.kind = kind
        self.title = title
        self.size = size
        self.weight = weight
    }

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            PlatformMark(kind: kind)
            Text(verbatim: title ?? L10n.text(kind.rawValue, context: locale))
                .seleneFont(size, weight)
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
        // Dense, filled marks need less width than the outlined marks in the same box.
        let scale: CGFloat = if mark?.isBrand == true {
            switch kind {
            case .switch1, .steam: 0.78
            case .epic, .gog, .drive: 0.84
            default: 1
            }
        } else { 1 }
        return VStack(spacing: 0) {
            Group {
                if let mark {
                    Image(nsImage: mark.image).renderingMode(.template).resizable()
                } else {
                    Image(systemName: kind.fallback).resizable()
                }
            }
            .scaledToFit()
            .frame(width: isSecond ? side * 0.87 : side * scale, height: isSecond ? side * 0.65 : side * scale)
            if isSecond {
                Text(verbatim: "2")
                    .font(.system(size: side * 0.44, weight: .bold, design: .monospaced))
                    .fixedSize()
                    .frame(height: side * 0.35)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
