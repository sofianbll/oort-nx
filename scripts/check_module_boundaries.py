#!/usr/bin/env python3
"""Check the module boundaries of the Swift package.

Layers come from architecture/model.c4 and must cover the production Swift
targets in Package.swift. A module may import only the layers below it.

Rules:

1. OortCore imports Foundation only.
2. Nothing imports a module at its own layer or above.
3. OortCore and NXLibraryCore import no interface or device framework
   (AppKit, SwiftUI, Metal, MetalKit, GameController), except the files in
   UI_BASELINE. That baseline can only shrink: a listed file that no longer
   imports the framework is also reported, so the entry gets removed.
4. Only the engine adapter reads checkout HEAD, bundle stamps or managed key status.

Run from the repository root, or pass --root. Exit status 1 on any violation.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

# shortcut: one swiftModule declaration with inline layer metadata per line;
# use LikeC4's JSON export if the model needs a more flexible declaration format.
SWIFT_MODULE = re.compile(
    r'^[ \t]*([A-Za-z_]\w*)[ \t]*=[ \t]*swiftModule[ \t]*\{'
    r'[ \t]*metadata[ \t]*\{[ \t]*layer[ \t]+"([0-9]+)"[ \t]*\}',
    re.MULTILINE,
)
CORE_MODULES = ("OortCore", "NXLibraryCore")
OORT_CORE_ALLOWED = {"Foundation"}
UI_FRAMEWORKS = {"AppKit", "SwiftUI", "Metal", "MetalKit", "GameController"}
# Known exceptions, by file (relative to the root). Remove an entry when its import goes away.
UI_BASELINE = {
    "Sources/NXLibraryCore/Selene/Motion.swift": {"SwiftUI"},
    "Sources/NXLibraryCore/Artwork/ArtworkStore.swift": {"AppKit"},
}
IMPORT = re.compile(r"^\s*(?:@\w+\s+)*import\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
ENGINE_READ = re.compile(r'"DMCommit"|"rev-parse"\s*,\s*"HEAD"|"--format=%h %s"|\.readStatus\(\)|'
                         r'fileExists\(atPath:[^\n]*(?:managedKeysURL|keyURL)\.path')
GIT_STATUS = re.compile(r'"status"\s*,\s*"--porcelain"')


def imports_of(path):
    return IMPORT.findall(path.read_text(encoding="utf-8"))


def read_layers(root):
    model = "architecture/model.c4"
    source = re.sub(r"/\*.*?\*/|//[^\n]*", "", (root / model).read_text(encoding="utf-8"), flags=re.DOTALL)
    entries = SWIFT_MODULE.findall(source)
    layers = {module: int(layer) for module, layer in entries}
    manifest = json.loads(subprocess.check_output(
        ["swift", "package", "dump-package"], cwd=root, text=True
    ))
    targets = {target["name"] for target in manifest["targets"] if target["type"] in ("regular", "executable")}
    violations = [f"{model}: missing Swift module {name}" for name in sorted(targets - layers.keys())]
    violations += [f"{model}: {name} is not a Swift module in Package.swift" for name in sorted(layers.keys() - targets)]
    if len(entries) != len(re.findall(r"\bswiftModule\b", source)):
        violations.append(f"{model}: expected a layer on the Swift module declaration line")
    if len(entries) != len(layers):
        violations.append(f"{model}: duplicate Swift module declaration")
    return layers, violations


def scan(root, layers):
    """Yield (module, relative file, imported module) for every import in Sources/."""
    for module in layers:
        folder = root / "Sources" / module
        if not folder.is_dir():
            continue
        for file in sorted(folder.rglob("*.swift")):
            if file.is_symlink():
                continue
            relative = file.relative_to(root).as_posix()
            for name in imports_of(file):
                yield module, relative, name


def check(root):
    root = Path(root)
    try:
        layers, violations = read_layers(root)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        return [f"Cannot compare architecture/model.c4 with Package.swift: {error}"]
    if violations:
        return violations
    seen_ui = {}
    for module, relative, name in scan(root, layers):
        if module == "OortCore" and name not in OORT_CORE_ALLOWED:
            violations.append(f"{relative}: OortCore imports {name}; only Foundation is allowed")
        if name in layers and layers[name] >= layers[module]:
            violations.append(f"{relative}: {module} imports {name}, which is not below it")
        if module in CORE_MODULES and name in UI_FRAMEWORKS:
            seen_ui.setdefault(relative, set()).add(name)
            if name not in UI_BASELINE.get(relative, set()):
                violations.append(f"{relative}: {module} imports the interface framework {name}")
    for relative, names in sorted(UI_BASELINE.items()):
        found = seen_ui.get(relative, set())
        for name in sorted(names - found):
            violations.append(f"{relative}: baseline lists {name}, but the file no longer imports it; remove the entry")
    for file in (root / "Sources").rglob("*.swift"):
        relative = file.relative_to(root).as_posix()
        if relative == "Sources/ArcanePorting/Setup/MacNXNative.swift":
            continue
        text = file.read_text(encoding="utf-8")
        matches = list(ENGINE_READ.finditer(text))
        # Keep the existing write-time guard immediately before changing the checkout.
        if relative != "Sources/ArcanePorting/Setup/NewestEngine.swift":
            matches.extend(GIT_STATUS.finditer(text))
        for match in matches:
            line = text.count("\n", 0, match.start()) + 1
            violations.append(f"{relative}:{line}: read engine facts through MacNXNative")
    return violations


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=".", help="repository root")
    args = parser.parse_args(argv)
    violations = check(args.root)
    for line in violations:
        print(line)
    if violations:
        print(f"{len(violations)} module boundary violation(s).")
        return 1
    print("Module boundaries hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
