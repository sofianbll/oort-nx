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
import uuid

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json
EXTRACTOR = ROOT / "scripts/extract_downgrade_checkpoint.py"
PROBE = Path(__file__).with_name("DowngradeProbe.swift")


def compile_probe(tree, binary, legacy):
    build = tree / ".build"
    products = build / "out/Products/Debug"
    targets = build / f"out/Intermediates.noindex/{names.PACKAGE}.build/Debug/{names.APP}-p.build/Objects-normal"
    [linkfile] = targets.glob(f"*/{names.APP}.LinkFileList")

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
    shutil.copytree(products / names.RESOURCE_BUNDLE, bundle_parent / names.RESOURCE_BUNDLE)
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
    if len(sys.argv) == 1:
        print("SKIP: supply the legacy checkout and a synthetic output path")
        sys.exit(0)
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
    before, after = (output / label / f"downgrade-fixture-{uuid.uuid4()}" for label in ("v030", "next"))
    compile_probe(old, before, legacy=True)
    compile_probe(ROOT, after, legacy=False)
    if args.capture:
        for language in ("fr", "en"):
            for notice in ("ready", "failed", "partial", "disk-full", "progress"):
                run_probe(after, output / "capture-home", "capture", language, str(output / f"{notice}-{language}.png"), notice)
    home = output / "fixture-home"
    previous = home / "Library/Application Support/NXLibrary"
    live = home / "Library/Application Support/Oort NX"
    run_probe(before, home, "seed")
    run_probe(after, home, "upgrade")
    # An ordinary return to 0.3.0 uses its own, unchanged library.
    run_probe(before, home, "restored")
    # Keep the newer fixture immutable while exercising the older writers on a copy at the same path.
    frozen = output / "kept-next"
    shutil.copytree(live, frozen)
    # Deliberately cross the folder boundary on a disposable copy to characterize unsupported sharing.
    previous.rename(output / "kept-v030")
    shutil.copytree(frozen, previous)
    run_probe(before, home, "direct")
    run_probe(after, home, "restored")  # The old writer cannot reach the current folder.
    previous.rename(output / "diverged")
    checkpoint = frozen / "DowngradeProtection/checkpoint.plist"
    subprocess.run([sys.executable, str(EXTRACTOR), str(checkpoint), str(previous)], check=True)
    (previous / "preferences-du-lanceur.plist").rename(previous / "fixture-preferences.plist")
    # Reproducible artwork cache deliberately absent from the checkpoint.
    shutil.copytree(frozen / "artwork", previous / "artwork")
    run_probe(before, home, "restored")
    print(f"Evidence: {output}")
