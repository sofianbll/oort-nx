import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Collection's single row of portrait covers (Main.xaml PART_ListGameItems,
/// 400 high). Selene units on the stage: Switch box covers 172 × 278, 14 apart, radius 12.
/// The selected cover grows with the focus ring and sits on top; the selection
/// walks to the anchor slot and then the row slides (`CollectionRow`). The covers sit in the row and one camera
/// slides the whole row, as in Spotlight (`SpotlightRowGeometry`), so it moves as one piece.
struct CollectionCoverRow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let games: [CatalogGame]
    let selectedID: UUID?
    let artwork: ArtworkStore
    let boxArt: BoxArtService
    let boxArtIndexVersion: Int
    /// The official name, once store metadata has it.
    let officialName: (PortedGame) -> String?
    /// Asks for a game's store metadata (its official name) when its cover shows.
    let needsMetadata: (PortedGame) -> Void
    /// The porting look of a game's cover (`PortingTileLook`).
    var tileLook: (PortedGame) -> PortingTileLook = { _ in .normal }
    @ObservedObject var cloud: CloudLibraryModel
    let showsCloudBadges: Bool
    var badgePosition: TileBadgePosition = .topRight
    let onSelect: (CatalogGame) -> Void
    let onActivate: (CatalogGame) -> Void
    var onOptions: (CatalogGame) -> Void = { _ in }

    /// The first cover lines up with Spotlight's 80 margin (Selene's list had 14).
    private static let startInset: CGFloat = 80

    var body: some View {
        let selected = selectedID.flatMap { id in games.firstIndex { $0.id == id } }
        let offset = selected.map(CollectionRow.scrollOffset(selectedIndex:)) ?? 0
        let window = visibleRange(offset: offset)
        ZStack(alignment: .topLeading) {
            ForEach(window.map { (index: $0, game: games[$0]) }, id: \.game.id) { entry in
                cover(entry.game, selected: entry.index == selected)
                    .offset(x: canvas.u(Self.startInset + CGFloat(entry.index) * CollectionRow.pitch),
                            y: canvas.u((CollectionRow.bandHeight - CollectionRow.coverHeight) / 2))
                    .zIndex(entry.index == selected ? 10 : 0)
                    .transition(.identity)
            }
        }
        // Covers made, and art arriving, during the slide ride it with the rest (`GlideGroup`).
        .modifier(GlideGroup())
        // The camera: the one slide of the whole row.
        .modifier(RailCamera(position: CGFloat(offset),
                             maximum: CGFloat(CollectionRow.scrollOffset(selectedIndex: games.count - 1)),
                             pitch: canvas.u(CollectionRow.pitch)))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: canvas.u(CollectionRow.bandHeight), alignment: .topLeading)
        .animation(Motion.rail(reduceMotion, .collection), value: selectedID)
        .animation(Motion.rail(reduceMotion, .collection), value: games.map(\.id))
    }

    /// Covers from a few left of the screen to a few past its right edge (the same spare as Spotlight's row).
    private func visibleRange(offset: Int) -> Range<Int> {
        let pitch = max(canvas.u(CollectionRow.pitch), 1)
        return SpotlightRowGeometry.window(count: games.count, offset: offset,
                                           tilesLeftOfStage: Int((canvas.stageOrigin.x / pitch).rounded(.up)),
                                           tilesAcross: Int((canvas.size.width / pitch).rounded(.up)))
    }

    private func cover(_ game: CatalogGame, selected: Bool) -> some View {
        let w = canvas.u(CollectionRow.coverWidth), h = canvas.u(CollectionRow.coverHeight)
        let face = RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous)
        let cloudState = game.nxnativeGame.flatMap(cloud.stateForTile)
        return OortGameTile(title: game.name, selected: selected, preset: .collection,
                            select: { onSelect(game) }, activate: { onActivate(game) }, options: { onOptions(game) }) {
            Group {
                if let native = game.nxnativeGame {
                    SwitchBoxArtCover(game: native, width: w, height: h, officialName: officialName(native),
                                      boxArt: boxArt, artwork: artwork, indexVersion: boxArtIndexVersion,
                                      cloudTile: .init(state: cloudState, buildLook: tileLook(native),
                                                       cornerRadius: canvas.u(SeleneTokens.Radius.content)))
                } else {
                    CatalogNativeArtwork(game: game, look: PortingTileLook.make(catalog: game))
                        .frame(width: w, height: h)
                        .clipShape(face)
                }
            }
            if game.nxnativeGame == nil {
                PortingDownloadMark(look: PortingTileLook.make(catalog: game), width: w, height: h)
            }
            SeleneShine(cornerRadius: canvas.u(SeleneTokens.Radius.content), active: selected)
                .frame(width: w, height: h)
        }
        .modifier(CloudLibraryTileBadge(state: cloudState, showsCopyBadge: showsCloudBadges, position: badgePosition,
                                        look: game.nxnativeGame.map(tileLook) ?? .normal, onlineTitleID: game.nxnativeGame?.titleId))
        .task(id: game.id) { if let native = game.nxnativeGame { needsMetadata(native) } }
    }
}
