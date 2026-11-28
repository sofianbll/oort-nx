#!/usr/bin/env python3
"""Run after a debug swift build; the real service is driven only by synthetic sources."""
from pathlib import Path
import os
import platform
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(root / "scripts"))
import probe_start  # noqa: E402  every probe that links the core starts in ProbeStart.swift
services = root / "apps/mac/OortMac/Services"
files = ["ControllerSource", "ControllerHardwareID", "ControllerRoster", "ControllerLive", "GameControllerService",
         "GCControllerSource", "HIDControllerSource"]
modules, core = probe_start.library(root)

with tempfile.TemporaryDirectory(prefix="hid-", dir="/private/tmp") as scratch:
    executable = Path(scratch) / "controller-identity"
    subprocess.run(["swiftc", "-j", "4", "-target", f"{platform.machine()}-apple-macosx26.0",
                    "-I", modules, root / "apps/mac/OortMac/Models/GamepadType.swift",
                    *(services / (name + ".swift") for name in files), *core,
                    Path(__file__).with_name("ControllerIdentityProbe.swift"), "-o", executable], cwd=root, check=True)
    subprocess.run([executable, *sys.argv[1:]], check=True,
                   env=dict(os.environ, HOME=scratch, CFFIXED_USER_HOME=scratch))
