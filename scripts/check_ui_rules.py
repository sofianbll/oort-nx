#!/usr/bin/env python3
"""Check the interface rules a script can measure, against a debt list that may only shrink.

Rules (docs/working-on-it/change-criteria.md gives the source and the reason of each):

  menu-size          more than 5 entries in a menu, bar, tab set, list of choices or group
  menu-depth         a surface more than 2 levels below its root
  menu-unregistered  a menu, tab set or iterated enum that nobody declared in ui-rules.json
  dialog-size        more than 5 fixed answers in a dialog
  untranslated       visible text that is not in the string catalog
  same-as-english    a translation identical to a long English sentence
  measure            a literal size, offset or duration in a screen (completes check_selene_tokens.py)
  shape              a surface drawn by hand in a screen instead of an OortUI piece
  a11y-label         a button made of a picture only, without an accessibility label
  a11y-tap           a tap with no button role for VoiceOver and Full Keyboard Access
  pointer-only       a view that takes clicks but knows no focus: no keyboard or controller path in sight
  pad-only           a hint shown for the controller only
  motion             a repeating animation in a file that never reads Reduce motion
  button-order       wrong dialog order (destructive pair, split group, or vertical list), row or hint
  focus-danger       a question that starts on an answer that deletes, quits, replaces or trashes
  keyboard-path      a click with no key: a Settings button or help no row presses, a link inside a dialog,
                     Return without the keypad's Enter, a declared action whose key is gone
  mouse-path         an action a hint alone offers: gone with the hints off, with no other place for the mouse

It reads text. It proves neither the look, nor a real focus order, nor what VoiceOver says. A dynamic list
(user content, a wallpaper service) is listed under "unmeasured" with its reason, never counted as passing.

  check_ui_rules.py                 fail on anything new, and on debt that is gone but still listed
  check_ui_rules.py --report        also print every known gap, then what is not measured
  check_ui_rules.py --prune         drop debt that is gone; never adds any
  check_ui_rules.py --base REV      fail when the debt list grew since REV
"""
import argparse
from collections import Counter, defaultdict
from functools import lru_cache
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / "scripts/ui-rules.json"
MAX_ENTRIES, MAX_DEPTH = 5, 2
CATALOG = "Sources/NXLibraryCore/Resources/Localizable.xcstrings"
VIEWS = "Sources/NXLibrary/Views/"
APP = "Sources/NXLibrary/"
LIBRARY = VIEWS + "OortUI/"
# Debug galleries and probes: never shown to a player.
NOT_SHIPPED = re.compile(r"(?:Gallery|Probe|Fixture\w*|Preview\w*)\.swift$")
LANGUAGES = ("it", "fr", "de", "es", "pt-BR", "zh-Hans")

NUMBER = r"-?(?:\d[\d_]*(?:\.\d+)?|\.\d+)"
DISCOVER = re.compile(r"\b(OortTabs|OortSegmented|OortSettingsSidebar|CommandMenu|Picker|Menu)\s*[({]|\.(contextMenu)\b")
# What a person touches: a SwiftUI or OortUI button, or a tap.
CLICK = re.compile(r"\b(?:Button|OortButton|SelenePillButton|SeleneRoundButton)\s*(?:\(|\{)")
# What ties it to the keyboard and the controller: a focus, an input handler, or the rows a Settings page declares.
FOCUS = re.compile(r"[fF]ocus|GamepadAction|isSelected|\bselected\b|keyDown|\.onKeyPress|keyboardShortcut|onExitCommand|\bonActions\b|\browActions\b")
VEIL = re.compile(r"[sS]crim|artShade|\bveil\b|Color\.clear|ignoresSafeArea")
ROLE = re.compile(r"\.isButton\b|accessibilityAction|\bButton\s*[({]")
SHAPE = re.compile(r"\b(?:RoundedRectangle|UnevenRoundedRectangle|Capsule|Circle|Ellipse|Rectangle)\s*\([^()]*(?:\([^()]*\)[^()]*)*\)"
                   r"\s*\.(?:fill|stroke|strokeBorder)\b")
MEASURE = re.compile(
    rf"(?P<canvas>\bcanvas\s*\.\s*u\s*\(\s*{NUMBER}\s*\))"
    rf"|(?P<let>\b(?:let|var)\s+\w+\s*:\s*CGFloat\s*=\s*{NUMBER})"
    rf"|(?P<frame>\b(?:width|height|minWidth|maxWidth|minHeight|maxHeight|idealWidth|idealHeight)\s*:\s*{NUMBER}(?=\s*[,)]))"
    rf"|(?P<offset>\.offset\s*\(\s*[xy]\s*:\s*{NUMBER})"
    rf"|(?P<duration>\b(?:duration|delay)\s*:\s*{NUMBER})")
VISIBLE = re.compile(r"(?:\b(?:Text|Button|Label|Toggle|Section|TextField|SecureField|Menu|Picker|CommandMenu|Link)"
                     r"|\.(?:help|accessibilityLabel|accessibilityHint|accessibilityValue|navigationTitle))\(\s*$")
KEYED = re.compile(r"(?:\b(?:title|label|message|placeholder|subtitle|detail|about|heading|confirmTitle|cancelTitle|hold|help|info)"
                   r"\s*:\s*|\bHintItem\(\s*(?:\.\w+|nil)\s*,\s*|\bchoices\s*:\s*\[[^\]]*)$")
LOOKUP = re.compile(r"(?:\bL10n\.(?:text|format|count)|(?<![.\w])(?:text|t))\(\s*$")
# The answers that leave things as they are: they come first, on the side of the B hint.
BACK = {"Cancel", "Back", "Not now", "Later", "Keep", "Keep editing", "Keep it", "Stay", "Close", "Continue editing settings"}
BACK_CASE = re.compile(r"\(\s*\.(?:cancel|back|notNow)\b|\bid\s*:\s*\"(?:back|cancel)\"|\bactivate\(\.(?:back|notNow)\)")
DANGER = re.compile(r"\b(?:Delete|Remove|Trash|Quit|Reset|Replace|Discard|Clear|Erase|Free up)\b")
KEY = re.compile(r"(?<![\w.])(?:Button|OortButton|SelenePillButton|pill|button|option)\s*(?=[({])")
SECTION = re.compile(r"Views/Settings/Settings\w*Section\.swift$")
# Buttons that a hint announces and a pointer has no direct target for by nature.
SECOND = {"x", "y", "menu", "rs", "lt", "rt", "lb", "rb", "view", "home", "search"}
IDENTIFIER = re.compile(r"[a-z0-9_.\-]+$|[\w\-]+(?:\.[\w\-]+)+$|[A-Z][a-z]+[A-Z]\w*$|[A-Z_0-9]+$")


class Source:
    """One Swift file: comments and string contents blanked out, and the strings beside."""

    def __init__(self, text):
        self.text, self.strings, self.out = text, [], list(text)
        sys.setrecursionlimit(10_000)
        self._code(0, False)
        self.code = "".join(self.out)

    def _blank(self, start, end):
        for index in range(start, min(end, len(self.out))):
            if self.out[index] != "\n":
                self.out[index] = " "

    def _code(self, i, inside):
        text, depth = self.text, 0
        while i < len(text):
            if text.startswith("//", i):
                end = text.find("\n", i)
                end = len(text) if end < 0 else end
                self._blank(i, end)
                i = end
            elif text.startswith("/*", i):
                end, level = i + 2, 1
                while level and end < len(text):
                    if text.startswith("/*", end): level, end = level + 1, end + 2
                    elif text.startswith("*/", end): level, end = level - 1, end + 2
                    else: end += 1
                self._blank(i, end)
                i = end
            elif (opening := re.compile(r'(#*)("""|")').match(text, i)):
                i = self._string(i, opening[1], opening[2])
            else:
                depth += (text[i] == "(") - (text[i] == ")")
                if inside and depth < 0:
                    return i + 1
                i += 1
        return i

    def _string(self, start, hashes, quote):
        text, i, piece = self.text, start + len(hashes) + len(quote), start + len(hashes) + len(quote)
        value, interpolated = [], False
        while i < len(text):
            if text.startswith(quote + hashes, i):
                value.append(text[piece:i])
                self._blank(piece, i)
                end = i + len(quote) + len(hashes)
                self.strings.append((start, end, "".join(value), interpolated))
                return end
            if text.startswith("\\" + hashes + "(", i):
                value.append(text[piece:i])
                self._blank(piece, i)
                interpolated = True
                i = piece = self._code(i + len(hashes) + 2, True)
            elif text[i] == "\\":
                i += 2
            elif text[i] == "\n" and quote == '"':
                break  # not a string after all
            else:
                i += 1
        return i

    def line(self, index):
        return self.text.count("\n", 0, index) + 1

    def close(self, index):
        """The index after the bracket that closes the one at `index`."""
        pairs, depth = {"(": ")", "[": "]", "{": "}"}, []
        for i in range(index, len(self.code)):
            char = self.code[i]
            if char in pairs: depth.append(pairs[char])
            elif depth and char == depth[-1]:
                depth.pop()
                if not depth: return i + 1
        return len(self.code)

    def body(self, pattern):
        """The braces that follow a declaration, as a range."""
        match = re.search(pattern, self.code)
        if not match: return None
        start = self.code.find("{", match.end())
        return (start, self.close(start)) if start >= 0 else None

    def enclosing(self, index, pattern):
        """The innermost declaration of this kind around an index."""
        found = None
        for match in re.finditer(pattern, self.code[:index]):
            start = self.code.find("{", match.end())
            if 0 <= start < index < self.close(start): found = match, start, self.close(start)
        return found


class Tree:
    def __init__(self, root):
        self.root = Path(root)

    @lru_cache(maxsize=None)
    def source(self, relative):
        return Source((self.root / relative).read_text(encoding="utf-8"))

    @lru_cache(maxsize=None)
    def files(self, prefix="Sources"):
        base = self.root / prefix
        return [path.relative_to(self.root).as_posix() for path in sorted(base.rglob("*.swift"))
                if not NOT_SHIPPED.search(path.name) and ".build" not in path.parts] if base.is_dir() else []

    @lru_cache(maxsize=None)
    def enums(self):
        """Every enum by name, with its cases. The same name twice is kept apart by file."""
        found = defaultdict(dict)
        for relative in self.files("Sources") + self.files("mobile"):
            source = self.source(relative)
            for match in re.finditer(r"\benum\s+(\w+)[^{]*\{", source.code):
                start = match.end() - 1
                found[match[1]][relative] = cases(source.code[start + 1:source.close(start) - 1])
        return found

    def enum(self, name):
        """One enum, as Name, or File.Name when several files use the name."""
        stem, _, name = name.rpartition(".")
        files = {path: cases for path, cases in self.enums().get(name, {}).items() if not stem or Path(path).stem == stem}
        return next(iter(files.items())) if len(files) == 1 else (None, None)

    def declaring(self, type_name, pattern):
        """The file where a type (or its extension) declares a member."""
        head = re.compile(rf"\b(?:enum|struct|class|extension)\s+{type_name}\b")
        for relative in self.files("Sources"):
            source = self.source(relative)
            if head.search(source.code) and re.search(pattern, source.code): return relative
        return None


def cases(body):
    """The cases declared at the top of an enum's body, not in its switches."""
    flat, depth = [], 0
    for char in body:
        depth -= char in "})]"
        flat.append(char if depth == 0 else "\n" if char == "\n" else " ")
        depth += char in "{(["
    names = []
    for match in re.finditer(r"(?<![.\w])case\s+([^\n]+)", "".join(flat)):
        names += [name for part in match[1].split(",") if (name := part.strip().split("=")[0].strip().strip("`").split(" ")[0].split("(")[0])]
    return names


def elements(code):
    """The top-level elements of a bracketed literal, brackets included."""
    inner, depth, parts, current = code[1:-1], 0, [], ""
    for char in inner:
        depth += (char in "([{") - (char in ")]}")
        if char == "," and depth == 0:
            parts.append(current)
            current = ""
        else: current += char
    return [part for part in parts + [current] if part.strip()]


def literal_after(source, pattern):
    match = re.search(pattern, source.code)
    if not match: return None
    start = source.code.find("[", match.end())
    return source.code[start:source.close(start)] if start >= 0 else None


def measure_surface(tree, item):
    """[(part, entries)] of a declared surface and the file it is in; None when the source no longer has it."""
    how = item["count"]
    kind, _, what = how.partition(":")
    if kind == "enum":
        relative, names = tree.enum(what)
        return (relative, [("", len(names))]) if names else None
    if kind == "kotlin-enum":
        relative, name = what.split("#")
        path = tree.root / relative
        match = path.is_file() and re.search(rf"enum class {name}\s*\{{([^}};]*)", path.read_text(encoding="utf-8"))
        return (relative, [("", len([x for x in match[1].split(",") if x.strip()]))]) if match else None
    owner, _, member = what.partition(".")
    if kind in ("array", "groups", "arrays"):
        pattern = rf"\b(?:static\s+)?(?:let|var)\s+`?{member}`?\b"
        relative = tree.declaring(owner, pattern)
        if not relative: return None
        source = tree.source(relative)
        if kind == "arrays":  # a switch that answers one list per case
            start, end = source.body(pattern)
            code = source.code[start:end]
            lists = [(name, code[at:]) for name, at in ((m[1], m.end() - 1) for m in re.finditer(r"case\s+([^:]+):\s*(?:return\s*)?\[", code))]
            return relative, [(name.strip(), len(elements(text[:bracket_end(text)]))) for name, text in lists]
        literal = literal_after(source, pattern + r"[^=\n]*=")
        if literal is None: return None
        parts = elements(literal)
        if kind == "array": return relative, [("", len(parts))]
        inner = [(f"group {index + 1}", len(elements(text[text.index("["):text.index("[") + bracket_end(text[text.index("["):])])))
                 for index, text in enumerate(parts)]
        return relative, [("groups", len(parts))] + inner
    if kind == "rows":  # a function that assembles rows of an enum, in one switch case or whole
        (owner, member), (row, *case) = what.split("/")[0].split("."), what.split("/")[1:]
        relative = tree.declaring(owner, rf"\bfunc\s+{member}\b")
        names = set(tree.enum(row)[1] or [])
        if not relative or not names: return None
        source = tree.source(relative)
        start, end = source.body(rf"\bfunc\s+{member}\b")
        code = source.code[start:end]
        if case:
            match = re.search(rf"case\s+\.{case[0]}\s*:(.*?)(?=\n\s*case\s+\.\w+\s*:|\Z)", code, re.DOTALL)
            code = match[1] if match else ""
        used = {name for name in re.findall(r"\.(\w+)", code)} & names
        if "settingRows" in code:
            used |= {part.strip().lstrip(".") for part in elements(literal_after(tree.source(tree.enum(row)[0]), r"\bsettingRows\b[^=\n]*=") or "[]")}
        # Two names that take turns in one place count once.
        used_once = len(used) - sum(len(used & set(group)) - 1 for group in item.get("alternatives", []) if used & set(group))
        return relative, [("", used_once + len(item.get("added", [])))]
    if kind == "commands":
        for relative in tree.files("Sources/NXLibrary"):
            source = tree.source(relative)
            for start, _, value, _ in source.strings:
                if value == what and re.search(r"CommandMenu\(\s*$", source.code[:start]):
                    open_at = source.code.index("{", start)
                    return relative, [("", len(re.findall(r"\bButton\b", source.code[open_at:source.close(open_at)])))]
        return None
    raise ValueError(f"unknown measure {how}")


def bracket_end(text):
    depth = 0
    for index, char in enumerate(text):
        depth += (char in "([{") - (char in ")]}")
        if depth == 0: return index + 1
    return len(text)


class Findings:
    def __init__(self):
        self.items = []

    def add(self, rule, relative, signature, message, line=0, times=1):
        self.items += [(rule, relative, re.sub(r"\s+", " ", signature).strip(), message, line)] * times

    def counts(self):
        return {rule: {path: dict(sorted(sigs.items())) for path, sigs in sorted(paths.items())}
                for rule, paths in sorted(self.grouped().items())}

    def grouped(self):
        out = defaultdict(lambda: defaultdict(Counter))
        for rule, path, signature, _, _ in self.items: out[rule][path][signature] += 1
        return out


def check_menus(tree, rules, found, notes):
    surfaces, levels = {item["id"]: item for item in rules["surfaces"]}, {}
    shared = {item["count"] for item in rules["surfaces"]}
    for item in rules["surfaces"]:
        measured = measure_surface(tree, item)
        if measured is None:
            # A port lives on its own branch; the Mac's own surfaces must exist.
            if item.get("system", "macos") == "macos":
                found.add("menu-unregistered", "scripts/ui-rules.json", f"gone:{item['id']}",
                          f"{item['id']}: {item['count']} is not in the sources any more")
            continue
        relative, parts = measured
        for part, count in parts:
            name = item["id"] + (f" ({part})" if part else "")
            notes.append((name, count, relative))
            if count > MAX_ENTRIES:
                found.add("menu-size", relative, name, f"{name} has {count} entries, at most {MAX_ENTRIES}", times=count - MAX_ENTRIES)

    def level(name, seen=()):
        if name in seen: raise SystemExit(f"ui-rules.json: {name} is its own parent")
        parent = surfaces[name].get("parent")
        return 1 + (level(parent, (*seen, name)) if parent else 0)

    for name, item in surfaces.items():
        levels[name] = level(name)
        if levels[name] > MAX_DEPTH:
            found.add("menu-depth", "scripts/ui-rules.json", name,
                      f"{name} is level {levels[name]} ({path_of(name, surfaces)}), at most {MAX_DEPTH}", times=levels[name] - MAX_DEPTH)

    # Rows that open a list declare it, so a new one cannot hide a level.
    for opener in rules["openers"]:
        relative = tree.declaring(opener["type"], rf"\b{opener['member']}\b")
        if not relative: continue
        body = tree.source(relative).body(rf"\bvar\s+{opener['member']}\b")
        rows = re.findall(r"\.(\w+)", tree.source(relative).code[slice(*body)].split(".contains")[0]) if body else []
        for row in rows:
            if row not in opener["opens"]:
                found.add("menu-unregistered", relative, f"{opener['type']}.{row}", f"{opener['type']}.{row} opens a list that no surface declares")

    declared = {how.split(":", 1)[1].rpartition(".")[2] for how in shared if how.startswith("enum:")} | set(rules["values"])
    for relative in tree.files("Sources/NXLibrary"):
        source = tree.source(relative)
        if relative.startswith(LIBRARY): continue
        for match in re.finditer(r"\b([A-Z]\w+)\.allCases\b", source.code):
            if match[1] not in declared and relative.startswith(VIEWS):
                found.add("menu-unregistered", relative, f"{match[1]}.allCases",
                          f"{match[1]}.allCases is drawn here: declare it as a surface or as a list of values", source.line(match.start()))
        for match in DISCOVER.finditer(source.code):
            name = match[1] or match[2]
            end = source.close(match.end() - 1) if match[1] else match.end()
            call = source.code[match.start():end]
            if name in ("OortTabs", "OortSegmented"):
                listed = re.search(r"\b(?:items|options)\s*:\s*(\[)", call)
                if re.search(r"\b[A-Z]\w+\.allCases\b", call): continue
                if listed:
                    count = len(elements(call[listed.start(1):listed.start(1) + bracket_end(call[listed.start(1):])]))
                    if count > MAX_ENTRIES:
                        found.add("menu-size", relative, f"{name} literal", f"{name} has {count} entries, at most {MAX_ENTRIES}",
                                  source.line(match.start()), count - MAX_ENTRIES)
                    continue
            elif name == "CommandMenu":
                counted = [measure_surface(tree, item) for item in rules["surfaces"] if item["count"].startswith("commands:")]
                if any(one and one[0] == relative for one in counted): continue
            if f"{relative}::{name}" not in rules["unmeasured"]:
                found.add("menu-unregistered", relative, name, f"{name} has a list this check cannot count: declare it", source.line(match.start()))


def path_of(name, surfaces):
    parent = surfaces[name].get("parent")
    return (path_of(parent, surfaces) + " › " if parent else "") + name


def check_dialogs(tree, found):
    for relative in tree.files("Sources/NXLibrary"):
        source = tree.source(relative)
        for match in re.finditer(r"\bSeleneChoiceDialog\s*\(", source.code):
            call = source.code[match.end() - 1:source.close(match.end() - 1)]
            listed = re.search(r"\bchoices\s*:\s*(\[)", call)
            if not listed: continue
            count = len(elements(call[listed.start(1):listed.start(1) + bracket_end(call[listed.start(1):])]))
            if count > MAX_ENTRIES:
                found.add("dialog-size", relative, "SeleneChoiceDialog", f"a dialog has {count} fixed answers, at most {MAX_ENTRIES}", source.line(match.start()), count - MAX_ENTRIES)


def unescape(value):
    value = re.sub(r"\\u\{([0-9a-fA-F]+)\}", lambda m: chr(int(m[1], 16)), value)
    return value.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def check_texts(tree, rules, found):
    path = tree.root / CATALOG
    if not path.is_file(): return
    strings = json.loads(path.read_text(encoding="utf-8"))["strings"]
    english = rules["english"]
    for relative in tree.files("Sources"):
        source = tree.source(relative)
        for start, _, raw, interpolated in source.strings:
            before, value = source.code[max(0, start - 160):start], unescape(raw)
            if LOOKUP.search(before):
                # An interpolated key is built at run time: only its fixed start can be looked for.
                known = any(key.startswith(value.split(":")[0]) for key in strings) if interpolated else value in strings
                # A key ended by a colon is a prefix the code completes.
                known = known or (value.endswith(": ") and any(key.startswith(value) for key in strings))
                if not known and re.search(r"[A-Za-z]{2}", value) and (relative.startswith(APP) or "L10n." in before[-14:]):
                    found.add("untranslated", relative, value[:70], f"no translation for {value[:60]!r}", source.line(start))
            elif relative.startswith(APP) and not interpolated and VISIBLE.search(before):
                words = re.sub(r"https?://\S+", "", value)
                if re.search(r"[A-Za-z]{2}", words) and value not in english:
                    found.add("untranslated", relative, value[:70], f"{value[:60]!r} never goes through L10n", source.line(start))
            elif relative.startswith(APP) and not interpolated and KEYED.search(before):
                if value not in strings and re.match(r"[A-Z][^\n]*[a-z]", value) and not IDENTIFIER.match(value) and value not in english:
                    found.add("untranslated", relative, value[:70], f"no translation for {value[:60]!r}", source.line(start))
    for key, entry in strings.items():
        for language in LANGUAGES:
            unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
            if unit.get("value") == key and key not in english and len(re.findall(r"[A-Za-z]{3,}", key)) >= 4:
                found.add("same-as-english", CATALOG, f"{language}: {key[:70]}", f"{language} repeats the English {key[:60]!r}")


def check_styles(tree, found):
    for relative in tree.files(VIEWS.rstrip("/")):
        if relative.startswith((LIBRARY, VIEWS + "Theme/")): continue
        source = tree.source(relative)
        for match in MEASURE.finditer(source.code):
            signature = re.sub(r"\s+", "", match[0])
            if re.search(rf"[:=(]-?0(?:\.0+)?\)?$", signature) or re.search(r":1(?:\.0)?$", signature): continue
            found.add("measure", relative, signature, f"{signature}: use a token", source.line(match.start()))
        for match in SHAPE.finditer(source.code):
            signature = re.sub(r"\s+", "", match[0])
            found.add("shape", relative, signature, f"{signature[:60]}: use an OortUI piece", source.line(match.start()))


def chain_end(source, index):
    """Where the modifiers that follow a view stop."""
    code = source.code
    while True:
        match = re.compile(r"\s*\.\w+").match(code, index)
        if not match: return index
        index = match.end()
        while (opening := re.compile(r"[ \t]*([({])").match(code, index)):
            index = source.close(opening.start(1))


def check_access(tree, rules, found):
    views, functions = defaultdict(str), defaultdict(str)
    files = [f for f in tree.files("Sources/NXLibrary") if not f.startswith(LIBRARY)]
    for relative in files:
        source = tree.source(relative)
        for match in re.finditer(r"\b(?:struct|extension|class)\s+(\w+)[^{]*\{", source.code):
            views[match[1]] += source.code[match.end():source.close(match.end() - 1)]
        for match in re.finditer(r"\bfunc\s+(\w+)[^{}]*\{", source.code):
            functions[relative.rsplit("/", 1)[0], match[1]] += source.code[match.end():source.close(match.end() - 1)]
    for relative in files:
        source = tree.source(relative)
        for match in re.finditer(r"\bButton\s*(?=[({])", source.code):
            index, parts = match.end(), []
            while (opening := re.compile(r"\s*(?:label\s*:\s*|\w+\s*:\s*(?=\{))?([({])").match(source.code, index)):
                end = source.close(opening.start(1))
                parts.append((opening.start(1), end))
                index = end
            label = source.code[parts[-1][0]:parts[-1][1]] if parts else ""
            drawn = "label" in source.code[match.start():index] and parts and source.code[parts[-1][0]] == "{"
            if not drawn or not re.search(r"\b(?:Image|MaterialIconView|SeleneIcon)\s*\(", label): continue
            if re.search(r"\b(?:Text|Label)\s*\(|\b\w*(?:Label|Title|Row|Card)\s*\(|accessibilityLabel", label): continue
            after = source.code[index:chain_end(source, index)]
            if "accessibilityLabel" in after or "accessibilityHidden(true)" in re.sub(r"\s", "", after) or "accessibilityElement" in after: continue
            found.add("a11y-label", relative, f"Button {label_of(label)}", "a picture-only button has no accessibility label", source.line(match.start()))
        for match in re.finditer(r"\.onTapGesture\b", source.code):
            opening = re.compile(r"\s*(\([^)]*\))?\s*(\{)?").match(source.code, match.end())
            body = source.code[opening.start(2):source.close(opening.start(2))] if opening[2] else ""
            if body and not body[1:-1].strip(): continue  # swallows a click on purpose
            above = source.code[:match.start()].rstrip().split("\n")[-6:]
            if VEIL.search("\n".join(above[-4:])): continue  # a veil: B and Esc close what it is behind
            rest = "\n".join(above) + source.code[match.start():chain_end(source, match.start())]
            # The tile that takes the tap often carries its own role.
            drawn = "".join(views.get(name, "") + functions.get((relative.rsplit("/", 1)[0], name), "")
                            for name in re.findall(r"\b(\w+)\(", "\n".join(above)))
            if ROLE.search(rest + drawn): continue
            around = source.enclosing(match.start(), r"\b(?:var|func)\s+\w+")
            if around and ROLE.search(source.code[around[1]:around[2]]) and around[2] - around[1] < 4000 and above[-1].strip().startswith("."): continue
            found.add("a11y-tap", relative, "onTapGesture " + re.sub(r"\s+", "", (body or opening[0]))[:50],
                      "a tap has no button role and no accessibility action", source.line(match.start()))
        if not relative.startswith(VIEWS): continue
        for match in re.finditer(r"\bstruct\s+(\w+)[^{]*\bView\b[^{]*\{", source.code):
            whole = views[match[1]]
            if CLICK.search(whole) and not FOCUS.search(whole):
                found.add("pointer-only", relative, match[1], f"{match[1]} takes clicks and knows no focus", source.line(match.start()))
        hints = list(re.finditer(r"\bcontrollerOnly\s*[=:]\s*true", source.code))
        for match in hints[:max(0, len(hints) - rules["keyboard_paths"].get(relative, {}).get("hints", 0))]:
            found.add("pad-only", relative, "controllerOnly", "a hint for the controller only: name its keyboard path in ui-rules.json", source.line(match.start()))
        for match in re.finditer(r"\.repeatForever\b|TimelineView\s*\(\s*\.animation", source.code):
            if not re.search(r"[rR]educeMotion|still\b|isAnimating|paused\s*:", source.code):
                found.add("motion", relative, re.sub(r"\s+", "", match[0]), "a loop that never reads Reduce motion", source.line(match.start()))


def label_of(label):
    return (re.findall(r"\(\s*\.?(\w+)", label) or ["?"])[0]


def call_end(source, index):
    """The end of a call that starts with a bracket at `index`, trailing closures included."""
    while (opening := re.compile(r"\s*(?:label\s*:\s*|\w+\s*:\s*(?=\{))?([({])").match(source.code, index)):
        index = source.close(opening.start(1))
    return index


def keys_in(source, start, end):
    """The buttons of a range, outermost only, as (start, end)."""
    found, upto = [], start
    for match in KEY.finditer(source.code, start, end):
        if match.start() < upto or re.search(r"\bfunc\s+$", source.code[max(0, match.start() - 8):match.start()]): continue
        upto = call_end(source, match.end())
        found.append((match.start(), upto))
    return found


def literals(source, start, end):
    return [value for at, _, value, _ in source.strings if start <= at < end]


def is_back(source, start, end):
    # The title is the first thing a button says: what its action does comes after.
    brace = source.code.find("{", start, end)
    head = brace if brace >= 0 else end
    titles = literals(source, start, head)
    return bool(titles and titles[0] in BACK) or bool(BACK_CASE.search(source.text[start:end]))


def check_order(tree, rules, found):
    for relative in tree.files("Sources/NXLibrary"):
        source = tree.source(relative)
        for match in re.finditer(r"(?<![.\w])(?:HStack|ViewThatFits)\b\s*(?=[({])", source.code):
            opening = match.end()
            if source.code[opening] == "(":
                opening = source.close(opening)
                brace = re.compile(r"\s*\{").match(source.code, opening)
                if not brace: continue
                opening = brace.end() - 1
            row = keys_in(source, opening, source.close(opening))
            if len(row) < 2: continue
            backs = [is_back(source, *one) for one in row]
            destructive = [bool(re.search(r"\b(?:destructive\s*:\s*true|(?:role|tone)\s*:\s*\.destructive)\b",
                                          source.code[start:end])) for start, end in row]
            for index, back in enumerate(backs):
                if back and not all(backs[i] or (len(row) >= 3 and destructive[i]) for i in range(index)):
                    words = literals(source, *row[index])[:1] or [re.sub(r"\s+", "", source.text[slice(*row[index])])[:40]]
                    found.add("button-order", relative, f"row {words[0]}", f"the way back ({words[0]}) comes after another button",
                              source.line(row[index][0]))
        for match in re.finditer(r"\bSeleneChoiceDialog\s*\(", source.code):
            call = source.code[match.end() - 1:source.close(match.end() - 1)]
            index = re.search(r"\bcancelIndex\s*:\s*([^,)\n]+)", call)
            listed = re.search(r"\bchoices\s*:\s*(\[)", call)
            if not index or not listed: continue
            start = listed.start(1)
            count = len(elements(call[start:start + bracket_end(call[start:])]))
            if count < 2: continue
            erased = re.search(r"\bdestructive\s*:\s*\[([0-9,\s]*)\]", call)
            danger = {int(n) for n in re.findall(r"\d+", erased[1])} if erased else set()
            stacked = count >= 4 or re.search(r"\blist\s*:\s*true", call)
            back = index[1].strip()
            expected = count - 1 if stacked else len(danger) if count >= 3 else 0
            wrong = (back.isdecimal() and int(back) != expected) or back.endswith(".count")
            if not stacked and danger:
                wrong |= danger != ({1} if count == 2 else set(range(expected)))
            if wrong:
                found.add("button-order", relative, f"cancelIndex {back}",
                          f"Cancel belongs in slot {expected}; a destructive pair is Cancel then action, lists end with Cancel",
                          source.line(match.start()))
        for match in re.finditer(r"\b(?:navigateLeft|\bdelta\s*<\s*0)\s*\?\s*\.confirm\s*:\s*\.cancel\b", source.code):
            found.add("button-order", relative, "confirm left of cancel",
                      "Binary confirmations navigate Cancel on the left and Confirm on the right", source.line(match.start()))
    # The hint bar sets the sides the keys follow: B on the left, A last on the right.
    for relative in tree.files("Sources/NXLibrary"):
        source = tree.source(relative)
        for match in re.finditer(r"\bSeleneHintsBar\s*\(", source.code):
            end = source.close(match.end() - 1)
            for at in re.finditer(r"\bright\s*:", source.code[match.start():end]):
                start, depth = match.start() + at.end(), 0
                stop = start
                while stop < end - 1 and (depth or source.code[stop] != ","):
                    depth += (source.code[stop] in "([{") - (source.code[stop] in ")]}")
                    stop += 1
                buttons = re.findall(r"\bHintItem\(\s*\.(\w+)", source.code[start:stop])
                if "b" in buttons:
                    found.add("button-order", relative, "hint B on the right", "the B hint belongs on the left", source.line(start))
    for row in rules.get("button_rows", []):
        relative = row["file"]
        if not (tree.root / relative).is_file():
            found.add("button-order", "scripts/ui-rules.json", f"gone:{row['id']}", f"{row['id']}: {relative} is not there any more")
            continue
        source = tree.source(relative)
        body = source.body(row["scope"])
        places = [re.compile(token).search(source.text, *body) if body else None for token in row["order"]]
        if any(place is None for place in places):
            found.add("button-order", "scripts/ui-rules.json", f"gone:{row['id']}", f"{row['id']}: a button of this row is not found any more")
        elif [place.start() for place in places] != sorted(place.start() for place in places):
            found.add("button-order", relative, row["id"], f"{row['id']}: expected {row['why']}", source.line(places[0].start()))


def check_focus(tree, rules, found):
    files = tree.files("Sources/NXLibrary")
    everything = "\n".join(tree.source(relative).code for relative in files)
    for relative in files:
        source = tree.source(relative)
        for match in re.finditer(r"\bshowSettingsNotice\s*\(", source.code):
            end = source.close(match.end() - 1)
            call = source.text[match.start():end]
            if not re.search(r"\bprimaryFirst\s*:\s*true", source.code[match.start():end]): continue
            title = re.search(r"\bactionTitle\s*:\s*(?:L10n\.text\(\s*)?(\"(?:[^\"\\]|\\.)*\"|[\w.]+)", call)
            title = title[1] if title else '"Retry"'
            if title.startswith('"'):
                if DANGER.search(title):
                    found.add("focus-danger", relative, f"notice {title}", f"the notice starts on {title}", source.line(match.start()))
            elif f"{relative}::{title}" not in rules.get("safe_focus", {}):
                found.add("focus-danger", relative, f"notice {title}", f"the notice starts on {title}: say in safe_focus why it is safe",
                          source.line(match.start()))
        for match in re.finditer(r"\bSeleneConfirmDialog\s*\(", source.code):
            end = call_end(source, match.end() - 1)
            call = source.text[match.start():end]
            confirm = re.search(r"\bconfirmTitle\s*:\s*(?:L10n\.(?:text|format)\(\s*)?\"([^\"]*)\"", call)
            bound = re.search(r"\bfocus\s*:\s*\$(?:\w+\.)*(\w+)", call)
            if not bound or not (re.search(r"\bdestructive\s*:\s*true\b", call)
                                 or confirm and DANGER.search(confirm[1]) or re.search(r"\bis lost|will be lost|will lose", call)): continue
            if re.search(rf"\b{bound[1]}\b(?:\s*:\s*SeleneConfirmButton)?\s*=\s*\.confirm\b(?!\s*:)", everything):
                found.add("focus-danger", relative, f"confirm {bound[1]}", f"{bound[1]} can start on a dangerous answer", source.line(match.start()))
        for match in re.finditer(r"\bSeleneChoiceDialog\s*\(", source.code):
            end = source.close(match.end() - 1)
            listed = re.search(r"\bchoices\s*:\s*(\[)", source.code[match.start():end])
            bound = re.search(r"\bfocus\s*:\s*\$?(\w+)\b", source.code[match.start():end])
            if not listed or not bound: continue
            at = match.start() + listed.start(1)
            choices = elements(source.text[at:at + bracket_end(source.code[at:])])
            start = re.search(rf"\bvar\s+{bound[1]}\s*=\s*(\d+)|\b{bound[1]}\w*\s*\?\?\s*(\d+)", source.code)
            if not start: continue
            first = int(start[1] or start[2])
            if first < len(choices) and DANGER.search(choices[first]):
                found.add("focus-danger", relative, f"choice {bound[1]}", f"the dialog starts on {choices[first].strip()}", source.line(match.start()))


def check_keyboard(tree, rules, found):
    component = tree.root / (LIBRARY + "SeleneSettingsRow.swift")
    helps_by_click = component.is_file() and re.search(r"\bSeleneInfoTip\(\s*info\s*\)", tree.source(LIBRARY + "SeleneSettingsRow.swift").code)
    for relative in tree.files("Sources/NXLibrary"):
        if relative.startswith(LIBRARY): continue
        source = tree.source(relative)
        if SECTION.search(relative):
            published, ranges = "", []
            for match in re.finditer(r"\bfunc\s+(?:publishActions|friendActionRow)\b|\bvar\s+(?:updateActions|accountButtons)\b|\bonActions\s*(?=\()|\bfunc\s+(?:requestButtons|removeButton|recentButton)\b", source.code):
                opening = re.compile(r"[({]").search(source.code, match.end())
                if opening and source.code[opening.start()] == "(" and not match[0].startswith("onActions"):
                    opening = re.compile(r"\{").search(source.code, source.close(opening.start()))
                if not opening: continue
                ranges.append((match.start(), source.close(opening.start())))
                published += source.code[slice(*ranges[-1])]
            for match in re.finditer(r"(?<![\w.])(?:Button|OortButton|SelenePillButton|SeleneButtonRow)\s*(?=[({])", source.code):
                if any(a <= match.start() < b for a, b in ranges): continue
                end = call_end(source, match.end())
                call = source.code[match.start():end]
                named = re.findall(r"\b(?:action|activate)\s*:\s*(?:\w+\.)*([a-z]\w*)\b", call)
                brace = call.rfind("}")
                if brace == len(call) - 1:
                    depth, at = 0, brace
                    while at >= 0:
                        depth += (call[at] == "}") - (call[at] == "{")
                        if depth == 0: break
                        at -= 1
                    inside = call[at:]
                    named += [name for name in re.findall(r"(?<![\w$])([a-z]\w*)\s*(?=[({]|\.toggle\b)", inside)
                              if name not in ("text", "if", "else", "guard", "switch", "action", "format")]
                    named += re.findall(r"(?<![\w.])([a-z]\w*)\s*=(?!=)", inside)
                # A helper that only passes its own `action` on is judged where it is called.
                if not set(named) - {"action", "perform"} or any(re.search(rf"\b{name}\b", published) for name in named): continue
                words = literals(source, match.start(), end)[:1]
                label = words[0] if words else named[0]
                found.add("keyboard-path", relative, f"button {label}", f"no Settings row presses {label}", source.line(match.start()))
            if helps_by_click:
                for match in re.finditer(r"\b(?:SeleneRow|Selene\w+Row|SelenePanel)\s*\(", source.code):
                    call = source.code[match.start():source.close(match.end() - 1)]
                    if re.search(r"\binfo\s*:\s*(?!nil\b)", call):
                        # The row's title, or what names it.
                        title = " ".join(elements(source.text[match.end() - 1:match.start() + len(call)])[0].split()).strip('"')[:40]
                        found.add("keyboard-path", relative, f"help {title}", f"the help of {title} opens by click only",
                                  source.line(match.start()))
        for match in re.finditer(r"\bcase\s+((?:\d+\s*(?:where\s+!?\w+)?\s*,\s*)*\d+(?:\s+where\s+!?\w+)?)\s*:(?!\s*break\b)", source.code):
            keys = re.findall(r"\b\d+\b", match[1])
            if "36" in keys and "76" not in keys:
                found.add("keyboard-path", relative, "Return without keypad Enter", "Return works and the keypad's Enter does not",
                          source.line(match.start()))
        for match in re.finditer(r"\bSeleneConfirmDialog\s*\(", source.code):
            after = source.close(match.end() - 1)
            if not (detail := re.compile(r"\s*\{").match(source.code, after)): continue
            for start, end in keys_in(source, detail.end() - 1, source.close(detail.end() - 1)):
                words = literals(source, start, end)[:1] or ["button"]
                found.add("keyboard-path", relative, f"dialog {words[0]}", f"{words[0]} is inside a dialog whose keys walk two answers only",
                          source.line(start))
        if relative.startswith(VIEWS) and ".keyboardShortcut" in source.code and not re.search(r"GamepadAction|onKeyPress|keyDown", source.code):
            for match in re.finditer(r"(?<![\w.])Button\s*(?=[({])", source.code):
                end = call_end(source, match.end())
                if "keyboardShortcut" not in source.code[end:chain_end(source, end)]:
                    words = literals(source, match.start(), end)[:1] or ["button"]
                    found.add("keyboard-path", relative, f"shortcut {words[0]}", f"{words[0]} has no shortcut among buttons that do",
                              source.line(match.start()))
    for action in rules.get("action_paths", []):
        (click_file, click), (key_file, key) = action["click"], action["key"]
        if not all((tree.root / path).is_file() for path in (click_file, key_file)) or not re.search(click, tree.source(click_file).text):
            found.add("keyboard-path", "scripts/ui-rules.json", f"gone:{action['id']}", f"{action['id']}: not in the sources any more")
        elif not re.search(key, tree.source(key_file).code):
            found.add("keyboard-path", click_file, action["id"], f"{action['id']}: {action['why']}")


def check_mouse(tree, rules, found):
    declared, seen = rules.get("mouse_paths", {}), set()
    files = tree.files("Sources/NXLibrary")
    # A bar that presses its hints' buttons, by view: View.swift and View+Part.swift are one.
    view = lambda relative: Path(relative).stem.split("+")[0]
    pressing = {view(relative) for relative in files if re.search(r"\b(?:SeleneHintsBar|SeleneHomeChrome)\s*\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\bpress\s*:",
                                                                  tree.source(relative).code)}
    for relative in files:
        source = tree.source(relative)
        for match in re.finditer(r"\bHintItem\s*\(", source.code):
            end = source.close(match.end() - 1)
            arguments = elements(source.text[match.end() - 1:end])
            if len(arguments) < 2: continue
            button = re.match(r"\s*\.(\w+)\s*$", arguments[0])
            name = button[1] if button else re.sub(r"\s+", "", arguments[0])
            if name in ("a", "b", "navigate", "move", "vertical"): continue
            label = " ".join(arguments[1].split())
            words = re.findall(r'"((?:[^"\\]|\\.)*)"', label)
            signature = f"{name} {words[0] if words else label[:40]}"
            clicks = bool(re.search(r"\baction\s*:", source.code[match.start():end])) or bool(re.compile(r"\s*\{").match(source.code, end))
            if signature in declared.get(relative, {}):
                seen.add((relative, signature))
            elif clicks:
                found.add("mouse-path", relative, signature, f"{signature}: only the hint offers it to the mouse", source.line(match.start()))
            elif name in SECOND and view(relative) not in pressing:
                found.add("mouse-path", relative, signature, f"{signature}: the hint cannot be clicked", source.line(match.start()))
    for relative, paths in declared.items():
        for signature in paths:
            if (relative, signature) not in seen:
                found.add("mouse-path", "scripts/ui-rules.json", f"gone:{relative} {signature}", f"{signature} is declared and not in {relative}")


def scan(root, rules):
    tree, found, notes = Tree(root), Findings(), []
    check_menus(tree, rules, found, notes)
    check_dialogs(tree, found)
    check_texts(tree, rules, found)
    check_styles(tree, found)
    check_access(tree, rules, found)
    check_order(tree, rules, found)
    check_focus(tree, rules, found)
    check_keyboard(tree, rules, found)
    check_mouse(tree, rules, found)
    return found, notes


def judged(script):
    """The rules a version of this script explains in its header."""
    header = script.split('"""')[1] if '"""' in script else ""
    return set(re.findall(r"^  ([a-z0-9-]+)  +\S", header, re.MULTILINE))


def flat(allowed):
    return Counter({(rule, path, sig): count for rule, paths in allowed.items() for path, sigs in paths.items() for sig, count in sigs.items()})


def grown(current, original, rules=None):
    """New debt. A rule the base did not judge yet (`rules`) declares what is there, once."""
    extra = flat(current) - flat(original)
    return Counter({key: count for key, count in extra.items() if rules is None or key[0] in rules})


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT, help="another checkout to read")
    parser.add_argument("--rules", type=Path, default=RULES)
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--prune", action="store_true")
    parser.add_argument("--base", metavar="REV")
    parser.add_argument("--json", action="store_true", help="print every finding as JSON, debt included")
    args = parser.parse_args()
    rules = json.loads(args.rules.read_text(encoding="utf-8"))
    found, notes = scan(args.root, rules)
    if args.json:
        print(json.dumps(found.counts(), indent=1, ensure_ascii=False))
        return 0
    allowed, active, failed = flat(rules["allowed"]), flat(found.counts()), False
    if args.prune:
        kept = allowed & active
        rules["allowed"] = {}
        for (rule, path, signature), count in sorted(kept.items()):
            rules["allowed"].setdefault(rule, {}).setdefault(path, {})[signature] = count
        args.rules.write_text(json.dumps(rules, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        allowed = kept
    if args.base:
        shown = subprocess.run(["git", "show", f"{args.base}:scripts/ui-rules.json"], cwd=ROOT, capture_output=True, text=True)
        if shown.returncode == 0:
            before = json.loads(shown.stdout)
            script = subprocess.run(["git", "show", f"{args.base}:scripts/check_ui_rules.py"], cwd=ROOT, capture_output=True, text=True)
            known = judged(script.stdout) if script.returncode == 0 else None
            for (rule, path, signature), count in sorted(grown(rules["allowed"], before["allowed"], known).items()):
                print(f"{path}: {rule} debt grows by {count} for {signature}", file=sys.stderr)
                failed = True
    remaining = Counter(allowed)
    for rule, path, signature, message, line in found.items:
        remaining[rule, path, signature] -= 1
        if remaining[rule, path, signature] < 0:
            print(f"{path}{f':{line}' if line else ''}: {rule}: {message}", file=sys.stderr)
            failed = True
        elif args.report:
            print(f"known  {rule}  {path}{f':{line}' if line else ''}  {message}")
    if args.root == ROOT or args.prune:
        for (rule, path, signature), count in sorted(remaining.items()):
            if count > 0:
                print(f"{path}: {rule}: {count} gone, remove from the debt list: {signature}", file=sys.stderr)
                failed = True
    if args.report:
        print("\nEntries counted")
        for name, count, relative in notes: print(f"  {count:>3}  {name}  {relative}")
        print("\nNot measured")
        for where, reason in rules["unmeasured"].items(): print(f"  {where}: {reason}")
    total = Counter(rule for rule, *_ in found.items)
    print("UI rules: " + (", ".join(f"{rule} {count}" for rule, count in sorted(total.items())) or "nothing found")
          + f" known; {'new problems above' if failed else 'nothing new'}.")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
