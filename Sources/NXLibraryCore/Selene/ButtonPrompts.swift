import Foundation

public enum ButtonNameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, nintendo, xbox, playstation

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

public enum PromptButton: String, CaseIterable {
    case a, b, x, y, lb, rb, lt, rt, ls, rs, view, menu, home, move, navigate, vertical, search
}

public enum ConnectedPad {
    case nintendo, xbox, playstation, other, none
}

/// A Mac keyboard key as a prompt: an SF Symbol or the key's printed text.
public enum KeyCap: Equatable {
    case symbol(String)
    case text(String)
}

public enum ButtonPrompts {
    /// Automatic names with no controller connected show the keyboard keys instead.
    public static func usesKeyboard(style: ButtonNameStyle, connected: ConnectedPad) -> Bool {
        style == .automatic && connected == .none
    }

    /// A left hint on a screen's bar: the ⌘F keycap shows only on the keyboard (a controller reaches search
    /// by holding View), and a controller-only hint never shows there. "Active" is `!usesKeyboard`: a
    /// connected controller or a chosen button style, so the bar and the badges agree.
    public static func showsHint(_ button: PromptButton?, controllerOnly: Bool, style: ButtonNameStyle,
                                 connected: ConnectedPad) -> Bool {
        usesKeyboard(style: style, connected: connected) ? !controllerOnly : button != .search
    }

    /// The key the screens' key monitors take for each prompt: Return confirms,
    /// Esc goes back, X and Y, Q/E for filters, Home/End for the triggers,
    /// F3 for sort, V for View and ⇧⌘K for Menu (⌘K is the command palette).
    public static func keyboardKey(_ button: PromptButton) -> KeyCap {
        switch button {
        case .a: return .symbol("return")
        case .b: return .text(L10n.text("esc"))
        case .x: return .text("X")
        case .y: return .text("Y")
        case .lb: return .text("Q")
        case .rb: return .text("E")
        case .ls: return .text("⌘F")
        case .rs: return .text("F3")
        case .lt: return .text(L10n.text("home"))
        case .rt: return .text(L10n.text("end"))
        case .view: return .text("V")
        case .menu: return .text(PaletteAction.controlCenter.shortcut ?? "")
        case .home: return .text("⇧⌘P")
        case .move: return .text("← →")
        case .vertical: return .text("↑ ↓")
        case .navigate: return .text("↑ ↓ ← →")
        case .search: return .text("⌘F")
        }
    }
    public static func label(_ button: PromptButton, style: ButtonNameStyle, connected: ConnectedPad) -> String {
        switch resolved(style, connected) {
        case .nintendo: return nintendoLabel(button)
        case .playstation: return playstationLabel(button)
        default: return xboxLabel(button)
        }
    }

    /// The SF Symbols name for a prompt (Apple's controller glyphs), or nil.
    /// Automatic with a controller connected prefers what the controller itself
    /// reports (`GCControllerElement.sfSymbolsName`, which follows the user's
    /// remapping), then that brand's table; a generic controller uses Xbox's.
    /// Automatic with no controller has none (`keyboardKey` applies); a chosen
    /// style always uses its table.
    public static func symbol(_ button: PromptButton, style: ButtonNameStyle, connected: ConnectedPad,
                              reported: [PromptButton: String] = [:]) -> String? {
        if style == .automatic {
            guard connected != .none else { return nil }
            // The stick click is never the bare "R" or "L" disc: it reads as the shoulder button.
            if let name = reported[button], !name.isEmpty, !isGenericShape(name),
               !(button == .rs && name.hasPrefix("r.joystick")), !(button == .ls && name.hasPrefix("l.joystick")) { return name }
        }
        switch resolved(style, connected) {
        case .nintendo: return nintendoSymbol(button)
        case .playstation: return playstationSymbol(button)
        default: return xboxSymbol(button)
        }
    }

    /// Shape-only placeholders have no button mark to show in a two-colour badge.
    /// Keep real glyphs such as `circle.circle`, `square.circle` and stacked rectangles.
    public static func isGenericShape(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        guard let shape = parts.first, genericShapes.contains(String(shape)) else { return false }
        return parts.dropFirst().allSatisfy { shapeModifiers.contains(String($0)) }
    }

    private static let genericShapes: Set<String> = ["circle", "capsule", "square", "rectangle", "oval", "button"]
    private static let shapeModifiers: Set<String> = [
        "fill", "portrait", "landscape", "horizontal", "vertical", "roundedtop", "roundedbottom",
        "inset", "filled", "dashed", "dotted", "lefthalf", "righthalf", "tophalf", "bottomhalf"
    ]

    /// The right-stick click, drawn as its family names it: RSB on Xbox, R3 on PlayStation. The Switch has
    /// no name of its own in SF Symbols; R3 cannot be mistaken for its R shoulder button.
    private static func stickClickSymbol(_ family: ButtonNameStyle, left: Bool = false) -> String {
        switch (family == .xbox, left) {
        case (true, false): "rsb.button.angledbottom.horizontal.right"
        case (true, true): "lsb.button.angledbottom.horizontal.left"
        case (false, false): "r3.button.angledbottom.horizontal.right"
        case (false, true): "l3.button.angledbottom.horizontal.left"
        }
    }

    private static func nintendoSymbol(_ b: PromptButton) -> String? {
        switch b {
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .lb: return "l.rectangle.roundedbottom"
        case .rb: return "r.rectangle.roundedbottom"
        case .lt: return "zl.rectangle.roundedtop"
        case .rt: return "zr.rectangle.roundedtop"
        case .ls: return stickClickSymbol(.playstation, left: true)
        case .rs: return stickClickSymbol(.playstation)
        case .view: return "minus.circle"
        case .menu: return "plus.circle"
        case .home: return "house.circle"
        case .move: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        case .navigate: return "dpad"
        case .search: return nil
        }
    }

    private static func xboxSymbol(_ b: PromptButton) -> String? {
        switch b {
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .lb: return "lb.rectangle.roundedbottom"
        case .rb: return "rb.rectangle.roundedbottom"
        case .lt: return "lt.rectangle.roundedtop"
        case .rt: return "rt.rectangle.roundedtop"
        case .ls: return stickClickSymbol(.xbox, left: true)
        case .rs: return stickClickSymbol(.xbox)
        case .view: return "rectangle.on.rectangle.circle"
        case .menu: return "line.3.horizontal.circle"
        case .home: return "xbox.logo"
        case .move: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        case .navigate: return "dpad"
        case .search: return nil
        }
    }

    private static func playstationSymbol(_ b: PromptButton) -> String? {
        switch b {
        case .a: return "xmark.circle"
        case .b: return "circle.circle"
        case .x: return "square.circle"
        case .y: return "triangle.circle"
        case .lb: return "l1.rectangle.roundedbottom"
        case .rb: return "r1.rectangle.roundedbottom"
        case .lt: return "l2.rectangle.roundedtop"
        case .rt: return "r2.rectangle.roundedtop"
        case .ls: return stickClickSymbol(.playstation, left: true)
        case .rs: return stickClickSymbol(.playstation)
        case .home: return "playstation.logo"
        case .move: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        case .navigate: return "dpad"
        case .view, .menu, .search: return nil // Use the key's label when no glyph is defined.
        }
    }

    private static func resolved(_ style: ButtonNameStyle, _ connected: ConnectedPad) -> ButtonNameStyle {
        guard style == .automatic else { return style }
        switch connected {
        case .nintendo: return .nintendo
        case .playstation: return .playstation
        default: return .xbox
        }
    }

    private static func nintendoLabel(_ b: PromptButton) -> String {
        switch b {
        case .a: return "A"
        case .b: return "B"
        case .x: return L10n.text("X")
        case .y: return L10n.text("Y")
        case .lb: return "L"
        case .rb: return "R"
        case .lt: return "ZL"
        case .rt: return "ZR"
        case .ls: return "L3"
        case .rs: return "R3"
        case .view: return "−"
        case .menu: return "+"
        case .home: return "⌂"
        case .move: return "← →"
        case .vertical: return "↑ ↓"
        case .navigate: return "↑ ↓ ← →"
        case .search: return "⌘F"
        }
    }

    private static func xboxLabel(_ b: PromptButton) -> String {
        switch b {
        case .a: return "A"
        case .b: return "B"
        case .x: return L10n.text("X")
        case .y: return L10n.text("Y")
        case .lb: return "LB"
        case .rb: return "RB"
        case .lt: return "LT"
        case .rt: return "RT"
        case .ls: return "LSB"
        case .rs: return "RSB"
        case .view: return "View"
        case .menu: return "Menu"
        case .home: return "Xbox"
        case .move: return "← →"
        case .vertical: return "↑ ↓"
        case .navigate: return "↑ ↓ ← →"
        case .search: return "⌘F"
        }
    }

    private static func playstationLabel(_ b: PromptButton) -> String {
        switch b {
        case .a: return "✕"
        case .b: return "○"
        case .x: return "□"
        case .y: return "△"
        case .lb: return "L1"
        case .rb: return "R1"
        case .lt: return "L2"
        case .rt: return "R2"
        case .ls: return "L3"
        case .rs: return "R3"
        case .view: return L10n.text("Touchpad")
        case .menu: return "Options"
        case .home: return "PS"
        case .move: return "← →"
        case .vertical: return "↑ ↓"
        case .navigate: return "↑ ↓ ← →"
        case .search: return "⌘F"
        }
    }
}
