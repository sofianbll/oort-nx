#!/usr/bin/env python3
"""Real Oort Play and LaunchServices, limited to one silent temporary app."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
from uuid import uuid4

from audit_probe_host import run_host

here = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="oort-native-play-", dir="/private/tmp") as tmp:
    contents = Path(tmp) / "Fixture.app" / "Contents"
    executable = contents / "MacOS" / "Fixture"
    executable.parent.mkdir(parents=True)
    bundle_id = "io.example.oort.playproof." + uuid4().hex
    with (contents / "Info.plist").open("wb") as f:
        plistlib.dump(dict(CFBundleIdentifier=bundle_id, CFBundleExecutable=executable.name, LSUIElement=True,
                           CFBundleVersion="1", CFBundlePackageType="APPL", DMTitleID="010000000000D999"), f)
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(here / "NativePlayFixture.swift"),
                    "-o", str(executable)], check=True)
    run_host((here / "NativePlayRace.swift").read_text(), save_model=True, launch_services_environment=True,
             environment=dict(OORT_PLAY_FIXTURE_DIR=tmp, OORT_PLAY_FIXTURE_ID=bundle_id))
