#!/usr/bin/env python3
"""Check the probes under apps/mac/Tests/CatalogAppChecks: what they prove and how they start.

R13: the text of a rendered PDF lists every string that was drawn, also when it is clipped, outside the frame,
covered or without contrast. A probe source that calls readProbeText must also use the result of assertVisible
(ProbeRenderedText.swift), which measures the pixels: `+=` or `let … =`, with texts to prove. Comments do not count.

Start: a probe that links the core's objects or builds the package does it through probe_start.py, so that
ProbeStart.swift gives the core the Mac implementations of its joints (MacPlatformServices) before the probe runs.
Elsewhere, the core's objects, their link lists, `swift build` and a renamed entry point are refused.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBES = "apps/mac/Tests/CatalogAppChecks"
HELPER = "ProbeRenderedText.swift"
READS = re.compile(r"\breadProbeText\s*\(")
PROVES = re.compile(r"(?:\+=|\blet\s+\w+\s*=)\s*assertVisible\s*\((?![^)]*,\s*\[\s*\]\s*\))")
COMMENT = re.compile(r"(?m)(?:^|\s)(?://|#)[^\n]*")
START = "probe_start.py"
# Ways to reach the core's objects or to build the package without ProbeStart.swift.
AROUND_START = re.compile(r"names\.objects\(|\.swift\.o\b|LinkFileList|[\"']swift[\"'],\s*[\"']build[\"']|"
                          r"entry-point-function-name")


def check(root):
    issues = []
    for path in sorted((Path(root) / PROBES).glob("*")):
        if path.suffix not in (".py", ".swift") or path.name == HELPER:
            continue
        text = COMMENT.sub("", path.read_text(encoding="utf-8"))
        if READS.search(text) and not PROVES.search(text):
            issues.append(f"{PROBES}/{path.name}: reads rendered text without using assertVisible")
        if path.suffix == ".py" and path.name != START and AROUND_START.search(text):
            issues.append(f"{PROBES}/{path.name}: links or builds the core without {START} (ProbeStart.swift)")
    start = Path(root) / PROBES / START
    swift = Path(root) / PROBES / "ProbeStart.swift"
    if not start.is_file() or "_oortProbeStart" not in start.read_text(encoding="utf-8"):
        issues.append(f"{PROBES}/{START}: must start every probe that runs the core in _oortProbeStart")
    if not swift.is_file() or "MacPlatformServices.register()" not in COMMENT.sub("", swift.read_text(encoding="utf-8")):
        issues.append(f"{PROBES}/ProbeStart.swift: must give the core MacPlatformServices.register() first")
    return issues


def main():
    issues = check(ROOT)
    for issue in issues:
        print(issue)
    if not issues:
        print("Every probe that reads rendered text proves it visible; every probe that runs the core starts in "
              "ProbeStart.swift.")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
