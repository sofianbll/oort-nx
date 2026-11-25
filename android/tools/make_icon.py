#!/usr/bin/env python3
"""Writes the launcher icon: a ring of dots round the Sun, on the charter's night. Provisional, like the Mac's until a
final mark is chosen. Re-run it after changing the numbers; the three XML files it writes are committed.
"""
import math
from pathlib import Path

RES = Path(__file__).resolve().parents[1] / "app/src/main/res"
SUN = "#FFF4CE8E"   # the charter's one gold
DOT = "#FFAFC3E6"   # frost, the palette's glyph colour


def circle(cx, cy, r):
    return f"M{cx - r:.2f},{cy:.2f}a{r:.2f},{r:.2f} 0 1,0 {2 * r:.2f},0a{r:.2f},{r:.2f} 0 1,0 {-2 * r:.2f},0z"


def ring(count, radius, size, cx=54.0, cy=54.0):
    return "".join(circle(cx + radius * math.cos(2 * math.pi * i / count), cy + radius * math.sin(2 * math.pi * i / count), size)
                   for i in range(count))


def vector(paths):
    body = "\n".join(f'    <path android:fillColor="{c}" android:pathData="{d}" />' for c, d in paths)
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n'
            f"{body}\n</vector>\n")


dots = ring(48, 24, 1.5) + ring(30, 16.5, 1.2) + ring(16, 9, 1.0)
(RES / "drawable").mkdir(parents=True, exist_ok=True)
(RES / "mipmap-anydpi").mkdir(parents=True, exist_ok=True)
(RES / "drawable/ic_launcher_foreground.xml").write_text(vector([(DOT, dots), (SUN, circle(54, 54, 5.2))]))
(RES / "drawable/ic_launcher_monochrome.xml").write_text(vector([("#FF000000", dots + circle(54, 54, 5.2))]))
(RES / "mipmap-anydpi/ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/oort_night" />\n'
    '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
    '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
    '</adaptive-icon>\n')
print("icon written")
