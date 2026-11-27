#!/usr/bin/env python3
"""Check the documentation (rule R8, first part).

- A .md file lives only where architecture/structure.c4 allows documentation (`markdown "yes"`).
- Every relative link of a .md file resolves to a tracked path.
- No .md file carries a private marker from scripts/private-markers.json, except the recorded allowances.
  With --base REF, an allowance that REF did not have is refused: the list only shrinks.
"""
import argparse
import json
import posixpath
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path

from repo_model import MODEL, read_layout, tracked

ROOT = Path(__file__).resolve().parents[1]
MARKERS = "scripts/private-markers.json"
FENCE = re.compile(r"^(```|~~~)[^\n]*\n.*?^\1[ \t]*$", re.MULTILINE | re.DOTALL)
CODE = re.compile(r"`[^`\n]*`")
LINK = re.compile(r"!?\[[^\]\n]*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")


def allowed_place(name, layout):
    folder = name.rpartition("/")[0]
    if not folder:
        return "" in layout.markdown
    return any(folder == place or folder.startswith(place + "/") for place in layout.markdown if place)


def links(text):
    text = CODE.sub("", FENCE.sub("", text))
    for match in LINK.finditer(text):
        target = match.group(1)
        if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target) or target.startswith("#"):
            continue
        yield target


def read_markers(root, ref=None):
    if ref is None:
        return json.loads((root / MARKERS).read_text(encoding="utf-8"))
    shown = subprocess.run(["git", "show", f"{ref}:{MARKERS}"], cwd=root, capture_output=True, text=True)
    return json.loads(shown.stdout) if shown.returncode == 0 else None


def check(root, base=None):
    root = Path(root)
    layout = read_layout(root)
    names = tracked(root)
    known = {"."} | set(names) | {"/".join(name.split("/")[:depth]) for name in names for depth in range(1, name.count("/") + 1)}
    markers = read_markers(root)
    allowed = {path: set(found) for path, found in markers.get("allowed", {}).items()}
    issues = []
    used = set()
    for name in sorted(n for n in names if n.endswith(".md")):
        if not allowed_place(name, layout):
            issues.append(f"{name}: documentation outside the folders {MODEL} marks markdown \"yes\"")
        text = (root / name).read_text(encoding="utf-8", errors="replace")
        for target in links(text):
            path = urllib.parse.unquote(target.split("#", 1)[0].split("?", 1)[0])
            if not path:
                continue
            joined = path.lstrip("/") if path.startswith("/") else posixpath.join(posixpath.dirname(name), path)
            resolved = posixpath.normpath(joined).rstrip("/")
            if resolved == ".." or resolved.startswith("../") or resolved not in known:
                issues.append(f"{name}: link to {target} does not resolve to a tracked path")
        for marker in markers["markers"]:
            if marker in text:
                if marker in allowed.get(name, set()):
                    used.add((name, marker))
                else:
                    issues.append(f"{name}: private marker {marker!r}; remove it ({MARKERS} records only old ones)")
    for name, found in allowed.items():
        for marker in found - {m for n, m in used if n == name}:
            issues.append(f"{MARKERS}: {name} no longer holds {marker!r}; remove the allowance")
    if base is not None:
        before = read_markers(root, base)
        old = {(path, m) for path, found in (before or {}).get("allowed", {}).items() for m in found}
        for name, found in allowed.items():
            for marker in sorted(found):
                if (name, marker) not in old:
                    issues.append(f"{MARKERS}: new allowance {name} {marker!r}; the list only shrinks")
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", help="Refuse allowances that this Git revision did not have.")
    args = parser.parse_args()
    issues = check(ROOT, args.base)
    for issue in issues:
        print(issue)
    if not issues:
        print("Documentation places, links and private markers hold.")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
