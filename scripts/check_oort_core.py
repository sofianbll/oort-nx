#!/usr/bin/env python3
"""Check the portable Swift target; optionally stage the same Swift sources for Linux."""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONDITIONAL = re.compile(r"^[ \t]*#(?:if|elseif|else|endif)\b[^\n]*", re.MULTILINE)
IMPORT = re.compile(r'^\s*\(import_decl .*? module="([^"]+)"', re.MULTILINE)
ALLOWED = {"Foundation", "Swift"}

LINUX_MANIFEST = """// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OortCoreChecks",
    targets: [
        .target(name: "OortCore"),
        .testTarget(name: "OortCoreTests", dependencies: ["OortCore"]),
    ]
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
    core = next((target for target in manifest["targets"] if target["name"] == "OortCore"), None)
    if (core is None or core["type"] != "regular"
            or core.get("path") not in (None, "Sources/OortCore")
            or any(core.get(key) for key in ("dependencies", "resources", "settings", "sources", "exclude"))):
        raise SystemExit("OortCore must have no dependencies, resources or custom build settings.")

    source_dir = ROOT / "Sources/OortCore"
    sources = sorted(source_dir.rglob("*.swift"))
    if not sources:
        raise SystemExit("No OortCore Swift sources.")
    check_imports(sources)
    print(f"OortCore: {len(sources)} Swift sources, Foundation/Swift only, no target dependencies or resources.")

    if args.linux_package:
        stage = args.linux_package
        stage.mkdir()
        shutil.copytree(source_dir, stage / "Sources/OortCore")
        shutil.copytree(ROOT / "Tests/OortCoreTests", stage / "Tests/OortCoreTests")
        (stage / "Package.swift").write_text(LINUX_MANIFEST, encoding="utf-8")


if __name__ == "__main__":
    main()
