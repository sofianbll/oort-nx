#!/usr/bin/env python3
"""Render real Spotlight screens and send rail commands without opening a window or starting a game."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

from audit_probe_host import run_host

def run(output):
    run_host(Path(__file__).with_name("PlatformCardsProbe.swift").read_text(), save_model=True, capture=output)
    if ffmpeg := shutil.which("ffmpeg"):
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-n", "-framerate", "24", "-i",
                        str(output / "frames/%02d.png"), "-vf", "format=yuv420p", "-an", "-movflags", "+faststart",
                        str(output / "glissement.mp4")], check=True)


parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path, nargs="?")
if output := parser.parse_args().output:
    if output.exists():
        parser.error("Choose a new output directory.")
    run(output.resolve())
else:
    with tempfile.TemporaryDirectory(prefix="platform-cards-") as folder:
        run(Path(folder))
