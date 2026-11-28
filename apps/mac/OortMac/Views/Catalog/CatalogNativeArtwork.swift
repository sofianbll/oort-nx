import SwiftUI
import AppKit
import OortLibrary
import NxnativeAdapter

/// Native-app artwork for non-nxnative entries, in the tile's layout role: a square
/// shows the app's own icon (or the player's pick), a portrait the cover. It never
/// asks Nintendo artwork services or writes the installed app.
struct CatalogNativeArtwork: View {
    let game: CatalogGame
    var role: LibraryArtworkRole = .cover
    /// The art's look (black and white while Steam installs the game).
    var look: PortingTileLook = .normal
    var cornerRadius: CGFloat = 12
    @Environment(\.seleneCanvas) private var canvas
    var body: some View {
        // No source label on the art: the page's Platform says Steam (maintainer's call, 15 Nov 2026).
        ZStack {
            SeleneTheme.glassSolid
            if let shortcut = game.macShortcut { MacShortcutArtwork(shortcut: shortcut, key: game.personalizationKey) }
            else { SteamArtwork(game: game, slot: role.slot) }
        }
        .portingLook(look, cornerRadius: canvas.u(cornerRadius))
        .accessibilityLabel(game.name)
    }
}

private struct MacShortcutArtwork: View {
    let shortcut: MacShortcutRecord
    let key: String
    @Environment(\.seleneCanvas) private var canvas
    private var picks = ArtworkPicks.shared
    @State private var image: NSImage?
    @State private var loadedKey: String?

    private var artKey: String { "mac|\(key)|\(picks.revision)" }
    private var fallback: NSImage? {
        let key = "mac-icon|\(shortcut.url.path)|\(shortcut.bundleIdentifier)" as NSString
        if let icon = TileArtMemo.shared.object(forKey: key) { return icon }
        guard let url = shortcut.verifiedURL() else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        TileArtMemo.store(icon, for: key)
        return icon
    }

    var body: some View {
        ZStack {
            if let selected = loadedKey == artKey ? image : TileArtMemo.shared.object(forKey: artKey as NSString) {
                Image(nsImage: selected).resizable().scaledToFill()
            } else if let fallback {
                Image(nsImage: fallback).resizable().scaledToFit().padding(canvas.u(SeleneTokens.Space.control))
            } else {
                Image(systemName: "macwindow").resizable().scaledToFit().padding(canvas.u(SeleneTokens.Space.section))
            }
        }
        .clipped()
        .task(id: artKey) {
            let expected = artKey
            let decoded: NSImage? = if let url = picks.url(titleID: key, slot: .cover) {
                await GameArtLoader.decode(at: url, maxPixelSize: 900)
            } else { nil }
            guard !Task.isCancelled else { return }
            if let decoded { TileArtMemo.store(decoded, for: expected as NSString) }
            image = decoded; loadedKey = expected
        }
    }
}

/// A shortcut has a title and two tile commands, but no store details or activity to display.
struct MacShortcutInfo: View {
    let game: CatalogGame
    var collection = false
    var focused: Int? = nil
    var canEdit = true
    let onAction: (Int) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.control)) {
            GameLogoArea(title: game.name, logo: nil, collection: collection)
            HStack(spacing: canvas.u(SeleneTokens.Space.control)) {
                SelenePillButton(title: "Open", icon: .play, focused: focused == 0) { onAction(0) }
                if canEdit {
                    SelenePillButton(title: "Tile options", focused: focused == 1) { onAction(1) }
                }
            }
            PlatformLabel(.mac, title: L10n.text("Mac app shortcut", context: localization), preset: .summary)
                .foregroundStyle(SeleneTheme.ink60)
        }
    }
}
