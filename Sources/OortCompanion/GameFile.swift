import Foundation

/// A game's settings file. TOML and INI are edited line by line: comments, order and unknown keys stay as they are.
struct GameFile {
    enum Kind: String { case toml, ini, json }
    struct Failure: Error, Equatable { let code: String }

    let kind: Kind
    private(set) var text: String

    init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    /// The value of `Section/key`, exactly as the file writes it.
    func value(_ key: String) -> String? {
        if kind == .json {
            var at = try? Self.object(text) as Any
            for part in key.split(separator: "/") { at = (at as? [String: Any])?[String(part)] }
            return at.flatMap(Self.json)
        }
        let (section, name) = Self.split(key)
        var here = ""
        for line in Self.lines(text) {
            if let next = Self.section(line) { here = next } else if here == section, let pair = Self.pair(line), pair.key == name {
                return String(line[pair.value])
            }
        }
        return nil
    }

    mutating func set(_ key: String, _ value: String) throws {
        if kind == .json { return try setJSON(key, value) }
        // One line stays one line.
        guard !value.contains(where: \.isNewline) else { throw Failure(code: "value-lines") }
        let (section, name) = Self.split(key)
        let end = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = Self.lines(text), here = ""
        var last: Int? = section.isEmpty ? 0 : nil
        for index in lines.indices {
            if let next = Self.section(lines[index]) {
                here = next
                if here == section { last = index + 1 }
            } else if here == section, let pair = Self.pair(lines[index]) {
                if pair.key == name {
                    lines[index].replaceSubrange(pair.value, with: value)
                    text = lines.joined(separator: end) + end
                    return
                }
                last = index + 1
            }
        }
        let line = kind == .ini ? "\(name)=\(value)" : "\(name) = \(value)"
        if let last { lines.insert(line, at: last) } else {
            if let final = lines.last, !final.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines += ["[\(section)]", line]
        }
        text = lines.joined(separator: end) + end
    }

    /// A path as this kind of file writes one.
    static func quoted(_ path: String, _ kind: Kind) -> String {
        guard kind != .ini else { return path }
        return "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The same value, whatever the quotes or the case of a boolean.
    func same(_ a: String, _ b: String) -> Bool {
        func bare(_ t: String) -> String { t.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: ["\""]).lowercased() }
        if a == b { return true }
        if let x = Double(bare(a)), let y = Double(bare(b)) { return x == y }
        return bare(a) == bare(b)
    }

    /// A slider's number, printf style (`%d`, `%.2f`, `%g`).
    static func number(_ format: String, _ value: Double) -> String {
        guard let at = format.firstIndex(of: "%") else { return plain(value) }
        let spec = format[format.index(after: at)...]
        guard let letter = spec.firstIndex(where: { $0.isLetter }) else { return plain(value) }
        let places = spec[..<letter].hasPrefix(".") ? Int(spec[spec.index(after: spec.startIndex)..<letter]) : nil
        let text: String = switch spec[letter] {
        case "d", "i", "u": String(Int(value.rounded()))
        case "f": fixed(value, places ?? 6)
        default: plain(value)
        }
        return format[..<at] + text + spec[spec.index(after: letter)...]
    }

    private static func plain(_ value: Double) -> String {
        let rounded = (value * 1e6).rounded() / 1e6
        return rounded == rounded.rounded() && abs(rounded) < 1e15 ? String(Int(rounded)) : String(rounded)
    }

    private static func fixed(_ value: Double, _ places: Int) -> String {
        guard (0...9).contains(places) else { return plain(value) }
        let scale = pow(10, Double(places)), whole = (abs(value) * scale).rounded()
        guard whole < 1e15 else { return plain(value) }
        let digits = String(Int(whole)), padded = String(repeating: "0", count: max(0, places + 1 - digits.count)) + digits
        let sign = value < 0 && whole > 0 ? "-" : ""
        return places == 0 ? sign + padded : sign + padded.dropLast(places) + "." + padded.suffix(places)
    }

    // MARK: - Lines

    private static func lines(_ text: String) -> [String] {
        var out = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if out.last?.isEmpty == true { out.removeLast() }
        return out
    }

    private static func split(_ key: String) -> (String, String) {
        guard let slash = key.lastIndex(of: "/") else { return ("", key) }
        return (String(key[..<slash]), String(key[key.index(after: slash)...]))
    }

    private static func section(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), !t.hasPrefix("[["), let close = t.firstIndex(of: "]") else { return nil }
        return t[t.index(after: t.startIndex)..<close].trimmingCharacters(in: .whitespaces)
    }

    /// `key = value`, without the comment after it (a # inside quotes is part of the value).
    private static func pair(_ line: String) -> (key: String, value: Range<String.Index>)? {
        let t = line.drop { $0 == " " || $0 == "\t" }
        guard let first = t.first, !"#;[".contains(first), let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: ["\""])
        var start = line.index(after: equals)
        while start < line.endIndex, line[start].isWhitespace { start = line.index(after: start) }
        var quote: Character?, end = line.endIndex, at = start, previous: Character = "x"
        while at < line.endIndex {
            let c = line[at]
            if let open = quote { if c == open { quote = nil } } else if c == "\"" || c == "'" { quote = c }
            else if c == "#" || c == ";", at > start, previous.isWhitespace {
                end = at
                break
            }
            previous = c
            at = line.index(after: at)
        }
        while end > start, line[line.index(before: end)].isWhitespace { end = line.index(before: end) }
        return (key, start..<end)
    }

    // MARK: - JSON

    private static func object(_ text: String) throws -> [String: Any] {
        let clean = text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        if clean.allSatisfy(\.isWhitespace) { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: Data(clean.utf8)) as? [String: Any] else {
            throw Failure(code: "json-shape")
        }
        return root
    }

    private static func json(_ value: Any) -> String? {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) }
    }

    // shortcut: JSON comes back with its keys sorted; keep the file's own order if a game ever cares.
    private mutating func setJSON(_ key: String, _ value: String) throws {
        let new = (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)) ?? value
        func put(_ map: [String: Any], _ path: ArraySlice<String>) -> [String: Any] {
            var map = map
            guard let head = path.first else { return map }
            map[head] = path.count == 1 ? new : put(map[head] as? [String: Any] ?? [:], path.dropFirst())
            return map
        }
        let root = put(try Self.object(text), key.split(separator: "/").map(String.init)[...])
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        text = String(decoding: data, as: UTF8.self) + "\n"
    }
}
