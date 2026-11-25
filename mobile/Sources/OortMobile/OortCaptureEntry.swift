import ShellHost
import ShellModel
import SwiftUI

/// A screen of the app in a given place, for captures without a device or a simulator.
public enum OortCaptureEntry {
    public static let screens = ["home", "home-pad", "library", "game", "options", "controllers", "mapping", "padtest", "settings", "activity", "credits"]

    @MainActor public static func view(_ screen: String, model: ShellHostModel, sounds: OortSounds) -> some View {
        let id = model.details.first?.id ?? ""
        let nav: OortNav = switch screen {
        case "library": OortNav(tab: .library, sounds: sounds)
        case "game": OortNav(route: [.game(id)], sounds: sounds)
        case "options": OortNav(route: [.options(id)], sounds: sounds)
        case "controllers": OortNav(tab: .controllers, sounds: sounds)
        case "mapping": OortNav(tab: .controllers, route: [.mapping(nil)], sounds: sounds)
        case "padtest": OortNav(tab: .controllers, route: [.padTest], sounds: sounds)
        case "settings": OortNav(tab: .settings, sounds: sounds)
        case "activity": OortNav(tab: .settings, route: [.activity], sounds: sounds)
        case "credits": OortNav(tab: .settings, route: [.credits], sounds: sounds)
        default: OortNav(sounds: sounds)
        }
        if screen.hasSuffix("-pad") { nav.device = .controller(.xbox) }
        return OortRootView(model: model, nav: nav, importRoot: nil).environment(\.oortStill, true)
    }
}
