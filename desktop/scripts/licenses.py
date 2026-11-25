#!/usr/bin/env python3
"""Write licenses-rust.txt: every Rust library that can end up in the program, with its licence."""
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
data = json.loads(subprocess.check_output(["cargo", "metadata", "--format-version", "1", "--locked"], cwd=HERE / "src-tauri"))
rows = sorted({(p["name"], p["version"], p["license"] or "see " + str(p["license_file"])) for p in data["packages"] if p["source"]})
(HERE / "licenses-rust.txt").write_text("".join(f"{n} {v}: {l}\n" for n, v, l in rows))
odd = sorted({l for _, _, l in rows if not any(x in l for x in ("MIT", "Apache", "BSD", "Zlib", "ISC", "Unicode", "CC0", "MPL"))})
print(f"{len(rows)} libraries" + (f"; to read: {odd}" if odd else ""))
