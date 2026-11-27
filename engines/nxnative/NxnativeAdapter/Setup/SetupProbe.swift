import Foundation
import OortLibrary

/// Gathers what the Setup check shows. Every command is cheap, so the screen can
/// run it every few seconds off the main thread.
public struct SetupProbe {
    private let runner: CommandRunning
    private let fileManager: FileManager
    private let toolchain: EngineToolchain
    private let developerDir: URL?
    private let engineFolder: URL
    private let certifiedMetal: String
    private let allowUntested: Bool
    private let libraryFolder: URL?
    private let sourcesFolder: URL?
    private let libraryNeedsConfirmation: Bool
    private let newestEngine: NewestEngineChoice?
    private let engineRemote: String?
    private let engine: MacNXNative

    package init(runner: any CommandRunning & Sendable, fileManager: FileManager = .default, toolchain: EngineToolchain,
                developerDir: URL?, engineFolder: URL, pinnedCommit: String, certifiedMetal: String,
                allowUntested: Bool, keysDirectory: URL, libraryFolder: URL?,
                sourcesFolder: URL? = nil, libraryNeedsConfirmation: Bool = false,
                newestEngine: NewestEngineChoice? = nil, engineRemote: String? = nil) {
        self.runner = runner
        self.fileManager = fileManager
        self.toolchain = toolchain
        self.developerDir = developerDir
        self.engineFolder = engineFolder
        self.engine = MacNXNative(place: Place(UUID()), checkout: engineFolder.path, prescribed: pinnedCommit,
                                  expected: newestEngine?.commit ?? pinnedCommit, keys: keysDirectory,
                                  developerDir: developerDir, runner: runner)
        self.certifiedMetal = certifiedMetal
        self.allowUntested = allowUntested
        self.libraryFolder = libraryFolder
        self.sourcesFolder = sourcesFolder
        self.libraryNeedsConfirmation = libraryNeedsConfirmation
        self.newestEngine = newestEngine
        self.engineRemote = engineRemote
    }

    package func workshop() -> Workshop { engine.workshop() }

    public func facts() -> SetupFacts {
        let snapshot = workshop()
        let xcode = xcode()
        var facts = SetupFacts(
            xcodeStatus: xcode.status,
            metalVersion: MetalVersion.parse(run("/usr/bin/xcrun", ["metal", "--version"]).stdout),
            certifiedMetal: certifiedMetal, allowUntested: allowUntested,
            engine: snapshot.checkout, engineFolder: engineFolder, pinnedCommit: snapshot.versions.reference,
            runtimeProblem: runtimeProblem(),
            keys: snapshot.localKeys, keysError: nil,
            libraryReadable: libraryFolder.map { readableDirectory($0) },
            xcodeVersion: xcode.version)
        let capabilities = EngineSourceCapabilities(repo: engineFolder)
        facts.keysOptional = capabilities.extractedFolders
        facts.libraryFolder = libraryFolder
        facts.libraryWritable = libraryFolder.map { GameAppDestination.folderProblem(at: $0) == nil }
        facts.libraryNeedsConfirmation = libraryNeedsConfirmation
        facts.newestEngine = newestEngine
        facts.engineRemote = engineRemote
        facts.runtimeIsBundled = toolchain.isBundled
        facts.sourcesFolder = sourcesFolder
        facts.sourcesReadable = sourcesFolder.map { readableDirectory($0) }
        facts.extractedFoldersSupported = capabilities.extractedFolders
        return facts
    }

    private func readableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue && fileManager.isReadableFile(atPath: url.path)
    }

    private func run(_ executable: String, _ args: [String], in directory: URL? = nil) -> CommandResult {
        let env = toolchain.environment(base: ProcessInfo.processInfo.environment, developerDir: developerDir)
        return (try? runner.run(URL(fileURLWithPath: executable), args, environment: env, currentDirectory: directory))
            ?? CommandResult(status: -1, stdout: "", stderr: "failed")
    }

    private func xcode() -> (status: Int32?, version: String?) {
        if let developerDir, !fileManager.fileExists(atPath: developerDir.path) { return (nil, nil) }
        let result = run("/usr/bin/xcodebuild", ["-version"])
        // 69 (EX_UNAVAILABLE) is xcodebuild's answer before the licence is accepted.
        guard result.status == 0 || result.status == 69 else { return (nil, nil) }
        return (result.status, ToolchainRequirements.xcodeVersion(from: result.stdout))
    }

    private func runtimeProblem() -> String? {
        // -I ignores PYTHONDONTWRITEBYTECODE; -B keeps __pycache__ out of a bundled runtime,
        // whose new files would break the app's code signature.
        let modules = run(toolchain.python.path,
                          ["-I", "-B", "-c", "import capstone, lz4.block, fontTools, zbic, nsz; assert capstone.cs_version()[0] == 5"])
        if modules.status != 0 { return "Python or its modules (capstone 5, lz4, fontTools, zbic, nsz) did not start" }
        for tool in ["zstd", "glslangValidator", "make"] where run("/usr/bin/env", [tool, "--version"]).status != 0 {
            return "\(tool) did not run"
        }
        return nil
    }
}
