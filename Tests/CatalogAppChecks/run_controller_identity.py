#!/usr/bin/env python3
"""Run after a debug swift build; the real service is driven only by synthetic sources."""
from pathlib import Path
import os
import platform
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
products = root / ".build/debug"
services = root / "Sources/NXLibrary/Services"
files = ["ControllerSource", "ControllerHardwareID", "ControllerRoster", "ControllerLive", "GameControllerService",
         "GCControllerSource", "HIDControllerSource"]
archive = products / "libNXLibraryCore.a"
if archive.is_file():
    modules, core = products, [archive]
else:
    modules = products / "Modules"
    core = [p for target in ("NXLibraryCore", "OortCore") for p in sorted((products / f"{target}.build").glob("*.swift.o"))]
if not core:
    raise SystemExit("Run a debug swift build --jobs 4 first")

with tempfile.TemporaryDirectory(prefix="hid-", dir="/private/tmp") as scratch:
    executable = Path(scratch) / "controller-identity"
    subprocess.run(["swiftc", "-j", "4", "-target", f"{platform.machine()}-apple-macosx26.0",
                    "-I", modules, root / "Sources/NXLibrary/Models/GamepadType.swift",
                    *(services / (name + ".swift") for name in files), *core,
                    Path(__file__).with_name("ControllerIdentityProbe.swift"), "-o", executable], cwd=root, check=True)
    subprocess.run([executable, *sys.argv[1:]], check=True,
                   env=dict(os.environ, HOME=scratch, CFFIXED_USER_HOME=scratch))
