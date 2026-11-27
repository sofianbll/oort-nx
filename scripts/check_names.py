#!/usr/bin/env python3
"""Rule R4, names: the package's technical names are written once, in architecture/names.json.

1. Hand-written build and check code (Package.swift, scripts/, .github/, architecture/*.c4, the Mac probes)
   writes no package, module, product, test-target or resource-bundle name of names.json. Python reads
   scripts/names.py; scripts/generate writes the rest. Allowed: inside a generated block or file, a Swift
   `import` line (Swift cannot read a variable; the names were rewritten there once), and a name that is a folder
   in a path (module folders are declared in names.json and architecture/structure.c4).
2. Every frozen value of names.json (players' data and settings: bundle identifiers, data folders, Info.plist and
   preferences keys, the app's name) is still written in each file names.json lists for it.

Run from the repository root, or pass --root. Exit status 1 on any finding.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "architecture/names.json"
SCOPE = re.compile(r"^(Package\.swift|scripts/.*|\.github/.*\.ya?ml|architecture/[^/]*\.c4|apps/[^/]+/Tests/[^/]+/[^/]*\.py)$")
GENERATED_FILES = ("architecture/names.c4",)
BEGIN, END = "BEGIN GENERATED NAMES", "END GENERATED NAMES"
IMPORT = re.compile(r"\bimport[ \t]+(\w+)")


def declared(data):
    names = {data["package"]}
    for module in data["modules"].values():
        names.add(module["name"])
        if "tests" in module:
            names.add(module["tests"]["name"])
    names.add(f'{data["package"]}_{data["modules"]["library"]["name"]}.bundle')
    folders = [module["path"] for module in data["modules"].values()]
    folders += [module["tests"]["path"] for module in data["modules"].values() if "tests" in module]
    return names, folders


def tracked(root):
    out = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    return [name for name in out if name]


def hand_written(root, data):
    names, folders = declared(data)
    generated = set(GENERATED_FILES) | {f'{data["modules"]["library"]["path"]}/Settings/GeneratedNames.swift'}
    pattern = re.compile(r"(?<![\w.])(" + "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True)) + r")(?![\w])")
    findings = []
    for name in tracked(root):
        if not SCOPE.match(name) or name in generated or name == SOURCE:
            continue
        path = Path(root) / name
        if path.is_symlink() or not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        inside = False
        for number, line in enumerate(text.splitlines(), 1):
            if BEGIN in line:
                inside = True
            if inside:
                inside = END not in line
                continue
            spans = [m.span() for folder in folders for m in re.finditer(re.escape(folder) + r"(?![\w\-])", line)]
            imported = {m.group(1) for m in IMPORT.finditer(line)}
            for match in pattern.finditer(line):
                folder_name = line[match.end():match.end() + 1] == "/"   # a path segment, such as a c4 folder title
                if match.group(1) in imported or folder_name or any(a <= match.start() < b for a, b in spans):
                    continue
                findings.append(f"{name}:{number}: {match.group(1)} is written by hand; read scripts/names.py or "
                                f"generate it from {SOURCE}")
    return findings


def frozen(root, data):
    findings = []
    for value, files in data.get("frozen", {}).get("values", {}).items():
        for name in files:
            path = Path(root) / name
            if not path.is_file() or value not in path.read_text(encoding="utf-8"):
                findings.append(f"{name}: frozen value {value!r} is missing; players' data depend on it, never change it")
    return findings


def check(root):
    data = json.loads((Path(root) / SOURCE).read_text(encoding="utf-8"))
    return hand_written(root, data) + frozen(root, data)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=str(ROOT))
    args = parser.parse_args(argv)
    findings = check(args.root)
    for line in findings:
        print(line)
    if not findings:
        data = json.loads((Path(args.root) / SOURCE).read_text(encoding="utf-8"))
        values = data.get("frozen", {}).get("values", {})
        print(f"Names are written once; {len(values)} frozen values in place, in {sum(map(len, values.values()))} places.")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
