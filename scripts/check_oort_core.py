#!/usr/bin/env python3
"""Check the portable Swift target; optionally stage the same Swift sources for Linux."""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import names  # architecture/names.json

ROOT = Path(__file__).resolve().parents[1]
CORE, CORE_TESTS = names.CORE, names.TESTS["core"]["name"]
CONDITIONAL = re.compile(r"^[ \t]*#(?:if|elseif|else|endif)\b[^\n]*", re.MULTILINE)
IMPORT = re.compile(r'^\s*\(import_decl .*? module="([^"]+)"', re.MULTILINE)
ALLOWED = {"Foundation", "Swift"}

LINUX_MANIFEST = f"""// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{CORE}Checks",
    targets: [
        .target(name: "{CORE}", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "{CORE_TESTS}", dependencies: ["{CORE}"]),
    ],
    swiftLanguageModes: [.v5]
)
"""


def check_imports(sources):
    with tempfile.TemporaryDirectory(prefix="oort-core-imports-") as scratch:
        for index, source in enumerate(sources):
            path = Path(scratch) / f"{index}.swift"
            # Parse every branch on any host; do not let #if hide an Apple-only import.
            path.write_text(CONDITIONAL.sub("", source.read_text(encoding="utf-8")), encoding="utf-8")
            output = subprocess.check_output(
                ["swiftc", "-frontend", "-dump-parse", str(path)], text=True
            )
            imports = IMPORT.findall(output)
            if len(imports) != output.count("(import_decl "):
                raise SystemExit(f"{source}: unsupported Swift import dump")
            unexpected = sorted({name.split(".")[0] for name in imports} - ALLOWED)
            if unexpected:
                raise SystemExit(f"{source}: disallowed imports: {', '.join(unexpected)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--linux-package", type=Path, help="new directory for the minimal Swift package")
    args = parser.parse_args()

    manifest = json.loads(subprocess.check_output(
        ["swift", "package", "--disable-sandbox", "dump-package"], cwd=ROOT
    ))
    core = next((target for target in manifest["targets"] if target["name"] == CORE), None)
    if (core is None or core["type"] != "regular"
            or core.get("path") != names.path("core")
            or any(core.get(key) for key in ("dependencies", "resources", "sources", "exclude"))
            or [setting["kind"] for setting in core.get("settings", [])] != [{"swiftLanguageMode": {"_0": "6"}}]):
        raise SystemExit(f"{CORE} must have no dependencies or resources, and only the Swift 6 language mode as a setting.")

    source_dir = ROOT / names.path("core")
    sources = sorted(source_dir.rglob("*.swift"))
    if not sources:
        raise SystemExit(f"No {CORE} Swift sources.")
    check_imports(sources)
    print(f"{CORE}: {len(sources)} Swift sources, Foundation/Swift only, no target dependencies or resources.")

    if args.linux_package:
        stage = args.linux_package
        stage.mkdir()
        # The minimal package keeps SwiftPM's default folders: Sources/<target>, Tests/<target>.
        shutil.copytree(source_dir, stage / "Sources" / CORE)
        shutil.copytree(ROOT / names.test_path("core"), stage / "Tests" / CORE_TESTS)
        (stage / "Package.swift").write_text(LINUX_MANIFEST, encoding="utf-8")


if __name__ == "__main__":
    main()
