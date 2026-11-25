import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import generate_oort_android_tokens as android  # noqa: E402

KOTLIN = ROOT / android.OUTPUT


class AndroidTokens(unittest.TestCase):
    def test_committed_kotlin_matches_the_tokens(self):
        android.generate(ROOT, check=True)

    def test_every_color_token_is_in_the_kotlin(self):
        data = json.loads((ROOT / android.SOURCE).read_text())
        text = KOTLIN.read_text()
        for name, leaf in data["primitive"].items():
            if name.startswith("$"):
                continue
            hex_value = leaf["$value"]["hex"].lstrip("#").upper()
            self.assertIn(f"val {android.pascal(name)} = Color(0xFF{hex_value})", text, name)

    def test_the_android_colors_carry_the_same_values(self):
        text = (ROOT / android.COLORS).read_text()
        self.assertIn('<color name="oort_night">#FF05070B</color>', text)
        self.assertIn('<color name="oort_orbit_high">#FF11151D</color>', text)

    def test_the_sun_is_not_a_token(self):
        # The Sun is the charter's one gold, kept in OortCharter by hand: it must not leak into the shared tokens.
        self.assertNotIn("F4CE8E", KOTLIN.read_text().upper())
        self.assertNotIn("F4CE8E", (ROOT / android.COLORS).read_text().upper())

    def test_durations_are_milliseconds_and_numbers_are_floats(self):
        text = KOTLIN.read_text()
        self.assertRegex(text, r"const val FocusInMs: Int = 180")
        self.assertRegex(text, r"const val PressScale: Float = 0\.975f")

    def test_a_bad_token_is_refused(self):
        data = json.loads((ROOT / android.SOURCE).read_text())
        data["color"]["ink"]["$value"] = "{primitive.nowhere}"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "design").mkdir()
            (root / "design/oort.tokens.json").write_text(json.dumps(data))
            with self.assertRaises(KeyError):
                android.generate(root, check=False)

    def test_generated_names_are_kotlin_identifiers(self):
        for name in re.findall(r"(?:val|object) (\w+)", KOTLIN.read_text()):
            self.assertRegex(name, r"^[A-Za-z][A-Za-z0-9]*$")


if __name__ == "__main__":
    unittest.main()
