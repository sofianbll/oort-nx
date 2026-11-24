import SwiftUI
import NXLibraryCore

struct OortGameTile<Artwork: View>: View {
    enum Preset { case spotlight, collection }

    @Environment(\.seleneCanvas) private var canvas
    let title: String
    let selected: Bool
    let preset: Preset
    let select: () -> Void
    let activate: () -> Void
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        let cover = preset == .collection
        let width = canvas.u(cover ? CollectionRow.coverWidth : SpotlightRowGeometry.host)
        let height = canvas.u(cover ? CollectionRow.coverHeight : SpotlightRowGeometry.host)
        let ringBleed = cover ? canvas.u(SeleneTokens.Space.small) : 0
        ZStack(alignment: cover ? .center : .topLeading) {
            if cover {
                artwork()
            } else {
                artwork().padding(canvas.u(SeleneTokens.Space.badge))
            }
            SeleneTileRing(cornerRadius: canvas.u(cover ? SeleneTokens.Radius.collectionFocus
                                                 : SeleneTokens.Radius.spotlightFocus), active: selected)
                .frame(width: width + ringBleed, height: height + ringBleed)
        }
        .frame(width: width, height: height, alignment: cover ? .center : .topLeading)
        .scaleEffect(cover && selected ? CollectionRow.selectedScale : 1)
        .contentShape(Rectangle())
        // A click selects immediately; it does not wait to disambiguate a double click.
        .onTapGesture(count: 2, perform: activate)
        .simultaneousGesture(TapGesture().onEnded { select() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { activate() }
    }
}
