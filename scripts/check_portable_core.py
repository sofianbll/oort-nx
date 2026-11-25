#!/usr/bin/env python3
"""Check the portable core: no Apple import in OortCore or in the NXLibraryCore files listed in Package.swift.

The list is `portableSources` in Package.swift; Windows and Linux build exactly those files (and a Mac does with
OORT_PORTABLE=1). This script reads it, parses every file the way the compiler does (so `#if` cannot hide an
import), and refuses Apple-only imports and a few Apple-only calls. It does not replace a build on Windows.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONDITIONAL = re.compile(r"^[ \t]*#(?:if|elseif|else|endif)\b[^\n]*", re.MULTILINE)
IMPORT = re.compile(r'^\s*\(import_decl .*? module="([^"]+)"', re.MULTILINE)
ALLOWED = {"Foundation", "Swift", "OortCore", "NXLibraryCore", "OortCompanion", "XCTest"}
# Calls that exist only on Apple platforms (or behave differently there), checked by name.
APPLE_CALLS = re.compile(r"\b(CFPreferences\w*|NSWorkspace|NSImage|CGContext|CGImage|SecItem\w*|os_log|OSLog|"
                         r"clonefile|renamex_np|FileManager\.default\.trashItem|DispatchSource\.makeFileSystemObject\w*|"
                         r"ObservableObject|@Published|autoreleasepool)\b")


def listed(name):
    text = (ROOT / "Package.swift").read_text(encoding="utf-8")
    match = re.search(r"let %s(?::\s*\[String\])? = \[(.*?)\n\]" % name, text, re.S)
    if not match:
        raise SystemExit(f"Package.swift has no `{name}` list.")
    return re.findall(r'"([^"]+)"', match.group(1))


def main():
    files = sorted((ROOT / "Sources/OortCore").rglob("*.swift"))
    files += [ROOT / "Sources/NXLibraryCore" / path for path in listed("portableSources")]
    for target in ("Sources/OortCompanion", "Sources/oort-core", "Tests/OortCompanionTests"):
        files += sorted((ROOT / target).rglob("*.swift"))
    files += [ROOT / "Tests/NXLibraryCoreTests" / path for path in listed("portableTests")]
    problems = []
    with tempfile.TemporaryDirectory(prefix="oort-portable-") as scratch:
        for index, source in enumerate(files):
            if not source.is_file():
                problems.append(f"{source.relative_to(ROOT)}: listed but missing")
                continue
            text = source.read_text(encoding="utf-8")
            stripped = CONDITIONAL.sub("", text)
            path = Path(scratch) / f"{index}.swift"
            path.write_text(stripped, encoding="utf-8")
            dump = subprocess.check_output(["swiftc", "-frontend", "-dump-parse", str(path)], text=True, stderr=subprocess.DEVNULL)
            imports = IMPORT.findall(dump)
            if len(imports) != dump.count("(import_decl "):
                problems.append(f"{source.relative_to(ROOT)}: unsupported import dump")
            bad = sorted({name.split(".")[0] for name in imports} - ALLOWED)
            if bad:
                problems.append(f"{source.relative_to(ROOT)}: Apple or unknown imports: {', '.join(bad)}")
            code = re.sub(r"//[^\n]*", "", text)
            for hit in sorted(set(APPLE_CALLS.findall(code))):
                if hit not in ("ObservableObject", "@Published") or "Tests/" not in str(source):
                    problems.append(f"{source.relative_to(ROOT)}: Apple-only name `{hit}`")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"portable core: {len(files)} Swift files, imports limited to {', '.join(sorted(ALLOWED))}, no Apple-only call.")


if __name__ == "__main__":
    main()
