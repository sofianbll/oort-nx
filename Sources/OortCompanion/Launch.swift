import Foundation
import NXLibraryCore

/// What to start, worked out here; the window's process starts and follows it.
struct Plan {
    var program: String
    var args: [String]
    var env: [String: String]
    var directory: String
    var folder: String

    var json: CatalogJSON {
        ["program": .string(Paths.native(program)), "args": .list(args), "env": .object(env.mapValues(CatalogJSON.string)),
         "directory": .string(Paths.native(directory)), "folder": .string(Paths.native(folder))]
    }
}

struct Launcher {
    let game: Game
    let state: GameState
    let shared: [String: String]
    let system: String
    var places: Places

    init(game: Game, state: GameState, shared: [String: String], base: Places, system: String) {
        (self.game, self.state, self.shared, self.system) = (game, state, shared, system)
        places = base
        places.install = game.folder
        for input in game.manifest?.inputs ?? [] {
            places.inputs.insert(input.id)
            places.picked[input.id] = picked(input)
        }
    }

    func picked(_ input: Manifest.Input) -> String? {
        let path = input.shared.map { shared[$0] } ?? state.inputs[input.id]
        return path.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    var inputs: [Manifest.Input] {
        game.manifest?.inputs(for: game.sub?.id, picked: places.picked) ?? []
    }

    /// Files the game cannot start without.
    var missing: [Manifest.Input] { inputs.filter { !$0.optional && picked($0) == nil } }

    // MARK: - Setup step

    var options: [Manifest.Option] {
        game.manifest?.prepare?.options.filter { $0.systems.isEmpty || $0.systems.contains(system) } ?? []
    }

    func isOn(_ option: Manifest.Option) -> Bool { state.options[option.id] ?? option.startsOn }

    /// What is installed now: a new release prepares again.
    var stamp: String? {
        guard let prepare = game.manifest?.prepare, let program = places.program(prepare.run.program) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: program)
        let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(Int(date))-\((attributes?[.size] as? NSNumber)?.intValue ?? 0)"
    }

    var needsPrepare: Bool {
        guard let prepare = game.manifest?.prepare else { return false }
        guard state.preparedFor != nil, state.preparedFor == stamp else { return true }
        return prepare.done.contains { text in
            guard let path = (try? places.fill(text)) ?? nil else { return true }
            return !FileManager.default.fileExists(atPath: path)
        }
    }

    var scratch: String { Paths.join(game.folder, ".recomplauncher-tmp") }
    static let room = 1_000_000_000

    func preparePlan() throws -> Plan {
        guard let manifest = game.manifest, let prepare = manifest.prepare else { throw Manifest.Failure(code: "nothing-to-prepare") }
        try refuse(manifest)
        if options.contains(where: { $0.required && !isOn($0) }) { throw Manifest.Failure(code: "option-required") }
        guard let program = places.program(prepare.run.program) else { throw Manifest.Failure(code: "program-missing") }
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: game.folder)[.systemFreeSize] as? NSNumber)?.intValue
        if let free, free < Self.room { throw Manifest.Failure(code: "disk-full") }
        // The format's own scratch folder, empty for each run.
        try? FileManager.default.removeItem(atPath: scratch)
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: places.data, withIntermediateDirectories: true)
        var env = try environment(prepare.run.env)
        for name in ["TMPDIR", "TEMP", "TMP"] { env[name] = Paths.native(scratch) }
        let chosen = try options.filter(isOn).flatMap { try places.fill($0.args) }
        return Plan(program: program, args: try places.fill(prepare.run.args) + chosen, env: env,
                    directory: (program as NSString).deletingLastPathComponent, folder: game.folder)
    }

    /// `progress 0.4 Unpacking` as the setup step prints it.
    static func progress(_ line: String) -> (value: Double, text: String)? {
        let words = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard words.count >= 2, words[0] == "progress", let value = Double(words[1]), value.isFinite else { return nil }
        return (min(1, max(0, value)), words.count > 2 ? String(words[2]) : "")
    }

    // MARK: - Play

    func plan(mode: String) throws -> Plan {
        if case .program(let p) = game.source {
            guard FileManager.default.isReadableFile(atPath: p.program) else { throw Manifest.Failure(code: "program-missing") }
            return Plan(program: p.program, args: p.args, env: [:], directory: game.folder, folder: game.folder)
        }
        guard let manifest = game.manifest else {
            if case .broken(let code) = game.source { throw Manifest.Failure(code: code) }
            throw Manifest.Failure(code: "program-missing")
        }
        try refuse(manifest)
        if needsPrepare { throw Manifest.Failure(code: "prepare-first") }
        guard let start = manifest.start, let program = places.program(start.program) else { throw Manifest.Failure(code: "program-missing") }
        try FileManager.default.createDirectory(atPath: places.data, withIntermediateDirectories: true)
        try writeConfigs(manifest)
        var args = try places.fill(start.args)
        for setting in manifest.settings where setting.within == "args" { args += try argument(setting) }
        args += try places.fill(game.sub?.args ?? [])
        var env = try environment(start.env)
        env["RECOMPLAUNCHER_MODE"] = mode
        return Plan(program: program, args: args, env: env, directory: (program as NSString).deletingLastPathComponent, folder: game.folder)
    }

    private func refuse(_ manifest: Manifest) throws {
        if let reason = manifest.unsupported.first { throw Manifest.Failure(code: "unsupported-" + reason) }
        if !missing.isEmpty { throw Manifest.Failure(code: "inputs-missing") }
    }

    private func argument(_ setting: Manifest.Setting) throws -> [String] {
        guard let value = state.args[setting.id] else { return try places.fill(setting.choices.first?.args ?? []) }
        if let slider = setting.slider {
            let text = GameFile.number(slider.format, value)
            return try places.fill(slider.args).map { $0.replacingOccurrences(of: "{value}", with: text) }
        }
        let index = Int(value)
        return setting.choices.indices.contains(index) ? try places.fill(setting.choices[index].args) : []
    }

    /// The names games written for this format read, whoever starts them.
    private func environment(_ own: [String: String]) throws -> [String: String] {
        var env: [String: String] = [:]
        for (name, value) in own where Places.mayName(name) { env[name] = try places.fill(value) }
        env["RECOMPLAUNCHER"] = "1"
        env["RECOMPLAUNCHER_PAD"] = places.pad
        env["RECOMPLAUNCHER_DATA"] = Paths.native(places.data)
        return env
    }

    // MARK: - Settings files

    func file(_ config: Manifest.Config) throws -> (path: String, file: GameFile)? {
        guard let kind = GameFile.Kind(rawValue: config.format), let path = try places.place(config.places) else { return nil }
        guard places.mayWrite(path) else { throw Manifest.Failure(code: "config-place") }
        guard FileManager.default.fileExists(atPath: path) else { return (path, GameFile(kind: kind, text: "")) }
        // A file that is not text is never rewritten.
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            throw Manifest.Failure(code: "config-unreadable")
        }
        return (path, GameFile(kind: kind, text: text))
    }

    static func save(_ file: GameFile, _ path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(file.text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func writeConfigs(_ manifest: Manifest) throws {
        for config in manifest.configs {
            guard var (path, file) = try file(config) else { continue }
            let before = file.text, isNew = !FileManager.default.fileExists(atPath: path)
            func put(_ values: [String: String]) throws {
                for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                    if let filled = try places.fill(value) { try file.set(key, filled) }
                }
            }
            if isNew { try put(config.new) }
            try put(config.ensure.filter { key, _ in ["", "\"\""].contains(file.value(key) ?? "") })
            try put(config.always)
            if let key = config.gamePath, let copy = places.picked["game"] {
                try file.set(key, GameFile.quoted(Paths.native(copy), file.kind))
            }
            if file.text != before { try Self.save(file, path) }
        }
    }

    /// A setting as it stands: its choice or its number, and whether it applies now.
    func shown(_ setting: Manifest.Setting) throws -> CatalogJSON {
        var out: [String: CatalogJSON] = ["id": .string(setting.id), "label": .string(setting.label), "help": .text(setting.help),
                                          "group": .text(setting.group), "advanced": .bool(setting.advanced)]
        if setting.isBindings {
            // Key bindings stay in the game's own menu.
            out["kind"] = "elsewhere"
            return .object(out)
        }
        let config = game.manifest?.configs.first { $0.id == setting.within }
        let file = try config.flatMap { try self.file($0) }?.file
        func value(_ key: String) -> String? { file?.value(key) ?? setting.defaults[key] }
        func matches(_ values: [String: String]) -> Bool {
            values.allSatisfy { key, wanted in value(key).map { (file ?? GameFile(kind: .toml, text: "")).same($0, wanted) } ?? false }
        }
        out["enabled"] = .bool(setting.when.isEmpty || matches(setting.when))
        if let slider = setting.slider {
            let own = setting.within == "args" ? state.args[setting.id]
                : slider.key.flatMap(value).flatMap { Double($0.trimmingCharacters(in: ["\""])) }
            let number = own ?? slider.key.flatMap { setting.defaults[$0] }.flatMap(Double.init) ?? slider.min
            out["kind"] = "slider"
            out["min"] = .number(slider.min)
            out["max"] = .number(slider.max)
            out["step"] = .number(slider.step)
            out["value"] = .number(number)
            out["text"] = .string(GameFile.number(slider.format, number))
        } else {
            let index = setting.within == "args" ? Int(state.args[setting.id] ?? 0) : setting.choices.firstIndex { matches($0.set) }
            out["kind"] = "choice"
            out["choices"] = .list(setting.choices.map(\.label))
            out["value"] = index.map { .number($0) } ?? .null
            // A value set in the game's own menu shows as it is.
            if index == nil, let key = setting.choices.first?.set.keys.sorted().first { out["text"] = .text(value(key)) }
        }
        return .object(out)
    }

    /// Writes a setting kept in a file; the ones passed as arguments are kept with the game.
    func write(_ setting: Manifest.Setting, _ number: Double) throws {
        guard let config = game.manifest?.configs.first(where: { $0.id == setting.within }), var (path, file) = try file(config) else {
            throw Manifest.Failure(code: "config-missing")
        }
        if let slider = setting.slider {
            guard let key = slider.key, (slider.min...slider.max).contains(number) else { throw Manifest.Failure(code: "value") }
            try file.set(key, GameFile.number(slider.format, number))
        } else {
            guard setting.choices.indices.contains(Int(number)) else { throw Manifest.Failure(code: "value") }
            for (key, value) in setting.choices[Int(number)].set.sorted(by: { $0.key < $1.key }) { try file.set(key, value) }
        }
        try Self.save(file, path)
    }
}
