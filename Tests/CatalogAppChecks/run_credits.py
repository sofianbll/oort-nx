#!/usr/bin/env python3
"""Render Settings › About and check that every credit is shown and within the controller's reach."""
from pathlib import Path
import argparse
import tempfile

from audit_probe_host import run_host


def run(output):
    run_host("// The screen with the credits of design/credits.json.\n"
             + Path(__file__).with_name("CreditsProbe.swift").read_text().replace("#if CREDITS", "#if true"),
             save_model=True, capture=output, resources=["AppIcon.icns"])


parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path, nargs="?")
if output := parser.parse_args().output:
    if output.exists():
        parser.error("Choose a new output directory.")
    run(output.resolve())
else:
    with tempfile.TemporaryDirectory(prefix="credits-") as folder:
        run(Path(folder))
