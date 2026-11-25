#!/usr/bin/env python3
"""What a reader would otherwise have to check by eye, in whichever of the two phone trees is here. Standard library only."""
import hashlib, json, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CONTRACT = [p for d in ("Sources/OortCore/Shelf", "android/shelf/src/main") for p in (ROOT / d).rglob("*.*") if p.suffix in (".swift", ".kt")]
CONNECTOR = [p for d in ("mobile/Sources/OortDrive", "android/drive/src/main") for p in (ROOT / d).rglob("*.*") if p.suffix in (".swift", ".kt")]
HOSTS = {"accounts.google.com", "oauth2.googleapis.com", "www.googleapis.com"}
problems = []


def code(path):
    return re.sub(r"/\*.*?\*/", "", re.sub(r"(?m)(?<!:)//.*$", "", path.read_text()), flags=re.S)


if not CONTRACT or not CONNECTOR:
    problems.append("no source found")
for p in CONTRACT:
    for word in re.findall(r"URLSession|URLRequest|java\.net\.|HttpURLConnection|https?://|[Gg]oogle|\bDrive\w*|android\.", code(p)):
        problems.append(f"{p.name}: the contract names {word}")
for p in CONNECTOR:
    for host in re.findall(r"https?://([^/\"\s:]+)", code(p)):
        if host not in HOSTS | {"127.0.0.1"}:
            problems.append(f"{p.name}: unexpected host {host}")
    for word in re.findall(r"\b(?:print|println|NSLog|debugPrint|os_log|Logger|Log)\s*[.(]", code(p)):
        problems.append(f"{p.name}: writes a log with {word}")
    for verb in re.findall(r'"(?:PUT|PATCH|DELETE)"', code(p)):
        problems.append(f"{p.name}: can write with {verb}")
for p in (ROOT / "mobile/Package.swift", ROOT / "android/app/build.gradle.kts"):
    if p.exists() and re.search(r'name: "OortMobile",\s*dependencies: \[[^]]*OortDrive|project\(":drive"\)', p.read_text()):
        problems.append(f"{p.name}: the app depends on the connector")
digest = hashlib.sha256()
for p in sorted(HERE.rglob("*")):
    if p.is_file() and "__pycache__" not in p.parts:
        digest.update(f"{p.relative_to(HERE)}\0".encode() + hashlib.sha256(p.read_bytes()).digest())
for p in (HERE / "vectors").glob("*.json"):
    if json.loads(p.read_text())["name"] != p.stem:
        problems.append(f"{p.name}: name")
print(f"{len(CONTRACT)} contract files, {len(CONNECTOR)} connector files, {len(list((HERE / 'vectors').glob('*.json')))} cases, shared folder {digest.hexdigest()[:16]}")
sys.exit("\n".join(problems) if problems else 0)
