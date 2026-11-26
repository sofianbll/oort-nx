#!/usr/bin/env python3
"""Run the palette announcement and inactive launch probes without showing a window."""
from pathlib import Path
import os
import sys
import tempfile

from audit_probe_host import run_host

source = Path(__file__).with_name("Beta4InputScreens.swift").read_text()
modes = sys.argv[2:] or ["palette", "launch", "cursor"]
if set(modes) - {"launch", "palette", "cursor"}:
    raise SystemExit("Expected an output directory and optional modes: launch, palette, cursor")
source = source.replace("[.palette, .launch, .cursor]", "[" + ", ".join("." + m for m in modes) + "]")
with tempfile.TemporaryDirectory() as scratch:
    os.environ["OORT_HEADLESS_INPUT"] = "1"
    run_host(source, save_model=True, capture=Path(sys.argv[1] if len(sys.argv) > 1 else scratch))
