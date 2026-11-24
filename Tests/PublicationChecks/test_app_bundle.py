import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest


BUILD_APP = Path(__file__).resolve().parents[2] / "scripts/build_app.sh"


class AppBundleInfo(unittest.TestCase):
    def test_publish_refuses_each_google_variable_even_if_empty_before_other_checks(self):
        release = BUILD_APP.with_name("release.sh")
        keys = ("ARCANE_GOOGLE_CLIENT_ID", "ARCANE_GOOGLE_CLIENT_SECRET")
        environment = {key: value for key, value in os.environ.items() if key not in keys}
        for key in keys:
            for value in ("", "placeholder"):
                with self.subTest(key=key, empty=not value):
                    result = subprocess.run(["/bin/bash", str(release), "0.0.0", "--publish"],
                                            env=environment | {key: value}, capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("unset ARCANE_GOOGLE_CLIENT_ID and ARCANE_GOOGLE_CLIENT_SECRET", result.stderr)

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

    def test_release_uses_only_the_public_canonical_fork_name(self):
        script = BUILD_APP.with_name("release.sh").read_text()
        start = script.index("fail() {")
        end = script.index('[[ "$VERSION"', start)
        source = BUILD_APP.parents[1] / "Sources/NXLibraryCore/App/AppUpdate.swift"
        probe = script[start:end] + """
        gh() {
            [[ "$*" == "api repos/sofianbll/NxLibrary --hostname github.com --jq select(.private == false and .permissions.push == true) | .full_name" ]] || return 2
            printf '%s' "$CANONICAL"
        }
        resolve_release_repository "$1"
        """
        for canonical, accepted in [("sofianbll/NxLibrary", True), ("sofianbll/oort-nx", True),
                                    ("someone/oort-nx", False), ("sofianbll/Oort-NX", False), ("", False)]:
            with self.subTest(canonical=canonical):
                result = subprocess.run(["/bin/bash", "-c", probe, "probe", str(source)],
                                        env=os.environ | {"CANONICAL": canonical}, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, accepted, result.stderr)
                if accepted:
                    self.assertEqual(result.stdout.strip(), canonical)

    def test_launcher_opts_out_of_game_mode(self):
        # Arcane declares the games category, so macOS would put the launcher
        # itself in Game Mode; the engine opts each game out for the same reason.
        script = BUILD_APP.read_text()
        self.assertIn("public.app-category.games", script)
        self.assertRegex(script, re.compile(r"<key>LSSupportsGameMode</key>\s*<false/>"))


if __name__ == "__main__":
    unittest.main()
