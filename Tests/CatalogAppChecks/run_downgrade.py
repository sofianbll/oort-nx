#!/usr/bin/env python3
"""Build no app and touch no live profile: link the Swift debug builders' actual readers and writers."""
import argparse
import json
import os
from pathlib import Path
import pwd
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
EXTRACTOR = ROOT / "scripts/extract_downgrade_checkpoint.py"
PROBE = Path(__file__).with_name("DowngradeProbe.swift")


def compile_probe(tree, binary, legacy):
    build = tree / ".build"
    products = build / "out/Products/Debug"
    targets = build / "out/Intermediates.noindex/NXLibrary.build/Debug/NXLibrary-p.build/Objects-normal"
    [linkfile] = targets.glob("*/NXLibrary.LinkFileList")

    def package_names(node):
        if isinstance(node, dict):
            if "SWIFT_PACKAGE_NAME" in node:
                yield node["SWIFT_PACKAGE_NAME"]
            for value in node.values():
                yield from package_names(value)
        elif isinstance(node, list):
            for item in node:
                yield from package_names(item)

    [name] = sorted(set(package_names(json.loads((build / "manifest.pif").read_text()))))
    bundle_parent = binary.parent
    bundle_parent.mkdir()
    shutil.copytree(products / "NXLibrary_NXLibraryCore.bundle", bundle_parent / "NXLibrary_NXLibraryCore.bundle")
    subprocess.run(["xcrun", "swiftc", "-j", "4", "-parse-as-library", "-package-name", name,
                    "-Xfrontend", "-entry-point-function-name", "-Xfrontend", "downgradeProbeMain",
                    "-Xlinker", "-e", "-Xlinker", "_downgradeProbeMain",
                    "-I", str(linkfile.parent), "-I", str(products), *(["-D", "LEGACY"] if legacy else []),
                    str(PROBE), *shlex.split(linkfile.read_text()), "-o", str(binary)], check=True, cwd=tree)


def run_probe(binary, home, *args):
    home.mkdir(exist_ok=True)
    (home / "Library/Preferences").mkdir(parents=True, exist_ok=True)
    real_home = Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()
    profile = ('(version 1) (allow default) (deny network*) '
               '(deny file-read-data file-write* (subpath (param "REAL_HOME")) (subpath "/Volumes")) '
               '(deny file-write* (subpath "/Applications"))')
    subprocess.run(["sandbox-exec", "-D", f"REAL_HOME={real_home}", "-p", profile, str(binary), *args],
                   env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(home),
                            PACKAGE_RESOURCE_BUNDLE_PATH=str(binary.parent)), check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("legacy", type=Path)
    parser.add_argument("output", type=Path, help="new path outside the real home, for synthetic data only")
    parser.add_argument("--capture", action="store_true", help="also render the warning in French and English")
    args = parser.parse_args()
    old = args.legacy.resolve()
    output = args.output.resolve()
    if output.is_relative_to(Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()):
        parser.error("fixture destination must be outside the real home")
    if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=old, text=True).strip() != "5070a5ecbfe2cc617cac1aba9d1e2aa197929613":
        parser.error("legacy worktree must be exactly v0.3.0")
    output.mkdir()
    before, after = output / "v030/probe", output / "next/probe"
    compile_probe(old, before, legacy=True)
    compile_probe(ROOT, after, legacy=False)
    if args.capture:
        for language in ("fr", "en"):
            run_probe(after, output / "capture-home", "capture", language, str(output / f"warning-{language}.png"))
    home = output / "fixture-home"
    live = home / "Library/Application Support/NXLibrary"
    run_probe(before, home, "seed")
    run_probe(after, home, "upgrade")
    # Keep the newer fixture immutable while exercising the older writers on a copy at the same path.
    frozen = output / "kept-next"
    shutil.copytree(live, frozen)
    run_probe(before, home, "direct")
    run_probe(after, home, "after-direct")
    live.rename(output / "diverged")
    checkpoint = frozen / "DowngradeProtection/checkpoint.plist"
    subprocess.run([sys.executable, str(EXTRACTOR), str(checkpoint), str(live)], check=True)
    (live / "preferences-du-lanceur.plist").rename(live / "fixture-preferences.plist")
    # Reproducible artwork cache deliberately absent from the checkpoint.
    shutil.copytree(frozen / "artwork", live / "artwork")
    run_probe(before, home, "restored")
    live.rename(output / "restored-v030")
    shutil.copytree(frozen, live)
    run_probe(after, home, "restored")
    print(f"Evidence: {output}")
