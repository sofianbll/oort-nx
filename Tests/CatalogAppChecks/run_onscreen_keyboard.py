#!/usr/bin/env python3
"""Type into real text fields with controller actions, offscreen and on an isolated home."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="onscreen-keyboard-") as scratch:
    output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(scratch) / "screens"
    subprocess.run([ROOT / ".build/debug/NXLibrary", "--render-keyboard", output], cwd=ROOT, check=True, timeout=300,
                   env=dict(os.environ, HOME=scratch, CFFIXED_USER_HOME=scratch))
