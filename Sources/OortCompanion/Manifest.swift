import Foundation
import NXLibraryCore

/// recomplauncher.json, format 1: what a game needs, how it starts and which settings it has.
///
/// The format is RecompLauncher SDK's, by Ripalda (MIT): https://github.com/elripalda/RecompLauncher-SDK.
/// This reader was written from its schema and guide; no code was taken from RecompLauncher (GPL-3.0).
/// Unknown keys are ignored, as releases in the wild carry keys newer than the schema.
struct Manifest: Sendable {
    struct Failure: Error, Equatable { let code: String }

    struct Input: Sendable {
        var id = "", label = "", role = "game"
        var optional = false
        var shared: String?
        var formats: [Format] = []
        var checkFile: String?
        /// The manifest names a check this reader does not do (disc serials, build IDs…): said to the player.
        var unchecked = false
        /// The launcher should copy or unpack the file into the game's folder, which this one does not do.
        var placed = false
    }

    struct Format: Sendable {
        var isFolder = false
        var extensions: [String] = []
        var requires: [String] = []
    }

    struct Run: Sendable {
        var program: [String] = []
        var args: [String] = []
        var env: [String: String] = [:]
    }

    struct Prepare: Sendable {
        var run = Run()
        var label: String?
        var done: [String] = []
        var keepsCopy = false
        var options: [Option] = []
    }

    struct Option: Sendable {
        var id = "", label = ""
        var note: String?
        var args: [String] = []
        var systems: [String] = []
        var license: (name: String, url: String)?
        var startsOn = true
        var required = false
    }

    struct Config: Sendable {
        var id = "main", format = ""
        var places: [Place] = []
        var gamePath: String?
        var ensure: [String: String] = [:], always: [String: String] = [:], new: [String: String] = [:]
    }

    struct Place: Sendable {
        var path = ""
        var when: String?
    }

    struct Setting: Sendable {
        var id = "", label = "", within = "main"
        var help: String?, group: String?
        var choices: [Choice] = []
        var slider: Slider?
        var isBindings = false
        var defaults: [String: String] = [:], when: [String: String] = [:]
        var advanced = false
    }

    struct Choice: Sendable {
        var label = ""
        var set: [String: String] = [:]
        var args: [String] = []
    }

    struct Slider: Sendable {
        var key: String?
        var min = 0.0, max = 1.0, step = 0.01
        var format = "%g"
        var args: [String] = []
    }

    struct SubGame: Sendable {
        var id = "", name = ""
        var args: [String] = [], inputs: [String] = []
    }

    struct Action: Sendable {
        var id = "", label = ""
        var help: String?, open: String?
    }

    static let fileName = "recomplauncher.json"
    /// The guide's own limit for a manifest.
    static let maxBytes = 1 << 20

    var name: String?, repo: String?
    var inputs: [Input] = []
    var start: Run?
    var prepare: Prepare?
    var configs: [Config] = []
    var settings: [Setting] = []
    var games: [SubGame] = []
    var folders: [String: [Place]] = [:]
    var exitCodes: [String: String] = [:]
    var actions: [Action] = []

    init(folder: URL) throws {
        let file = folder.appendingPathComponent(Self.fileName)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue,
              size <= Self.maxBytes, let data = try? Data(contentsOf: file) else { throw Failure(code: "manifest-unreadable") }
        try self.init(data)
    }

    init(_ data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        let clean = text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        guard let root = try? JSONDecoder().decode(CatalogJSON.self, from: Data(clean.utf8)), case .object = root else {
            throw Failure(code: "manifest-json")
        }
        guard root["format"]?.int == 1 else { throw Failure(code: "manifest-format") }
        name = root["name"]?.stringValue
        repo = root["repo"]?.stringValue
        inputs = root["inputs"].items.map(Self.input)
        if let old = root["game"] { takeOldGame(old) }
        start = root["start"].map(Self.run)
        prepare = root["prepare"].map(Self.prepare)
        configs = root["config"].items.map {
            Config(id: $0["id"]?.stringValue ?? "main", format: $0["format"]?.stringValue ?? "", places: Self.places($0["file"]),
                   gamePath: $0["game_path"]?.stringValue, ensure: $0["ensure"].values, always: $0["always"].values,
                   new: $0["new"].values)
        }
        let advancedGroups = Set(root["groups"].items.filter { $0["advanced"] == .bool(true) }.compactMap { $0["id"]?.stringValue })
        settings = root["settings"].items.map { Self.setting($0, advancedGroups: advancedGroups) }
        games = root["games"].items.map {
            SubGame(id: $0["id"]?.stringValue ?? "", name: $0["name"]?.stringValue ?? "", args: $0["args"].strings,
                    inputs: $0["inputs"].strings)
        }.filter { !$0.id.isEmpty }
        if games.count < 2 { games = [] }
        if case .object(let named)? = root["folders"] { folders = named.mapValues { Self.places($0) } }
        exitCodes = root["exit_codes"].values
        actions = root["actions"].items.map {
            Action(id: $0["id"]?.stringValue ?? "", label: $0["label"]?.stringValue ?? "", help: $0["help"]?.stringValue,
                   open: $0["open"]?.stringValue)
        }
    }

    // MARK: - Reading

    private static func input(_ json: CatalogJSON) -> Input {
        let check = json["check"]
        var others = false
        if case .object(let members)? = check { others = members.keys.contains { $0 != "file" } }
        return Input(id: json["id"]?.stringValue ?? "", label: json["label"]?.stringValue ?? "",
                     role: json["role"]?.stringValue ?? "game", optional: json["optional"] == .bool(true),
                     shared: json["shared"]?.stringValue,
                     formats: json["formats"].items.map {
                         Format(isFolder: $0["type"]?.stringValue == "folder",
                                extensions: $0["extensions"].strings.map { $0.lowercased() }, requires: $0["requires"].strings)
                     },
                     checkFile: check?["file"]?.stringValue,
                     unchecked: others || json["sha256"] != nil || json["dumps"] != nil,
                     placed: json["into"] != nil || json["destination"] != nil || json["extract"] != nil)
    }

    /// The deprecated top-level `game` reads as the inputs `game` and `update`.
    private mutating func takeOldGame(_ old: CatalogJSON) {
        func formats(_ kind: String?) -> [Format] {
            switch kind {
            case "folder": [Format(isFolder: true)]
            case "iso_or_folder", "file or folder": [Format(), Format(isFolder: true)]
            default: [Format()]
            }
        }
        if !inputs.contains(where: { $0.id == "game" }) {
            var game = Self.input(old)
            game.id = "game"
            game.formats = formats(old["kind"]?.stringValue)
            inputs.insert(game, at: 0)
        }
        if let update = old["update"], !inputs.contains(where: { $0.id == "update" }) {
            var second = Self.input(update)
            second.id = "update"
            second.role = "update"
            second.formats = formats(update["accepts"]?.stringValue)
            inputs.append(second)
        }
    }

    private static func run(_ json: CatalogJSON) -> Run {
        Run(program: json["program"].strings, args: json["args"].strings, env: json["env"].values)
    }

    private static func prepare(_ json: CatalogJSON) -> Prepare {
        Prepare(run: run(json), label: json["label"]?.stringValue, done: json["done"].strings,
                keepsCopy: json["keeps_copy"] == .bool(true),
                options: json["options"].items.map { option in
                    let license = option["license"].flatMap { l in l["name"]?.stringValue.map { ($0, l["url"]?.stringValue ?? "") } }
                    return Option(id: option["id"]?.stringValue ?? "", label: option["label"]?.stringValue ?? "",
                                  note: option["note"]?.stringValue, args: option["args"].strings, systems: option["os"].strings,
                                  license: license,
                                  // With a licence only the player ticks it.
                                  startsOn: license == nil && option["default"] != .bool(false),
                                  required: option["required"] == .bool(true))
                })
    }

    private static func setting(_ json: CatalogJSON, advancedGroups: Set<String>) -> Setting {
        let group = json["group"]?.stringValue
        let slider = json["slider"].map { s -> Slider in
            let low = s["min"]?.double ?? 0, high = s["max"]?.double ?? 1
            let own = s["args"].strings
            return Slider(key: s["key"]?.stringValue, min: low, max: high, step: s["step"]?.double ?? max((high - low) / 100, .ulpOfOne),
                          format: s["format"]?.stringValue ?? "%g", args: own.isEmpty ? json["args"].strings : own)
        }
        return Setting(id: json["id"]?.stringValue ?? "", label: json["label"]?.stringValue ?? "",
                       within: json["in"]?.stringValue ?? "main", help: json["help"]?.stringValue, group: group,
                       choices: json["choices"].items.map {
                           Choice(label: $0["label"]?.stringValue ?? "", set: $0["set"].values, args: $0["args"].strings)
                       },
                       slider: slider, isBindings: json["bindings"] != nil, defaults: json["defaults"].values,
                       when: json["when"].values,
                       advanced: json["advanced"] == .bool(true) || group.map(advancedGroups.contains) == true)
    }

    private static func places(_ json: CatalogJSON?) -> [Place] {
        json.items.compactMap { item in
            item["path"]?.stringValue.map { Place(path: $0, when: item["if"]?.stringValue) }
        }
    }

    // MARK: - What a game needs

    /// The inputs one game of the release needs: its own, and the ones no game claims. A shared key that a format asks
    /// for counts only when that format was picked.
    func inputs(for sub: String?, picked: [String: String]) -> [Input] {
        let own = Set(games.first { $0.id == sub }?.inputs ?? [])
        let claimed = Set(games.flatMap(\.inputs))
        let named = Set(inputs.flatMap(\.formats).flatMap(\.requires))
        let asked = Set(inputs.flatMap { input in
            picked[input.id].flatMap { input.format(of: $0)?.requires } ?? []
        })
        return inputs.filter { (own.contains($0.id) || !claimed.contains($0.id)) && (!named.contains($0.id) || asked.contains($0.id)) }
    }

    /// What this reader does not do for the game, said on its page rather than half done.
    var unsupported: [String] {
        var out: [String] = []
        if inputs.contains(where: { $0.placed && !$0.optional }) { out.append("placing") }
        if inputs.contains(where: { $0.shared == "nvidia.dlss" && !$0.optional }) { out.append("download") }
        return out
    }
}

extension Manifest.Input {
    /// The first format the path on disk fits.
    func format(of path: String) -> Manifest.Format? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        return formats.first { $0.isFolder == isFolder.boolValue && (isFolder.boolValue || $0.extensions.isEmpty || $0.extensions.contains(ext)) }
    }
}

extension CatalogJSON {
    var int: Int? { if case .number(let n) = self { NSDecimalNumber(decimal: n).intValue } else { nil } }
    var double: Double? { if case .number(let n) = self { NSDecimalNumber(decimal: n).doubleValue } else { nil } }
    /// The value as a manifest writes it in a settings file: strings as they are, the rest as text.
    var raw: String? {
        switch self {
        case .string(let s): s
        case .number(let n): "\(n)"
        case .bool(let b): b ? "true" : "false"
        default: nil
        }
    }
}

extension Optional where Wrapped == CatalogJSON {
    var items: [CatalogJSON] { if case .array(let items)? = self { items } else { [] } }
    var strings: [String] { items.compactMap(\.stringValue) }
    var values: [String: String] {
        if case .object(let members)? = self { members.compactMapValues(\.raw) } else { [:] }
    }
}
