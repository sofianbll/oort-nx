import Foundation
import NXLibraryCore

enum ControllerHomeAccess: Equatable {
    case disconnected, noHome, launcher, system, unavailable

    var hasHome: Bool { self == .launcher }
    var title: String {
        switch self {
        case .disconnected: "Not connected"
        case .noHome: "No Home button"
        case .launcher: "Home is available to Oort"
        case .system: "Home opens the Apple overlay"
        case .unavailable: "Home setting unavailable"
        }
    }
}

enum GamepadBrand: String, CaseIterable, Identifiable {
    case nintendoSwitch = "Nintendo Switch"
    case xbox = "Xbox Series / One"
    case playstation = "PlayStation DualShock / DualSense"
    case generic = "8BitDo / Generic Gamepad"

    var id: String { rawValue }

    var confirmButtonName: String {
        switch self {
        case .nintendoSwitch: return "A (Confirm)"
        case .xbox: return "A (Confirm)"
        case .playstation: return "✕ (Confirm)"
        case .generic: return "A (Confirm)"
        }
    }

    var cancelButtonName: String {
        switch self {
        case .nintendoSwitch: return "B (Back)"
        case .xbox: return "B (Back)"
        case .playstation: return "○ (Back)"
        case .generic: return "B (Back)"
        }
    }

    var secondaryButtonName: String {
        switch self {
        case .nintendoSwitch: return "X (Settings)"
        case .xbox: return "X (Settings)"
        case .playstation: return "□ (Settings)"
        case .generic: return "X (Settings)"
        }
    }

    var contextButtonName: String {
        switch self {
        case .nintendoSwitch: return "Y (Save Folder)"
        case .xbox: return "Y (Save Folder)"
        case .playstation: return "△ (Save Folder)"
        case .generic: return "Y (Save Folder)"
        }
    }

    var shoulderTabsPrompt: String {
        switch self {
        case .nintendoSwitch: return "L / R"
        case .xbox: return "LB / RB"
        case .playstation: return "L1 / R1"
        case .generic: return "L / R"
        }
    }

    var menuButtonGlyph: String {
        switch self {
        case .nintendoSwitch: return "＋"
        case .playstation: return "☰"
        case .xbox, .generic: return "≡"
        }
    }
}

enum GamepadAction: Hashable {
    case navigateUp
    case navigateDown
    case navigateLeft
    case navigateRight
    case confirm           // A or Cross
    case cancel            // B or Circle
    case secondaryAction   // X or Square
    case contextAction     // Y or Triangle
    case tabPrevious       // Left Shoulder (L / LB)
    case tabNext           // Right Shoulder (R / RB)
    case menu              // Menu / + / Options (tap)
    case menuHold          // Menu / + / Options (hold)
    case view              // View / − / Touchpad
    case search
    case browseSearch
    case controlCenter
    case fullMenu
    case profiles          // Home / Guide / PS (tap)
    case jumpToStart       // Left trigger
    case jumpToEnd         // Right trigger
    case rightStickPress   // R3

}

enum GamepadLayout: String, CaseIterable {
    case oort, arcane

    var title: String { rawValue.capitalized }

    func gameHome(_ chosen: InGameHomeButton) -> InGameHomeButton {
        chosen == .auto && self == .oort ? .quickAccess : chosen
    }

    init(_ settings: AppSettings) {
        self = settings.launcherChoices.gamepadLayout.flatMap(Self.init(rawValue:)) ?? .arcane
    }

    struct Binding {
        let button: ControllerButton
        let prompt: PromptButton
        let tap: GamepadAction
        let hold: GamepadAction?
        let release: Bool

        init(_ button: ControllerButton, _ prompt: PromptButton, _ tap: GamepadAction,
             _ hold: GamepadAction? = nil, release: Bool = false) {
            self.button = button
            self.prompt = prompt
            self.tap = tap
            self.hold = hold
            self.release = release || hold != nil
        }
    }

    private static let common: [Binding] = [
        .init(.up, .navigate, .navigateUp), .init(.down, .navigate, .navigateDown),
        .init(.left, .navigate, .navigateLeft), .init(.right, .navigate, .navigateRight),
        .init(.a, .a, .confirm), .init(.b, .b, .cancel), .init(.x, .x, .secondaryAction),
        .init(.l, .lb, .tabPrevious), .init(.r, .rb, .tabNext),
        .init(.zl, .lt, .jumpToStart), .init(.zr, .rt, .jumpToEnd), .init(.r3, .rs, .rightStickPress),
        .init(.view, .view, .view, .search),
        .init(.y, .y, .contextAction), .init(.menu, .menu, .menu, .menuHold),
    ]

    private static let tables: [Self: (everywhere: [Binding], browsing: [Binding])] = [
        .arcane: ([.init(.home, .home, .profiles, release: true)], []),
        .oort: ([.init(.home, .home, .controlCenter, .fullMenu)], [
            .init(.menu, .menu, .contextAction, .controlCenter),
            .init(.y, .y, .browseSearch),
            .init(.view, .view, .view, .browseSearch),
        ]),
    ]

    func bindings(browsing: Bool) -> [Binding] {
        let table = Self.tables[self]!
        let overrides = (browsing ? table.browsing : []) + table.everywhere
        return Self.common.map { row in overrides.first { $0.button == row.button } ?? row }
             + overrides.filter { row in !Self.common.contains { $0.button == row.button } }
    }

    func binding(_ button: ControllerButton, browsing: Bool) -> Binding? {
        bindings(browsing: browsing).first { $0.button == button }
    }

    func tap(_ action: GamepadAction) -> Binding? {
        bindings(browsing: true).first { $0.tap == action }
    }

    func guide(hasHome: Bool = true) -> [Binding] {
        bindings(browsing: true).filter { $0.prompt != .navigate && (hasHome || $0.prompt != .home) }
    }
}

extension GamepadLayout.Binding {
    func summary(style: ButtonNameStyle, pad: ConnectedPad) -> String {
        let name = ButtonPrompts.label(prompt, style: style, connected: pad)
        return name + " · " + L10n.text(tap.guideTitle) + (hold.map {
            " / " + L10n.format("Hold: %@", [L10n.text($0.guideTitle)])
        } ?? "")
    }
}

extension GamepadAction {
    var guideTitle: String {
        switch self {
        case .navigateUp, .navigateDown, .navigateLeft, .navigateRight: "Move"
        case .confirm: "Select"
        case .cancel: "Back"
        case .secondaryAction: "Details"
        case .contextAction: "Options"
        case .tabPrevious: "Previous"
        case .tabNext: "Next"
        case .menu, .controlCenter: "Control center"
        case .menuHold, .fullMenu: "Settings"
        case .view: "Change view"
        case .search, .browseSearch: "Search"
        case .profiles: "Profiles"
        case .jumpToStart: "First"
        case .jumpToEnd: "Last"
        case .rightStickPress: "Sort"
        }
    }
}
