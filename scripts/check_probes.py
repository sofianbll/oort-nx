#!/usr/bin/env python3
"""Check that a probe which reads rendered text also proves that text visible (rule R13).

The text of a rendered PDF lists every string that was drawn, also when it is clipped, outside the frame,
covered or without contrast. A probe source under apps/mac/Tests/CatalogAppChecks that calls readProbeText must also
use the result of assertVisible (ProbeRenderedText.swift), which measures the pixels: `+=` or `let … =`, with
texts to prove. Comments do not count.
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


def check(root):
    issues = []
    for path in sorted((Path(root) / PROBES).glob("*")):
        if path.suffix not in (".py", ".swift") or path.name == HELPER:
            continue
        text = COMMENT.sub("", path.read_text(encoding="utf-8"))
        if READS.search(text) and not PROVES.search(text):
            issues.append(f"{PROBES}/{path.name}: reads rendered text without using assertVisible")
    return issues


def main():
    issues = check(ROOT)
    for issue in issues:
        print(issue)
    if not issues:
        print("Every probe that reads rendered text proves it visible.")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
