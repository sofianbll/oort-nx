#!/usr/bin/env python3
"""Ratchet literal view styles and duplicate components while migrating to OortUI."""
import argparse
from collections import Counter
import json
import io
from pathlib import Path
import re
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "scripts/selene-token-debt.json"
TOKENS = {"Sources/OortCore/SeleneTokens.swift"}
VIEWS = "Sources/NXLibrary/Views/"
LIBRARY = VIEWS + "OortUI/"
VERSION = 3
# Assembled only from OortUI pieces around one screen's data; like any screen, they hold no style of their own.
COMPOSITIONS = {
    "CollectionCoverRow", "AppUpdateDialog", "IGDBCredentialsDialog", "SteamGridDBKeyDialog", "CloudPersonalAppUpdateRow",
    "DetailsAchievementsCard", "CloudReferenceDialog", "NextendoClientDialog", "ActivityRow", "ProfilePINDialog",
    "ProfileSwitchDialog", "MenuCard", "AchievementsScreenRow", "ModStoreRow",
}
# The one place a font file is named.
FONTS = VIEWS + "Theme/SeleneFonts.swift"
ADDED_IN_3 = ("spacing:", "lineWidth:")
NUMBER = r"[+-]?(?:\d[\d_]*(?:\.[\d_]+)?|\.\d+)(?:[eE][+-]?\d+)?\b"
CALL = re.compile(
    r"(?P<font>\.font\s*\(\s*\.system\s*\(\s*size\s*:\s*|\.seleneFont\s*\(\s*)"
    r"|(?P<padding>\.padding\s*\(\s*(?:\.[a-zA-Z]\w*\s*,\s*)?)"
    r"|(?P<radius>\bcornerRadius\s*(?:\(|:)\s*)"
    r"|(?P<spacing>\bspacing\s*:\s*)"
    r"|(?P<stroke>\blineWidth\s*:\s*)"
)
VALUE = re.compile(rf"(?:\bcanvas\s*\.\s*u\s*\(\s*)?({NUMBER})")
NON_CODE = re.compile(
    r'//[^\n]*|/\*.*?\*/|(?P<raw>\#*)"""[\s\S]*?"""(?P=raw)'
    r'|(?P<hash>\#+)"[^\n]*?"(?P=hash)|"(?:\\.|[^"\\\n])*"',
    re.DOTALL,
)
SWIFT_COLOR = (r"black|white|clear|gray|red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|"
               r"brown|primary|secondary|accentColor|labelColor|secondaryLabelColor|controlAccentColor")
STYLE = re.compile(
    rf"(?P<opacity>\.opacity\s*\(\s*{NUMBER})"
    rf"|(?P<color>\b(?:NSColor|Color)\s*\.\s*(?:{SWIFT_COLOR})\b"
    rf"|\b(?:NSColor|Color)\s*\(\s*(?:red|white|hue|srgbRed)\s*:"
    rf"|\b0x[0-9a-fA-F]{{6}}(?:[0-9a-fA-F]{{2}})?\b"
    rf"|\.(?:foregroundStyle|foregroundColor|background|fill|stroke(?:Border)?|tint|shadow)\s*\(\s*"
    rf"(?:color\s*:\s*)?\.(?:{SWIFT_COLOR})\b)"
    r"|(?P<shadow>\.shadow\s*\()"
    r"|(?P<font>\.font\s*\(\s*(?!\s*\.system\s*\(\s*size\s*:)(?:\.\w+|Font\.system))"
    r"|(?P<animation>(?<!\w)(?:withAnimation|\.animation|\.withAnimation)\s*\(\s*(?:Animation\s*)?"
    r"\.(?:spring|bouncy|smooth|snappy|linear|easeInOut|easeIn|easeOut|timingCurve|interpolatingSpring)\b)"
    r"|(?P<component>\bstruct\s+\w*(?:Row|Card|Dialog|Button)(?:\s*<[^{}]+?>)?\s*:\s*(?:SwiftUI\.)?View\b)"
)


def numeric(code):
    for call in CALL.finditer(code):
        value = VALUE.match(code, call.end())
        # Zero spacing is the absence of a gap, not a style.
        if value and not (call.lastgroup == "spacing" and float(value[1].replace("_", "")) == 0):
            signature = re.sub(r"\s+", "", call[0] + value[0])
            yield signature, code.count("\n", 0, call.start()) + 1


def added_styles(code):
    for match in STYLE.finditer(code):
        text = match[0]
        if match.lastgroup == "shadow":
            depth = 1
            for bracket in re.finditer(r"[()]", code[match.end():]):
                depth += 1 if bracket[0] == "(" else -1
                if depth == 0:
                    text += code[match.end():match.end() + bracket.end()]
                    break
        signature = re.sub(r"\s+", "", text)
        # Like zero spacing: nothing drawn, or drawn whole, is the absence of a style.
        if match.lastgroup == "component" and re.search(r"struct(\w+)", signature)[1] in COMPOSITIONS:
            continue
        if re.search(r"(?:Color\.|\.|\(\.)clear$", signature) or re.fullmatch(r"\.opacity\((?:0|1)(?:\.0)?", signature):
            continue
        yield f"{match.lastgroup}:{signature}", code.count("\n", 0, match.start()) + 1


def literals(text, *, styles=False, numeric_enabled=True):
    # Preserve newlines so diagnostics point to the source, not the stripped text.
    code = NON_CODE.sub(lambda m: re.sub(r"[^\n]", " ", m[0]), text)
    if numeric_enabled:
        yield from numeric(code)
    if styles:
        yield from added_styles(code)


def scan(root=ROOT):
    return {
        relative: list(literals(path.read_text(), styles=relative.startswith(VIEWS) and not relative.startswith(LIBRARY)
                                and relative != FONTS))
        for path in sorted((root / "Sources").rglob("*.swift"))
        if (relative := path.relative_to(root).as_posix()) not in TOKENS
    }


def counts(found):
    return {path: dict(sorted(Counter(sig for sig, _ in matches).items())) for path, matches in found.items() if matches}


def base_allowances(base, tracked):
    if tracked.get("version") == VERSION:
        return tracked["files"]
    if tracked.get("version") == 2:
        # Bootstrap only the numeric categories added in 3, from actual source at the base revision.
        archived = subprocess.check_output(["git", "archive", base, "Sources"], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archived)) as archive:
            added = counts({
                item.name: [match for match in literals(archive.extractfile(item).read().decode())
                            if match[0].startswith(ADDED_IN_3)]
                for item in archive.getmembers()
                if item.isfile() and item.name.endswith(".swift") and item.name not in TOKENS
            })
        files = tracked["files"]
        return {path: files.get(path, {}) | added.get(path, {}) for path in files.keys() | added.keys()}
    # Bootstrap only newly checked style categories from actual source at the base revision.
    # The original numeric allowances are never recalculated from source.
    archived = subprocess.check_output(["git", "archive", base, VIEWS], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archived)) as archive:
        styles = counts({
            item.name: list(literals(archive.extractfile(item).read().decode(), styles=True, numeric_enabled=False))
            for item in archive.getmembers()
            if item.isfile() and item.name.endswith(".swift") and not item.name.startswith(LIBRARY)
        })
    return {path: tracked.get(path, {}) | styles.get(path, {}) for path in tracked.keys() | styles.keys()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Git revision whose baseline must not grow")
    parser.add_argument("--prune", action="store_true", help="Remove obsolete allowances, without adding new ones")
    args = parser.parse_args()
    baseline = json.loads(BASELINE.read_text())
    if baseline["version"] != VERSION:
        parser.error("Unexpected style baseline version")
    allowed = baseline["files"]
    found = scan()
    if args.prune:
        active = counts(found)
        allowed = {path: dict(remaining) for path, matches in allowed.items()
                   if (remaining := Counter(matches) & Counter(active.get(path, {})))}
        BASELINE.write_text(json.dumps({"version": VERSION, "files": allowed}, indent=2) + "\n")
    failed = False
    if args.base:
        relative = BASELINE.relative_to(ROOT).as_posix()
        tracked = subprocess.check_output(["git", "ls-tree", args.base, "--", relative], cwd=ROOT)
        if tracked:
            original = json.loads(subprocess.check_output(["git", "show", f"{args.base}:{relative}"], cwd=ROOT))
            for path, allowances in baseline_additions(allowed, base_allowances(args.base, original)).items():
                for signature, count in sorted(allowances.items()):
                    print(f"{path}: baseline grows by {count} for {signature}", file=sys.stderr)
                    failed = True
    for path, matches in found.items():
        remaining = Counter(allowed.get(path, {}))
        for signature, line in matches:
            remaining[signature] -= 1
            if remaining[signature] < 0:
                print(f"{path}:{line}: use a Selene token instead of {signature}", file=sys.stderr)
                failed = True
        for signature, count in sorted(remaining.items()):
            if count > 0:
                print(f"{path}: remove {count} obsolete baseline allowance(s) for {signature}", file=sys.stderr)
                failed = True
    for path in allowed.keys() - found.keys():
        print(f"{path}: remove obsolete baseline file entry", file=sys.stderr)
        failed = True
    return int(failed)


def baseline_additions(current, original):
    return {
        path: extra
        for path, allowances in current.items()
        if (extra := Counter(allowances) - Counter(original.get(path, {})))
    }


if __name__ == "__main__":
    sys.exit(main())
