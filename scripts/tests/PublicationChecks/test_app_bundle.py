import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest


BUILD_APP = Path(__file__).resolve().parents[3] / "scripts/build_app.sh"


class AppBundleInfo(unittest.TestCase):
    def test_optional_google_client_pair_is_injected_without_xml_interpolation(self):
        helper = BUILD_APP.with_name("inject_google_client.py")
        keys = ("ARCANE_GOOGLE_CLIENT_ID", "ARCANE_GOOGLE_CLIENT_SECRET")
        environment = {key: value for key, value in os.environ.items() if key not in keys}
        values = [f"placeholder {index} <&>" for index in range(2)]
        original = {"CFBundleName": "Fixture"}
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "Info.plist"
            path.write_bytes(plistlib.dumps(original))
            for options in ({}, {keys[0]: values[0]}, {keys[1]: values[1]}, dict(zip(keys, values))):
                subprocess.run([sys.executable, str(helper), str(path)], env=environment | options, check=True)
                expected = original if len(options) != 2 else dict(
                    original, ArcaneGoogleClientID=values[0], ArcaneGoogleClientSecret=values[1])
                self.assertEqual(plistlib.loads(path.read_bytes()), expected)

    def test_launcher_opts_out_of_game_mode(self):
        # Arcane declares the games category, so macOS would put the launcher
        # itself in Game Mode; the engine opts each game out for the same reason.
        script = BUILD_APP.read_text()
        self.assertIn("public.app-category.games", script)
        self.assertRegex(script, re.compile(r"<key>LSSupportsGameMode</key>\s*<false/>"))


if __name__ == "__main__":
    unittest.main()
