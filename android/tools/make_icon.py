#!/usr/bin/env python3
"""Writes the launcher icon from the app mark in Resources/AppIcon.icon (drawn by scripts/brand_icons.py): the same
dots and Sun, in the mark's dark colours, inside Android's adaptive icon. The XML files it writes are committed.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"
MARK = ROOT / "Resources/AppIcon.icon/Assets"
SUN = "#FFF4CE8E"     # the charter's one gold
SILVER = "#FFD6DEEA"  # icon.json, dark appearance of the glyph
RADIUS = 26.0         # of the mark's unit circle, in Android's 108 units (72 are seen, 66 are always safe)


def circle(cx, cy, r):
    return f"M{cx - r:.2f},{cy:.2f}a{r:.2f},{r:.2f} 0 1,0 {2 * r:.2f},0a{r:.2f},{r:.2f} 0 1,0 {-2 * r:.2f},0z"


def dots(name):
    found = re.findall(r"<circle ([^>]*)/>", (MARK / name).read_text())
    out = []
    for attributes in found:
        value = dict(re.findall(r'(\w+)="([^"]*)"', attributes))
        out.append(circle(54 + RADIUS * float(value.get("cx", 0)), 54 + RADIUS * float(value.get("cy", 0)), RADIUS * float(value["r"])))
    return "".join(out)


def vector(paths):
    body = "\n".join(f'    <path android:fillColor="{c}" android:pathData="{d}" />' for c, d in paths)
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Written by android/tools/make_icon.py from Resources/AppIcon.icon. Do not edit. -->\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n'
            f"{body}\n</vector>\n")


glyph, sun = dots("glyph.svg"), dots("sun.svg")
(RES / "drawable/ic_launcher_foreground.xml").write_text(vector([(SILVER, glyph), (SUN, sun)]))
(RES / "drawable/ic_launcher_monochrome.xml").write_text(vector([("#FF000000", glyph + sun)]))
print("icon written")
