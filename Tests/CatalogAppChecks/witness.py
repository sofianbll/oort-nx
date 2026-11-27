#!/usr/bin/env python3
"""Temporary CI witness: witness.py OUTPUT. Renders a label under each modifier and says what ImageRenderer's PDF keeps."""
import os, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from audit_probe_host import run_host  # noqa: E402
from probe_visible import TEXT_CONTRAST  # noqa: E402
os.environ["OORT_HEADLESS_INPUT"] = "1"
helper = (HERE / "ProbeRenderedText.swift").read_text() + f"\nlet probeMinimumContrast = {TEXT_CONTRAST}\n"
run_host((HERE / "ButtonWitness.swift").read_text(), helper, save_model=True, capture=Path(sys.argv[1]))
