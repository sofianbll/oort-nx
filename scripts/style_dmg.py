"""Build the styled installer image: the Oort cloud behind Finder's own icons."""

import json
import math
from pathlib import Path
from subprocess import run
import sys
from tempfile import TemporaryDirectory

from brand_icons import density
import dmgbuild

WIDTH, HEIGHT = 660, 420
VOLUME = "Oort NX"
APP = "Oort NX.app"
ICON_SIZE, LABEL_SIZE = 96, 13
LOCATIONS = {APP: (170, 194), "Applications": (490, 194)}
# Finder can show hidden files: they sit below the window, never among the two icons.
HIDDEN = {name: (170 + 160 * (index % 3), 900 + 160 * (index // 3)) for index, name in enumerate(
    (".background.tiff", ".VolumeIcon.icns", ".DS_Store", ".fseventsd", ".Trashes", ".Spotlight-V100"))}
ROOT = Path(__file__).resolve().parents[1]


def settings(app, background):
    return {
        "files": [str(app)], "symlinks": {"Applications": "/Applications"},
        "icon": str(ROOT / "apps/mac/AppIcon.icns"), "background": str(background),
        "format": "UDZO", "filesystem": "HFS+",
        "window_rect": ((200, 140), (WIDTH, HEIGHT + 32)), "default_view": "icon-view",
        "show_status_bar": False, "show_tab_view": False, "show_toolbar": False, "show_pathbar": False, "show_sidebar": False,
        "icon_size": ICON_SIZE, "text_size": LABEL_SIZE, "arrange_by": None, "label_pos": "bottom",
        "icon_locations": {**LOCATIONS, **HIDDEN},
    }


def cloud_points():
    step = 4.25 / (WIDTH * 0.435)
    for ring in range(1, int(1 / step) + 1):
        radius = 1 - (ring - 0.5) * step
        count = round(math.tau * radius / step)
        for index in range(count):
            angle = math.tau * (index + (0.5 if ring % 2 == 0 else 0)) / count
            x, y = radius * math.cos(angle), radius * math.sin(angle)
            d = density(x, y)
            if d > 0:
                yield (x, y, d)


def build(app, image):
    with TemporaryDirectory(prefix="oort-dmg-art.") as tmp:
        cloud = Path(tmp) / "cloud.json"
        cloud.write_text(json.dumps(list(cloud_points())))
        points = [str(value) for point in LOCATIONS.values() for value in point]
        run(["swift", str(ROOT / "scripts/make_dmg_background.swift"), tmp,
             str(WIDTH), str(HEIGHT), str(ICON_SIZE), *points, str(cloud)], check=True)
        background = Path(tmp) / "combined.tiff"
        run(["/usr/bin/tiffutil", "-cathidpicheck", f"{tmp}/background.tiff", f"{tmp}/background@2x.tiff",
             "-out", str(background)], check=True)
        dmgbuild.build_dmg(str(image), VOLUME, settings=settings(app, background))


if __name__ == "__main__":
    build(Path(sys.argv[1]), Path(sys.argv[2]))
