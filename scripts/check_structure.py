#!/usr/bin/env python3
"""Check that every tracked root file and every first- and second-level folder is declared in
architecture/structure.c4, and that nothing declared there is missing (rule R1). The CI may not
name a path under a root folder the layout retired (architecture/names.json, `former`): a job that
sleeps on main, such as Android, would otherwise keep a dead path that no build notices."""
import json
import re
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
    issues.update(retired_paths(root, layout))
    return sorted(issues)


CI_FILES = (".github/workflows/*.yml", "scripts/ci_changed_areas.py")


def retired_paths(root, layout):
    """Paths the CI names under a root folder of the former layout that no longer exists."""
    names = Path(root) / "architecture/names.json"
    if not names.exists():
        return set()
    roots = set()
    for former in json.loads(names.read_text(encoding="utf-8")).get("former", []):
        for module in former.get("modules", {}).values():
            for entry in (module, module.get("tests") or {}):
                if "/" in entry.get("path", ""):
                    roots.add(entry["path"].split("/")[0])
    roots -= {folder.split("/")[0] for folder in layout.folders}
    if not roots:
        return set()
    cited = re.compile(r"(?<![\w./$-])((?:%s)/[\w./*-]*)" % "|".join(map(re.escape, sorted(roots))))
    issues = set()
    for pattern in CI_FILES:
        for path in sorted(Path(root).glob(pattern)):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                issues.update(f"{path.relative_to(root)}:{number}: {match} is under a folder the layout retired"
                              f" ({names.relative_to(root)}, former)" for match in cited.findall(line))
    return issues


def main():
    issues = check(ROOT)
    for issue in issues:
        print(issue)
    if not issues:
        print("Structure matches architecture/structure.c4.")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
