import Foundation
@preconcurrency import NXLibraryCore

/// The app's own folder: one JSON file per subject, written whole or not at all.
struct Store {
    let folder: String

    init(folder: String) throws {
        self.folder = folder
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL { URL(fileURLWithPath: Paths.join(folder, name + ".json")) }

    /// A file that does not read is set aside, never overwritten.
    func read<Value: Decodable>(_ name: String, _ empty: Value) -> Value {
        guard let data = try? Data(contentsOf: url(name)) else { return empty }
        if let value = try? Self.decoder.decode(Value.self, from: data) { return value }
        let aside = url("\(name)-unreadable-\(Int(Date.now.timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: url(name), to: aside)
        return empty
    }

    func write(_ name: String, _ value: some Encodable) throws {
        try Self.encoder.encode(value).write(to: url(name), options: .atomic)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Where the games are. Everything the Mac app already stores elsewhere (settings, profiles, sessions) has its own file.
struct Shelf: Codable, Equatable {
    var folders: [String] = []
    var programs: [Program] = []
    /// A file several games ask for, by its shared name. Only its path is kept; it is never read or copied.
    var shared: [String: String] = [:]
    var games: [String: GameState] = [:]
}

/// Any program with arguments: an emulator with a game, a game without a manifest.
struct Program: Codable, Equatable {
    var key: String
    var name: String
    var program: String
    var args: [String]
}

struct GameState: Codable, Equatable {
    var inputs: [String: String] = [:]
    /// Settings passed on the command line: the choice's place, or the slider's number.
    var args: [String: Double] = [:]
    var options: [String: Bool] = [:]
    /// What was installed when the setup step last finished.
    var preparedFor: String?
}

struct Profiles: Codable {
    var list: [LocalProfile] = []
    var active: UUID?
}
