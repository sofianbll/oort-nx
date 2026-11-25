import Foundation
@_exported import OortCore

public extension Credits {
    /// `design/credits.json`, as shipped with the app.
    static let bundled: Credits? = L10n.resources()?.url(forResource: "credits", withExtension: "json")
        .flatMap { try? Credits(contentsOf: $0) }
}
