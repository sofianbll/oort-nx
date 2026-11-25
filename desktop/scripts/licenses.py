#!/usr/bin/env python3
"""The Rust libraries that can end up in the program, with their licences.

licenses.py                           write licenses-rust.txt: name, version, licence (kept in the repository)
licenses.py --texts <file> <target>   write every licence text of one target's libraries (made for each package)
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
WORDS = ("licen", "copying", "notice", "unlicense", "copyright")


def metadata(*more):
    return json.loads(subprocess.check_output(["cargo", "metadata", "--format-version", "1", "--locked", *more], cwd=HERE / "src-tauri"))


def names():
    rows = sorted({(p["name"], p["version"], p["license"] or "see " + str(p["license_file"])) for p in metadata()["packages"] if p["source"]})
    (HERE / "licenses-rust.txt").write_text("".join(f"{n} {v}: {l}\n" for n, v, l in rows))
    odd = sorted({l for _, _, l in rows if not any(x in l for x in ("MIT", "Apache", "BSD", "Zlib", "ISC", "Unicode", "CC0", "MPL"))})
    print(f"{len(rows)} libraries" + (f"; to read: {odd}" if odd else ""))


def texts(out, target):
    data = metadata("--filter-platform", target)
    used = {n["id"] for n in data["resolve"]["nodes"]}
    packages = sorted((p for p in data["packages"] if p["source"] and p["id"] in used), key=lambda p: (p["name"], p["version"]))
    bodies, lines = {}, []
    for p in packages:
        folder = Path(p["manifest_path"]).parent
        files = sorted(f for f in folder.iterdir() if f.is_file() and any(w in f.name.lower() for w in WORDS))
        marks = []
        for file in files:
            body = file.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n").strip()
            mark = hashlib.sha256(body.encode()).hexdigest()[:12]
            bodies.setdefault(mark, body)
            marks.append(mark)
        where = p["repository"] or f"https://crates.io/crates/{p['name']}"
        lines.append(f"{p['name']} {p['version']}: {p['license'] or 'see its text'}; {where}; "
                     + (f"text {', '.join(marks)}" if marks else "no licence file in the package: its licence is the one named here"))
    head = ("Rust libraries linked into Oort NX, their licences, and where their source is. Libraries under MPL-2.0 are used\n"
            "unchanged; their source is at the address given and at https://crates.io/crates/<name>/<version>.\n\n")
    body = "".join(f"\n{'-' * 80}\ntext {mark}\n\n{text}\n" for mark, text in bodies.items())
    Path(out).write_text(head + "\n".join(lines) + "\n" + body, encoding="utf-8")
    print(f"{len(packages)} libraries, {len(bodies)} texts in {out}")


if __name__ == "__main__":
    texts(sys.argv[2], sys.argv[3]) if sys.argv[1:2] == ["--texts"] else names()
