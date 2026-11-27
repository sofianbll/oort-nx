#!/usr/bin/env python3
"""Decide which CI areas a change touches.

Reads changed paths on stdin, one per line, and prints `name=true|false` lines
for GITHUB_OUTPUT. An area is switched off when its folder is absent from the
checkout (for example `desktop/` on main before the alpha branch is merged).

Usage:
  git diff --name-only BASE HEAD | python3 scripts/ci_changed_areas.py --root .
  python3 scripts/ci_changed_areas.py --root . --all
"""

import argparse
from pathlib import Path
import sys

# Prefixes end with "/"; other entries are exact file names.
AREAS = {
    "swift": ("core/", "Sources/", "Tests/", "Resources/", "scripts/", "Package.swift", "runtime.lock", "VERSION"),
    "desktop": ("desktop/", "core/OortCore/", "Sources/NXLibraryCore/", "scripts/check_portable_core.py", "Package.swift",
                # desktop/scripts/generate.py reads these.
                "design/", "Resources/Selene/palettes.json", "scripts/generate_oort_tokens.py"),
    "mobile": ("mobile/", "core/OortCore/", "Package.swift"),
    "android": ("android/", "Tests/AndroidChecks/", "scripts/generate_oort_android_tokens.py",
                # The tokens and the app mark Android is drawn from.
                "design/", "Resources/AppIcon.icon/"),
}
# An area needs its folder in the checkout; without it the area stays off.
FOLDER = {"desktop": "desktop", "mobile": "mobile", "android": "android"}
# A change to the workflows themselves exercises every area.
EVERYTHING = (".github/",)


def matches(path, rules):
    return any(path.startswith(rule) if rule.endswith("/") else path == rule for rule in rules)


def decide(paths, root, everything=False):
    paths = [path.strip() for path in paths if path.strip()]
    result = {}
    for area, rules in AREAS.items():
        on = everything or any(matches(path, rules + EVERYTHING) for path in paths)
        if area in FOLDER and not (Path(root) / FOLDER[area]).is_dir():
            on = False
        result[area] = on
    return result


def main(argv=None, stdin=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=".", help="checkout to look for area folders")
    parser.add_argument("--all", action="store_true", help="turn every area on (pushes without a base, manual runs)")
    args = parser.parse_args(argv)
    paths = (stdin if stdin is not None else sys.stdin).read().splitlines()
    for area, on in decide(paths, args.root, args.all).items():
        print(f"{area}={'true' if on else 'false'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
