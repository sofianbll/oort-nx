#!/usr/bin/env python3
"""Make a folder of invented games for the proofs: small shell programs, invented names, drawn covers. No real game,
name, key, save or picture. usage: fixtures.py <folder>"""
import json
import math
import os
import random
import stat
import struct
import sys
import zlib
from pathlib import Path


def png(path, w, h, pixel):
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            rows += bytes(max(0, min(255, int(c))) for c in pixel(x / w, y / h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b""))


def landscape(seed):
    r = random.Random(seed)
    hue = r.random()

    def rgb(hh, s, v):
        i = int(hh * 6) % 6
        f = hh * 6 % 1
        p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
        return [x * 255 for x in ((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))[i]]

    sky, low = rgb(hue, .45, .35 + r.random() * .4), rgb((hue + .12) % 1, .35, .9)
    moon = (r.uniform(.2, .8), r.uniform(.12, .4), r.uniform(.05, .12))
    hills = [(r.uniform(.45, .9), r.uniform(.03, .1), r.uniform(1, 4), r.uniform(0, 6), rgb((hue + .5 + k * .06) % 1, .4, .45 - k * .11)) for k in range(4)]
    hills.sort(key=lambda x: x[0])

    def pixel(x, y):
        c = [a + (b - a) * min(1, y * 1.3) for a, b in zip(sky, low)]
        if math.hypot(x - moon[0], y - moon[1]) < moon[2]:
            c = [246, 240, 226]
        for base, amp, freq, phase, color in hills:
            if y > base + amp * math.sin(x * freq * 3 + phase) + amp * .4 * math.sin(x * freq * 9 + phase):
                c = color
        return c
    return pixel


def main(root):
    root = Path(root)
    games = root / "games"
    run = "#!/bin/sh\nprintf '%s\\n' \"$0\" \"$@\" > \"$RECOMPLAUNCHER_DATA/last-run.txt\" 2>/dev/null\nenv | grep -E 'RECOMPLAUNCHER|ONE_' | sort >> \"$RECOMPLAUNCHER_DATA/last-run.txt\" 2>/dev/null\n"

    def game(folder, manifest, programs, art=True, hero=False):
        d = games / folder
        d.mkdir(parents=True, exist_ok=True)
        (d / "recomplauncher.json").write_text(manifest if isinstance(manifest, str) else json.dumps({"format": 1, **manifest}, ensure_ascii=False, indent=1))
        for name, text in programs.items():
            (d / name).write_text(text)
            (d / name).chmod(0o755)
        if art:
            picture = landscape(folder)
            png(d / "cover.png", 258, 417, picture)
            png(d / "icon.png", 256, 256, picture)
        if hero:
            png(d / "hero.png", 960, 540, landscape(folder))

    game("LunarObservatory", {
        "name": "Lunar Observatory", "repo": "example/lunar-observatory",
        "inputs": [{"id": "game", "label": "Your copy of Lunar Observatory (.iso)", "formats": [{"type": "file", "extensions": ["iso"]}], "check": {"ids": ["LUNA-0001"]}}],
        "start": {"program": ["run"], "args": ["--iso", "{input:game}"], "env": {"ONE_DATA": "{data}"}},
        "config": [{"format": "toml", "file": [{"path": "{install}/settings.toml"}], "game_path": "disc", "new": {"scale": "2", "vsync": "true"}}],
        "settings": [{"id": "scale", "label": "Resolution", "help": "What the game draws at.", "group": "Picture", "choices": [{"label": "720p", "set": {"scale": "1"}}, {"label": "1440p", "set": {"scale": "2"}}, {"label": "4K", "set": {"scale": "3"}}], "defaults": {"scale": "1"}},
                     {"id": "vsync", "label": "V-Sync", "group": "Picture", "choices": [{"label": "On", "set": {"vsync": "true"}}, {"label": "Off", "set": {"vsync": "false"}}], "defaults": {"vsync": "true"}},
                     {"id": "sens", "label": "Stick sensitivity", "help": "How fast the view turns.", "group": "Controls", "in": "args", "slider": {"min": 0.5, "max": 2, "step": 0.1, "format": "%.1f", "args": ["--sens", "{value}"]}},
                     {"id": "keys", "label": "Keyboard", "group": "Controls", "bindings": {"actions": [{"label": "A", "key": "a"}]}}],
        "folders": {"logs": [{"path": "{install}"}]}, "actions": [{"id": "logs", "label": "Logs", "help": "What the game wrote.", "open": "logs"}],
        "exit_codes": {"3": "It could not read your copy of the game. Choose it again."}}, {"run": run + "sleep ${OORT_FAKE_SECONDS:-3}\nexit ${OORT_FAKE_CODE:-0}\n"}, hero=True)
    game("CoastRunner", {"name": "Coast Runner", "repo": "example/coast-runner", "start": {"program": ["launcher"]}}, {"launcher": "#!/bin/sh\n# a stub that starts the game and leaves at once\n./game &\nexit 0\n", "game": "#!/bin/sh\nsleep 4\n"}, hero=True)
    game("TidalWorks", {"name": "Tidal Works", "repo": "example/tidal-works", "prepare": {"program": ["setup"], "args": ["--out", "{data}/built.pak"], "label": "Builds the game from what it ships with", "done": ["{data}/built.pak"], "options": [{"id": "hd", "label": "Sharper textures", "note": "Takes a little longer.", "args": ["--hd"]}]}, "start": {"program": ["run"]}}, {"setup": "#!/bin/sh\nfor i in 1 2 3 4 5 6 7 8; do echo \"progress 0.$i Unpacking part $i\"; sleep 0.25; done\nprintf x > \"$2\"\necho 'progress 1 Done'\n", "run": run + "sleep 2\n"})
    game("Crash", {"name": "Broken Compass", "repo": "example/broken-compass", "start": {"program": ["run"]}, "exit_codes": {"3": "This copy is the wrong edition. Choose the other one."}}, {"run": "#!/bin/sh\nsleep 1\nexit 3\n"})
    game("Stubborn", {"name": "Endless Garden", "repo": "example/endless-garden", "start": {"program": ["run"]}}, {"run": "#!/bin/sh\nsleep 600\n"})
    game("Series/v1", {"name": "Harbour Series", "repo": "example/harbour", "start": {"program": ["run"]}, "games": [{"id": "one", "name": "Harbour", "args": ["--game=one"]}, {"id": "two", "name": "Harbour II", "args": ["--game=two"]}]}, {"run": run + "sleep 1\n"})
    game("Placed", {"name": "Glass Forest", "inputs": [{"id": "game", "label": "Your copy", "formats": [{"type": "file"}], "into": "game"}], "start": {"program": ["run"]}}, {"run": run})
    game("Damaged", "{ not json", {}, art=False)
    names = ["Amber Station", "Brass Tide", "Cinder Vale", "Drift", "Ember Post", "Fathom", "Grey Meridian", "Hollow Sky", "Iron Orchard", "Juniper", "Kestrel", "Lantern Bay", "Mirror Lake", "North Passage", "Open Circuit", "Paper Moon", "Quiet Engine", "Red Horizon", "Salt and Light", "The Very Long Voyage of a Small Boat Across an Unreasonably Wide Sea"]
    for i, name in enumerate(names):
        game(f"Extra{i:02}", {"name": name, "repo": f"example/extra-{i}", "start": {"program": ["run"]}}, {"run": run + "sleep 1\n"}, art=i % 5 != 3, hero=i % 6 == 0)
    (root / "copies").mkdir(exist_ok=True)
    (root / "copies/lunar.iso").write_bytes(b"not a game")
    emulator = root / "emulator"
    emulator.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$(dirname \"$0\")/emulator-args.txt\"\nsleep 2\n")
    emulator.chmod(0o755)
    (root / "copies/Sunken City.rom").write_bytes(b"not a game")
    print(f"{len(list(games.rglob('recomplauncher.json')))} invented games in {games}")


if __name__ == "__main__":
    main(sys.argv[1])
