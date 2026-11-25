"""Write the Finder presentation into an unmounted disk image's staging folder."""

import json
import math
from pathlib import Path
from subprocess import run
import sys
from tempfile import TemporaryDirectory

from brand_icons import density
from ds_store import DSStore
from mac_alias import ALIAS_NO_CNID, Alias, TargetInfo, VolumeInfo
from mac_alias.utils import mac_epoch

WIDTH, HEIGHT = 660, 420
VOLUME = "Oort NX"
ICON_SIZE, LABEL_SIZE = 96, 13
LOCATIONS = {"Oort NX.app": (170, 194), "Applications": (490, 194)}
BACKGROUND = ".background.tiff"
ROOT = Path(__file__).resolve().parents[1]


def write_store(stage):
    # The filesystem doesn't exist yet. Resolve by volume name and volume-relative
    # path, without borrowing dates, IDs or host paths from the staging folder.
    background_alias = Alias(
        volume=VolumeInfo(VOLUME, mac_epoch, b"H+", 0, 0, b"\0\0"),
        target=TargetInfo(0, BACKGROUND, 2, ALIAS_NO_CNID, mac_epoch, b"\0"*4, b"\0"*4,
                          folder_name=VOLUME, carbon_path=f"{VOLUME}:{BACKGROUND}",
                          posix_path=f"/{BACKGROUND}"),
    )
    # shortcut: diskutil's folder importer drops the exact spelling .DS_Store.
    # Its case-insensitive APFS still opens this record as .DS_Store; drop the
    # alternate spelling when diskutil preserves the canonical name.
    with DSStore.open(str(stage / ".ds_store"), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["icvl"] = ("type", b"icnv")
        store["."]["bwsp"] = {
            "WindowBounds": f"{{{{100, 100}}, {{{WIDTH}, {HEIGHT + 32}}}}}",
            "ShowToolbar": False, "ShowStatusBar": False, "ShowTabView": False,
            "ShowPathbar": False, "ShowSidebar": False, "ContainerShowSidebar": False,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1, "backgroundType": 2,
            "backgroundImageAlias": background_alias.to_bytes(),
            "arrangeBy": "none", "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0,
            "scrollPositionX": 0.0, "scrollPositionY": 0.0,
            "showItemInfo": False, "showIconPreview": False, "labelOnBottom": True,
            "iconSize": float(ICON_SIZE), "textSize": float(LABEL_SIZE),
        }
        for name, point in LOCATIONS.items():
            store[name]["Iloc"] = point


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


def style(stage):
    with TemporaryDirectory(prefix="oort-dmg-art.") as tmp:
        cloud = Path(tmp) / "cloud.json"
        cloud.write_text(json.dumps(list(cloud_points())))
        points = [str(value) for point in LOCATIONS.values() for value in point]
        run(["swift", str(ROOT / "scripts/make_dmg_background.swift"), tmp,
             str(WIDTH), str(HEIGHT), str(ICON_SIZE), *points, str(cloud)], check=True)
        run(["/usr/bin/tiffutil", "-cathidpicheck", f"{tmp}/background.tiff", f"{tmp}/background@2x.tiff",
             "-out", str(stage / BACKGROUND)], check=True)
    run(["/bin/cp", str(ROOT / "Resources/AppIcon.icns"), str(stage / ".VolumeIcon.icns")],
        check=True)
    run(["/usr/bin/SetFile", "-a", "C", str(stage)], check=True)
    write_store(stage)


if __name__ == "__main__":
    style(Path(sys.argv[1]))
