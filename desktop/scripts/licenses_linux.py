#!/usr/bin/env python3
"""The Debian libraries an AppImage carries, with the licence text of each and where its source is.

licenses_linux.py <folder of the extracted AppImage> <file>   fails when a library belongs to no package
"""
import subprocess
import sys
from pathlib import Path

OWN = {"oort-core", "oort-desktop"}


def main(root, out):
    files = sorted({f.name for f in Path(root).rglob("*") if ".so" in f.name and (f.is_file() or f.is_symlink())} - OWN)
    owners, orphans = {}, []
    for name in files:
        found = subprocess.run(["dpkg", "-S", f"*/{name}"], capture_output=True, text=True).stdout
        # The exact file name: the pattern also finds longer ones.
        packages = sorted({line.rsplit(": ", 1)[0].split(",")[0].split(":")[0] for line in found.splitlines() if line.rsplit("/", 1)[-1] == name})
        if packages:
            owners.setdefault(packages[0], []).append(name)
        else:
            orphans.append(name)
    if orphans:
        raise SystemExit("libraries of no package: " + ", ".join(orphans))
    lines, texts = [], []
    for package, names in sorted(owners.items()):
        info = subprocess.check_output(["dpkg-query", "-W", "-f", "${Version}\t${source:Package}\t${source:Version}\n", package], text=True).splitlines()[0]
        version, source, source_version = info.split("\t")
        file = Path("/usr/share/doc") / package / "copyright"
        if not file.is_file():
            raise SystemExit(f"{package}: no copyright file")
        lines.append(f"{package} {version}; source: https://snapshot.debian.org/package/{source}/{source_version}/; files: {', '.join(names)}")
        texts.append(f"\n{'-' * 80}\n{package}\n\n{file.read_text(encoding='utf-8', errors='replace').strip()}\n")
    head = ("Libraries of Debian 12 carried by the Oort NX AppImage, unchanged, as separate files: their package, where the\n"
            "source of that exact version is, and their licence.\n\n")
    Path(out).write_text(head + "\n".join(lines) + "\n" + "".join(texts), encoding="utf-8")
    print(f"{len(files)} libraries of {len(owners)} packages in {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
