#!/usr/bin/env python3
"""Make a folder of invented games for the proofs: small programs, invented names, drawn covers. No real game, name,
key, save or picture. usage: fixtures.py <folder> [--windows <FakeGame.exe>]

A program is said by what it does (see `shell`); on Windows each is a copy of FakeGame.exe beside a .play file."""
import json
import math
import random
import shutil
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


def landscape(seed, shape=1.0):
    """`shape` is width over height: the moon is round in every picture."""
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
        if math.hypot((x - moon[0]) * max(shape, 1), (y - moon[1]) * max(1 / shape, 1)) < moon[2]:
            c = [246, 240, 226]
        for base, amp, freq, phase, color in hills:
            if y > base + amp * math.sin(x * freq * 3 + phase) + amp * .4 * math.sin(x * freq * 9 + phase):
                c = color
        return c
    return pixel


def shell(does):
    """The same behaviours as tests/windows/FakeGame.cs, for a system with a shell."""
    out = ["#!/bin/sh"]
    if "log" in does:
        out += ["printf '%s\\n' \"$0\" \"$@\" > \"$RECOMPLAUNCHER_DATA/last-run.txt\" 2>/dev/null",
                "env | grep -E 'RECOMPLAUNCHER|ONE_' | sort >> \"$RECOMPLAUNCHER_DATA/last-run.txt\" 2>/dev/null"]
    if "args" in does:
        out.append("printf '%s\\n' \"$@\" > \"$0-args.txt\"")
    for i in range(1, does.get("steps", 0) + 1):
        out += [f"echo \"progress 0.{i} Unpacking part {i}\"", "sleep 0.25"]
    if "out" in does:
        out += ["printf x > \"$2\"", "echo 'progress 1 Done'"]
    if "start" in does:
        out.append(f"\"$(dirname \"$0\")/{does['start']}\" &")
    if "seconds" in does:
        out.append(f"sleep {does['seconds']}")
    return "\n".join(out + [f"exit {does.get('code', 0)}", ""])


def main(root, fake=None):
    root = Path(root)
    games = root / "games"

    def program(file, does):
        if fake:
            shutil.copy2(fake, file.with_name(file.name + ".exe"))
            file.with_name(file.name + ".play").write_text("".join(f"{k}={v}\n" for k, v in does.items()))
        else:
            file.write_text(shell(does))
            file.chmod(0o755)

    def game(folder, manifest, programs, art=True, hero=False):
        d = games / folder
        d.mkdir(parents=True, exist_ok=True)
        if fake and not isinstance(manifest, str):
            for part in ("start", "prepare"):
                if part in manifest:
                    manifest[part]["program"] = [n if "." in n else n + ".exe" for n in manifest[part]["program"]]
        (d / "recomplauncher.json").write_text(manifest if isinstance(manifest, str) else json.dumps({"format": 1, **manifest}, ensure_ascii=False, indent=1), encoding="utf-8")
        for name, does in programs.items():
            program(d / name, does)
        if art:
            png(d / "cover.png", 258, 417, landscape(folder, 258 / 417))
            png(d / "icon.png", 256, 256, landscape(folder))
        if hero:
            png(d / "hero.png", 960, 540, landscape(folder, 960 / 540))

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
        "exit_codes": {"3": "It could not read your copy of the game. Choose it again."}}, {"run": {"log": 1, "seconds": 3, "window": 1}}, hero=True)
    game("CoastRunner", {"name": "Coast Runner", "repo": "example/coast-runner", "start": {"program": ["launcher"]}}, {"launcher": {"start": "game"}, "game": {"seconds": 4}}, hero=True)
    game("TidalWorks", {"name": "Tidal Works", "repo": "example/tidal-works", "prepare": {"program": ["setup"], "args": ["--out", "{data}/built.pak"], "label": "Builds the game from what it ships with", "done": ["{data}/built.pak"], "options": [{"id": "hd", "label": "Sharper textures", "note": "Takes a little longer.", "args": ["--hd"]}]}, "start": {"program": ["run"]}}, {"setup": {"steps": 8, "out": 1}, "run": {"log": 1, "seconds": 2}})
    game("Crash", {"name": "Broken Compass", "repo": "example/broken-compass", "start": {"program": ["run"]}, "exit_codes": {"3": "This copy is the wrong edition. Choose the other one."}}, {"run": {"seconds": 1, "code": 3}})
    game("Stubborn", {"name": "Endless Garden", "repo": "example/endless-garden", "start": {"program": ["run"]}}, {"run": {"seconds": 600, "window": 1}})
    game("Series/v1", {"name": "Harbour Series", "repo": "example/harbour", "start": {"program": ["run"]}, "games": [{"id": "one", "name": "Harbour", "args": ["--game=one"]}, {"id": "two", "name": "Harbour II", "args": ["--game=two"]}]}, {"run": {"log": 1, "seconds": 1}})
    game("Placed", {"name": "Glass Forest", "inputs": [{"id": "game", "label": "Your copy", "formats": [{"type": "file"}], "into": "game"}], "start": {"program": ["run"]}}, {"run": {"log": 1}})
    game("Damaged", "{ not json", {}, art=False)
    names = ["Amber Station", "Brass Tide", "Cinder Vale", "Drift", "Ember Post", "Fathom", "Grey Meridian", "Hollow Sky", "Iron Orchard", "Juniper", "Kestrel", "Lantern Bay", "Mirror Lake", "North Passage", "Open Circuit", "Paper Moon", "Quiet Engine", "Red Horizon", "Salt and Light", "The Very Long Voyage of a Small Boat Across an Unreasonably Wide Sea"]
    for i, name in enumerate(names):
        game(f"Extra{i:02}", {"name": name, "repo": f"example/extra-{i}", "start": {"program": ["run"]}}, {"run": {"log": 1, "seconds": 1}}, art=i % 5 != 3, hero=i % 6 == 0)
    (root / "copies").mkdir(exist_ok=True)
    (root / "copies/lunar.iso").write_bytes(b"not a game")
    program(root / "emulator", {"args": 1, "seconds": 2})
    (root / "copies/Sunken City.rom").write_bytes(b"not a game")
    if fake:
        windows_only(game, games)
    print(f"{len(list(games.rglob('recomplauncher.json')))} invented games in {games}")


def windows_only(game, games):
    """What only Windows does: a game outside the launcher's job, one that ignores its X button, a batch file, names."""
    game("Breakaway", {"name": "Night Ferry", "start": {"program": ["launcher"]}}, {"launcher": {"start": "game", "breakaway": 1}, "game": {"seconds": 5}})
    game("Ignores", {"name": "Locked Gate", "start": {"program": ["run"]}}, {"run": {"seconds": 600, "window": 1, "ignore": 1}})
    game("Île d’Été (1)", {"name": "Winter Lantern", "start": {"program": ["run"], "args": ["--name", "Forêt & « neige »", "100%"]}}, {"run": {"log": 1, "seconds": 5, "window": 1}}, hero=True)
    game("Fault", {"name": "Sudden Stop", "start": {"program": ["run"]}}, {"run": {"seconds": 1, "code": -1073741819}})
    game("Batch", {"name": "Old Script", "start": {"program": ["run.cmd"]}}, {})
    (games / "Batch/run.cmd").write_text("@echo off\r\nping -n 4 127.0.0.1 >nul\r\nexit /b 0\r\n", newline="")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[3] if sys.argv[2:3] == ["--windows"] else None)
