#!/usr/bin/env python3
"""Run after a debug swift build; the real service is driven only by synthetic sources."""
from pathlib import Path
import os
import platform
import shlex
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "scripts"))
import names  # noqa: E402  architecture/names.json
build = root / ".build"
products = build / "debug"
services = root / "Sources/NXLibrary/Services"
files = ["ControllerSource", "ControllerHardwareID", "ControllerRoster", "ControllerLive", "GameControllerService",
         "GCControllerSource", "HIDControllerSource"]
intermediates = build / f"out/Intermediates.noindex/{names.PACKAGE}.build/Debug"
link_lists = [
    list((intermediates / f"{target}-t.build/Objects-normal").glob(f"*/{target}.LinkFileList"))
    for target in (names.LIBRARY, names.CORE)
]
archive = products / f"lib{names.LIBRARY}.a"
if all(len(matches) == 1 for matches in link_lists):
    modules = build / "out/Products/Debug"
    core = [obj for matches in link_lists for obj in shlex.split(matches[0].read_text())]
elif archive.is_file():
    modules, core = products, [archive]
else:
    modules = products / "Modules"
    core = [p for target in (names.LIBRARY, names.CORE) for p in sorted((products / f"{target}.build").glob("*.swift.o"))]
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
