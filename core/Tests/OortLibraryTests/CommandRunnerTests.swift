import XCTest
@testable import OortLibrary

final class CommandRunnerTests: XCTestCase {
    func testBoundedCommandPipesAreCloseOnExec() throws {
        let pipe = try BoundedCommandRunner.commandPipe()
        for end in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
            XCTAssertEqual(fcntl(end.fileDescriptor, F_GETFD), FD_CLOEXEC)
        }
    }

    func testChildUsesItsWorkingDirectoryAndDefaultSIGPIPE() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let shell = URL(fileURLWithPath: "/bin/sh")
        let runner = BoundedCommandRunner(seconds: 3, cancellation: .init())
        // Stdin configures the parent's broken-pipe policy before the child is spawned.
        let result = try runner.run(shell, ["-c", "pwd -P; /bin/cat >/dev/null; kill -PIPE $$; exit 0"],
                                    environment: [:], currentDirectory: directory, input: Data([1]))
        let workingPath = result.stdout.trimmingCharacters(in: .newlines)
        XCTAssertEqual(OortSystem.physicalSystemPath(workingPath), OortSystem.physicalSystemPath(directory.path))
        XCTAssertEqual(result.status, 128 + SIGPIPE)
    }

    func testCancellableCommandTerminatesRunningProcess() async throws {
        let started = expectation(description: "process is running")
        let task = Task {
            try await SystemCommandRunner().runCancellable(URL(fileURLWithPath: "/bin/sh"),
                ["-c", "printf 'ready\\n' >&2; exec /bin/sleep 10"], environment: nil) { line in
                if line == "ready" { started.fulfill() }
            }
        }
        await fulfillment(of: [started], timeout: 3)
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(3))
        }
    }

    func testCancellationDoesNotWaitForAnInheritedPipeOrIgnoredTerm() async throws {
        let started = expectation(description: "child inherited the output pipe")
        let task = Task {
            try await SystemCommandRunner().runCancellable(URL(fileURLWithPath: "/bin/sh"),
                ["-c", "trap '' TERM; /bin/sleep 2 & printf 'ready\\n' >&2; wait"], environment: [:]) { line in
                if line == "ready" { started.fulfill() }
            }
        }
        await fulfillment(of: [started], timeout: 3)
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { XCTAssertLessThan(start.duration(to: clock.now), .seconds(1)) }
    }

    func testDeadlineBoundsSilentChildAndBlockedStdin() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await SystemCommandRunner().runCancellable(URL(fileURLWithPath: "/bin/sleep"),
                ["4"], environment: [:], input: Data(repeating: 1, count: 512 * 1024), seconds: 0.25)
            XCTFail("The command outlasted its deadline")
        } catch is CommandDeadline {
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
        }
    }

    func testDrainsBothStreamsAfterLeaderExit() async throws {
        let result = try await SystemCommandRunner().runCancellable(URL(fileURLWithPath: "/bin/sh"),
            ["-c", "printf 'leader:'; (/bin/sleep 1.2; printf 'tail'; printf 'late\\n' >&2) & exit 0"],
            environment: [:], seconds: 8)
        XCTAssertEqual(result, CommandResult(status: 0, stdout: "leader:tail", stderr: "late\n"))
    }

    func testPostExitDrainStillHasDeadline() async throws {
        let start = ContinuousClock().now
        do {
            _ = try await SystemCommandRunner().runCancellable(URL(fileURLWithPath: "/bin/sh"),
                ["-c", "/bin/sleep 12 & exit 0"], environment: [:], seconds: 10)
            XCTFail("The command returned while a descendant still held the streams open")
        } catch is CommandDeadline {
            XCTAssertLessThan(start.duration(to: .now), .seconds(7))
        }
    }

    func testProgressExtendsAnInactivityDeadlineButRepeatedStatsDoNot() async throws {
        let runner = SystemCommandRunner(), shell = URL(fileURLWithPath: "/bin/sh")
        let progress: @Sendable (String) -> [Int64]? = { Int64($0).map { [$0] } }
        let result = try await runner.runCancellable(shell,
            ["-c", "for i in 1 2 3 4 5; do printf '%s\\n' \"$i\" >&2; /bin/sleep 0.2; done"],
            environment: [:], seconds: 0.7, activity: progress)
        XCTAssertEqual(result.status, 0)
        do {
            _ = try await runner.runCancellable(shell,
                ["-c", "for i in 1 2 3 4 5; do printf '1\\n' >&2; /bin/sleep 0.2; done"],
                environment: [:], seconds: 0.5, activity: progress)
            XCTFail("Repeated statistics kept an inactive process alive")
        } catch is CommandDeadline {}
    }

    @MainActor
    func testWaitingForExitDoesNotServiceTheMainRunLoop() async throws {
        try checkWaitingForExit()
    }

    @MainActor
    private func checkWaitingForExit() throws {
        let runner = SystemCommandRunner()
        let shell = URL(fileURLWithPath: "/bin/sh")
        // Close both pipes before exiting so even the synchronous path has to wait.
        let arguments = ["-c", "printf out; printf err >&2; exec 1>&- 2>&-; /bin/sleep 0.5; exit 7"]
        for streaming in [false, true] {
            let tick = expectation(description: "main run loop timer")
            let timer = Timer(timeInterval: 0, repeats: false) { _ in tick.fulfill() }
            RunLoop.main.add(timer, forMode: .default)
            defer { timer.invalidate() }

            let result = try streaming
                ? runner.stream(shell, arguments, environment: nil, currentDirectory: nil, onLine: { _ in })
                : runner.run(shell, arguments, environment: nil, currentDirectory: nil)

            XCTAssertTrue(timer.isValid, "Main run loop serviced while waiting (streaming: \(streaming))")
            XCTAssertEqual(result, CommandResult(status: 7, stdout: "out", stderr: "err"))
            wait(for: [tick], timeout: 1)
        }
    }
}
