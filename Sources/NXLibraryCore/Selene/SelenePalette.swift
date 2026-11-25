import Foundation

/// A Selene colour palette (ported from Selene's theme/Palettes, MIT). Colours are 0xRRGGBB.
public struct SelenePalette: Codable, Equatable, Identifiable {
    public enum Mode: String, Codable { case dark, light }

    public struct BaseGradient: Codable, Equatable {
        public enum Kind: String, Codable { case linear, radial }
        public struct Stop: Codable, Equatable {
            public var color: UInt32
            public var location: Double
            public init(color: UInt32, location: Double) {
                self.color = color
                self.location = location
            }
        }
        public var kind: Kind
        public var stops: [Stop]
        public init(kind: Kind, stops: [Stop]) {
            self.kind = kind
            self.stops = stops
        }
    }

    public var id: String
    public var name: String
    public var mode: Mode
    public var focus: UInt32
    public var onFocus: UInt32
    public var ink: UInt32
    public var scrim: UInt32
    public var glass: UInt32
    public var glyph: UInt32
    public var success: UInt32
    public var moonlight: String? = nil
    /// The background light, when it is not the accent.
    public var light: UInt32? = nil
    public var backgroundLight: UInt32 { light ?? glyph }
    public var surface: MoonlightSurface { MoonlightSurface(rawValue: moonlight ?? "") ?? .classic }
    public var base: BaseGradient

    /// Built-in Oort palette, used when palettes.json is unavailable.
    public static let fallback = SelenePalette(
        id: SelenePaletteCatalog.defaultID, name: "Oort", mode: .dark,
        focus: SeleneTokens.Palette.focus, onFocus: SeleneTokens.Palette.onFocus,
        ink: SeleneTokens.Palette.ink, scrim: SeleneTokens.Palette.scrim,
        glass: SeleneTokens.Palette.glass, glyph: SeleneTokens.Palette.glyph,
        success: SeleneTokens.Palette.success, moonlight: MoonlightSurface.cloud.rawValue, light: SeleneTokens.Palette.light,
        base: .init(kind: .radial, stops: [
            .init(color: SeleneTokens.Palette.gradientStart, location: SeleneTokens.Palette.positionStart),
            .init(color: SeleneTokens.Palette.gradientEnd, location: SeleneTokens.Palette.positionEnd)
        ])
    )
}

extension SelenePalette {
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ color: UInt32) -> Double {
            let parts = [16, 8, 0].map { Double((color >> UInt32($0)) & 255) / 255 }
                .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]
        }
        let low = min(luminance(a), luminance(b)), high = max(luminance(a), luminance(b))
        return (high + 0.05) / (low + 0.05)
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ share: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { sum, shift in
            let x = Double((a >> UInt32(shift)) & 255), y = Double((b >> UInt32(shift)) & 255)
            return sum | UInt32((x + (y - x) * share).rounded()) << UInt32(shift)
        }
    }

    /// The palette with its focus, glyph and text on focus moved only as far as reading them needs:
    /// 3:1 for a shape on a panel, 4.5:1 for text (WCAG 1.4.11 and 1.4.3).
    public var readable: SelenePalette {
        func reach(_ color: UInt32, on ground: UInt32, toward target: UInt32, _ ratio: Double) -> UInt32 {
            stride(from: 0.0, through: 1, by: 0.05).lazy.map { Self.mix(color, target, $0) }
                .first { Self.contrast($0, ground) >= ratio } ?? target
        }
        var next = self
        next.focus = reach(focus, on: glass, toward: ink, 3)
        next.glyph = reach(glyph, on: glass, toward: ink, 3)
        let extreme: UInt32 = Self.contrast(0, next.focus) > Self.contrast(0xFFFFFF, next.focus) ? 0 : 0xFFFFFF
        next.onFocus = reach(onFocus, on: next.focus, toward: extreme, 4.5)
        return next
    }
}

public enum SelenePaletteCatalog {
    /// The theme used without a preference, first in the picker.
    public static let defaultID = "oort"
    /// The classic blue palette keeps its softer row icons and headings.
    public static let classicBlueID = "selene"

    /// The picker's order: the default first, then the rest by name.
    public static func pickerOrder(_ palettes: [SelenePalette]) -> [SelenePalette] {
        palettes.filter { $0.id == defaultID }
            + palettes.filter { $0.id != defaultID }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func load(from url: URL) throws -> [SelenePalette] {
        try JSONDecoder().decode([SelenePalette].self, from: Data(contentsOf: url)).map(\.readable)
    }

    public static func resolve(_ id: String, in palettes: [SelenePalette]) -> SelenePalette {
        palettes.first { $0.id == id }
            ?? palettes.first { $0.id == defaultID }
            ?? .fallback
    }
}
