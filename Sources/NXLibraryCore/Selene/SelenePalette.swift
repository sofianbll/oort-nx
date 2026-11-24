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
    public var surface: MoonlightSurface { MoonlightSurface(rawValue: moonlight ?? "") ?? .classic }
    public var base: BaseGradient

    /// Built-in Oort palette, used when palettes.json is unavailable.
    public static let fallback = SelenePalette(
        id: SelenePaletteCatalog.defaultID, name: "Oort", mode: .dark,
        focus: 0xFFFFFF, onFocus: 0x000000, ink: 0xFFFFFF, scrim: 0x000000,
        glass: 0x0B0B0B, glyph: 0xFFC799, success: 0x99FFE4,
        base: .init(kind: .radial, stops: [
            .init(color: 0x121212, location: 0),
            .init(color: 0x000000, location: 1)
        ])
    )
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
        try JSONDecoder().decode([SelenePalette].self, from: Data(contentsOf: url))
    }

    public static func resolve(_ id: String, in palettes: [SelenePalette]) -> SelenePalette {
        palettes.first { $0.id == id }
            ?? palettes.first { $0.id == defaultID }
            ?? .fallback
    }
}
