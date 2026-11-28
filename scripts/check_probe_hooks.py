#!/usr/bin/env python3
"""The Release app carries no probe hook. Probes on the shared Debug build reach the app through hooks named
`oortProbe…`, each inside `#if DEBUG`; this refuses a Release binary that still holds one of those names.

  scripts/check_probe_hooks.py           the Release product of `swift build -c release` (run by `scripts/check release-build`)
  scripts/check_probe_hooks.py BINARY    any binary: the Debug app holds the hooks, so it fails
"""
import subprocess
import sys
from pathlib import Path

import names

MARKER = b"oortProbe"


def hooks(binary):
    """Every distinct name around the marker, as the linker and the string table keep them."""
    data = Path(binary).read_bytes()
    found, start = set(), data.find(MARKER)
    while start != -1:
        end = start + len(MARKER)
        while end < len(data) and (chr(data[end]).isalnum() or data[end] == ord("_")):
            end += 1
        found.add(data[start:end].decode("ascii", "replace"))
        start = data.find(MARKER, end)
    return sorted(found)


def release_binary():
    command = ["swift", "build", "-c", "release", "--product", names.APP, "--show-bin-path"]
    return Path(subprocess.check_output(command, text=True).strip()) / names.APP


def main(argv):
    if len(argv) > 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    binary = Path(argv[0]) if argv else release_binary()
    found = hooks(binary)
    for name in found:
        print(f"{binary}: probe hook {name} (keep it inside #if DEBUG)")
    if not found:
        print(f"{binary}: no probe hook.")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
