#!/usr/bin/env python3
"""Run the CatalogAppChecks glob in bounded CI batches."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def partition(paths):
    debug, standalone = [], []
    for path in paths:
        # Standalone probes build a temporary package, directly or via the Cloud build helper.
        source = path.read_text(encoding="utf-8")
        group = standalone if "--package-path" in source or "build_probe(package)" in source else debug
        group.append(path)
    return debug, [standalone[i:i + 2] for i in range(0, len(standalone), 2)]


def run(paths, temp):
    failed = False
    for path in paths:
        with tempfile.TemporaryDirectory(prefix="oort-home-", dir=temp) as home:
            print(f"Running {path.name}", flush=True)
            start = time.monotonic()
            env = dict(os.environ, HOME=home, CFFIXED_USER_HOME=home, OORT_PROBE_BUILD_HOME=str(Path.home()))
            code = subprocess.run([sys.executable, str(path)], cwd=ROOT, env=env).returncode
            print(f"{path.name}: exit {code} in {time.monotonic() - start:.1f}s", flush=True)
            failed |= code != 0
    return int(failed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("batch", help="matrix, debug, or a numbered standalone batch")
    batch = parser.parse_args().batch
    debug, standalone = partition(sorted((ROOT / "Tests/CatalogAppChecks").glob("run_*.py")))
    if not debug or not standalone:
        parser.error("expected both shared-debug and standalone probes")
    if batch == "matrix":
        print(json.dumps(list(range(1, len(standalone) + 1))))
        return 0
    if batch == "debug":
        paths = debug
    elif batch.isdecimal() and 1 <= int(batch) <= len(standalone):
        paths = standalone[int(batch) - 1]
    else:
        parser.error("unknown batch")
    return run(paths, os.environ.get("RUNNER_TEMP"))


if __name__ == "__main__":
    sys.exit(main())
