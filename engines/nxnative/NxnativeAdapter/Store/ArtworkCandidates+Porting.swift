import Foundation
import OortLibrary

/// The images a Switch game's picker offers: GameTDB, Title DB and the Nintendo store, then everything found online.
extension ArtworkCandidates {
    /// Cover regions the picker tries for each GameTDB entry.
    public static let pickerRegions = ["US", "EN", "JA", "FR", "DE"]

    /// Every image worth offering for `slot`, in the order the picker shows them.
    /// `entries` are GameTDB matches, best first.
    public static func list(for slot: ArtworkSlot, entries: [GameTDBEntry], titleDB: TitleDBInfo?,
                            storeHeader: URL?, storeImage: URL?, storeLogo: URL?,
                            online: [ArtworkCandidate] = [], storeSquare: URL? = nil,
                            storeCover: URL? = nil) -> [ArtworkCandidate] {
        var list: [ArtworkCandidate] = []
        func add(_ source: String, _ url: URL?) {
            guard let url, !list.contains(where: { $0.url == url }) else { return }
            list.append(ArtworkCandidate(slot: slot, source: source, url: url))
        }
        func addStore(_ url: URL?) {
            guard let url else { return }
            if url.host == "www.nintendo.com", url.path.hasPrefix("/eu/media/images/") {
                add("Nintendo Europe", url)
            } else if url.host == "api.nlib.cc" {
                add("Title DB", url)
            } else {
                add(L10n.text("Nintendo store"), url)
            }
        }
        switch slot {
        case .cover:
            addStore(storeCover)
            for entry in entries {
                let urls = GameTDB.coverURLs(id: entry.id)
                for region in pickerRegions {
                    add("GameTDB · \(region)", urls.first { $0.pathComponents.dropLast().last == region })
                }
            }
        case .background:
            addStore(storeHeader)
            add("Title DB banner", titleDB?.banner)
            for (index, url) in (titleDB?.screenshots ?? []).enumerated() {
                add("Title DB screenshot \(index + 1)", url)
            }
            addStore(storeImage)
        case .icon:
            addStore(storeSquare)
            add("Title DB icon", titleDB?.icon)
        case .logo:
            addStore(storeLogo)
        }
        // Everything found online (`OnlineArtwork`) after the Nintendo sources, in its order.
        for candidate in online where candidate.slot == slot && !list.contains(where: { $0.url == candidate.url }) {
            list.append(candidate)
        }
        return list
    }
}
