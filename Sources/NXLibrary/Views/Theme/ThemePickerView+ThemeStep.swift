import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// The theme step: the palettes' swatches, their colour chips and the wallpaper each previews.
extension ThemePickerView {
    // MARK: - Theme step

    var themeStep: some View {
        let palette = palettes[min(state.themeIndex, palettes.count - 1)]
        return ZStack(alignment: .top) {
            header(L10n.text("Choose your theme"), L10n.text("Colors for all of Arcane. Move through them to see each one in the preview."))
            HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.settingsInfoClearance)) {
                grid(count: palettes.count, columns: ThemePickerState.themeColumns) { index in
                    ThemePaletteSwatch(palette: palettes[index], focused: index == state.themeIndex)
                        .onTapGesture { tap(index) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ThemePreview(palette: palette, wallpaperURL: previewWallpaper(theme: palette),
                                 games: games, width: 780, shade: settings.settings.backgroundShade,
                                 animated: settings.settings.animatedBackground)
                    chips(palette)
                        .padding(.top, canvas.u(SeleneTokens.Space.control))
                        .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
                    Text(palette.name + (palette.mode == .light ? L10n.text("  ·  light") : ""))
                        .seleneFont(.heading)
                        .foregroundColor(SeleneTheme.ink)
                        .padding(.top, canvas.u(SeleneTokens.Space.small))
                        .padding(.leading, canvas.u(SeleneTokens.Space.hairline))
                }
            }
            .padding(.top, canvas.u(SeleneTokens.Space.stageDropDeep))
        }
    }

}

struct ThemePaletteSwatch: View {
    let palette: SelenePalette
    let focused: Bool
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let background = Color(hex: palette.base.stops.first?.color ?? palette.glass)
        let readingShade = palette.mode == .light ? Color(hex: palette.scrim) : background
        let shape = RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous)
        return VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            ZStack {
                background
                if let url = WallpaperCatalog.resolve(nil, themeID: palette.id, in: theme.wallpapers)?.url {
                    WallpaperThumb(url: url)
                }
                // The theme's color fades in from the left so "Aa" reads on any wallpaper.
                LinearGradient(stops: [.init(color: readingShade.opacity(SeleneTokens.Alpha.near), location: 0),
                                       .init(color: readingShade.opacity(SeleneTokens.Alpha.mist), location: 0.55),
                                       .init(color: readingShade.opacity(0), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                HStack {
                    Text(L10n.text("Aa")).seleneFont(.row).foregroundColor(Color(hex: palette.ink))
                    Spacer(minLength: 0)
                    Circle()
                        .fill(Color(hex: palette.glyph))
                        .overlay(Circle().strokeBorder(SeleneTheme.artShade.opacity(SeleneTokens.Alpha.shade), lineWidth: SeleneTokens.Space.thinStroke))
                        .frame(width: canvas.u(20), height: canvas.u(20))
                }
                .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
            }
            .frame(width: canvas.u(132), height: canvas.u(76))
            .clipShape(shape)
            .overlay(shape.strokeBorder(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.line), lineWidth: SeleneTokens.Space.thinStroke))
            .modifier(TileFocus(focused: focused, radius: 14, scale: 1.08))
            Text(palette.name)
                .seleneFont(.text)
                .foregroundColor(SeleneTheme.ink75)
                .lineLimit(1)
                .frame(maxWidth: canvas.u(140))
        }
        .padding(.horizontal, canvas.u(SeleneTokens.Space.compact))
        .padding(.top, canvas.u(SeleneTokens.Space.tight))
        .padding(.bottom, canvas.u(SeleneTokens.Space.compact))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(palette.name)
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }

}

extension ThemePickerView {
    /// The palette's colors as a strip of chips.
    private func chips(_ palette: SelenePalette) -> some View {
        var colors: [UInt32] = []
        for color in palette.base.stops.map(\.color) + [palette.glass, palette.ink, palette.focus, palette.glyph, palette.success]
        where !colors.contains(color) {
            colors.append(color)
        }
        return HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.row), style: .continuous)
                    .fill(Color(hex: color))
                    .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.row), style: .continuous)
                        .strokeBorder(SeleneTheme.ink25, lineWidth: SeleneTokens.Space.thinStroke))
                    .frame(width: canvas.u(46), height: canvas.u(26))
            }
        }
        .id(palette.id)
        .transition(.opacity)
    }

    /// The theme's own wallpaper unless one was picked (as Selene shows it).
    private func previewWallpaper(theme palette: SelenePalette) -> URL? {
        switch settings.settings.wallpaperID {
        case nil: return WallpaperCatalog.resolve(nil, themeID: palette.id, in: theme.wallpapers)?.url
        case let id?: return theme.wallpaper(for: id)?.url
        }
    }
}
