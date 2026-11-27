#!/usr/bin/env python3
"""Hold every system's translations to design/vocabulary.json.

Four rules:
  term    a listed key says the vocabulary's words (French everywhere, English too on Android, whose keys are names)
  absent  a listed key exists, so a rename does not escape the first rule
  voice   French says « tu », never « vous »
  avoid   French leaves out the words the vocabulary replaced
  shared  the same English says the same French as the Mac catalogue

Today's gaps are recorded in design/vocabulary-debt.json. A new gap fails; a repaired one fails until it is pruned, so
the file only shrinks. Catalogues are read from a folder (--root, repeatable) or from a Git ref (--ref, repeatable):

  python3 scripts/check_vocabulary.py                                   # the systems of this checkout
  python3 scripts/check_vocabulary.py --ref alpha/windows --ref alpha/android --ref alpha/ios
  python3 scripts/check_vocabulary.py --system site --root ~/path/to/site
  python3 scripts/check_vocabulary.py --report                          # every gap with its words
  python3 scripts/check_vocabulary.py --prune                           # forget repaired gaps
  python3 scripts/check_vocabulary.py --init --system ios --ref alpha/ios   # first record of a system
"""
import argparse
import html
import json
import re
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
VOCABULARY = ROOT / "design/vocabulary.json"
DEBT = ROOT / "design/vocabulary-debt.json"
MAC = "core/OortLibrary/Resources/Localizable.xcstrings"
DESKTOP = "desktop/ui/gen/strings.js"
ANDROID = "android/app/src/main/res"
IOS = re.compile(r"mobile/Sources/([^/]+)/Resources/Localizable\.xcstrings")
SYSTEMS = ("mac", "desktop", "android", "ios", "site")
# « vous », « votre », « vos », « veuillez » and the verb endings that address them. Words that only look like one stay out.
VOUS = re.compile(
    r"(?<!\w)(?:vous|votre|vos)(?!\w)"
    r"|(?<!\w)(?!(?:assez|chez|nez|rez)(?!\w))[^\W\d_]{2,}ez(?!\w)",
    re.IGNORECASE,
)


class Tree:
    """The files of a folder, or of a Git ref of this repository."""

    def __init__(self, root=None, ref=None):
        self.root, self.ref = root, ref
        self.name = ref or str(root)

    def files(self):
        if self.ref:
            return subprocess.check_output(["git", "-C", str(ROOT), "ls-tree", "-r", "--name-only", self.ref],
                                           text=True).splitlines()
        out = []
        for pattern in (MAC, DESKTOP, f"{ANDROID}/values*/strings.xml", "mobile/Sources/*/Resources/Localizable.xcstrings",
                        "**/*.html"):
            out += [p.relative_to(self.root).as_posix() for p in self.root.glob(pattern)]
        return out

    def read(self, path):
        if self.ref:
            return subprocess.check_output(["git", "-C", str(ROOT), "show", f"{self.ref}:{path}"]).decode("utf-8")
        return (self.root / path).read_text(encoding="utf-8")


def units(entry):
    """Every text of one language of a string catalogue entry, plural forms included."""
    if "stringUnit" in entry:
        return [entry["stringUnit"].get("value", "")]
    return [text for group in entry.get("variations", {}).values() for item in group.values() for text in units(item)]


def xcstrings(text):
    out = {}
    for key, item in json.loads(text).get("strings", {}).items():
        languages = item.get("localizations", {})
        out[key] = (units(languages.get("en", {})) or [key], units(languages.get("fr", {})))
    return out


def desktop(text):
    start = text.index("{", text.index("export const STRINGS ="))
    strings, _ = json.JSONDecoder().raw_decode(text[start:])
    forms = lambda value: list(value.values()) if isinstance(value, dict) else [value]
    return {key: (forms(value), forms(strings["fr"].get(key, ""))) for key, value in strings["en"].items()}


def android(english, french):
    def read(text):
        out = {}
        for element in ElementTree.fromstring(text.encode("utf-8")):
            if element.get("name"):
                values = [item.text or "" for item in element] if len(element) else ["".join(element.itertext())]
                out[element.get("name")] = [v.replace("\\'", "’").replace('\\"', '"') for v in values]
        return out
    fr = read(french)
    return {key: (value, fr.get(key, [])) for key, value in read(english).items()}


def site(text):
    """The visible sentences of a French page."""
    if not re.search(r"<html[^>]*\blang=\"fr", text):
        return {}
    text = re.sub(r"<(script|style|svg)\b[\s\S]*?</\1>", " ", text)
    lines = (html.unescape(line).strip() for line in re.sub(r"<[^>]+>", "\n", text).split("\n"))
    return {line: ([], [line]) for line in lines if line}


def catalogues(tree, wanted):
    """{system: {key: (english texts, french texts)}} for what this tree holds, and the Mac reference."""
    files = set(tree.files())
    found = {}
    reference = xcstrings(tree.read(MAC)) if MAC in files else {}
    if DESKTOP in files:
        found["desktop"] = desktop(tree.read(DESKTOP))
    pair = f"{ANDROID}/values/strings.xml", f"{ANDROID}/values-fr/strings.xml"
    if set(pair) <= files:
        found["android"] = android(tree.read(pair[0]), tree.read(pair[1]))
    mobile = {}
    for path in sorted(files):
        if match := IOS.fullmatch(path):
            for key, value in xcstrings(tree.read(path)).items():
                mobile[f"{match[1]}:{key}"] = value
    if mobile:
        found["ios"] = mobile
    # A platform branch carries the shared Mac catalogue as its reference: it is checked as Mac only on request.
    if reference and (not found or "mac" in wanted):
        found["mac"] = reference
    if "site" in wanted:
        pages = {}
        for path in sorted(files):
            if path.endswith(".html"):
                for line, value in site(tree.read(path)).items():
                    pages[f"{path}:{line}"] = value
        found["site"] = pages
    return {system: value for system, value in found.items() if not wanted or system in wanted}, reference


def spaced(texts):
    """French texts with their non-breaking spaces read as spaces: typography is not a difference of words."""
    return [text.replace("\u00a0", " ").replace("\u202f", " ") for text in texts]


def gaps(vocabulary, system, catalogue, reference):
    """{identifier: explanation} of everything in one system that does not hold to the vocabulary."""
    out = {}
    plain = (lambda key: key.split(":", 1)[1]) if system == "ios" else (lambda key: key)
    avoid = [(rule["id"], re.compile(rule["pattern"], re.IGNORECASE), rule["use"]) for rule in vocabulary["avoid"]["fr"]]
    for key, (_, french) in catalogue.items():
        for text in french:
            if match := VOUS.search(text):
                out[f"voice|{system}|{key}"] = f"« {match[0]} » in {text!r}"
            for name, pattern, use in avoid:
                if match := pattern.search(text):
                    out[f"avoid:{name}|{system}|{key}"] = f"« {match[0]} » in {text!r}; say {use}"
    if system == "site":
        return out
    by_name = {}
    for key in catalogue:
        by_name.setdefault(plain(key), []).append(key)
    listed = set()
    for term in vocabulary["terms"]:
        for item in term["keys"].get(system, []):
            item = item if isinstance(item, dict) else {"key": item}
            listed.add(item["key"])
            matches = by_name.get(item["key"], [])
            if not matches:
                out[f"absent|{system}|{item['key']}"] = f"{term['id']}: the key is gone"
            for key in matches:
                english, french = catalogue[key]
                expected = item.get("fr", term["fr"])
                if spaced(french) != spaced([expected]):
                    out[f"term|{system}|{key}"] = f"{term['id']}: French {french} instead of {expected!r}"
                elif system == "android" and english != [item.get("en", term["en"])]:
                    out[f"term|{system}|{key}"] = f"{term['id']}: English {english} instead of {item.get('en', term['en'])!r}"
    if system != "mac":
        mac = {}
        for english, french in reference.values():
            if len(english) == 1 and len(french) == 1:
                mac.setdefault(english[0], set()).add(spaced(french)[0])
        for key, (english, french) in catalogue.items():
            if plain(key) in listed or f"{system}|{key}" in vocabulary.get("homonyms", []) or len(english) != 1 or len(french) != 1:
                continue
            if english[0] in mac and spaced(french)[0] not in mac[english[0]]:
                out[f"shared|{system}|{key}"] = f"{english[0]!r}: {french[0]!r}, the Mac says {sorted(mac[english[0]])}"
    return out


def invalid(vocabulary):
    """What is wrong in the vocabulary itself."""
    errors = []
    terms = [term.get("id") for term in vocabulary["terms"]]
    states = [state.get("id") for state in vocabulary["states"]]
    for name, ids in (("term", terms), ("state", states)):
        errors += [f"{name} {i!r} appears twice" for i in sorted({i for i in ids if ids.count(i) > 1})]
    for entry in vocabulary["terms"] + vocabulary["states"]:
        errors += [f"{entry.get('id')}: no {field}" for field in ("id", "en", "fr", "icon") if not entry.get(field)]
        french = entry.get("fr", "")
        if VOUS.search(french):
            errors.append(f"{entry.get('id')}: says « vous »")
        errors += [f"{entry.get('id')}: uses the avoided word {rule['id']}" for rule in vocabulary["avoid"]["fr"]
                   if re.search(rule["pattern"], french, re.IGNORECASE)]
        errors += [f"{entry.get('id')}: unknown system {system!r}" for system in entry.get("keys", {}) if system not in SYSTEMS]
    used = [state.get("action") for state in vocabulary["states"]] + vocabulary.get("menu", []) + vocabulary.get("power", [])
    used += [control.get("action") for control in vocabulary.get("controls", {}).get("browsing", [])]
    errors += [f"unknown term {i!r}" for i in sorted({i for i in used if i and i not in terms})]
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", action="append", default=[], type=Path, help="a folder to read")
    parser.add_argument("--ref", action="append", default=[], help="a Git ref of this repository to read")
    parser.add_argument("--system", action="append", default=[], choices=SYSTEMS, help="only these systems")
    parser.add_argument("--vocabulary", type=Path, default=VOCABULARY)
    parser.add_argument("--debt", type=Path, default=DEBT)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--report", action="store_true", help="list every gap, recorded or not")
    mode.add_argument("--prune", action="store_true", help="forget the recorded gaps that are repaired")
    mode.add_argument("--init", action="store_true", help="record the gaps of a system that has no record yet")
    args = parser.parse_args(argv)

    vocabulary = json.loads(args.vocabulary.read_text(encoding="utf-8"))
    if errors := invalid(vocabulary):
        print("\n".join(errors))
        return 1
    trees = [Tree(root=p.expanduser().resolve()) for p in args.root] + [Tree(ref=r) for r in args.ref]
    found = {}
    for tree in trees or [Tree(root=ROOT)]:
        systems, reference = catalogues(tree, args.system)
        for system, catalogue in systems.items():
            if system in found:
                print(f"{system} is read twice ({tree.name}): name one source with --system")
                return 1
            if catalogue:
                found[system] = gaps(vocabulary, system, catalogue, reference)
    if missing := [s for s in args.system if s not in found] or ([] if found else ["any system"]):
        print(f"Nothing to read for: {', '.join(missing)}")
        return 1

    debt = json.loads(args.debt.read_text(encoding="utf-8")) if args.debt.exists() else {}
    if args.init:
        if known := sorted(set(found) & set(debt)):
            print(f"Already recorded: {', '.join(known)}. Repair, then --prune.")
            return 1
        debt.update({system: sorted(value) for system, value in found.items()})
    failed = False
    for system, value in sorted(found.items()):
        recorded = set(debt.get(system, []))
        new, stale = sorted(set(value) - recorded), sorted(recorded - set(value))
        if args.prune:
            debt[system], stale = sorted(recorded & set(value)), []
        print(f"{system}: {len(value)} gaps, {len(new)} new, {len(stale)} repaired and still recorded")
        for identifier in sorted(value) if args.report else new:
            print(f"  {identifier}\n      {value[identifier]}")
        for identifier in stale:
            print(f"  repaired, prune it: {identifier}")
        failed = failed or bool(new or stale)
    if args.init or args.prune:
        args.debt.write_text(json.dumps(debt, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    return 1 if failed and not args.report else 0


if __name__ == "__main__":
    sys.exit(main())
