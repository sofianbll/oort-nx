#!/usr/bin/env python3
"""Check the module boundaries of the Swift package.

Modules, kinds, layers and folders come from architecture/names.json and must
match the production Swift targets in Package.swift. A module may import only
the layers below it.

Rules:

1. The core module (role "core") imports Foundation only.
2. Nothing imports a module at its own layer or above.
3. What the core may import on every system is R3: scripts/check_oort_core.py.
4. Only the engine adapter reads checkout HEAD, bundle stamps or managed key status.
5. Play adapters can be admitted only through PlayEngine; views cannot resume native apps directly.
6. In an app, only its entry point (`entry` in names.json) imports a module of kind "engine"
   (docs/adr/0002-engine-adapters-at-the-entry-point.md). The files that do so today are listed in
   ENGINE_DEBT; the list can only shrink: a listed file that no longer imports the engine is reported,
   and with --base a file that the base did not list is refused.

Run from the repository root, or pass --root. Exit status 1 on any violation.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

from repo_model import renamed

NAMES = "architecture/names.json"
ENGINE_DEBT = "scripts/engine-import-debt.json"
OORT_CORE_ALLOWED = {"Foundation"}
IMPORT = re.compile(r"^\s*(?:@\w+\s+)*import\s+(?:(?:struct|class|enum|protocol|typealias|func|let|var)\s+)?"
                    r"([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
ENGINE_READ = re.compile(r'"DMCommit"|"rev-parse"\s*,\s*"HEAD"|"--format=%h %s"|\.readStatus\(\)|'
                         r'fileExists\(atPath:[^\n]*(?:managedKeysURL|keyURL)\.path')
GIT_STATUS = re.compile(r'"status"\s*,\s*"--porcelain"')
LEGACY_PLAY = re.compile(r"\b(?:GamePlay|PlayConnector|NXNativePlayConnector|playRouter|playNXNative)\b")
NATIVE_PLAY = re.compile(r"\bNSWorkspace\.shared\.openApplication\s*\(")
NATIVE_PLAY_ADAPTERS = {
    "engines/nxnative/NxnativeAdapter/Launch/LaunchService.swift",
    "apps/mac/OortMac/Services/MacShortcutAdapter.swift",
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


def engine_debt(root, ref=None):
    """The files listed in ENGINE_DEBT, in the checkout or in REF (named as they are now); None when REF has none."""
    if ref is None:
        path = Path(root) / ENGINE_DEBT
        return set(json.loads(path.read_text(encoding="utf-8"))["files"]) if path.is_file() else set()
    shown = subprocess.run(["git", "show", f"{ref}:{ENGINE_DEBT}"], cwd=root, capture_output=True, text=True)
    if shown.returncode:
        return None
    moved = renamed(root, ref)
    return {moved.get(name, name) for name in json.loads(shown.stdout)["files"]}


def check(root, base=None):
    root = Path(root)
    try:
        modules, violations = read_modules(root)
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError) as error:
        return [f"Cannot compare {NAMES} with Package.swift: {error}"]
    if violations:
        return violations
    layers = {name: module["layer"] for name, module in modules.items()}
    debt = engine_debt(root)
    seen_engine = set()
    for module, relative, name in scan(root, modules):
        if modules[module]["kind"] == "app" and modules.get(name, {}).get("kind") == "engine" \
                and relative != modules[module].get("entry"):
            seen_engine.add(relative)
            if relative not in debt:
                violations.append(f"{relative}: {module} imports the engine {name}; only the app's entry point may "
                                  f"(ADR 0002)")
        if modules[module]["role"] == "core" and name not in OORT_CORE_ALLOWED:
            violations.append(f"{relative}: {module} imports {name}; only Foundation is allowed")
        if name in layers and layers[name] >= layers[module]:
            violations.append(f"{relative}: {module} imports {name}, which is not below it")
    for relative in sorted(debt - seen_engine):
        violations.append(f"{ENGINE_DEBT}: {relative} no longer imports an engine; remove the entry")
    if base is not None:
        before = engine_debt(root, base)
        if before is not None:
            for relative in sorted(debt - before):
                violations.append(f"{ENGINE_DEBT}: new entry {relative}; the list only shrinks (ADR 0002)")
    for file in (file for module in modules.values() for file in (root / module["path"]).rglob("*.swift")):
        relative = file.relative_to(root).as_posix()
        text = file.read_text(encoding="utf-8")
        for match in LEGACY_PLAY.finditer(text):
            violations.append(f"{relative}:{text.count(chr(10), 0, match.start()) + 1}: use engine.play, not {match[0]}")
        if relative not in NATIVE_PLAY_ADAPTERS and NATIVE_PLAY.search(text):
            violations.append(f"{relative}: native Play opens belong to the adapter")
        if relative.startswith("apps/mac/OortMac/Views/") and re.search(r"\brunningGames\.resume\s*\(", text):
            violations.append(f"{relative}: resume through engine.play")
        if relative != "core/OortLibrary/Catalog/PlayEngine.swift" and re.search(r"\.admit\([^\n]*gesture:", text):
            violations.append(f"{relative}: only PlayEngine admits a gesture")
        if relative == "engines/nxnative/NxnativeAdapter/Setup/MacNXNative.swift":
            continue
        matches = list(ENGINE_READ.finditer(text))
        # Keep the existing write-time guard immediately before changing the checkout.
        if relative != "engines/nxnative/NxnativeAdapter/Setup/NewestEngine.swift":
            matches.extend(GIT_STATUS.finditer(text))
        for match in matches:
            line = text.count("\n", 0, match.start()) + 1
            violations.append(f"{relative}:{line}: read engine facts through MacNXNative")
    return violations


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument("--base", help="refuse an engine-import debt entry this Git revision did not have")
    args = parser.parse_args(argv)
    violations = check(args.root, args.base)
    for line in violations:
        print(line)
    if violations:
        print(f"{len(violations)} module boundary violation(s).")
        return 1
    print("Module boundaries hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
