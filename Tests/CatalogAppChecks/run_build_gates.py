#!/usr/bin/env python3
"""Exercise the final build gate without a real engine, game, or player profile."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "Sources/NXLibrary/ViewModels/PortingModel+Build.swift").read_text()
move_source = (ROOT / "Sources/NXLibrary/ViewModels/AppViewModel+CloudLibraryMove.swift").read_text()
activity = (ROOT / "Sources/NXLibrary/Views/Shell/ActivityCenterView.swift").read_text()
assert "case .build: return viewModel.isBuilding && !porting.isInstallingBuild" in activity
assert "case .move: return cloudLibrary.libraryMove?.canCancel == true" in activity
assert "cloud.libraryMove?.isVerifying = done == total" in move_source


def declaration(signature, source=source):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


host = """
import Foundation
struct PortedGame { var id = UUID() }
struct RunningGameMonitor { static func runningApplication(for game: PortedGame) -> Bool? { nil } }
enum L10n { static func text(_ value: String) -> String { value } }
enum NXLibraryError: Error { case buildAlreadyRunning, environmentBlocked(String) }
enum CloudArchiveError: Error { case busy }
struct LogEntry {
    enum Level { case warning }
    var level: Level
    var message: String
}
struct BuildService {
    var acceptsCancellation = false
    @discardableResult func cancel() -> Bool { acceptsCancellation }
}
struct LibraryMoveRequest {}
// MOVE_STATE
struct BuildHost {
    struct App {
        struct Cloud { var isChangingConnection = false; var isWorking = false; func conflicts(with: Int) -> Bool { false } }
        struct Icon { var appIconsInFlight: Set<UUID> = [] }
        struct Setup { var isSwitchingEngine = false }
        var cloudLibrary = Cloud()
        var appIcon = Icon()
        var setup = Setup()
        var isBuilding = false
        var isCleaningStorage = false
        var isUpdatingApp = false
        var logs: [LogEntry] = []
    }
    var app = App()
    var buildService: BuildService? = BuildService()
    var isCancellingBuild = false
    var currentStageName = "Installing"
    func stopStageElapsedTimer() {}
    func buildScope(for game: PortedGame) -> Int { 0 }
    // RULES
    func allowsBuild() -> Bool { (try? checkBuildIdle(for: PortedGame())) != nil }
}
var fixture = BuildHost()
var failures = 0
func require(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: " + message); failures += 1 }
}
require(fixture.allowsBuild(), "idle engine can build")
fixture.app.setup.isSwitchingEngine = true
require(!fixture.allowsBuild(), "build cannot start during an engine switch")
fixture.app.setup.isSwitchingEngine = false
require(fixture.allowsBuild(), "build can start after the engine switch")
fixture.app.isBuilding = true
fixture.cancelBuild()
require(!fixture.isCancellingBuild && fixture.app.logs.isEmpty,
        "a cancellation rejected by the worker does not show Cancelling during installation")
fixture.buildService?.acceptsCancellation = true
fixture.cancelBuild()
require(fixture.isCancellingBuild, "a cancellation accepted by the worker is shown")
var move = LibraryMoveActivity(id: UUID(), request: LibraryMoveRequest())
require(move.canCancel, "a move can be cancelled before completion")
move.isCancelling = true
require(!move.canCancel, "a cancelling move cannot be cancelled again")
move.isCancelling = false
move.isVerifying = true
require(move.canCancel, "read-only move verification remains cancellable")
move.isCancelling = true
require(!move.canCancel, "verification cancellation cannot be requested twice")
if failures != 0 { exit(1) }
print("Build gates: engine switch, cancellation: PASS")
"""

with tempfile.TemporaryDirectory(prefix="arcane-build-gate-") as directory:
    main = Path(directory) / "main.swift"
    executable = main.with_suffix("")
    rules = [declaration("private func checkBuildIdle("), declaration("func cancelBuild(").replace("func cancelBuild(", "mutating func cancelBuild(", 1)]
    main.write_text(host.replace("// RULES", "\n".join(rules))
                    .replace("// MOVE_STATE", declaration("struct LibraryMoveActivity", move_source)))
    subprocess.run(["xcrun", "swiftc", str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
