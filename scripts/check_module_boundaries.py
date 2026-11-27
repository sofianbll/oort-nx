#!/usr/bin/env python3
"""Check the module boundaries of the Swift package.

Modules, kinds, layers and folders come from architecture/names.json and must
match the production Swift targets in Package.swift. A module may import only
the layers below it.

Rules:

1. The core module (role "core") imports Foundation only.
2. Nothing imports a module at its own layer or above.
3. Modules of kind "core" import no interface or device framework
   (AppKit, SwiftUI, Metal, MetalKit, GameController), except the files in
   UI_BASELINE. That baseline can only shrink: a listed file that no longer
   imports the framework is also reported, so the entry gets removed.
4. Only the engine adapter reads checkout HEAD, bundle stamps or managed key status.
5. Play adapters can be admitted only through PlayEngine; views cannot resume native apps directly.

Run from the repository root, or pass --root. Exit status 1 on any violation.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

NAMES = "architecture/names.json"
OORT_CORE_ALLOWED = {"Foundation"}
UI_FRAMEWORKS = {"AppKit", "SwiftUI", "Metal", "MetalKit", "GameController"}
# Known exceptions, by file (relative to the root). Remove an entry when its import goes away.
UI_BASELINE = {
    "core/OortLibrary/Selene/Motion.swift": {"SwiftUI"},
    "core/OortLibrary/Artwork/ArtworkStore.swift": {"AppKit"},
}
IMPORT = re.compile(r"^\s*(?:@\w+\s+)*import\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
ENGINE_READ = re.compile(r'"DMCommit"|"rev-parse"\s*,\s*"HEAD"|"--format=%h %s"|\.readStatus\(\)|'
                         r'fileExists\(atPath:[^\n]*(?:managedKeysURL|keyURL)\.path')
GIT_STATUS = re.compile(r'"status"\s*,\s*"--porcelain"')
LEGACY_PLAY = re.compile(r"\b(?:GamePlay|PlayConnector|NXNativePlayConnector|playRouter|playNXNative)\b")
NATIVE_PLAY = re.compile(r"\bNSWorkspace\.shared\.openApplication\s*\(")
NATIVE_PLAY_ADAPTERS = {
    "Sources/ArcanePorting/Launch/LaunchService.swift",
    "Sources/NXLibrary/Services/MacShortcutAdapter.swift",
}


def imports_of(path):
    return IMPORT.findall(path.read_text(encoding="utf-8"))


def read_modules(root):
    """(modules by name, violations): every Swift module of names.json against Package.swift's targets."""
    declared = json.loads((Path(root) / NAMES).read_text(encoding="utf-8"))["modules"]
    modules = {module["name"]: dict(module, role=role) for role, module in declared.items()}
    manifest = json.loads(subprocess.check_output(
        ["swift", "package", "dump-package"], cwd=root, text=True
    ))
    targets = {target["name"] for target in manifest["targets"] if target["type"] in ("regular", "executable")}
    violations = [f"{NAMES}: missing Swift module {name}" for name in sorted(targets - modules.keys())]
    violations += [f"{NAMES}: {name} is not a Swift module in Package.swift" for name in sorted(modules.keys() - targets)]
    return modules, violations


def scan(root, modules):
    """Yield (module, relative file, imported module) for every import in each module's folder."""
    for module, declared in modules.items():
        folder = root / declared["path"]
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
        modules, violations = read_modules(root)
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError) as error:
        return [f"Cannot compare {NAMES} with Package.swift: {error}"]
    if violations:
        return violations
    layers = {name: module["layer"] for name, module in modules.items()}
    seen_ui = {}
    for module, relative, name in scan(root, modules):
        if modules[module]["role"] == "core" and name not in OORT_CORE_ALLOWED:
            violations.append(f"{relative}: {module} imports {name}; only Foundation is allowed")
        if name in layers and layers[name] >= layers[module]:
            violations.append(f"{relative}: {module} imports {name}, which is not below it")
        if modules[module]["kind"] == "core" and name in UI_FRAMEWORKS:
            seen_ui.setdefault(relative, set()).add(name)
            if name not in UI_BASELINE.get(relative, set()):
                violations.append(f"{relative}: {module} imports the interface framework {name}")
    for relative, names in sorted(UI_BASELINE.items()):
        found = seen_ui.get(relative, set())
        for name in sorted(names - found):
            violations.append(f"{relative}: baseline lists {name}, but the file no longer imports it; remove the entry")
    for file in (file for module in modules.values() for file in (root / module["path"]).rglob("*.swift")):
        relative = file.relative_to(root).as_posix()
        text = file.read_text(encoding="utf-8")
        for match in LEGACY_PLAY.finditer(text):
            violations.append(f"{relative}:{text.count(chr(10), 0, match.start()) + 1}: use engine.play, not {match[0]}")
        if relative not in NATIVE_PLAY_ADAPTERS and NATIVE_PLAY.search(text):
            violations.append(f"{relative}: native Play opens belong to the adapter")
        if relative.startswith("Sources/NXLibrary/Views/") and re.search(r"\brunningGames\.resume\s*\(", text):
            violations.append(f"{relative}: resume through engine.play")
        if relative != "core/OortLibrary/Catalog/PlayEngine.swift" and re.search(r"\.admit\([^\n]*gesture:", text):
            violations.append(f"{relative}: only PlayEngine admits a gesture")
        if relative == "Sources/ArcanePorting/Setup/MacNXNative.swift":
            continue
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
