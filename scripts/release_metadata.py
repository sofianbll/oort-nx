#!/usr/bin/env python3
"""Read release inputs, verify a Mac bundle, and enforce R9 and R12."""
import argparse
import os
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIEW_MODEL = "apps/mac/OortMac/ViewModels/AppViewModel.swift"
TOOLCHAIN = "engines/nxnative/NxnativeAdapter/Setup/ToolchainRequirements.swift"
NUMBER = r"(?:0|[1-9][0-9]*)"
STABLE = rf"{NUMBER}\.{NUMBER}\.{NUMBER}"
VERSION = rf"{STABLE}(?:-(?:alpha|beta|rc)\.[1-9][0-9]*)?"
WRITE_RELEASE = re.compile(
    r"\bgh\s+release\b|/releases(?:/|\b)|\b(?:softprops/action-gh-release|"
    r"actions/(?:create-release|upload-release-asset)|ncipollo/release-action)\b"
)


def read_version(root):
    version = (root / "VERSION").read_text().removesuffix("\n")
    if not re.fullmatch(VERSION, version):
        raise ValueError("VERSION must contain one Oort SemVer, such as 0.6.0")
    return version


def swift_value(root, path, pattern, name):
    matches = re.findall(pattern, (root / path).read_text())
    if len(matches) != 1:
        raise ValueError(f"{path}: expected exactly one valid {name}")
    return matches[0]


def engine_commit(root):
    return swift_value(root, VIEW_MODEL, r'(?m)^\s*static let defaultPinnedEngineCommit = "([0-9a-f]{40})"$',
                       "defaultPinnedEngineCommit")


def engine_repository(root):
    return swift_value(root, VIEW_MODEL,
                       r'(?m)^\s*static let defaultPinnedEngineRepository = '
                       r'"(https://github\.com/[A-Za-z0-9_-]+/[A-Za-z0-9_-][A-Za-z0-9_.-]*)"$',
                       "defaultPinnedEngineRepository")


def check_version(root, ref):
    version, commit = read_version(root), engine_commit(root)
    engine_repository(root)
    if ref.startswith("refs/tags/v") and (not re.fullmatch(rf"refs/tags/v{STABLE}", ref)
                                          or ref != f"refs/tags/v{version}"):
        raise ValueError(f"{ref}: expected stable tag v{version} matching VERSION")
    result = subprocess.run(
        ["git", "grep", "--untracked", "-inIE", rf"(^|[^0-9a-f]){commit[:7]}[0-9a-f]{{0,33}}([^0-9a-f]|$)",
         "--", ".", f":(exclude){VIEW_MODEL}", ":(exclude)docs/history/**"],
        cwd=root, text=True, capture_output=True,
    )
    if result.returncode == 0:
        raise ValueError(f"read the engine pin from {VIEW_MODEL}; stale copies:\n{result.stdout.rstrip()}")
    if result.returncode != 1:
        raise ValueError(f"could not check copies of the engine pin: {result.stderr.strip()}")


def check_release(root):
    local = root / "scripts/release"
    text = local.read_text()
    if WRITE_RELEASE.search(text) or re.search(r"\bgit\s+(?:push|tag)\b", text):
        raise ValueError("scripts/release must not publish or write tags")
    for workflow in (root / ".github/workflows").iterdir():
        if workflow.suffix not in {".yml", ".yaml"} or workflow.name == "release.yml":
            continue
        # Actions artifacts are not release assets. A read-only proof may download a public release.
        for line in workflow.read_text().splitlines():
            if (not line.lstrip().startswith("#") and
                    (re.search(r"\b(?:contents:\s*write|permissions:\s*write-all)\b", line) or
                     WRITE_RELEASE.search(re.sub(r"https://[^\s\"']+/releases/download/\S+", "", line)))):
                raise ValueError(f"{workflow.relative_to(root)}: only release.yml may publish")


def verify_app(root, app, public):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    expected = {"CFBundleShortVersionString": read_version(root), "NXLibraryRelease": True,
                "NXLibraryEngineRepository": engine_repository(root), "NXLibraryEngineCommit": engine_commit(root)}
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f"{app.name}: {key} must match the release inputs")
    if "NXLibraryDevelopmentProfile" in info:
        raise ValueError(f"{app.name}: a release must not select the development profile")
    if public and {"ArcaneGoogleClientID", "ArcaneGoogleClientSecret"} & info.keys():
        raise ValueError(f"{app.name}: unexpected private Google credentials in release bundle")
    print(f"{app.name}: {expected['CFBundleShortVersionString']} / {expected['NXLibraryEngineCommit']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("version", "engine-commit", "engine-repository", "notes",
                                            "check-version", "check-release", "verify-app"))
    parser.add_argument("--app", type=Path)
    parser.add_argument("--public", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "check-version":
            check_version(ROOT, os.getenv("GITHUB_REF", ""))
        elif args.command == "check-release":
            check_release(ROOT)
        elif args.command == "verify-app":
            if args.app is None:
                parser.error("verify-app requires --app")
            verify_app(ROOT, args.app, args.public)
        elif args.command == "notes":
            xcode = swift_value(ROOT, TOOLCHAIN, r'minimumXcode: "([0-9.]+)"', "minimumXcode")
            print(f"<!-- nxlibrary-requires xcode={xcode} engine={engine_commit(ROOT)} -->")
        else:
            reader = {"version": read_version, "engine-commit": engine_commit, "engine-repository": engine_repository}
            print(reader[args.command](ROOT))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
