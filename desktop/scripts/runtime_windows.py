#!/usr/bin/env python3
"""The libraries a Windows program needs beside it, read from what its files import.

runtime_windows.py copy <program.exe> <out> --from <folder>...   copy the ones Windows does not have
runtime_windows.py check <folder> [--imports]                    fail when a file of <folder> needs one that is missing
"""
import argparse
import shutil
import struct
import sys
from pathlib import Path

# Part of Windows 10 and 11. Anything else travels with the app, the Visual C++ runtime included.
WINDOWS = set("""advapi32 bcrypt bcryptprimitives cfgmgr32 combase comctl32 comdlg32 crypt32 cryptbase d2d1 d3d11 dbghelp dwmapi
dwrite dxgi gdi32 hid imm32 iphlpapi kernel32 kernelbase mpr msvcrt ncrypt netapi32 normaliz ntdll ole32 oleaut32 powrprof propsys
psapi rpcrt4 secur32 setupapi shcore shell32 shlwapi ucrtbase user32 userenv uxtheme version winmm winspool ws2_32 wtsapi32
xinput1_4""".split())


def is_windows(name):
    stem = name.lower().removesuffix(".dll")
    return stem in WINDOWS or stem.startswith(("api-ms-win-", "ext-ms-win-")) or stem == "winspool.drv"


def imports(path):
    """Names of the libraries a PE file imports, at start and on first use."""
    data = path.read_bytes()
    if data[:2] != b"MZ":
        raise ValueError(f"{path.name} is not a program")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError(f"{path.name} is not a program")
    count, optional = struct.unpack_from("<H", data, pe + 6)[0], struct.unpack_from("<H", data, pe + 20)[0]
    header = pe + 24
    plus = struct.unpack_from("<H", data, header)[0] == 0x20B
    base = struct.unpack_from("<Q", data, header + 24)[0] if plus else struct.unpack_from("<I", data, header + 28)[0]
    directories = header + (112 if plus else 96)
    sections = [struct.unpack_from("<IIII", data, header + optional + 40 * i + 8) for i in range(count)]

    def offset(rva):
        for size, start, raw_size, raw in sections:
            if start <= rva < start + max(size, raw_size):
                return rva - start + raw
        raise ValueError(f"{path.name}: address outside its sections")

    def text(rva):
        at = offset(rva)
        return data[at:data.index(b"\0", at)].decode("ascii")

    names = []
    for index, step, field in ((1, 20, 12), (13, 32, 4)):
        rva = struct.unpack_from("<I", data, directories + 8 * index)[0]
        if not rva:
            continue
        at = offset(rva)
        while True:
            name = struct.unpack_from("<I", data, at + field)[0]
            if not name:
                break
            # An old delay-load table holds addresses, not offsets from the image's start.
            if index == 13 and not struct.unpack_from("<I", data, at)[0] & 1:
                name -= base
            names.append(text(name))
            at += step
    return names


def copy(program, out, folders):
    out.mkdir(parents=True, exist_ok=True)
    found, todo = {}, [program]
    while todo:
        for name in imports(todo.pop()):
            key = name.lower()
            if is_windows(name) or key in found:
                continue
            source = next((f for folder in folders for f in Path(folder).glob("*.dll") if f.name.lower() == key), None)
            if source is None:
                raise SystemExit(f"{name}: not in Windows, and in none of the folders given")
            found[key] = source
            todo.append(source)
    for source in sorted(found.values(), key=lambda f: f.name.lower()):
        shutil.copy2(source, out / source.name)
        print(f"{source.stat().st_size:>10} {source.name}")


def check(folder, show):
    files = [f for f in folder.rglob("*") if f.suffix.lower() in (".exe", ".dll")]
    here = {f.name.lower() for f in files}
    missing = []
    for file in sorted(files):
        names = imports(file)
        if show:
            print(f"{file.name}: {', '.join(sorted(names, key=str.lower))}")
        missing += [f"{file.name} needs {n}" for n in names if not is_windows(n) and n.lower() not in here]
    if missing:
        raise SystemExit("\n".join(missing))
    print(f"{len(files)} programs and libraries: everything they import is here or in Windows.")


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    one = commands.add_parser("copy")
    one.add_argument("program", type=Path)
    one.add_argument("out", type=Path)
    one.add_argument("--from", dest="folders", nargs="+", required=True)
    two = commands.add_parser("check")
    two.add_argument("folder", type=Path)
    two.add_argument("--imports", action="store_true")
    a = parser.parse_args()
    copy(a.program, a.out, a.folders) if a.command == "copy" else check(a.folder, a.imports)


if __name__ == "__main__":
    sys.exit(main())
