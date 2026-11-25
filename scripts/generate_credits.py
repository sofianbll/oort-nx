#!/usr/bin/env python3
"""Write every copy of design/credits.json and check it against what the projects really use.

generate_credits.py                    write the copies this checkout has a place for
generate_credits.py --check            fail when a copy, a notice, the README or a credit is missing or different
generate_credits.py --engine <folder>  also check the third-party code of an nxnative checkout
generate_credits.py --site <folder>    also write (or check) the site's copy and check its built pages
generate_credits.py --same <ref>       also fail when the ref's design/credits.json, or the copy of one of its apps, differs
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "design/credits.json"
ART = "Resources/Brands/Credits"
CARDS = ROOT / "design/credits.css"
TOKENS = ROOT / "design/oort-tokens.css"
# The views that draw the cards; what each may not write itself is in style().
CARD_VIEWS = ("Sources/NXLibrary/Views/OortUI/OortCreditCard.swift",)
CARD_SCREENS = ("Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift",)
LANGUAGES = ("en", "fr", "de", "es", "it", "pt-BR", "zh-Hans")
SYSTEMS = {"mac": "Mac", "windows": "Windows", "linux": "Linux", "ios": "iPhone and iPad", "android": "Android", "site": "site"}
USES = {"adapted": "code adapted", "shipped": "in the app", "engine": "in the engine, which is downloaded separately",
        "service": "service, off until used", "download": "downloaded only on request", "reference": "reference, no code in the app",
        "build": "used to make the app"}
SPDX = {"MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Zlib", "0BSD", "NCSA", "Unlicense", "MPL-2.0", "GPL-2.0-only",
        "LGPL-2.1-or-later", "PSF-2.0", "OFL-1.1", "CC0-1.0", "CC-BY-SA-4.0", "Unicode-3.0", "EPL-1.0", "Swift-exception",
        "LicenseRef-Microsoft-WebView2", "LicenseRef-Microsoft-Visual-Studio"}
BEGIN, END = "BEGIN GENERATED CREDITS (design/credits.json, scripts/generate_credits.py)", "END GENERATED CREDITS"
# Addresses in the code that name no third party: the app itself, a test, a template.
OWN_HOSTS = {"localhost", "127.0.0.1", "cdn", "github", "fr.wikipedia.org", "xwikipedia.org", "steamstatic.com.x.org", "sofianbll.github.io",
             "www.apple.com", "developer.apple.com", "apps.apple.com", "support.apple.com", "schemas.android.com"}


def unique(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate key {key}")
        out[key] = value
    return out


def load(path=None):
    return json.loads((path or SOURCE).read_text(encoding="utf-8"), object_pairs_hook=unique)


def schema(data):
    issues = []

    def words(where, text):
        if set(text) != set(LANGUAGES) or not all(isinstance(v, str) and v.strip() for v in text.values()):
            issues.append(f"{where}: needs a text in {', '.join(LANGUAGES)}")

    for name in ("labels", "roles"):
        for key, text in data[name].items():
            words(f"{name}.{key}", text)
    for item in data["categories"]:
        words(f"category {item['id']}", item["title"])
    for item in data["legal"]:
        words(f"legal {item['id']}", item["text"])
    categories = {c["id"] for c in data["categories"]}
    seen, covered = set(), {}
    for c in data["credits"]:
        who = f"credit {c.get('id')}"
        if c["id"] in seen:
            issues.append(f"{who}: id used twice")
        seen.add(c["id"])
        if c["role"] not in data["roles"]:
            issues.append(f"{who}: unknown role {c['role']}")
        if c["category"] not in categories:
            issues.append(f"{who}: unknown category {c['category']}")
        if c["use"] not in USES:
            issues.append(f"{who}: unknown use {c['use']}")
        if not c["systems"] or not set(c["systems"]) <= set(SYSTEMS):
            issues.append(f"{who}: unknown system")
        if not re.fullmatch(r"https://[^\s]+", c["url"]):
            issues.append(f"{who}: bad link")
        if c["license"] is not None and not set(re.split(r" (?:AND|OR|WITH) ", c["license"])) <= SPDX:
            issues.append(f"{who}: unknown licence {c['license']}")
        if c.get("glyph", data["categories"][0]["glyph"]) not in {x["glyph"] for x in data["categories"]}:
            issues.append(f"{who}: unknown glyph {c['glyph']}")
        if c["license"] is None and c["use"] in ("adapted", "engine") or not c["name"] or not c["author"]:
            issues.append(f"{who}: code needs a licence, a name and an author")
        icon = c.get("icon", data["iconDefault"])
        if icon["allowed"] and not all(icon.get(k) for k in ("asset", "source", "basis")):
            issues.append(f"{who}: an icon needs its file, its source and why it may be shown")
        for key in c["covers"]:
            if key in covered:
                issues.append(f"{who}: {key} is already credited by {covered[key]}")
            covered[key] = c["id"]
    base = data["base"]
    if len(base) != len(set(base)) or not set(base) <= seen:
        issues.append("base: each card once, each with a credit")
    if len(base) % data["columns"] or len(base) % (data["columns"] - 1):
        issues.append(f"base: {len(base)} cards leave a hole in {data['columns']} or {data['columns'] - 1} columns")
    if wrong := [c["id"] for c in data["credits"] if (c["category"] == "base") != (c["id"] in base)]:
        issues.append(f"base: not the same as its category: {', '.join(wrong)}")
    missing = set(data["roles"]) - {c["role"] for c in data["credits"]}
    if missing:
        issues.append(f"roles nobody uses: {', '.join(sorted(missing))}")
    return issues, covered


# ---- what the code really uses -----------------------------------------------------------------------------

def read(path):
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def tracked():
    names = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT).decode().split("\0")
    return [n for n in names if n and (ROOT / n).is_file()]


def dependencies():
    """Every dependency found in this checkout, as the key a credit must cover, with where it was found."""
    found = {}

    def add(key, where):
        found.setdefault(key, where)

    names = tracked()
    if text := read(ROOT / "runtime.lock"):
        lock = json.loads(text)
        add("python:cpython", "runtime.lock")
        add("python:standalone", "runtime.lock")
        for wheel in lock["wheels"]:
            add("wheel:" + wheel["name"].lower(), "runtime.lock")
        for item in lock["brew"]:
            add("brew:" + item["formula"], "runtime.lock")
        # The libraries those two tools load, copied beside them by bundle_runtime.sh.
        bundled = read(ROOT / "scripts/bundle_runtime.sh") + read(ROOT / "scripts/relink_macho.py")
        if bundled:
            add("dylib:lz4", "zstd (Homebrew)"), add("dylib:xz", "zstd (Homebrew)"), add("dylib:spirv-tools", "glslang (Homebrew)")
        if any(w["name"] == "nsz" for w in lock["wheels"]):
            add("font:MPLUS1p-Medium.ttf", "nsz wheel")
    for name in re.findall(r"^([A-Za-z0-9_.-]+)==", read(ROOT / "scripts/dmg-requirements.txt"), re.M):
        add("pip:" + name.lower(), "scripts/dmg-requirements.txt")
    for manifest in ("Package.swift", "mobile/Package.swift"):
        if text := read(ROOT / manifest):
            add("swift:runtime", manifest)
            for url in re.findall(r"\.package\(\s*(?:name:[^,]+,\s*)?url:\s*\"([^\"]+)\"", text):
                add("swiftpm:" + url.removesuffix(".git").rsplit("/", 1)[-1].lower(), manifest)
    if "xcodegen" in read(ROOT / "mobile/scripts/get_xcodegen.sh"):
        add("script:xcodegen", "mobile/scripts/get_xcodegen.sh")
    if text := read(ROOT / "desktop/src-tauri/Cargo.toml"):
        add("cargo:transitive", "Cargo.lock"), add("rust:std", "Cargo.toml")
        for body in re.findall(r"^\[(?:target\.[^\n]*\.)?(?:build-|dev-)?dependencies\]\n(.*?)(?=^\[|\Z)", text, re.M | re.S):
            for name in re.findall(r"^([A-Za-z0-9_-]+)\s*=", body, re.M):
                add("cargo:" + name, "Cargo.toml")
    if text := read(ROOT / "desktop/package.json"):
        for group in ("dependencies", "devDependencies"):
            for name in json.loads(text).get(group, {}):
                add("npm:" + name, "desktop/package.json")
    for name in names:
        if name.startswith("desktop/licenses/") and name.endswith(".txt") and "Swift" not in name:
            add("text:" + Path(name).name, name)
    notice = read(ROOT / "desktop/NOTICE")
    for word, key in (("Visual C++", "windows:vcruntime"), ("NSIS", "windows:nsis"), ("WebKitGTK", "linux:webkitgtk")):
        if word in notice:
            add(key, "desktop/NOTICE")
    for path in sorted((ROOT / "android").rglob("*.gradle.kts")) if (ROOT / "android").is_dir() else []:
        text = path.read_text(encoding="utf-8")
        for group in re.findall(r"(?:mplementation|classpath)\((?:platform\()?\"([\w.-]+):", text):
            key = "androidx.compose" if group.startswith("androidx.compose") else group
            add("gradle:" + key, str(path.relative_to(ROOT)))
        for plugin in re.findall(r"id\(\"([\w.]+)\"\)", text):
            add("gradle:org.jetbrains.kotlin" if plugin.startswith("org.jetbrains.kotlin") else "gradle:" + plugin, str(path.relative_to(ROOT)))
        add("gradle:wrapper", "android/gradle/wrapper")
    for name in names:
        path = Path(name)
        if path.suffix.lower() in (".ttf", ".otf", ".woff", ".woff2"):
            add("font:" + path.name, name)
        if name.startswith("Resources/ThirdPartyLicenses/") and "wheel" not in name:
            add("dir:ThirdPartyLicenses/" + path.name.split("-")[0], name)
        if name.startswith("Resources/Selene/"):
            add("dir:Resources/Selene", name)
        if name.startswith("Resources/SoundPacks/"):
            add("dir:Resources/SoundPacks", name)
        if name.startswith("Resources/Brands/Platforms/"):
            add("dir:Resources/Brands/Platforms", name)
        if "Sources/NXLibraryCore/Resources/crystal-" in name:
            add("media:crystal", name)
    for name, entry in json.loads(read(ROOT / "scripts/bundle-licences.json") or "{}").items():
        if isinstance(entry, dict):
            source = entry["source"]
            add("mark:" + ("simple-icons" if "simple-icons" in source else "wikimedia" if "wikimedia" in source
                           else "codeweavers" if "codeweavers" in source else source), name)
    families = ("selene", "catppuccin", "everforest", "flexoki", "gruvbox", "kanagawa", "nord", "rose-pine", "tokyo-night")
    for palette in json.loads(read(ROOT / "Resources/Selene/palettes.json") or "[]"):
        for family in families:
            if palette["id"].startswith(family):
                add("palette:" + family, "Resources/Selene/palettes.json")
    if (ROOT / "LICENSE").is_file():
        add("file:LICENSE", "LICENSE")
    code = [n for n in names if re.match(r"(Sources|mobile/Sources|mobile/App|android/app/src/main|desktop/src-tauri/src|desktop/ui)/", n)
            and n.endswith((".swift", ".kt", ".rs", ".js", ".m", ".h")) and "/gen/" not in n]
    for name in code:
        text = read(ROOT / name)
        for host in re.findall(r"https?://([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*)", text):
            if host not in OWN_HOSTS:
                add("host:" + host.lower(), name)
        if "titledb" in text.lower():
            add("repo:titledb", name)
        # Only a project named in a comment, as the place code or facts come from.
        comments = "\n".join(re.findall(r"//[^\n]*|/\*.*?\*/|^ \* [^\n]*", text, re.S | re.M))
        for project in ("NX2Apple", "LASRecomp", "Padwake", "nx2android", "LumaNX"):
            if project.lower() in comments.lower():
                add("source:" + project, name)
        if "recomplauncher.json" in text:
            add("source:RecompLauncher", name)
        if "OortSynth" in text or "func sun(" in text:
            add("sound:sun", name)
    for name in ("scripts/bundle_runtime.sh", "scripts/relink_macho.py"):
        if "LumaNX" in read(ROOT / name):
            add("source:LumaNX", name)
    if list(ROOT.glob("Resources/Selene/Sounds/*.wav")):
        add("sound:Selene", "Resources/Selene/Sounds")
    return found


def engine_parts(folder):
    """What an nxnative checkout carries or names in its README."""
    found = {"engine:root": "LICENSE"}
    for path in sorted((folder / "dm/third_party").iterdir()):
        if path.name == "notices":
            found.update({"engine:" + p.name: f"dm/third_party/notices/{p.name}" for p in path.iterdir()})
        elif path.is_dir():
            found["engine:" + path.name] = f"dm/third_party/{path.name}"
    if (folder / "dm/gfx/tools/spirv_cross_bin").is_dir():
        found["engine:spirv_cross_bin"] = "dm/gfx/tools/spirv_cross_bin"
    for project in folder.glob("dm/**/*.csproj"):
        for name in re.findall(r'PackageReference Include="([^"]+)"', project.read_text(encoding="utf-8-sig")):
            found["engine:" + name] = str(project.relative_to(folder))
    if list(folder.glob("dm/**/*.csproj")):
        found["engine:dotnet"] = "the AOT programs built from dm/**/*.csproj"
    for needle, key, file in (("h1k421", "nvn.h", "dm/gfx/nvn/include/nvn.h"), ("deko3d", "deko3d", "dm/gfx/nvn/nvn_tex.c"),
                              ("Touchline23", "Touchline23", "dm/gfx/tools/easf/README.md"), ("d2r-mobile", "d2r-mobile", "README.md"),
                              ("Atmosph", "atmosphere", "README.md")):
        if needle in read(folder / file):
            found["engine:" + key] = file
    return found


# ---- the copies ------------------------------------------------------------------------------------------

def notice_block(data):
    """The index every NOTICE carries: the same list as the screens and the site."""
    lines = ["The same list as in the app’s settings and on the site. The licence texts are in this file, in LICENSE and in",
             "the folders it names; a project whose code is not in the app keeps its own licence where it lives."]
    for category in data["categories"]:
        lines += ["", category["title"]["en"]]
        for c in data["credits"]:
            if c["category"] != category["id"]:
                continue
            lines.append(f"- {c['name']}, by {c['author']}. {data['roles'][c['role']]['en']}. {c['license'] or 'No licence stated'}. "
                         f"{USES[c['use']][0].upper() + USES[c['use']][1:]} ({', '.join(SYSTEMS[s] for s in c['systems'])}). {c['url']}")
            if c.get("includes"):
                lines.append(f"  Includes {', '.join(c['includes'])}.")
    return "\n".join(lines)


def with_block(text, block, markdown=False):
    begin, end = (f"<!-- {BEGIN} -->", f"<!-- {END} -->") if markdown else (f"----- {BEGIN} -----", f"----- {END} -----")
    body = ("## Every credit\n\n" if markdown else "") + block
    new = f"{begin}\n{body}\n{end}\n"
    if begin in text:
        head, _, rest = text.partition(begin)
        return head + new + rest.partition(end + "\n")[2]
    return text.rstrip("\n") + "\n\n" + ("" if markdown else "-" * 80 + "\n") + new


def desktop_script(data):
    keep = [c for c in data["credits"] if {"windows", "linux"} & set(c["systems"]) or c["id"] in data["base"]]
    glyphs = {"heart": "heart", "gamepad": "gamepad", "terminal": "terminal", "puzzle": "puzzle", "palette": "palette", "globe": "language", "hammer": "build"}
    pick = lambda text: {lang: text[lang] for lang in ("en", "fr")}
    out = {"base": data["base"], "columns": data["columns"], "labels": {k: pick(v) for k, v in data["labels"].items()},
           "categories": [dict(id=c["id"], glyph=glyphs[c["glyph"]], title=pick(c["title"])) for c in data["categories"]],
           "legal": [dict(systems=x["systems"], text=pick(x["text"])) for x in data["legal"]],
           "credits": [dict(id=c["id"], name=c["name"], author=c["author"], role=pick(data["roles"][c["role"]]), byline={lang: terms(data, c, lang) if c["author"] == c["name"] else f"{c['author']} · {terms(data, c, lang)}" for lang in ("en", "fr")},
                            url=c["url"], glyph=glyphs[c.get("glyph", next(x["glyph"] for x in data["categories"] if x["id"] == c["category"]))],
                            category=c["category"], systems=c["systems"],
                            art=c["icon"]["asset"] if c.get("icon", {}).get("asset", "") in arts(data) else None) for c in keep]}
    return ("// Generated by scripts/generate_credits.py. Do not edit.\nexport const CREDITS = "
            + json.dumps(out, ensure_ascii=False, indent=0, sort_keys=True) + "\n")


def arts(data):
    return {c["icon"]["asset"] for c in data["credits"] if c.get("icon", {}).get("allowed") and (ROOT / ART / f"{c['icon']['asset']}.png").is_file()}


def terms(data, c, lang):
    """The licence, or what stands in its place; the same rule as Credits.byline."""
    return c["license"] or data["labels"]["online" if c["use"] == "service" else "unlisted"][lang]


def compact(data):
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"


def copies(data):
    """Path to bytes, for every place this checkout has."""
    out, block = {}, notice_block(data)
    text = compact(data).encode()
    for folder, reader in (("Sources/NXLibraryCore/Resources", "Sources/NXLibraryCore/App/Credits+Bundled.swift"),
                           ("mobile/Sources/OortMobile/Resources", "mobile"), ("android/app/src/main/assets", "android")):
        if (ROOT / reader).exists():
            out[f"{folder}/credits.json"] = text
    out["NOTICE"] = with_block(read(ROOT / "NOTICE"), block).encode()
    if (ROOT / "android/NOTICE.md").is_file():
        out["android/NOTICE.md"] = with_block(read(ROOT / "android/NOTICE.md"), block, markdown=True).encode()
        out["android/app/src/main/assets/licences/notices.txt"] = out["android/NOTICE.md"]
    if (ROOT / "desktop/ui/gen").is_dir():
        out["desktop/ui/gen/credits.js"] = desktop_script(data).encode()
        out["desktop/ui/gen/credits.css"] = sheet(data)
    for name in sorted(arts(data)):
        art = (ROOT / ART / f"{name}.png").read_bytes()
        if (ROOT / "mobile/Sources/OortMobile/Resources").is_dir():
            out[f"mobile/Sources/OortMobile/Resources/credit-{name}.png"] = art
        if (ROOT / "android/app/src/main/res").is_dir():
            out[f"android/app/src/main/res/drawable-nodpi/credit_{name}.png"] = art
        if (ROOT / "desktop/ui").is_dir():
            out[f"desktop/ui/gen/credit-{name}.png"] = art
    return out


def manifest(data):
    """The reviewed hashes of the pictures, in the app's own list."""
    path = ROOT / "scripts/bundle-licences.json"
    if not path.is_file():
        return None
    listed = json.loads(path.read_text(encoding="utf-8"))
    listed.update({f"{ART.removeprefix('Resources/')}/{n}.png": hashlib.sha256((ROOT / ART / f"{n}.png").read_bytes()).hexdigest() for n in arts(data)})
    return json.dumps(dict(sorted(listed.items())), indent=2, ensure_ascii=False) + "\n"


def sheet(data):
    """The cards' rules, with the number of columns the source gives; the switch only tells « fits » from « does not »."""
    return (f"/* Generated by scripts/generate_credits.py from design/credits.css. Do not edit. */\n"
            f":root{{--credit-columns:{data['columns']};--credit-switch:9999}}\n").encode() + CARDS.read_bytes()


def ids(text):
    return re.findall(r'data-credit="([^"]+)"', text)


def style(css, views=(), screens=()):
    """A value written by hand where a token must be: (where, value)."""
    found = []
    for name, text in css:
        plain = re.sub(r"/\*.*?\*/|--[\w-]+|\"[^\"]*\"", lambda m: re.sub(r"[^\n]", " ", m[0]), text, flags=re.S)
        for line, code in enumerate(plain.splitlines(), 1):
            values = re.findall(r"#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?|oklch|oklab|lab|lch|cubic-bezier)\(|(?<![\w#.-])[+-]?(?:\d+\.?\d*|\.\d+)[a-z%]*", code)
            # Nothing, the whole, the layer under, one share of the free space and the quarter turn of an arrow are not sizes.
            found += [(f"{name}:{line}", v) for v in values if v not in ("0", "1", "-1", "100%", "1fr", "90deg")]
    strip = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"', re.S)
    for name, text in (*views, *screens):
        plain = strip.sub(lambda m: re.sub(r"[^\n]", " ", m[0]), text)
        for line, code in enumerate(plain.splitlines(), 1):
            if (name, text) in views:
                values = [v for v in re.findall(r"(?<![\w.$])(?:\d+\.?\d*|0x[0-9a-fA-F]+)", code) if v not in ("0", "1")]
                values += re.findall(r"\bColor\s*\.\s*\w+|\bColor\s*\(|\.font\(|\.system\(", code)
            else:
                values = [m for m in re.findall(r"(?:canvas\.u|\.padding|\.opacity|\.cornerRadius|\.system)\([^)]*?\b(\d+\.?\d*)|\b(?:spacing|width|height|minWidth|minHeight|radius|lineWidth|size):\s*([1-9]\d*\.?\d*)", code)]
                values = ["".join(m) for m in values]
            found += [(f"{name}:{line}", v) for v in values]
    return found


def site_style(folder):
    """The site's own sheets may place the cards, not restyle them by hand: every rule that names one."""
    rules = []
    for name in ("site.css", "pages.css", "mobile.css"):
        text = read(folder / name)
        if not text:
            continue
        plain = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m[0]), text, flags=re.S)
        for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", plain):
            if re.search(r"\.cred(?:its?|it-row|it-groups)?\b", m[1]):
                rules.append((f"{name}:{plain.count(chr(10), 0, m.start(2)) + 1} {m[1].strip()[:60]}", m[2]))
    return rules


def site_copies(data, folder):
    out = {"source/credits.json": compact(data).encode(), "oort-tokens.css": TOKENS.read_bytes(), "credits.css": sheet(data)}
    out.update({f"art/merci/{n}.png": (ROOT / ART / f"{n}.png").read_bytes() for n in sorted(arts(data))})
    return {folder / k: v for k, v in out.items()}


def site_pages(data, folder):
    """The built pages name every credit, with its licence and link, in both languages."""
    import html
    issues = []
    for lang, page in (("fr", "credits/index.html"), ("en", "en/credits/index.html")):
        text = read(folder / page)
        if not text:
            issues.append(f"site: {page} is missing")
            continue
        for c in data["credits"]:
            row = re.search(rf'<a [^>]*data-credit="{re.escape(c["id"])}".*?</a>', text, re.S)
            wanted = [c["name"], c["author"], data["roles"][c["role"]][lang], terms(data, c, lang), c["url"]]
            if not row or any(html.escape(w, quote=False) not in html.unescape(row[0]) and w not in html.unescape(row[0]) for w in wanted):
                issues.append(f"site: {page} differs for {c['id']}")
        shown = ids(text)
        if sorted(shown) != sorted(c["id"] for c in data["credits"]):
            issues.append(f"site: {page} does not list each credit once")
        if shown[:len(data["base"])] != data["base"]:
            issues.append(f"site: {page} does not begin with the six cards, in their order")
    for lang, page in (("fr", "index.html"), ("en", "en/index.html")):
        text = read(folder / page)
        if ids(text) != data["base"]:
            issues.append(f"site: {page} does not show the six cards, in their order")
    return issues


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--site", type=Path)
    parser.add_argument("--same", action="append", default=[])
    args = parser.parse_args(argv)
    data = load()
    issues, covered = schema(data)
    if issues:
        raise SystemExit("\n".join(issues))
    if not args.check:
        for name, content in copies(data).items():
            path = ROOT / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        if (text := manifest(data)) is not None:
            (ROOT / "scripts/bundle-licences.json").write_text(text, encoding="utf-8")
        for path, content in (site_copies(data, args.site) if args.site else {}).items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    issues += [f"{name} is not what design/credits.json says: run scripts/generate_credits.py" for name, content in copies(data).items()
               if not (ROOT / name).is_file() or (ROOT / name).read_bytes() != content]
    if (text := manifest(data)) is not None and read(ROOT / "scripts/bundle-licences.json") != text:
        issues.append("scripts/bundle-licences.json does not hold the pictures’ hashes: run scripts/generate_credits.py")
    found = dependencies()
    issues += [f"no credit for {key} (found in {where}): add it to design/credits.json" for key, where in sorted(found.items()) if key not in covered]
    if args.engine:
        issues += [f"no credit for {key} ({where} of the engine)" for key, where in sorted(engine_parts(args.engine).items()) if key not in covered]
    notice = "".join(read(ROOT / n) for n in ("NOTICE", "android/NOTICE.md", "desktop/NOTICE"))
    prose = re.sub(rf"-*\s*{re.escape(BEGIN)}.*?{re.escape(END)}", "", notice, flags=re.S)
    # A notice is asked only where the code is: the Android and Windows ones live in their own branches.
    here = {"mac"} | ({"android"} if (ROOT / "android").is_dir() else set()) | ({"windows", "linux"} if (ROOT / "desktop").is_dir() else set())
    issues += [f"NOTICE does not speak of {c['id']} (“{c['notice']}”)" for c in data["credits"]
               if c.get("notice") and here & set(c["systems"]) and " ".join(c["notice"].split()) not in " ".join(prose.split())]
    if (lock := read(ROOT / "desktop/src-tauri/Cargo.lock")):
        listed = read(ROOT / "desktop/licenses-rust.txt")
        issues += [f"licenses-rust.txt does not list {n} {v}: run desktop/scripts/licenses.py"
                   for n, v in re.findall(r'name = "([^"]+)"\nversion = "([^"]+)"\nsource', lock) if f"{n} {v}: " not in listed]
    for readme in ("README.md", "README.fr.md"):
        text = read(ROOT / readme)
        issues += [f"{readme} does not thank {c['id']} ({c['url']})" for c in data["credits"] if c["id"] in data["base"] and c["url"] not in text]
    sheets = [("design/credits.css", read(CARDS))] + (site_style(args.site) if args.site else [])
    issues += [f"{where}: {value} is written by hand, take a token" for where, value in
               style(sheets, [(n, read(ROOT / n)) for n in CARD_VIEWS], [(n, read(ROOT / n)) for n in CARD_SCREENS])]
    if args.site:
        issues += [f"{path} differs" for path, content in site_copies(data, args.site).items() if not path.is_file() or path.read_bytes() != content]
        issues += site_pages(data, args.site)
    for ref in args.same:
        shown = subprocess.run(["git", "show", f"{ref}:design/credits.json"], cwd=ROOT, capture_output=True)
        if shown.returncode or shown.stdout != SOURCE.read_bytes():
            issues.append(f"{ref} does not have the same design/credits.json")
        # What that branch's own apps were given: Mac, iOS, Android, Windows and Linux.
        for name, text in (("Sources/NXLibraryCore/Resources/credits.json", compact(data)), ("mobile/Sources/OortMobile/Resources/credits.json", compact(data)),
                           ("android/app/src/main/assets/credits.json", compact(data)), ("desktop/ui/gen/credits.js", desktop_script(data))):
            copy = subprocess.run(["git", "show", f"{ref}:{name}"], cwd=ROOT, capture_output=True)
            if copy.returncode == 0 and copy.stdout != text.encode():
                issues.append(f"{ref}: {name} is not what design/credits.json says")
    if issues:
        print("\n".join(issues), file=sys.stderr)
        return 1
    print(f"{len(data['credits'])} credits, {len(found)} dependencies found here, every one credited.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
