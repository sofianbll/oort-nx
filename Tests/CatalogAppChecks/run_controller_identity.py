#!/usr/bin/env python3
"""Run after a debug swift build; the real service is driven only by synthetic sources."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
products = Path(subprocess.check_output(["swift", "build", "--jobs", "4", "--show-bin-path"], cwd=root, text=True).strip())
services = root / "Sources/NXLibrary/Services"
files = ["ControllerSource", "ControllerHardwareID", "ControllerRoster", "ControllerLive", "GameControllerService",
         "GCControllerSource", "HIDControllerSource"]
archive = products / "libNXLibraryCore.a"
if archive.is_file():
    modules, core = products, [archive]
else:
    modules, core = products / "Modules", sorted((products / "NXLibraryCore.build").glob("*.swift.o"))
if not core:
    raise SystemExit("Run a debug swift build --jobs 4 first")

with tempfile.TemporaryDirectory(prefix="controller-identity-") as scratch:
    executable = Path(scratch) / "controller-identity"
    subprocess.run(["swiftc", "-j", "4", "-target", f"{platform.machine()}-apple-macosx26.0",
                    "-I", modules, root / "Sources/NXLibrary/Models/GamepadType.swift",
                    *(services / (name + ".swift") for name in files), *core,
                    Path(__file__).with_name("ControllerIdentityProbe.swift"), "-o", executable], cwd=root, check=True)
    subprocess.run([executable], check=True)
