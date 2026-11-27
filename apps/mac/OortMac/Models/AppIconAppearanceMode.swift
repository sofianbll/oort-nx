import OortLibrary
import Foundation

enum AppIconAppearanceMode: String, CaseIterable, Identifiable, Hashable {
    case auto = "Auto (System)"
    case light = "Light"
    case dark = "Dark"
    case mono = "Monochrome"

    var id: String { rawValue }
    /// Keep legacy preference values: Auto uses the system icon; Monochrome now selects particles.
    static let selectable: [Self] = [.auto, .mono]
    var label: String { self == .mono ? L10n.text("Particles") : L10n.text("Halftone") }
}
