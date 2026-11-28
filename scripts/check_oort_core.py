#!/usr/bin/env python3
"""R3: the core compiles on every system. Check its manifest, its imports and its Apple-only names.

The core is every module of kind "core" in architecture/names.json, with its tests. Every Swift file is parsed the
way the compiler does, after removing the #if lines, so that a condition cannot hide an import. A core file imports
only portable modules. The system folder of the library (SYSTEM) is the one place where a file may import the C
library of a system, branch on the system with #if os(...) or call an Apple-only name: one API, one variant per
system. Outside it, the only conditional import is FoundationNetworking, which Linux and Windows keep apart.
"""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import names  # architecture/names.json

ROOT = Path(__file__).resolve().parents[1]
CONDITIONAL = re.compile(r"^[ \t]*#(?:if|elseif|else|endif)\b[^\n]*", re.MULTILINE)
CONDITION = re.compile(r"^[ \t]*#(?:if|elseif)\b([^\n]*)", re.MULTILINE)
IMPORT = re.compile(r'^\s*\(import_decl .*? module="([^"]+)"', re.MULTILINE)
PORTABLE = {"Foundation", "FoundationEssentials", "FoundationNetworking", "Swift", "Synchronization", "Observation",
            "Crypto"}
TESTING = {"XCTest", "Testing"}
# The C library of each system, the system log, and the core's own C target: SYSTEM only.
SYSTEM_SHIM = names.MODULES["cSystem"]["name"]
SYSTEM_MODULES = {"Darwin", "Glibc", "Musl", "Android", "WinSDK", "ucrt", "os", SYSTEM_SHIM}
# Names that exist only on Apple systems, or behave differently there: SYSTEM only.
APPLE_NAMES = re.compile(
    r"\b(CFPreferences\w*|NSWorkspace|NSImage|NSBitmapImageRep|CGContext|CGImage\w*|SecItem\w*|SecKeychain\w*|"
    r"SecStaticCode\w*|os_log|OSLog|OSAllocatedUnfairLock|clonefile|fclonefileat|renamex_np|renameatx_np|trashItem|"
    r"makeFileSystemObject\w*|ObservableObject|Published|AnyCancellable|PassthroughSubject|autoreleasepool|"
    r"NLLanguageRecognizer|FSEvent\w*|vDSP_\w+|volumeAvailableCapacityForImportantUsage\w*|st_\w+timespec|d_namlen|"
    r"Darwin\.\w+|Glibc\.\w+)\b")
# Outside SYSTEM, a condition may name the build (DEBUG...) or FoundationNetworking, nothing about the system.
SYSTEM_CONDITION = re.compile(r"\b(os|arch|targetEnvironment|canImport|_runtime)\s*\(")
NETWORKING_CONDITION = re.compile(r"^\s*canImport\s*\(\s*FoundationNetworking\s*\)\s*$")
# A string literal without interpolation cannot call an API: a test may name one in a message or a source it reads.
LITERAL = re.compile(r'"""(?:(?!""").)*?"""|"(?:[^"\\\n]|\\.)*"', re.DOTALL)


def core_modules():
    """(module name, source folder, test folder or None) for every Swift core module."""
    return [(module["name"], module["path"], module.get("tests", {}).get("path"))
            for module in names.MODULES.values() if module["kind"] == "core" and module.get("language") != "c"]


def system_folder():
    return f"{names.path('library')}/System/"


def dump_imports(path, scratch):
    """The modules a Swift file imports, every #if branch included."""
    stripped = Path(scratch) / (path.as_posix().replace("/", "_"))
    stripped.write_text(CONDITIONAL.sub("", path.read_text(encoding="utf-8")), encoding="utf-8")
    output = subprocess.check_output(["swiftc", "-frontend", "-dump-parse", str(stripped)], text=True,
                                     stderr=subprocess.DEVNULL)
    found = IMPORT.findall(output)
    if len(found) != output.count("(import_decl "):
        raise SystemExit(f"{path}: unsupported Swift import dump")
    return {name.split(".")[0] for name in found}


def problems_of(root, relative, imports, own_modules, is_test):
    """What a core file breaks, as short phrases."""
    text = (root / relative).read_text(encoding="utf-8")
    in_system = relative.startswith(system_folder())
    allowed = PORTABLE | own_modules | (TESTING if is_test else set()) | (SYSTEM_MODULES if in_system else set())
    found = [f"imports {name}" for name in sorted(imports - allowed)]
    if not in_system:
        code = re.sub(r"//[^\n]*", "", text)
        code = LITERAL.sub(lambda literal: literal[0] if "\\(" in literal[0] else '""', code)
        found += [f"uses {name}" for name in sorted(set(APPLE_NAMES.findall(code)))]
        for condition in CONDITION.findall(code):
            if SYSTEM_CONDITION.search(condition) and not NETWORKING_CONDITION.match(condition):
                found.append(f"branches on the system ({condition.strip()})")
    return found


def scan(root):
    """{relative path: [problems]} for every Swift file of the core and its tests."""
    root = Path(root)
    modules = core_modules()
    own = {name for name, _, _ in modules}
    files = []
    for _, source, tests in modules:
        files += [(path, False) for path in sorted((root / source).rglob("*.swift"))]
        if tests:
            files += [(path, True) for path in sorted((root / tests).rglob("*.swift"))]
    with tempfile.TemporaryDirectory(prefix="oort-core-imports-") as scratch, ThreadPoolExecutor(8) as pool:
        imports = list(pool.map(lambda item: dump_imports(item[0], scratch), files))
    result = {}
    for (path, is_test), found in zip(files, imports):
        relative = path.relative_to(root).as_posix()
        result[relative] = problems_of(root, relative, found, own, is_test)
    return result


def check_manifest(root):
    manifest = json.loads(subprocess.check_output(["swift", "package", "--disable-sandbox", "dump-package"], cwd=root))
    return check_targets(manifest["targets"])


def check_targets(manifest_targets):
    """What the manifest's targets (swift package dump-package) break of R3."""
    targets = {target["name"]: target for target in manifest_targets}
    own = {name for name, _, _ in core_modules()}
    violations = []
    shim = targets.get(SYSTEM_SHIM)
    if (not shim or shim["type"] != "regular" or shim.get("path") != names.path("cSystem")
        or any(shim.get(key) for key in ("dependencies", "resources", "sources", "exclude", "settings"))):
        violations.append(f"Package.swift: {SYSTEM_SHIM} must be a plain C target with no dependencies")
    for name, path, _ in core_modules():
        target = targets.get(name)
        if target is None or target["type"] != "regular" or target.get("path") != path:
            violations.append(f"Package.swift: {name} must be a regular target at {path}")
            continue
        # The catalogue is copied unchanged; a source cannot be hidden by treating it as a resource.
        copied = {resource["path"] for resource in target.get("resources", [])
                  if resource["path"].endswith(".xcstrings") and "copy" in resource.get("rule", {})}
        if target.get("sources") or not set(target.get("exclude") or []) <= copied:
            violations.append(f"Package.swift: {name} lists files; the core is a folder")
        if [setting["kind"] for setting in target.get("settings", [])] != [{"swiftLanguageMode": {"_0": "6"}}]:
            violations.append(f"Package.swift: {name} has only the Swift 6 language mode as a setting")
        for dependency in target.get("dependencies", []):
            kind, value = next(iter(dependency.items()))
            dependency_name = value[0]
            if dependency_name == SYSTEM_SHIM and name == names.LIBRARY and kind in {"target", "byName"}:
                if (value[1] or {}).get("platformNames") != ["linux"]:
                    violations.append(f"Package.swift: {SYSTEM_SHIM} is a Linux-only system shim")
                continue
            if kind == "product" and value[1] == "swift-crypto" and dependency_name == "Crypto":
                continue
            if dependency_name not in own:
                violations.append(f"Package.swift: {name} depends on {dependency_name}, outside the core")
    core = targets.get(names.CORE)
    if core and (core.get("dependencies") or core.get("resources")):
        violations.append(f"Package.swift: {names.CORE} has no dependencies or resources")
    return violations


def check(root):
    return [f"{relative}: {phrase}; the core must compile on every system (R3)"
            for relative, found in sorted(scan(root).items()) for phrase in found]


def main():
    violations = check_manifest(ROOT) + check(ROOT)
    for line in violations:
        print(line)
    if violations:
        print(f"{len(violations)} portable-core violation(s).")
        return 1
    print("Core: portable imports, names and conditions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
