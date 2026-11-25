import Foundation
import OortCompanion

/// oort-core --data <folder> --resources <folder> --system windows|linux|macos [--home …] [--documents …] [--local …]
/// [--config …] [--languages fr,en]. Reads one JSON request per line, writes one JSON reply per line, ends with its input.
@main struct OortCoreProgram {
    static func main() {
        var options: [String: String] = [:]
        var arguments = CommandLine.arguments.dropFirst()
        while let name = arguments.popFirst(), name.hasPrefix("--") { options[String(name.dropFirst(2))] = arguments.popFirst() ?? "" }
        func folder(_ name: String) -> String { (options[name] ?? "").replacingOccurrences(of: "\\", with: "/") }
        do {
            guard !folder("data").isEmpty else { throw CocoaError(.fileNoSuchFile) }
            let companion = try Companion(.init(
                data: folder("data"), resources: folder("resources"), system: options["system"] ?? "linux", home: folder("home"),
                documents: folder("documents"), local: folder("local"), config: folder("config"),
                languages: (options["languages"] ?? "").split(separator: ",").map(String.init)))
            while let line = readLine(strippingNewline: true) {
                if line.isEmpty { continue }
                // The window may be gone before the answer.
                guard (try? FileHandle.standardOutput.write(contentsOf: Data((companion.answer(line) + "\n").utf8))) != nil else { return }
            }
        } catch {
            FileHandle.standardError.write(Data("oort-core: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
