#!/usr/bin/env python3
"""Check tracked publication inputs; never print matching secret values."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


PRIVATE_ROOTS = {"output", "reports", "research_notes", ".superpowers", ".aws"}
# Directories that hold private notes or artwork and must never be published.
PRIVATE_DIRS = {
    ("docs", "audits"),
    ("docs", "superpowers"),
    ("docs", "upstream-issues"),
    ("docs", "private"),
    ("Resources", "Selene", "Wallpapers"),
}
PRIVATE_EXTENSIONS = {
    ".keys", ".nsp", ".xci", ".nsz", ".xcz", ".nca", ".nso", ".tik", ".cert",
    ".app", ".dmg", ".ipa", ".log", ".p12", ".pfx",
}
SECRET_PATTERNS = [
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})\b"),
    re.compile(rb"(?im)^\s*(?:header_key|master_key_[0-9a-f]{2}|key_area_key_application_[0-9a-f]{2})\s*=\s*[0-9a-f]{32,128}\s*$"),
]
NINTENDO_PLATFORM_MARKS = {
    "Brands/Platforms/Marks/Nintendo Switch.svg": "cca242aa61d7cdccf1ff8b62f5329994bab7d8af433a7e994e99c63f8071714b",
    "Brands/Platforms/Marks/Nintendo Switch 2.svg": "7d4b99ea3894f662e39430e3be2a59ab501af02f1ae565337763a9a73f8bccb1",
}


def brand_digests(manifest):
    result = {}
    for name, entry in manifest.items():
        if name.startswith("Brands/Platforms/Marks/"):
            if not isinstance(entry, dict) or not all(isinstance(entry.get(key), str) and entry[key]
                    for key in ("sha256", "source", "drawingLicence", "trademarkOwner", "adaptation")):
                raise ValueError("Incomplete platform-mark provenance")
            if "nintendo" in name.lower() and NINTENDO_PLATFORM_MARKS.get(name) != entry["sha256"]:
                raise ValueError("Unapproved Nintendo mark or digest")
            result[name] = entry["sha256"]
        else:
            result[name] = entry
    return result


def check_files(root):
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    issues = []
    resources = root / "Resources"
    manifest = root / "scripts/bundle-licences.json"
    try:
        expected = brand_digests(json.loads(manifest.read_text())) if manifest.is_file() else {}
    except (OSError, ValueError, AttributeError):
        return ["Bundle licence manifest could not be verified."]
    for name in filter(None, names):
        relative = Path(name)
        if (relative.parts[0] in PRIVATE_ROOTS
                or any(relative.parts[:len(folder)] == folder for folder in PRIVATE_DIRS)
                or any(Path(part).suffix.lower() in PRIVATE_EXTENSIONS for part in relative.parts)
                or (relative.name.startswith(".env") and relative.name != ".env.example")
                or relative.name == "env.txt"):
            issues.append("Private or game content path: " + name)
            continue
        file = root / relative
        if relative.parts[:2] == ("Resources", "Brands"):
            resource = Path(*relative.parts[1:]).as_posix()
            if (file.is_symlink() or not file.is_file()
                    or not file.resolve().is_relative_to(resources.resolve())
                    or ("nintendo" in resource.lower() and resource not in NINTENDO_PLATFORM_MARKS)
                    or hashlib.sha256(file.read_bytes()).hexdigest() != expected.get(resource)):
                issues.append("Unreviewed or changed brand resource: " + name)
            continue
        if not file.is_file() or file.is_symlink():
            continue
        data = file.read_bytes()
        if b"\0" not in data[:8192] and any(pattern.search(data) for pattern in SECRET_PATTERNS):
            issues.append("Possible secret material: " + name)
    # The licence ships in the app; its reviewed digest is the one in the bundle manifest.
    licence = root / "LICENSE"
    if isinstance(expected.get("LICENSE"), str) and (
            not licence.is_file() or hashlib.sha256(licence.read_bytes()).hexdigest() != expected["LICENSE"]):
        issues.append("LICENSE differs from its reviewed digest in scripts/bundle-licences.json.")
    return issues


def check_runtime(root, runtime):
    try:
        lock_bytes = (root / "runtime.lock").read_bytes()
        lock = json.loads(lock_bytes)
        versions = json.loads((runtime / "versions.json").read_text())
        expected = {"python": lock["python"]["version"],
                    "lock": hashlib.sha256(lock_bytes).hexdigest()}
        expected.update((item["name"].lower(), item["version"]) for item in lock["wheels"])
        expected.update((item["formula"], item["version"]) for item in lock["brew"])
        if any(versions.get(name) != value for name, value in expected.items()):
            return ["Runtime does not match runtime.lock; run scripts/bundle_runtime.sh."]
        required = ["python/bin/python3", "bin/zstd", "bin/glslangValidator"]
        if not all((runtime / name).is_file() and os.access(runtime / name, os.X_OK) for name in required):
            return ["Runtime is missing an executable."]
        if not (runtime / "licenses").is_dir():
            return ["Runtime is missing its licenses."]
        if not all((runtime / "sources" / item["file"]).is_file() for item in lock.get("sources", [])):
            return ["Runtime is missing the source of a GPL package."]
    except (OSError, ValueError, KeyError, TypeError):
        return ["Runtime metadata could not be verified."]
    return []


def unexpected_brands(resources, expected):
    folder = resources / "Brands"
    if folder.is_symlink():
        return ["Invalid bundle brand folder: Brands"]
    return ["Unreviewed brand resource: " + name
            for path in sorted(folder.rglob("*"))
            if ((name := path.relative_to(resources).as_posix()) not in expected
                and (path.is_symlink() or not path.is_dir()))]


def check_app(root, app, require_runtime=True):
    resources = app / "Contents/Resources"
    issues = []
    if require_runtime or (resources / "Runtime").exists():
        require_runtime = True
        issues += check_runtime(root, resources / "Runtime")
    try:
        for _, dirs, files in os.walk(app):
            if any(re.fullmatch(r"rclone(?:\.exe|(?:-.*)?\.zip)?", name, re.I) for name in dirs + files):
                issues.append("App must not contain rclone or its binary archive.")
                break
        if not resources.resolve().is_relative_to(app.resolve()):
            return issues + ["Bundle resources point outside the app."]
        expected = json.loads((root / "scripts/bundle-licences.json").read_text())
        if not isinstance(expected, dict) or not expected:
            return issues + ["Bundle licence manifest must not be empty."]
        expected = brand_digests(expected)
        issues += unexpected_brands(resources, expected)
        expected["NOTICE"] = hashlib.sha256((root / "NOTICE").read_bytes()).hexdigest()
        for name, digest in expected.items():
            if not require_runtime and name.startswith("Runtime/"):
                continue
            path = resources / name
            if path.is_symlink() or not path.resolve().is_relative_to(resources.resolve()):
                issues.append("Invalid bundle licence path: " + name)
                continue
            if not path.is_file():
                issues.append("Missing bundle licence or source: " + name)
            elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                issues.append("Changed bundle licence or source: " + name)
    except (OSError, ValueError, RuntimeError):
        issues.append("Bundle licence manifest could not be verified.")
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, help="Also verify a bundled runtime against runtime.lock.")
    parser.add_argument("--app", type=Path, help="Also verify a release app's reviewed licence and source files.")
    parser.add_argument("--without-runtime", action="store_true", help="Allow a development bundle without the runtime.")
    args = parser.parse_args()
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"]).decode().strip())
    issues = check_files(root)
    if args.runtime:
        issues += check_runtime(root, args.runtime)
    if args.app:
        issues += check_app(root, args.app, require_runtime=not args.without_runtime)
    for issue in issues:
        print(issue)
    if not issues:
        print("Publication checks passed.")
    return bool(issues)


if __name__ == "__main__":
    raise SystemExit(main())
