#!/usr/bin/env python3
"""Temporary diagnostic: which fixture step makes macOS change an installed bundle's ctime later on."""
import os, shutil, subprocess, sys, tempfile, time
from pathlib import Path


def make(app, version):
    (app / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    exe = app / "Contents/MacOS/Fixture"
    if not exe.exists():
        shutil.copyfile("/usr/bin/true", exe)
        exe.chmod(0o755)
    sign(app, version)


def sign(app, version):
    import plistlib
    with open(app / "Contents/Info.plist", "wb") as f:
        plistlib.dump(dict(CFBundleIdentifier="local.arcane.screen-game", CFBundleExecutable="Fixture",
                           CFBundlePackageType="APPL", CFBundleShortVersionString=version,
                           DMTitleID="0100000000009000"), f)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)


def files(app):
    return sorted(p for p in app.rglob("*") if p.is_file())


def state(app):
    out = {}
    for p in files(app):
        st = os.lstat(p)
        out[str(p.relative_to(app))] = (st.st_ino, st.st_ctime_ns, st.st_mtime_ns, st.st_flags, st.st_nlink)
    return out


def details(app):
    return subprocess.run(["ls", "-lReO@", str(app)], capture_output=True, text=True).stdout


def watch(label, app, start, seconds=6.0):
    before, first = state(app), details(app)
    changes, t0 = [], time.monotonic()
    while time.monotonic() - t0 < seconds:
        now = state(app)
        for name, value in now.items():
            if before.get(name) != value:
                old = before.get(name)
                changes.append(f"{time.monotonic() - start:6.2f}s {name}: ctime {old and old[1]} -> {value[1]}, "
                               f"flags {old and hex(old[3])} -> {hex(value[3])}, nlink {old and old[4]} -> {value[4]}")
        before = now
        time.sleep(0.02)
    print(f"== {label}: {len(changes)} change(s)")
    for line in changes:
        print("  " + line)
    after = details(app)
    if after != first:
        print("  before:\n" + first + "  after:\n" + after)


def run(variant, root):
    folder = root / variant
    folder.mkdir()
    app = folder / "Running.app"
    make(app, "1.0")
    time.sleep(3)  # Let the first signature settle, as the installed copy has in the probe.
    start = time.monotonic()
    if variant == "swap":  # The current probe: build 2.0 in place, then put a clone of 1.0 back.
        older = folder / "previous"
        subprocess.run(["cp", "-cR", str(app), str(older)], check=True)
        time.sleep(1)
        sign(app, "2.0")
        shutil.rmtree(app)
        os.rename(older, app)
    elif variant == "clone":  # Clone and rename only.
        older = folder / "previous"
        subprocess.run(["cp", "-cR", str(app), str(older)], check=True)
        time.sleep(1)
        shutil.rmtree(app)
        os.rename(older, app)
    elif variant == "sign-in-place":  # Sign the installed path again, nothing else.
        time.sleep(1)
        sign(app, "1.0")
    elif variant == "separate":  # The proposed probe: build 2.0 elsewhere, leave the installed copy alone.
        build = folder / "reference-build" / "Running.app"
        build.parent.mkdir()
        subprocess.run(["cp", "-cR", str(app), str(build)], check=True)
        time.sleep(1)
        sign(build, "2.0")
    print(f"-- {variant}: steps done in {time.monotonic() - start:.2f}s")
    watch(variant, app, start)


root = Path(tempfile.mkdtemp(prefix="fs-touch-", dir=os.environ.get("RUNNER_TEMP")))
for variant in sys.argv[1:] or ["swap", "clone", "sign-in-place", "separate"]:
    run(variant, root)
