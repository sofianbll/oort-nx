#!/usr/bin/env python3
"""Builds made-up "games" for the emulator check: tiny apps named as nx2android names its own (org.nx2a.*), with an
invented name, an invented picture drawn here, and one activity that shows a text. No game, no game asset.

    make_test_games.py --out DIR --keystore FILE --password PASS     (needs ANDROID_HOME and a JDK)
"""
import argparse
import os
import shutil
import struct
import subprocess
import tempfile
import zlib
from math import hypot, sin
from pathlib import Path

PLATFORM = "android-36"
BUILD_TOOLS = "36.0.0"


def png(width, height, pixel):
    raw = b"".join(b"\0" + b"".join(bytes(max(0, min(255, int(c))) for c in pixel(x / width, y / height)) for x in range(width)) for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    channels = len(pixel(0, 0))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, {3: 2, 4: 6}[channels], 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def mix(a, b, t):
    return tuple(p + (q - p) * t for p, q in zip(a, b))


def lighthouse(x, y):
    sky = mix((24, 40, 72), (142, 120, 226), y)
    if y > 0.84 + 0.03 * sin(x * 9):
        return (6, 14, 30)
    if hypot(x - 0.68, y - 0.24) < 0.055:
        return (255, 224, 130)
    if 0.29 < y < 0.84 and abs(x - 0.68) < 0.06 + (y - 0.29) * 0.08:
        return (204, 72, 52) if 0.39 < y < 0.48 or 0.6 < y < 0.69 else (220, 230, 244)
    if x < 0.64 and abs(y - 0.24 - (0.64 - x) * 0.12) < (0.64 - x) * 0.14:
        return mix(sky, (255, 255, 255), 0.18)
    return sky


def tide(x, y):
    if hypot(x - 0.78, y - 0.34) < 0.2 and y < 0.5 + 0.02 * sin(x * 14):
        return (255, 218, 166)
    for i in range(6, -1, -1):
        if y > 0.5 + i * 0.075 + 0.022 * sin(x * (12 + i * 2) + i * 2):
            return mix((60, 190, 188), (14, 34, 52), i / 6)
    return mix((16, 48, 52), (44, 92, 112), y * 2)


def hills(x, y):
    if hypot(x - 0.7, y - 0.3) < 0.12:
        return (255, 232, 176)
    for i in range(4, -1, -1):
        if y > 0.46 + i * 0.11 + 0.06 * sin(x * (4 + i) + i * 1.7):
            return mix((188, 62, 44), (40, 20, 14), i / 4)
    return mix((52, 18, 16), (140, 96, 62), y * 2)


def comet(x, y):
    """The foreground layer of an adaptive icon: transparent but for the comet."""
    if hypot(x - 0.6, y - 0.42) < 0.09:
        return (235, 244, 255, 255)
    along = (0.6 - x) * 0.8 + (y - 0.42) * 0.6
    across = abs((0.6 - x) * 0.6 - (y - 0.42) * 0.8)
    if 0 < along < 0.5 and across < 0.085 * (1 - along / 0.5):
        return (150, 190, 255, int(220 * (1 - along / 0.5)))
    return (0, 0, 0, 0)


GAMES = [
    ("org.nx2a.testphare", "Le phare de Brume", "1.0.0", lighthouse),
    ("org.nx2a.testmaree", "Marée haute", "1.2.0", tide),
    ("org.nx2a.testcollines", "Collines rouges", "2.0.1", hills),
    ("org.nx2a.testcomete", "Les très longues aventures de la comète perdue", "1.0.10", comet),  # an adaptive icon
    ("org.example.decoy", "Pas un jeu", "1.0", hills),  # must not be listed
]

MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{package}" android:versionCode="1" android:versionName="{version}">
    <uses-sdk android:minSdkVersion="29" android:targetSdkVersion="36" />
    <application android:label="{label}" android:icon="@mipmap/icon" android:hasCode="true" android:isGame="true" android:appCategory="game"
        android:theme="@android:style/Theme.Material.NoActionBar">
        <activity android:name="org.nx2a.testgame.Main" android:exported="true"
            android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboard|keyboardHidden|navigation|uiMode|density|fontScale|locale">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
"""

JAVA = """package org.nx2a.testgame;
public class Main extends android.app.Activity {
    @Override public void onCreate(android.os.Bundle state) {
        super.onCreate(state);
        android.widget.TextView text = new android.widget.TextView(this);
        text.setText("FAUX JEU " + getPackageName());
        text.setTextSize(22);
        text.setTextColor(0xFFFFFFFF);
        text.setGravity(android.view.Gravity.CENTER);
        text.setBackgroundColor(0xFF203040);
        setContentView(text);
    }
}
"""

ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/back" />
    <foreground android:drawable="@drawable/front" />
</adaptive-icon>
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--keystore", required=True)
    parser.add_argument("--password", required=True)
    args = parser.parse_args()
    sdk = Path(os.environ["ANDROID_HOME"])
    tools = sdk / "build-tools" / BUILD_TOOLS
    jar = sdk / "platforms" / PLATFORM / "android.jar"
    args.out.mkdir(parents=True, exist_ok=True)

    def run(*command, **kw):
        subprocess.run([str(c) for c in command], check=True, **kw)

    with tempfile.TemporaryDirectory() as folder:
        work = Path(folder)
        source = work / "src/org/nx2a/testgame/Main.java"
        source.parent.mkdir(parents=True)
        source.write_text(JAVA)
        run("javac", "--release", "11", "-cp", jar, "-d", work / "classes", source)
        run(tools / "d8", "--min-api", "29", "--lib", jar, "--output", work, *(work / "classes").rglob("*.class"))
        for package, label, version, picture in GAMES:
            app = work / package
            res = app / "res"
            if picture is comet:
                for name in ("mipmap-anydpi-v26", "drawable-xxxhdpi", "values"):
                    (res / name).mkdir(parents=True)
                (res / "mipmap-anydpi-v26/icon.xml").write_text(ADAPTIVE)
                (res / "drawable-xxxhdpi/front.png").write_bytes(png(432, 432, comet))
                (res / "values/colors.xml").write_text('<resources><color name="back">#FF1A2350</color></resources>')
            else:
                (res / "mipmap-xxxhdpi").mkdir(parents=True)
                (res / "mipmap-xxxhdpi/icon.png").write_bytes(png(256, 256, picture))
            (app / "AndroidManifest.xml").write_text(MANIFEST.format(package=package, version=version, label=label))
            run(tools / "aapt2", "compile", "--dir", res, "-o", app / "res.zip")
            run(tools / "aapt2", "link", "-o", app / "raw.apk", "-I", jar, "--manifest", app / "AndroidManifest.xml", app / "res.zip")
            shutil.copy(work / "classes.dex", app / "classes.dex")
            run("zip", "-q", "raw.apk", "classes.dex", cwd=app)
            run(tools / "zipalign", "-f", "4", app / "raw.apk", app / "aligned.apk")
            run(tools / "apksigner", "sign", "--ks", args.keystore, "--ks-pass", f"pass:{args.password}", "--out", args.out / f"{package}.apk", app / "aligned.apk")
            (args.out / f"{package}.apk.idsig").unlink(missing_ok=True)
            print(f"{package}: {label}")


if __name__ == "__main__":
    main()
