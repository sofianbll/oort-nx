import Foundation
@preconcurrency import NXLibraryCore

/// The Settings rows this app has: the Mac app's own values, titles and help, two levels deep.
struct SettingRow {
    enum Kind {
        case toggle
        case choice([(value: String, label: String)])
        case slider(ClosedRange<Double>, step: Double)
    }

    let id: String
    let section: SettingsSection
    let title: String
    let about: String
    let kind: Kind
    let field: AppSettingsDraft.Field
    let get: (AppSettings) -> CatalogJSON
    let set: (inout AppSettings, CatalogJSON) -> Bool

    static let all: [SettingRow] = {
        let words = Dictionary(SettingsCatalog.baseRows.map { ($0.id, $0) }) { a, _ in a }
        func row<Value: Equatable>(_ id: String, _ key: WritableKeyPath<AppSettings, Value>, _ kind: Kind,
                                   to: @escaping (Value) -> CatalogJSON, from: @escaping (CatalogJSON) -> Value?) -> SettingRow {
            let word = words[id]
            return SettingRow(id: id, section: word?.group ?? .startUp, title: word?.title ?? id, about: word?.about ?? "", kind: kind,
                              field: .init(id, key, previews: true) { to($0).raw ?? "" }, get: { to($0[keyPath: key]) },
                              set: { settings, json in
                                  guard let value = from(json) else { return false }
                                  settings[keyPath: key] = value
                                  return true
                              })
        }
        func toggle(_ id: String, _ key: WritableKeyPath<AppSettings, Bool>) -> SettingRow {
            row(id, key, .toggle, to: CatalogJSON.bool, from: \.boolValue)
        }
        func choice<Value: Equatable>(_ id: String, _ key: WritableKeyPath<AppSettings, Value>, _ options: [(Value, String, String)]) -> SettingRow {
            row(id, key, .choice(options.map { (value: $0.1, label: $0.2) }),
                to: { value in .text(options.first { $0.0 == value }?.1) },
                from: { json in options.first { $0.1 == json.stringValue }?.0 })
        }
        func slider(_ id: String, _ key: WritableKeyPath<AppSettings, Double>, _ range: ClosedRange<Double>, _ step: Double) -> SettingRow {
            row(id, key, .slider(range, step: step), to: { .number($0) }, from: { json in
                json.double.map { min(range.upperBound, max(range.lowerBound, (($0 / step).rounded() * step * 1e6).rounded() / 1e6)) }
            })
        }
        let zoom = Double(InterfaceZoom.range.lowerBound)...Double(InterfaceZoom.range.upperBound)
        return [
            choice("appLanguage", \.appLanguage, [(.automatic, "auto", "Automatic"), (.english, "en", "English"), (.french, "fr", "Français")]),
            choice("startOn", \.startOn, [(.spotlight, "spotlight", "Spotlight"), (.collection, "collection", "Collection"),
                                          (.last, "last", "Where I left")]),
            toggle("restoreLastGame", \.restoreLastGame),
            toggle("startInFullscreen", \.startInFullscreen),
            row("colorThemeID", \.colorThemeID, .choice([]), to: CatalogJSON.string, from: \.stringValue),
            slider("interfaceZoom", \.interfaceZoom, zoom, Double(InterfaceZoom.step)),
            toggle("reduceMotion", \.reduceMotion),
            toggle("animatedBackground", \.animatedBackground),
            toggle("keepWallpaperOnGames", \.keepWallpaperOnGames),
            toggle("showClock", \.showClock),
            toggle("interfaceSounds", \.interfaceSounds),
            slider("soundVolume", \.soundVolume, 0...1, 0.05),
            choice("soundPack", \.soundPackID, [("oort", "oort", "Oort"), ("pollen", "pollen", "Pollen"), ("umbra", "umbra", "Umbra"),
                                                ("impulsion", "impulsion", "Impulsion")]),
            choice("noteFigure", \.noteFigure, figures.map { ($0, $0.rawValue, $1) }),
            row("noteOctave", \.noteOctave, .slider(-2...2, step: 1), to: { .number($0) },
                from: { $0.int.flatMap { OortSynth.octaves.contains($0) ? $0 : nil } }),
            toggle("showButtonHints", \.showButtonHints),
            choice("buttonNames", \.buttonNames, [(.automatic, "automatic", "Automatic"), (.nintendo, "nintendo", "Nintendo"),
                                                  (.xbox, "xbox", "Xbox"), (.playstation, "playstation", "PlayStation")]),
            toggle("viewButtonSwitches", \.viewButtonSwitches),
            choice("startingTab", \.startingTab, tabs.map { ($0.rawValue, $0.rawValue, $0.rawValue) }),
            choice("librarySort", \.librarySort, LibrarySort.allCases.map { ($0, $0.rawValue, $0.title) }),
            toggle("showsSessionCard", \.showsSessionCard),
        ]
    }()

    /// Named as in the Mac app (OortNotes).
    private static let figures: [(OortSynth.Figure, String)] = [
        (.rise, "Rise"), (.major, "Major"), (.pentatonic, "Pentatonic"), (.minor, "Minor"), (.arpeggio, "Arpeggio"), (.dream, "Dream"),
        (.moonlit, "Moonlit"), (.wave, "Wave"), (.descent, "Descent"),
    ]

    /// The tabs a library without a cloud has, five at most.
    static let tabs: [LibraryFilter] = [.all, .installed, .favorites, .recentlyPlayed, .notPlayed]

    /// Categories with something on this system, in the Mac app's order and groups.
    static let categories: [SettingsCategory] = [.general, .appearance, .sound, .controllers, .account, .home, .library, .integrations, .about]

    func json(_ values: AppSettings, saved: AppSettings) -> CatalogJSON {
        var out: [String: CatalogJSON] = ["id": .string(id), "title": .string(title), "about": .string(about), "section": .string(section.rawValue),
                                          "value": get(values), "pending": .bool(get(values) != get(saved)), "saved": get(saved),
                                          "changed": .bool(get(values) != get(AppSettings())), "default": get(AppSettings())]
        switch kind {
        case .toggle: out["kind"] = "toggle"
        case .choice(let options):
            out["kind"] = "choice"
            out["options"] = .array(options.map { ["value": .string($0.value), "label": .string($0.label)] })
        case .slider(let range, let step):
            out["kind"] = "slider"
            out["min"] = .number(range.lowerBound)
            out["max"] = .number(range.upperBound)
            out["step"] = .number(step)
        }
        return .object(out)
    }
}
