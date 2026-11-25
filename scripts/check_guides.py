#!/usr/bin/env python3
"""Check the player guides (docs/guides) and the feature matrix (docs/features.json).

usage: check_guides.py [--strict] [--json OUT]
--strict  a proof in a commit this clone does not have is an error, not a warning
--json    also write what was read, in one file, for the site
The format is in docs/guides/README.md. Standard library only.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

LANGS = ("fr", "en")
SYSTEMS = ("mac", "windows", "linux", "android", "ios")
# Every system answers these; "add-" is one guide per kind of game.
TOPICS = ("install", "first-launch", "add-", "play", "controls", "settings", "saves", "updates", "uninstall", "troubleshooting", "data")
FIELDS = ("title", "system", "topic", "order", "version", "minutes", "tried", "captures")
# How a step is known: a person did it; an automatic check did it with invented games; read in the published code; someone else's page.
STATES = ("played", "checked", "code", "elsewhere")
CELLS = ("yes", "partly", "not-yet", "na")
IMAGE_LIMIT = 200_000
PROMISES = re.compile(r"\b(bientôt|prochainement|coming soon|will soon|sera bientôt|prochaine version|next version)\b", re.I)
VOUS = re.compile(r"\b(vous|votre|vos)\b", re.I)
STEP = re.compile(r"<!-- step (?P<id>[a-z0-9-]+) (?P<state>\S+) (?P<proofs>[^>]+?) -->")
IMAGE = re.compile(r"^!\[(?P<alt>[^\]]+)\]\((?P<path>[^)]+)\)$", re.M)
MISSING = re.compile(r"^<!-- missing (?P<id>[a-z0-9-]+): (?P<why>[^>]+) -->$", re.M)
LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)\s]+)\)")
COMMIT = re.compile(r"^([0-9a-f]{8}):(\S+)$")


class Report:
    def __init__(self):
        self.errors, self.warnings = [], []

    def error(self, where, what):
        self.errors.append(f"{where}: {what}")

    def warn(self, where, what):
        self.warnings.append(f"{where}: {what}")


def read_guide(path):
    """(header, steps) of one guide. Raises ValueError with a reason the writer can act on."""
    text = path.read_text(encoding="utf-8")
    match = re.match(r"---\n(.*?)\n---\n(.*)\Z", text, re.S)
    if not match:
        raise ValueError("no header between --- lines")
    header = {}
    for line in match[1].splitlines():
        key, sep, value = line.partition(": ")
        if not sep or key in header:
            raise ValueError(f"unreadable or repeated header line: {line!r}")
        header[key] = value.strip()
    if set(header) != set(FIELDS):
        raise ValueError(f"header fields must be {', '.join(FIELDS)}; got {', '.join(header)}")
    for key in ("order", "minutes"):
        if not header[key].isdigit():
            raise ValueError(f"{key} must be a number")
        header[key] = int(header[key])
    header["captures"] = [x.strip() for x in header["captures"].split(",") if x.strip()]
    intro, *blocks = re.split(r"^## ", match[2], flags=re.M)
    if intro.strip():
        raise ValueError("text before the first step")
    steps = []
    for block in blocks:
        title, _, body = block.partition("\n")
        mark = STEP.search(body)
        if not mark:
            raise ValueError(f"step {title!r} has no <!-- step id state proof --> line")
        image, missing = IMAGE.findall(body), MISSING.findall(body)
        if len(image) + len(missing) != 1:
            raise ValueError(f"step {title!r} needs one image, or one <!-- missing id: why --> line")
        words = MISSING.sub("", IMAGE.sub("", STEP.sub("", body))).strip()
        steps.append({"id": mark["id"], "title": title.strip(), "state": mark["state"], "proofs": mark["proofs"].split(), "text": words,
                      "image": image[0][1] if image else None, "alt": image[0][0] if image else None,
                      "missing": missing[0][0] if missing else None, "why": missing[0][1] if missing else None})
    if not steps:
        raise ValueError("no step")
    return header, steps


def capture_id(step):
    """The name of a picture, the same in both languages: first-home.fr.webp and first-home.en.webp are first-home."""
    if step["missing"]:
        return "missing:" + step["missing"]
    return re.sub(r"(\.(fr|en))?\.webp$", "", Path(step["image"]).name)


class Proofs:
    def __init__(self, root, report, strict):
        self.root, self.report, self.strict, self.seen = root, report, strict, {}

    def git(self, spec):
        if spec not in self.seen:
            self.seen[spec] = subprocess.run(["git", "cat-file", "-e", spec], cwd=self.root, capture_output=True).returncode == 0
        return self.seen[spec]

    def check(self, where, proof):
        if proof.startswith("https://"):
            return
        commit = COMMIT.match(proof)
        if commit:
            if not self.git(commit[1] + "^{commit}"):
                (self.report.error if self.strict else self.report.warn)(where, f"commit {commit[1]} is not in this clone")
            elif not self.git(f"{commit[1]}:{commit[2]}"):
                self.report.error(where, f"{commit[2]} does not exist in {commit[1]}")
        elif not (self.root / proof).is_file():
            self.report.error(where, f"proof {proof!r} is not a file, a commit:path or an https address")


def check_image(path, where, report):
    if not re.fullmatch(r"[a-z0-9-]+(\.(fr|en))?\.webp", path.name):
        report.error(where, f"{path.name}: a picture is named like-this.webp, or like-this.fr.webp and like-this.en.webp")
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        report.error(where, f"{path.name} is not a WebP file")
    if len(data) > IMAGE_LIMIT:
        report.error(where, f"{path.name} weighs {len(data)} bytes, over {IMAGE_LIMIT}")


def check_step(where, lang, path, step, root, report, proofs, used):
    if step["state"] not in STATES:
        report.error(where, f"state {step['state']!r} is not one of {', '.join(STATES)}")
    if step["state"] == "elsewhere" and not any(p.startswith("https://") for p in step["proofs"]):
        report.error(where, "a step from someone else's page needs its https address")
    if step["state"] != "elsewhere" and not any(not p.startswith("https://") for p in step["proofs"]) and step["state"] != "played":
        report.error(where, "a step known from the code or a check needs a file as proof")
    for proof in step["proofs"]:
        proofs.check(where, proof)
    if not step["text"]:
        report.error(where, "no sentence")
    sentences = re.split(r"[.!?…]»?(?:\s+|$)", re.sub(r"\([^)]*\)|`[^`]*`|\*\*[^*]*\*\*", "x", step["text"]))
    if len([s for s in sentences if s.strip()]) > 3 and "\n|" not in step["text"] and "\n- " not in step["text"]:
        report.error(where, "more than three sentences")
    for text in (step["title"], step["text"]):
        if PROMISES.search(text):
            report.error(where, f"a promise: {PROMISES.search(text)[0]!r}")
        # The app's own words, in bold or quotes, may say "vous"; the guide says "tu".
        if lang == "fr" and VOUS.search(re.sub(r"\*\*[^*]*\*\*|«[^»]*»", "", text)):
            report.error(where, "the guide says “tu”")
    if step["image"]:
        image = (path.parent / step["image"]).resolve()
        if not image.is_file():
            report.error(where, f"picture {step['image']} does not exist")
        else:
            used.add(image)
            tag = re.search(r"\.(fr|en)\.webp$", image.name)
            if tag and tag[1] != lang and image.with_name(image.name.replace(tag[0], f".{lang}.webp")).exists():
                report.error(where, f"{image.name} has a picture in this language")
            if tag and tag[1] != lang and not re.search(r"\(.*(français|anglais|French|English).*\)", step["alt"]):
                report.error(where, f"{image.name} is in the other language: its description must say so")
    for link in LINK.findall(step["text"]):
        if link.startswith("http://"):
            report.error(where, f"{link}: https only")
        elif not link.startswith("https://") and not (path.parent / link.partition("#")[0]).is_file():
            report.error(where, f"link {link} leads nowhere")


def check_matrix(root, report, proofs):
    path = root / "docs/features.json"
    try:
        matrix = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        report.error("docs/features.json", str(error))
        return {"systems": {}, "features": []}
    where = "docs/features.json"
    if tuple(matrix.get("systems", {})) != SYSTEMS:
        report.error(where, f"systems must be {', '.join(SYSTEMS)}")
    for system, about in matrix.get("systems", {}).items():
        if not re.fullmatch(r"\d+\.\d+\.\d+(-(alpha|beta|rc)\.\d+)?", about.get("version", "")):
            report.error(where, f"{system}: unreadable version")
        if not re.fullmatch(r"[0-9a-f]{8}", about.get("commit", "")):
            report.error(where, f"{system}: the commit is eight letters")
        elif not proofs.git(about["commit"] + "^{commit}"):
            (report.error if proofs.strict else report.warn)(where, f"{system}: commit {about['commit']} is not in this clone")
    ids = set()
    for feature in matrix.get("features", []):
        here = f"{where}: {feature.get('id')}"
        if feature.get("id") in ids:
            report.error(here, "twice")
        ids.add(feature.get("id"))
        for key in ("name", "text"):
            for lang in LANGS:
                words = feature.get(key, {}).get(lang, "")
                if not words:
                    report.error(here, f"{key} is missing in {lang}")
                if PROMISES.search(words) or (lang == "fr" and VOUS.search(words)):
                    report.error(here, f"{key} in {lang}: a promise or a “vous”")
        if feature.get("group") not in matrix.get("groups", {}):
            report.error(here, "unknown group")
        cells = feature.get("systems", {})
        if set(cells) != set(SYSTEMS):
            report.error(here, f"a system is forgotten: {', '.join(sorted(set(SYSTEMS) - set(cells)))}")
        for system, cell in cells.items():
            spot = f"{here}, {system}"
            if cell.get("state") not in CELLS:
                report.error(spot, f"state {cell.get('state')!r} is not one of {', '.join(CELLS)}")
            if cell.get("version") != matrix["systems"].get(system, {}).get("version"):
                report.error(spot, "its version is not the system's: look at it again, then write the new one")
            if cell.get("state") in ("yes", "partly") and cell.get("tried") not in STATES:
                report.error(spot, "say how it is known: played, checked, code or elsewhere")
            if cell.get("state") == "partly" and not cell.get("note"):
                report.error(spot, "“partly” says what is missing")
            if cell.get("state") != "na" and not cell.get("proof"):
                report.error(spot, "no proof")
            for proof in cell.get("proof", []):
                proofs.check(spot, proof)
            if cell.get("note"):
                for lang in LANGS:
                    words = cell["note"].get(lang, "")
                    if not words or PROMISES.search(words) or (lang == "fr" and VOUS.search(words)):
                        report.error(spot, f"note in {lang}: missing, a promise or a “vous”")
    return matrix


def check(root, strict=False):
    report = Report()
    proofs = Proofs(root, report, strict)
    matrix = check_matrix(root, report, proofs)
    guides, used = {lang: {} for lang in LANGS}, set()
    folder = root / "docs/guides"
    for lang in LANGS:
        for path in sorted((folder / lang).glob("*/*.md")):
            where = path.relative_to(root).as_posix()
            try:
                header, steps = read_guide(path)
            except ValueError as error:
                report.error(where, str(error))
                continue
            system, topic = path.parent.name, path.stem
            guides[lang][system, topic] = {"header": header, "steps": steps, "path": where}
            if system not in SYSTEMS or header["system"] != system or header["topic"] != topic:
                report.error(where, "system and topic must be the folder and the file")
            if not any(topic == t or t.endswith("-") and topic.startswith(t) or topic.startswith(t + "-") for t in TOPICS + ("cloud",)):
                report.error(where, f"unknown topic {topic!r}")
            if header["version"] != matrix["systems"].get(system, {}).get("version"):
                report.error(where, f"version {header['version']} is not the one of docs/features.json: check the guide again")
            if not 1 <= header["minutes"] <= 60:
                report.error(where, "minutes: from 1 to 60")
            if header["captures"] != [capture_id(s) for s in steps]:
                report.error(where, "captures must name the picture of each step, in order: " + ", ".join(capture_id(s) for s in steps))
            if len({s["id"] for s in steps}) != len(steps):
                report.error(where, "two steps have the same id")
            for step in steps:
                check_step(f"{where}#{step['id']}", lang, path, step, root, report, proofs, used)
    for key in sorted(set(guides["fr"]) ^ set(guides["en"])):
        report.error("docs/guides", f"{'/'.join(key)} exists in one language only")
    for key in sorted(set(guides["fr"]) & set(guides["en"])):
        fr, en = guides["fr"][key], guides["en"][key]
        for field in ("order", "version", "minutes", "captures"):
            if fr["header"][field] != en["header"][field]:
                report.error(en["path"], f"{field} differs from French")
        pick = lambda g: [(s["id"], s["state"], s["proofs"], [x for x in LINK.findall(s["text"]) if x.startswith("https://support.apple.com") is False]) for s in g["steps"]]
        if pick(fr) != pick(en):
            report.error(en["path"], "steps, states, proofs or links differ from French")
    for system in SYSTEMS:
        topics = {topic for s, topic in guides["fr"] if s == system}
        for wanted in TOPICS:
            if not any(t == wanted or wanted.endswith("-") and t.startswith(wanted) or t.startswith(wanted + "-") for t in topics):
                report.error("docs/guides", f"{system} has no {wanted.rstrip('-')} guide")
        orders = [g["header"]["order"] for (s, _), g in guides["fr"].items() if s == system]
        if len(set(orders)) != len(orders):
            report.error("docs/guides", f"{system}: two guides have the same order")
    for path in sorted((folder / "media").rglob("*")):
        if path.is_file():
            check_image(path, path.relative_to(root).as_posix(), report)
            if path.resolve() not in used:
                report.error(path.relative_to(root).as_posix(), "no guide shows this picture")
    return report, matrix, guides


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    options = parser.parse_args()
    report, matrix, guides = check(options.root, options.strict)
    for line in report.warnings:
        print("warning", line)
    for line in report.errors:
        print("error", line)
    if options.json and not report.errors:
        out = {"matrix": matrix, "guides": {lang: [{**g["header"], "steps": g["steps"], "path": g["path"]}
               for _, g in sorted(guides[lang].items(), key=lambda x: (SYSTEMS.index(x[0][0]), x[1]["header"]["order"]))] for lang in LANGS}}
        options.json.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    steps = [s for g in guides["fr"].values() for s in g["steps"]]
    print(f"{len(guides['fr'])} guides in 2 languages, {len(steps)} steps, {sum(bool(s['image']) for s in steps)} with a picture, "
          f"{len(matrix['features'])} features, {len(report.errors)} errors, {len(report.warnings)} warnings")
    return bool(report.errors)


if __name__ == "__main__":
    sys.exit(main())
