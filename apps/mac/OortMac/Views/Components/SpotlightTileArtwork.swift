import SwiftUI
import AppKit
import OortLibrary
import NxnativeAdapter

/// Square tile art: the player's pick first. Then, with `ownIconFirst`, the
/// game's own icon art (the built app's icon, as on the Mac), so every tile is
/// the same full-bleed square.
/// Otherwise (or without one): Title DB's 1024 icon by title ID, then the
/// generic icon. Crossfades when fetched art arrives.
/// The caller applies the corner radius.
struct SpotlightTileArtwork: View {
    @Environment(\.catalogPersonalizations) private var personalizations
    let game: PortedGame
    /// Side length in points, already scaled by the caller.
    let side: CGFloat
    /// The app's shared artwork cache.
    let artwork: ArtworkStore
    /// Show the game's own icon art (as on the Mac) whenever it exists (Spotlight's row).
    var ownIconFirst = false
    var cloudTile: DownloadCloudTileStyle? = nil

    private var picks = ArtworkPicks.shared
    @State private var better: NSImage?
    @State private var picked: NSImage?
    @State private var loadedPickKey: NSString?
    /// The first look-up has ended (art found or not): the tile is ready for Spotlight's entrance.
    @State private var settled = false

    private var automaticKey: NSString { "nxnative|\(game.id)" as NSString }

    private func pickKey(_ url: URL) -> NSString {
        "nxnative|pick|\(url.path)|\(picks.revision)" as NSString
    }

    /// Read the warm cache while constructing the view, before its task runs.
    private var pickedImage: NSImage? {
        guard let url = picks.url(titleID: personalizations.nxnativeKey(for: game), slot: .icon) else { return nil }
        let key = pickKey(url)
        return TileArtMemo.shared.object(forKey: key) ?? (loadedPickKey == key ? picked : nil)
    }

    private var automaticImage: NSImage? { better ?? TileArtMemo.shared.object(forKey: automaticKey) }

    var body: some View {
        let personal = pickedImage
        let own = personal == nil && ownIconFirst ? GameIconProvider.squareArt(for: game) : nil
        let automatic = personal == nil && own == nil ? automaticImage : nil
        let fallback = personal == nil && own == nil && automatic == nil ? GameIconProvider.icon(for: game) : nil
        let face = art(personal, own, automatic, fallback)
        return Group {
            if let cloudTile {
                DownloadCloudArt(art: face, style: cloudTile, id: game.id,
                                 revision: .init(images: [personal, own, automatic, fallback]))
            } else {
                face
            }
        }
        .frame(width: side, height: side)
        .preference(key: TileArtPendingKey.self, value: settled ? 0 : 1)
        .task(id: "\(game.id)|\(picks.revision)") {
            defer { if !settled { settled = true } }
            if let url = picks.url(titleID: personalizations.nxnativeKey(for: game), slot: .icon) {
                let key = pickKey(url)
                let decoded: NSImage?
                if let cached = TileArtMemo.shared.object(forKey: key) { decoded = cached }
                else { decoded = await GameArtLoader.decode(at: url, maxPixelSize: 512) }
                guard !Task.isCancelled else { return }
                if let decoded { TileArtMemo.store(decoded, for: key) }
                picked = decoded
                loadedPickKey = key
                return
            }
            picked = nil
            loadedPickKey = nil
            guard !ownIconFirst || GameIconProvider.squareArt(for: game) == nil else { return }
            let key = automaticKey
            if let memo = TileArtMemo.shared.object(forKey: key) {
                better = memo
                return
            }
            let loaded = await loadIcon()
            guard !Task.isCancelled, let loaded else { return }
            TileArtMemo.store(loaded, for: key)
            withAnimation(SeleneTheme.arrival) { better = loaded }
        }
    }

    private func art(_ picked: NSImage?, _ own: NSImage?, _ automatic: NSImage?, _ fallback: NSImage?) -> some View {
        ZStack {
            SeleneTheme.glassSolid
            if let picked {
                Image(nsImage: picked)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if let own {
                Image(nsImage: own)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if let better = automatic {
                Image(nsImage: better)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if let fallback {
                Image(nsImage: fallback)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: side, height: side)
        .clipped()
    }

    private func loadIcon() async -> NSImage? {
        guard let titleID = game.titleId, !titleID.isEmpty else { return nil }
        guard let url = await artwork.automaticIcon(titleID: titleID, name: game.name) else { return nil }
        return await GameArtLoader.decode(at: url, maxPixelSize: 512)
    }
}

/// How many tiles below are still looking up their first art; Spotlight's entrance waits for none (or 1 s).
struct TileArtPendingKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

/// Decoded tile art, so a tile that scrolls back into the row paints at once.
enum TileArtMemo {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    static func store(_ image: NSImage, for key: NSString) {
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
        shared.setObject(image, forKey: key, cost: max(pixels, 1) * 4)
    }
}
