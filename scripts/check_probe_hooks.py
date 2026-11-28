#!/usr/bin/env python3
"""The Release app carries no probe hook. Probes on the shared Debug build reach the app through hooks named
`oortProbe…`. In the sources, every such name outside a Tests folder sits inside `#if DEBUG` (the `hooks` rule of
scripts/check): a Release build cannot even name it. The binary scan is a second net, since an inlined or unused hook
leaves no name behind.

  scripts/check_probe_hooks.py --source  every tracked Swift file outside Tests folders
  scripts/check_probe_hooks.py           the Release product of `swift build -c release` (run by `scripts/check release-build`)
  scripts/check_probe_hooks.py BINARY    any binary: the Debug app holds the hooks, so it fails
"""
import re
import subprocess
import sys
from pathlib import Path

import names
from repo_model import tracked

ROOT = Path(__file__).resolve().parents[1]

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


DIRECTIVE = re.compile(r"\s*#(if|elseif|else|endif)\b(.*)")


def outside_debug(text):
    """Line numbers where `oortProbe` appears outside an `#if DEBUG` branch (`#else` of DEBUG counts as outside)."""
    stack, lines = [], []  # one entry per open #if: is the current branch a DEBUG branch?
    for number, line in enumerate(text.splitlines(), 1):
        if directive := DIRECTIVE.match(line):
            keyword, condition = directive[1], directive[2].strip()
            if keyword == "if":
                stack.append(condition == "DEBUG")
            elif keyword in ("elseif", "else") and stack:
                stack[-1] = False
            elif keyword == "endif" and stack:
                stack.pop()
            continue
        if "oortProbe" in line.split("//")[0] and not any(stack):
            lines.append(number)
    return lines


def sources(root):
    issues = []
    for name in tracked(root):
        if name.endswith(".swift") and "Tests" not in name.split("/"):
            for number in outside_debug((Path(root) / name).read_text(encoding="utf-8")):
                issues.append(f"{name}:{number}: probe hook outside #if DEBUG")
    return issues


def release_binary():
    command = ["swift", "build", "-c", "release", "--product", names.APP, "--show-bin-path"]
    return Path(subprocess.check_output(command, text=True).strip()) / names.APP


def main(argv):
    if argv == ["--source"]:
        issues = sources(ROOT)
        print("\n".join(issues) or "Every probe hook in the sources is inside #if DEBUG.")
        return 1 if issues else 0
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
