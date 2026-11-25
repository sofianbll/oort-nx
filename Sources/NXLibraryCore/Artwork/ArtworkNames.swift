import Foundation

/// When a store's title is the player's game: the same name, or the same name
/// with an edition after it ("Voidheart Edition", "Nintendo Switch Edition").
/// A sequel, a DLC or a soundtrack never is.
public enum ArtworkNames {
    /// Platform words a store adds to the name.
    private static let platformTails = [["nintendo", "switch", "edition"], ["for", "nintendo", "switch"],
                                        ["nintendo", "switch"]]

    public static func matches(_ title: String, _ names: [String]) -> Bool {
        let store = words(title)
        guard !store.isEmpty else { return false }
        return names.contains { name in
            let game = words(name)
            guard !game.isEmpty, store.starts(with: game) else { return false }
            let rest = store.dropFirst(game.count)
            return rest.isEmpty || (rest.last == "edition" && rest.count <= 5)
        }
    }

    private static func words(_ name: String) -> [String] {
        var list = GameTitleKey.normalize(name).split(separator: " ").map(String.init)
        for tail in platformTails where list.count > tail.count && list.suffix(tail.count).elementsEqual(tail) {
            list.removeLast(tail.count)
            break
        }
        return list
    }
}
