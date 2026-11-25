import Foundation

/// The games the player marked, kept on this device only: identifiers on one line, so a view can watch them.
enum OortFavorites {
    static let key = "oort.favorites"
    static func ids(_ line: String) -> Set<String> { Set(line.split(separator: ",").map(String.init)) }
    static func toggled(_ id: String, in line: String) -> String {
        var ids = ids(line)
        if ids.remove(id) == nil { ids.insert(id) }
        return ids.sorted().joined(separator: ",")
    }
}
