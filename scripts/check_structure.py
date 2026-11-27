#!/usr/bin/env python3
"""Check that every tracked root file and every first- and second-level folder is declared in
architecture/structure.c4, and that nothing declared there is missing (rule R1)."""
import sys
from pathlib import Path

from repo_model import MODEL, read_layout, tracked

ROOT = Path(__file__).resolve().parents[1]


def check(root):
    layout = read_layout(root)
    names = tracked(root)
    issues = set()
    seen_folders, seen_files = set(), set()
    for name in names:
        parts = name.split("/")
        if len(parts) == 1:
            seen_files.add(name)
            if name not in layout.files:
                issues.add(f"{name}: root file not declared in {MODEL}")
            continue
        for depth in (1, 2):
            if len(parts) > depth:
                folder = "/".join(parts[:depth])
                seen_folders.add(folder)
                if folder not in layout.folders:
                    issues.add(f"{folder}/: folder not declared in {MODEL}")
    issues.update(f"{folder}/: declared in {MODEL} but holds no tracked file"
                  for folder in layout.folders - seen_folders)
    issues.update(f"{name}: declared in {MODEL} but not tracked" for name in layout.files - seen_files)
    return sorted(issues)


def main():
    issues = check(ROOT)
    for issue in issues:
        print(issue)
    if not issues:
        print("Structure matches architecture/structure.c4.")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
