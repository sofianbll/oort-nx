import Foundation
import Synchronization

public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning {
    func run(_ executable: URL, _ arguments: [String],
             environment: [String: String]?,
             currentDirectory: URL?) throws -> CommandResult
}

/// Keeps no state, so the background tasks that run commands can share it.
public final class SystemCommandRunner: CommandRunning, Sendable {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String],
                    environment: [String: String]?,
                    currentDirectory: URL?) throws -> CommandResult {
        try execute(executable, arguments, environment: environment, currentDirectory: currentDirectory)
    }

    /// Runs like `run`, and hands every line of either pipe to `onLine` as it
    /// arrives (on a background queue), for installs that report progress.
    public func stream(_ executable: URL, _ arguments: [String],
                       environment: [String: String]?, currentDirectory: URL?,
                       onLine: @escaping @Sendable (String) -> Void) throws -> CommandResult {
        try execute(executable, arguments, environment: environment, currentDirectory: currentDirectory,
                    onStdout: onLine, onStderr: onLine)
    }

    /// Runs off the caller's executor and terminates the subprocess on cancellation.
    package func runCancellable(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                                input: Data? = nil, output: FileHandle? = nil, seconds: Double = 60,
                                activity: (@Sendable (String) -> [Int64]?)? = nil,
                                onStderr: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        try await withBoundedCommands(seconds: seconds) { runner in
            try runner.run(executable, arguments, environment: environment, input: input, output: output,
                           onStderr: onStderr, activity: activity)
        }
    }

    package func withCancellableCommands<T: Sendable>(_ work: @escaping @Sendable (CommandRunning) throws -> T) async throws -> T {
        try await withBoundedCommands(seconds: 60) { try work($0) }
    }

    static func runBounded(_ executable: URL, _ arguments: [String], seconds: Double) throws -> CommandResult {
        try BoundedCommandRunner(seconds: seconds, cancellation: .init())
            .run(executable, arguments, environment: [:], input: nil)
    }

    package static func stopCloudProcesses() { BoundedChild.stopAll() }

    private func withBoundedCommands<T: Sendable>(seconds: Double,
                                                  _ work: @escaping @Sendable (BoundedCommandRunner) throws -> T) async throws -> T {
        let cancellation = CommandCancellation()
        return try await withTaskCancellationHandler {
            let result: Result<T, Error> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Result {
                        try work(BoundedCommandRunner(seconds: seconds, cancellation: cancellation))
                    })
                }
            }
            try Task.checkCancellation()
            return try result.get()
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func execute(_ executable: URL, _ arguments: [String],
                         environment: [String: String]?, currentDirectory: URL?,
                         onStdout: (@Sendable (String) -> Void)? = nil,
                         onStderr: (@Sendable (String) -> Void)? = nil) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        if let environment { process.environment = environment }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let group = DispatchGroup()
        let waitForExit = try process.runWithExitWait()

        let collected = Mutex([Data(), Data()])
        for (slot, pipe) in [out, err].enumerated() {
            let onLine = slot == 0 ? onStdout : onStderr
            let buffer = Mutex(LineBuffer())
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    if let onLine { buffer.withLock { $0.finish() }.forEach(onLine) }
                    group.leave()
                    return
                }
                collected.withLock { $0[slot].append(chunk) }
                if let onLine { buffer.withLock { $0.append(chunk) }.forEach(onLine) }
            }
        }
        waitForExit()
        group.wait()
        func decode(_ data: Data) -> String {
            onStdout == nil && onStderr == nil ? (String(data: data, encoding: .utf8) ?? "") : String(decoding: data, as: UTF8.self)
        }
        let output = collected.withLock { $0 }
        return CommandResult(status: process.terminationStatus, stdout: decode(output[0]), stderr: decode(output[1]))
    }
}

extension Process {
    /// Starts the process and returns the wait for its end, which blocks without running the current run loop.
    /// `waitUntilExit` runs it while it waits, so a command awaited inside a SwiftUI update (Game options reading the
    /// engine's ancestry) let SwiftUI start another update inside the first and abort. Call the wait once.
    public func runWithExitWait() throws -> () -> Void {
        try runWithExitWait(launch: run)
    }

    fileprivate func runWithExitWait(launch: () throws -> Void) throws -> () -> Void {
        let exited = DispatchSemaphore(value: 0)
        let previous = terminationHandler
        // Set before `run`, so an end that comes at once is never missed.
        terminationHandler = { process in
            previous?(process)
            exited.signal()
        }
        try launch()
        return { exited.wait() }
    }
}

final class CommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }

    func cancel() { lock.withLock { cancelled = true } }
}
