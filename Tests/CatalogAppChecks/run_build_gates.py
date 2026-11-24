#!/usr/bin/env python3
"""Exercise the final build gate without a real engine, game, or player profile."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "Sources/NXLibrary/ViewModels/PortingModel+Build.swift").read_text()


def declaration(signature):
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
    }
    var app = App()
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
if failures != 0 { exit(1) }
print("Build gate: engine switch: PASS")
"""

with tempfile.TemporaryDirectory(prefix="arcane-build-gate-") as directory:
    main = Path(directory) / "main.swift"
    executable = main.with_suffix("")
    main.write_text(host.replace("// RULES", declaration("private func checkBuildIdle(")))
    subprocess.run(["xcrun", "swiftc", str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
