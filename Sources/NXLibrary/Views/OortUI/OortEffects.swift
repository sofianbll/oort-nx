import SwiftUI
import NXLibraryCore

/// What a shadow is for. Screens name the role; the size and strength live here.
enum OortShadow {
    /// Text, icons and logos drawn on artwork.
    case text
    /// A tile or a band resting on the backdrop.
    case tile
    /// A card or a panel above the screen.
    case floating

    var radius: CGFloat {
        switch self {
        case .text: 6
        case .tile: 9
        case .floating: 18
        }
    }
    var drop: CGFloat { self == .floating ? 8 : 0 }
    var opacity: Double { self == .tile ? 0.55 : 0.45 }
}

private struct OortShadowModifier: ViewModifier {
    let role: OortShadow
    @Environment(\.seleneCanvas) private var canvas

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(role.opacity), radius: canvas.u(role.radius), y: canvas.u(role.drop))
    }
}

extension View {
    func oortShadow(_ role: OortShadow) -> some View { modifier(OortShadowModifier(role: role)) }
}
